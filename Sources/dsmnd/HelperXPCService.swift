import DSMNCore
import Foundation

final class DSMNHelperXPCService: NSObject, DSMNHelperXPCProtocol, @unchecked Sendable {
    private let controller: DSMNController
    private let powerManager: any PowerManaging
    private let liveSleepDisabledProvider: @Sendable () -> Bool?
    private let operationLock = NSLock()
    private let timerQueue = DispatchQueue(label: "com.nomdelasociete.dsmn.helper.reconcile")
    private var periodicReconcileTimer: DispatchSourceTimer?
    private var sleepReleaseTimer: DispatchSourceTimer?

    init(
        controller: DSMNController = DSMNController(store: StateStore.daemonStore()),
        powerManager: any PowerManaging = PMSetPowerManager(dryRun: DSMNHelperXPCService.shouldDryRunPowerChanges()),
        liveSleepDisabledProvider: @escaping @Sendable () -> Bool? = DSMNHelperXPCService.defaultLiveSleepDisabled
    ) {
        self.controller = controller
        self.powerManager = powerManager
        self.liveSleepDisabledProvider = liveSleepDisabledProvider
    }

    deinit {
        periodicReconcileTimer?.cancel()
        sleepReleaseTimer?.cancel()
    }

    func status(withReply reply: @escaping (String) -> Void) {
        reply(encode {
            .success(status: try locked {
                try controller.status()
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
        reply(encode {
            let requester = requesterName.map {
                ActivationRequester(name: $0, context: requesterContext, event: requesterEvent)
            }
            return .success(run: try locked {
                _ = try controller.enableManual(minutes: minutes, extendOnly: extendOnly, requester: requester)
                return try reconcileLocked()
            })
        })
    }

    func stop(withReply reply: @escaping (String) -> Void) {
        reply(encode {
            return .success(run: try locked {
                _ = try controller.stop()
                return try reconcileLocked()
            })
        })
    }

    func reconcile(withReply reply: @escaping (String) -> Void) {
        reply(encode {
            .success(run: try locked {
                try reconcileLocked()
            })
        })
    }

    func repair(withReply reply: @escaping (String) -> Void) {
        reply(encode {
            return .success(run: try locked {
                let report: DaemonRunReport
                do {
                    report = try controller.repair(
                        powerManager: powerManager,
                        liveSleepDisabled: liveSleepDisabled()
                    )
                } catch {
                    rearmSleepReleaseFromSavedState()
                    throw error
                }
                scheduleSleepRelease(from: report.status)
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
            })
        })
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
        do {
            _ = try locked {
                try reconcileLocked()
            }
        } catch {
            fputs("dsmnd: reconcile failed: \(error.localizedDescription)\n", stderr)
        }
    }

    private func reconcileLocked() throws -> DaemonRunReport {
        let report: DaemonRunReport
        do {
            report = try controller.reconcile(
                powerManager: powerManager,
                liveSleepDisabled: liveSleepDisabled()
            )
        } catch {
            rearmSleepReleaseFromSavedState()
            throw error
        }
        scheduleSleepRelease(from: report.status)
        return report
    }

    private func rearmSleepReleaseFromSavedState() {
        do {
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

    private func locked<T>(_ operation: () throws -> T) throws -> T {
        operationLock.lock()
        defer {
            operationLock.unlock()
        }
        return try operation()
    }

    private func liveSleepDisabled() -> Bool? {
        liveSleepDisabledProvider()
    }

    private static func defaultLiveSleepDisabled() -> Bool? {
        try? SleepDiagnosticsInspector().report().sleepDisabled
    }

    private func encode(_ operation: () throws -> DSMNHelperCommandResponse) -> String {
        let response: DSMNHelperCommandResponse
        do {
            response = try operation()
        } catch {
            response = .failure(error)
        }

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
