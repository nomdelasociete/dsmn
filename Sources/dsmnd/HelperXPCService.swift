import DSMNCore
import Foundation

final class DSMNHelperXPCService: NSObject, DSMNHelperXPCProtocol, @unchecked Sendable {
    private let controller: DSMNController
    private let powerManager: any PowerManaging
    private let liveSleepDisabledProvider: @Sendable () -> Bool?
    private let thermalConditionProvider: @Sendable () -> ThermalCondition
    private let thermalNotificationCenter: NotificationCenter
    private var thermalObserver: NSObjectProtocol?
    private let operationLock = NSLock()
    private let timerQueue = DispatchQueue(label: "com.nomdelasociete.dsmn.helper.reconcile")
    private let telemetryQueue = DispatchQueue(label: "com.nomdelasociete.dsmn.helper.telemetry")
    private let sleepProbeQueue = DispatchQueue(label: "com.nomdelasociete.dsmn.helper.sleep-probe")
    private var periodicReconcileTimer: DispatchSourceTimer?
    private var sleepReleaseTimer: DispatchSourceTimer?
    // All cache, generation, and flight flags below are protected by operationLock.
    private var telemetry = ControllerTelemetry.unavailable(at: Date())
    private var cachedLiveSleepDisabled: Bool?
    private var mutationEpoch: UInt64 = 0
    private var sampleGeneration: UInt64 = 0
    private var publishedGeneration: UInt64 = 0
    private var telemetryInFlight = false
    private var sleepProbeInFlight = false
    private var pendingSleepEpoch: UInt64?
    private var nextOwnedReleaseAttempt: Date?

    init(
        controller: DSMNController = DSMNController(store: StateStore.daemonStore()),
        powerManager: any PowerManaging = PMSetPowerManager(dryRun: DSMNHelperXPCService.shouldDryRunPowerChanges()),
        liveSleepDisabledProvider: @escaping @Sendable () -> Bool? = DSMNHelperXPCService.defaultLiveSleepDisabled,
        thermalConditionProvider: @escaping @Sendable () -> ThermalCondition = { .current },
        thermalNotificationCenter: NotificationCenter = .default
    ) {
        self.controller = controller
        self.powerManager = powerManager
        self.liveSleepDisabledProvider = liveSleepDisabledProvider
        self.thermalConditionProvider = thermalConditionProvider
        self.thermalNotificationCenter = thermalNotificationCenter
        super.init()
        thermalObserver = thermalNotificationCenter.addObserver(
            forName: ProcessInfo.thermalStateDidChangeNotification, object: nil, queue: nil
        ) { [weak self] _ in
            self?.reconcileSilently()
        }
    }

    deinit {
        if let thermalObserver { thermalNotificationCenter.removeObserver(thermalObserver) }
        periodicReconcileTimer?.cancel()
        sleepReleaseTimer?.cancel()
    }

    func status(withReply reply: @escaping (String) -> Void) {
        defer { requestTelemetryRefresh() }
        reply(encode {
            .success(status: try locked {
                try controller.status(telemetry: telemetry)
            })
        })
    }

    func enableManual(minutes: Int, withReply reply: @escaping (String) -> Void) {
        enableManualV2(
            minutes: minutes,
            extendOnly: false,
            requesterName: nil,
            requesterContext: nil,
            requesterEvent: nil,
            withReply: reply
        )
    }

    func enableManualV2(
        minutes: Int,
        extendOnly: Bool,
        requesterName: String?,
        requesterContext: String?,
        requesterEvent: String?,
        withReply reply: @escaping (String) -> Void
    ) {
        defer { requestTelemetryRefresh() }
        reply(encode {
            let requester = requesterName.map {
                ActivationRequester(name: $0, context: requesterContext, event: requesterEvent)
            }
            return .success(run: try mutate(recoverPendingAcquisition: true) {
                _ = try controller.enableManualIntent(minutes: minutes, extendOnly: extendOnly, requester: requester)
            })
        })
    }

    func stop(withReply reply: @escaping (String) -> Void) {
        defer { requestTelemetryRefresh() }
        reply(encode {
            let report = try mutate {
                _ = try controller.stopIntent()
            }
            guard !report.status.state.ownsSleepDisable, !report.status.state.sleepDisablePending else {
                throw DSMNError.invalidCommand("Stop could not confirm power lock release; recovery will retry.")
            }
            return .success(run: report)
        })
    }

    func addManualTime(minutes: Int, withReply reply: @escaping (String) -> Void) {
        defer { requestTelemetryRefresh() }
        reply(encode {
            .success(run: try mutate(recoverPendingAcquisition: true) {
                try controller.addManualTimeIntent(
                    minutes: minutes, requester: ActivationRequester(name: "dsmn", context: "menu")
                )
            })
        })
    }

    func reconcile(withReply reply: @escaping (String) -> Void) {
        defer { requestTelemetryRefresh() }
        reply(encode {
            .success(run: try locked {
                try reconcileLocked()
            })
        })
    }

    func repair(withReply reply: @escaping (String) -> Void) {
        defer { requestTelemetryRefresh() }
        reply(encode {
            let initial = try locked {
                mutationEpoch &+= 1
                let needsLiveProbe = !(try controller.store.load().ownsSleepDisable)
                // Explicit Repair discovers an unowned lock from a fresh
                // observation, even when the telemetry cache says it is off.
                let report = try repairLocked(liveSleepDisabled: nil)
                return (report, needsLiveProbe, mutationEpoch)
            }
            guard initial.1 else { return .success(run: initial.0) }

            // Discover an unowned external lock only after ending intent, and
            // outside the operation lock. Never clear a renewal arriving here.
            let live = liveSleepDisabledProvider()
            return .success(run: try locked {
                guard mutationEpoch == initial.2 else {
                    throw DSMNHelperClientError.commandFailed("Repair was superseded by a newer command; retry if needed.")
                }
                return try repairLocked(liveSleepDisabled: live)
            })
        })
    }

    private func mutate(recoverPendingAcquisition: Bool = false, _ intent: () throws -> Void) throws -> DaemonRunReport {
        try locked {
            mutationEpoch &+= 1
            do {
                // Recover the old uncertain lock before committing a new lease.
                // The intent rejects requests if release still failed.
                if recoverPendingAcquisition, try controller.store.load().sleepDisablePending {
                    _ = try reconcileLocked()
                }
                try intent()
                // An accepted renewal supersedes even a recovery release that
                // happened earlier in this same command.
                mutationEpoch &+= 1
                return try reconcileLocked()
            } catch {
                rearmSleepReleaseFromSavedState()
                throw error
            }
        }
    }

    private func repairLocked(liveSleepDisabled: Bool?) throws -> DaemonRunReport {
        do {
            let report = try controller.repair(
                powerManager: powerManager,
                telemetry: telemetry,
                liveSleepDisabled: liveSleepDisabled
            )
            finishRunLocked(report)
            if let release = report.operations.first(where: { $0.action == .enableSleep }), !release.succeeded {
                throw NSError(
                    domain: DSMNServiceConstants.helperLabel,
                    code: Int(release.exitCode ?? -1),
                    userInfo: [NSLocalizedDescriptionKey: release.dryRun
                        ? "Repair did not release the power lock because power changes are in dry-run mode."
                        : "Repair could not release the power lock (pmset exit \(release.exitCode.map(String.init) ?? "unknown"))."]
                )
            }
            return report
        } catch {
            rearmSleepReleaseFromSavedState()
            throw error
        }
    }

    func startPeriodicReconcile(interval: TimeInterval) {
        reconcileSilently()

        timerQueue.async { [weak self] in
            guard let self else {
                return
            }

            periodicReconcileTimer?.cancel()
            let timer = DispatchSource.makeTimerSource(queue: timerQueue)
            timer.schedule(
                deadline: .now() + interval,
                repeating: interval,
                leeway: .seconds(5)
            )
            timer.setEventHandler { [weak self] in
                self?.reconcileSilently()
            }
            periodicReconcileTimer = timer
            timer.resume()
        }
    }

    private func reconcileSilently() {
        defer { requestTelemetryRefresh() }
        do {
            _ = try locked {
                try reconcileLocked()
            }
        } catch {
            fputs("dsmnd: reconcile failed: \(error.localizedDescription)\n", stderr)
        }
    }

    private func reconcileLocked(updateTracking: Bool = false) throws -> DaemonRunReport {
        let report: DaemonRunReport
        do {
            let now = Date()
            let mandatory = try controller.needsMandatoryRelease(now: now)
            if updateTracking, mandatory, let retry = nextOwnedReleaseAttempt, now < retry {
                return DaemonRunReport(
                    generatedAt: now,
                    status: try controller.status(telemetry: telemetry, now: now),
                    operation: nil,
                    stateChanged: false
                )
            }
            let base = mandatory ? ControllerTelemetry.unavailable(at: now) : telemetry
            var snapshot = base.snapshot
            // Read directly on every command/deadline/event, independent of blocked probes.
            snapshot.thermalCondition = thermalConditionProvider()
            let safetyTelemetry = ControllerTelemetry(snapshot: snapshot, agents: base.agents,
                                                       diagnosticErrors: base.diagnosticErrors)
            report = try controller.reconcile(
                powerManager: powerManager,
                telemetry: safetyTelemetry,
                liveSleepDisabled: mandatory ? nil : cachedLiveSleepDisabled,
                updateTracking: updateTracking && !mandatory,
                now: now
            )
        } catch {
            rearmSleepReleaseFromSavedState()
            throw error
        }
        finishRunLocked(report)
        return report
    }

    private func finishRunLocked(_ report: DaemonRunReport) {
        scheduleSleepRelease(from: report.status)
        if report.operation?.action == .enableSleep {
            nextOwnedReleaseAttempt = report.operation?.succeeded == true ? nil : Date().addingTimeInterval(1)
        }
        if report.operation?.action == .enableSleep, report.operation?.succeeded == true {
            mutationEpoch &+= 1
            // A pre-release live=true sample must not trigger repeated cleanup.
            cachedLiveSleepDisabled = false
            pendingSleepEpoch = mutationEpoch
            startSleepProbeLocked()
        }
    }

    private func requestTelemetryRefresh() {
        let flight: (UInt64, UInt64)? = locked {
            guard !telemetryInFlight else { return nil }
            telemetryInFlight = true
            sampleGeneration &+= 1
            return (mutationEpoch, sampleGeneration)
        }
        guard let (epoch, generation) = flight else { return }

        telemetryQueue.async { [weak self] in
            guard let self else { return }
            let sample = controller.collectTelemetry()
            let live = liveSleepDisabledProvider()
            let stale = locked {
                telemetryInFlight = false
                guard epoch == mutationEpoch, generation > publishedGeneration else { return true }
                telemetry = sample
                cachedLiveSleepDisabled = live
                publishedGeneration = generation
                do { _ = try reconcileLocked(updateTracking: true) }
                catch { fputs("dsmnd: telemetry reconcile failed: \(error.localizedDescription)\n", stderr) }
                return false
            }
            if stale { requestTelemetryRefresh() }
        }
    }

    private func startSleepProbeLocked() {
        guard !sleepProbeInFlight, let epoch = pendingSleepEpoch else { return }
        pendingSleepEpoch = nil
        sleepProbeInFlight = true
        sleepProbeQueue.async { [weak self] in
            guard let self else { return }
            let probeStartedAt = Date()
            let snapshot = try? controller.snapshotProvider.sleepSnapshot(now: probeStartedAt)
            locked {
                sleepProbeInFlight = false
                // Epoch covers every new command, including a renewal whose
                // power acquisition failed and therefore still has owns=false.
                if epoch == mutationEpoch, let snapshot, snapshot.now >= probeStartedAt {
                    do { _ = try controller.completeReleaseSleep(powerManager: powerManager, snapshot: snapshot) }
                    catch { fputs("dsmnd: post-release sleep failed: \(error.localizedDescription)\n", stderr) }
                }
                startSleepProbeLocked()
            }
        }
    }

    private func rearmSleepReleaseFromSavedState() {
        do {
            if try controller.needsMandatoryRelease() { nextOwnedReleaseAttempt = Date().addingTimeInterval(1) }
            scheduleSleepRelease(ReconcileSchedule.sleepReleaseDeadline(
                for: try controller.store.load(),
                now: Date(),
                noRouteGraceSeconds: controller.decisionEngine.policy.noRouteGraceSeconds
            ))
        } catch {
            fputs("dsmnd: could not rearm sleep release: \(error.localizedDescription)\n", stderr)
        }
    }

    private func scheduleSleepRelease(from status: StatusReport) {
        scheduleSleepRelease(ReconcileSchedule.sleepReleaseDeadline(for: status))
    }

    private func scheduleSleepRelease(_ schedule: ReconcileSchedule) {
        timerQueue.async { [weak self] in
            guard let self else {
                return
            }

            sleepReleaseTimer?.cancel()
            sleepReleaseTimer = nil

            guard let deadline = schedule.deadline else {
                return
            }

            let delay = max(0.1, deadline.timeIntervalSince(Date()))
            let timer = DispatchSource.makeTimerSource(queue: timerQueue)
            timer.schedule(deadline: .now() + delay, leeway: .seconds(1))
            timer.setEventHandler { [weak self] in
                self?.reconcileSilently()
            }
            sleepReleaseTimer = timer
            timer.resume()
        }
    }

    private func locked<T>(_ operation: () throws -> T) rethrows -> T {
        operationLock.lock()
        defer {
            operationLock.unlock()
        }
        return try operation()
    }

    private static func defaultLiveSleepDisabled() -> Bool? {
        try? SleepDiagnosticsInspector().liveSleepDisabled()
    }

    private func encode(_ operation: () throws -> DSMNHelperCommandResponse) -> String {
        var response: DSMNHelperCommandResponse
        do {
            response = try operation()
        } catch {
            response = .failure(error)
        }
        response.status?.supportsAddManualTime = true
        response.status?.manualDurationLimitMinutes = controller.decisionEngine.policy.maxManualDurationMinutes
        response.run?.status.supportsAddManualTime = true
        response.run?.status.manualDurationLimitMinutes = controller.decisionEngine.policy.maxManualDurationMinutes

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]

        do {
            let data = try encoder.encode(response)
            return String(data: data, encoding: .utf8) ?? #"{"error":"encoding failed"}"#
        } catch {
            return #"{"error":"encoding failed"}"#
        }
    }

    private static func shouldDryRunPowerChanges() -> Bool {
        let environment = ProcessInfo.processInfo.environment

        if environment["DSMN_APPLY_PMSET"] == "1" {
            return false
        }

        if environment["DSMN_APPLY_PMSET"] == "0" {
            return true
        }

        return getuid() != 0
    }
}

final class DSMNHelperXPCDelegate: NSObject, NSXPCListenerDelegate {
    private let service: DSMNHelperXPCService

    init(service: DSMNHelperXPCService = DSMNHelperXPCService()) {
        self.service = service
    }

    func listener(_ listener: NSXPCListener, shouldAcceptNewConnection connection: NSXPCConnection) -> Bool {
        let validation = DSMNXPCClientAuthentication.validate(connection: connection)
        guard case .accepted = validation else {
            DSMNXPCClientAuthentication.logRejection(validation)
            connection.invalidate()
            return false
        }

        connection.exportedInterface = NSXPCInterface(with: DSMNHelperXPCProtocol.self)
        connection.exportedObject = service
        connection.resume()
        return true
    }
}
