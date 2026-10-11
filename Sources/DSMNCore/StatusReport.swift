import Foundation

public struct StatusReport: Codable, Equatable, Sendable {
    public var generatedAt: Date
    public var state: DSMNState
    public var snapshot: SystemSnapshot
    public var agents: [AgentProcess]
    public var decision: PowerDecision
    public var manualRemainingSeconds: Int?
    public var noRouteGraceRemainingSeconds: Int?
    public var diagnosticErrors: [String]?
    /// Absent on helpers predating additive timer commands.
    public var supportsAddManualTime: Bool?
    public var manualDurationLimitMinutes: Int?

    public init(
        generatedAt: Date,
        state: DSMNState,
        snapshot: SystemSnapshot,
        agents: [AgentProcess],
        decision: PowerDecision,
        manualRemainingSeconds: Int?,
        noRouteGraceRemainingSeconds: Int? = nil,
        diagnosticErrors: [String]? = nil
    ) {
        self.generatedAt = generatedAt
        self.state = state
        self.snapshot = snapshot
        self.agents = agents
        self.decision = decision
        self.manualRemainingSeconds = manualRemainingSeconds
        self.noRouteGraceRemainingSeconds = noRouteGraceRemainingSeconds
        self.diagnosticErrors = diagnosticErrors
    }
}

public struct DaemonRunReport: Codable, Equatable, Sendable {
    public var generatedAt: Date
    public var status: StatusReport
    public var operation: PowerOperationResult?
    public var operations: [PowerOperationResult]
    public var stateChanged: Bool

    public init(
        generatedAt: Date,
        status: StatusReport,
        operation: PowerOperationResult?,
        operations: [PowerOperationResult]? = nil,
        stateChanged: Bool
    ) {
        self.generatedAt = generatedAt
        self.status = status
        self.operation = operation
        self.operations = operations ?? operation.map { [$0] } ?? []
        self.stateChanged = stateChanged
    }

    private enum CodingKeys: String, CodingKey {
        case generatedAt
        case status
        case operation
        case operations
        case stateChanged
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        generatedAt = try container.decode(Date.self, forKey: .generatedAt)
        status = try container.decode(StatusReport.self, forKey: .status)
        operation = try container.decodeIfPresent(PowerOperationResult.self, forKey: .operation)
        operations = try container.decodeIfPresent([PowerOperationResult].self, forKey: .operations)
            ?? operation.map { [$0] }
            ?? []
        stateChanged = try container.decode(Bool.self, forKey: .stateChanged)
    }
}

public struct DSMNController: Sendable {
    public var store: StateStore
    public var detector: AgentDetector
    public var processListing: any ProcessListing
    public var snapshotProvider: any SystemSnapshotProviding
    public var decisionEngine: PowerDecisionEngine

    public init(
        store: StateStore,
        detector: AgentDetector = AgentDetector(),
        processListing: any ProcessListing = PSProcessListing(),
        snapshotProvider: any SystemSnapshotProviding = MacSystemSnapshotProvider(),
        decisionEngine: PowerDecisionEngine = PowerDecisionEngine()
    ) {
        self.store = store
        self.detector = detector
        self.processListing = processListing
        self.snapshotProvider = snapshotProvider
        self.decisionEngine = decisionEngine
    }

    public func status(now: Date = Date()) throws -> StatusReport {
        try status(telemetry: collectTelemetry(now: now), now: now)
    }

    public func status(telemetry: ControllerTelemetry, now: Date = Date()) throws -> StatusReport {
        makeStatus(state: try store.load(), telemetry: telemetry, now: now)
    }

    public func collectTelemetry(now: Date = Date()) -> ControllerTelemetry {
        var errors: [String] = []
        let snapshot: SystemSnapshot
        do { snapshot = try snapshotProvider.snapshot(now: now) }
        catch {
            snapshot = SystemSnapshot(now: now)
            errors.append("System snapshot unavailable: \(error.localizedDescription)")
        }
        let agents: [AgentProcess]
        do { agents = try detector.detect(using: processListing) }
        catch {
            agents = []
            errors.append("Agent process listing unavailable: \(error.localizedDescription)")
        }
        return ControllerTelemetry(snapshot: snapshot, agents: agents, diagnosticErrors: errors)
    }

    public func enableManual(
        minutes: Int,
        now: Date = Date(),
        extendOnly: Bool = false,
        requester: ActivationRequester? = nil
    ) throws -> StatusReport {
        _ = try enableManualIntent(minutes: minutes, now: now, extendOnly: extendOnly, requester: requester)
        return try status(now: now)
    }

    @discardableResult
    public func enableManualIntent(
        minutes: Int,
        now: Date = Date(),
        extendOnly: Bool = false,
        requester: ActivationRequester? = nil
    ) throws -> DSMNState {
        guard minutes > 0 else {
            throw DSMNError.invalidDuration("minutes must be greater than 0")
        }

        guard minutes <= decisionEngine.policy.maxManualDurationMinutes else {
            throw DSMNError.invalidDuration("minutes must be <= \(decisionEngine.policy.maxManualDurationMinutes)")
        }

        var state = try store.load()
        let requestedUntil = now.addingTimeInterval(TimeInterval(minutes * 60))
        if extendOnly, let manualUntil = state.manualUntil, manualUntil > requestedUntil {
            if let requester {
                state.recordRequester(requester, at: now)
                state.updatedAt = now
                try store.save(state)
            }

            return state
        }

        if !state.manualIsActive(at: now) { state.noRouteUnavailableSince = nil }
        state.manualUntil = requestedUntil
        state.lastActivationReason = extendOnly ? "manual_lease" : "manual_timer"
        if let requester {
            state.recordRequester(requester, at: now)
        } else {
            state.lastRequester = nil
        }
        state.lastStopReason = nil
        state.updatedAt = now
        try store.save(state)
        return state
    }

    /// Called under the helper's operation lock, so concurrent hooks cannot be lost.
    @discardableResult
    public func addManualTimeIntent(
        minutes: Int,
        now: Date = Date(),
        requester: ActivationRequester? = nil
    ) throws -> DSMNState {
        let maximum = decisionEngine.policy.maxManualDurationMinutes
        _ = try ManualDuration.validate(minutes, maximum: maximum)
        var state = try store.load()
        let wasActive = state.manualIsActive(at: now)
        let base = max(now, state.manualUntil ?? now)
        let until = base.addingTimeInterval(TimeInterval(minutes * 60))
        guard until <= now.addingTimeInterval(TimeInterval(maximum * 60)) else {
            throw DSMNError.invalidDuration("Adding this duration would exceed \(ManualDuration.label(maximum)) remaining. Choose less time or replace the timer.")
        }
        if !wasActive { state.noRouteUnavailableSince = nil }
        state.manualUntil = until
        state.lastActivationReason = "manual_timer"
        if let requester { state.recordRequester(requester, at: now) }
        state.lastStopReason = nil
        state.updatedAt = now
        try store.save(state)
        return state
    }

    public func stop(now: Date = Date()) throws -> StatusReport {
        _ = try stopIntent(now: now)
        return try status(now: now)
    }

    @discardableResult
    public func stopIntent(now: Date = Date()) throws -> DSMNState {
        var state = try store.load()
        state.manualUntil = nil
        state.noRouteUnavailableSince = nil
        state.lidOpenedAt = nil
        state.lastLidClosed = nil
        state.lastStopReason = "user_stop"
        state.updatedAt = now
        try store.save(state)
        return state
    }

    public func repairState(now: Date = Date()) throws -> StatusReport {
        var state = try store.load()
        state.manualUntil = nil
        state.ownsSleepDisable = false
        state.noRouteUnavailableSince = nil
        state.lidOpenedAt = nil
        state.lastLidClosed = nil
        state.lastStopReason = "repair"
        state.updatedAt = now
        try store.save(state)
        return makeStatus(state: state, telemetry: collectTelemetry(now: now), now: now)
    }

    public func repair(
        powerManager: any PowerManaging,
        liveSleepDisabled: Bool? = nil,
        now: Date = Date()
    ) throws -> DaemonRunReport {
        let report = try repair(
            powerManager: powerManager,
            telemetry: .unavailable(at: now),
            liveSleepDisabled: liveSleepDisabled,
            now: now
        )
        let telemetry = collectTelemetry(now: now)
        return try finishRelease(report, powerManager: powerManager, telemetry: telemetry, sleepSnapshot: telemetry.snapshot, now: now)
    }

    public func repair(
        powerManager: any PowerManaging,
        telemetry: ControllerTelemetry,
        liveSleepDisabled: Bool? = nil,
        now: Date = Date()
    ) throws -> DaemonRunReport {
        let originalState = try store.load()
        var nextState = originalState
        nextState.manualUntil = nil
        nextState.noRouteUnavailableSince = nil
        nextState.lidOpenedAt = nil
        nextState.lastLidClosed = nil
        nextState.lastStopReason = "repair"
        nextState.updatedAt = now
        // End the lease before attempting cleanup, but retain responsibility for
        // an owned lock if launching pmset or persisting its result fails.
        try store.save(nextState)

        var operations: [PowerOperationResult] = []
        if originalState.ownsSleepDisable || liveSleepDisabled == true {
            operations = try releaseSleepDisable(
                powerManager: powerManager,
                state: &nextState,
                reason: "release:repair",
                stopReason: "repair",
                now: now
            )
        }

        return DaemonRunReport(
            generatedAt: now,
            status: makeStatus(state: nextState, telemetry: telemetry, now: now),
            operation: operations.first,
            operations: operations,
            stateChanged: nextState != originalState
        )
    }

    public func reconcile(
        powerManager: any PowerManaging,
        liveSleepDisabled: Bool? = nil,
        now: Date = Date()
    ) throws -> DaemonRunReport {
        let mandatory = try needsMandatoryRelease(now: now)
        let telemetry = mandatory ? .unavailable(at: now) : collectTelemetry(now: now)
        let report = try reconcile(
            powerManager: powerManager,
            telemetry: telemetry,
            liveSleepDisabled: liveSleepDisabled,
            updateTracking: !mandatory,
            now: now
        )
        let finalTelemetry = mandatory ? collectTelemetry(now: now) : telemetry
        let sleepSnapshot = mandatory ? finalTelemetry.snapshot :
            ((report.operation?.action == .enableSleep && report.operation?.succeeded == true)
                ? (try? snapshotProvider.sleepSnapshot(now: now)) : nil)
        return try finishRelease(report, powerManager: powerManager, telemetry: finalTelemetry, sleepSnapshot: sleepSnapshot, now: now)
    }

    public func needsMandatoryRelease(now: Date = Date()) throws -> Bool {
        let state = try store.load()
        return state.ownsSleepDisable && (
            !state.manualIsActive(at: now)
                || state.noRouteGraceRemainingSeconds(at: now, graceSeconds: decisionEngine.policy.noRouteGraceSeconds) == 0
        )
    }

    /// Uses already-collected facts only. The caller serializes state/power
    /// operations and performs optional collection and post-release sleep later.
    public func reconcile(
        powerManager: any PowerManaging,
        telemetry: ControllerTelemetry,
        liveSleepDisabled: Bool? = nil,
        updateTracking: Bool = true,
        now: Date = Date()
    ) throws -> DaemonRunReport {
        let originalState = try store.load()
        let agents = telemetry.agents
        var snapshot = telemetry.snapshot
        snapshot.now = now
        let previousLidClosed = originalState.lastLidClosed
        var evaluatedState = originalState
        if updateTracking { evaluatedState.syncSnapshotTracking(with: telemetry.snapshot) }

        // A critical thermal event ends the lease; cooling down must not restart it.
        if snapshot.thermalCondition == .critical, evaluatedState.manualIsActive(at: now) {
            evaluatedState.manualUntil = nil
            evaluatedState.lastStopReason = "thermal_critical"
            if evaluatedState != originalState { try store.save(evaluatedState) }
        }

        if let manualUntil = evaluatedState.manualUntil, manualUntil <= now {
            evaluatedState.manualUntil = nil
            evaluatedState.lastStopReason = "manual_expired"
        }
        if !evaluatedState.manualIsActive(at: now) { evaluatedState.noRouteUnavailableSince = nil }

        let decision = decisionEngine.evaluate(state: evaluatedState, agents: agents, snapshot: snapshot)

        var nextState = evaluatedState
        var operation: PowerOperationResult?
        var operations: [PowerOperationResult] = []

        if decision.shouldPreventSleep && !originalState.ownsSleepDisable {
            operation = try powerManager.setSleepDisabled(true)
            if let operation {
                operations.append(operation)
                nextState.recordPowerOperation(
                    operation,
                    at: now,
                    reason: powerOperationReason(prefix: "enable", decision: decision, state: nextState)
                )
            }
            if operation?.succeeded == true {
                nextState.ownsSleepDisable = true
                nextState.lastActivationReason = decision.reasons.joined(separator: ",")
                nextState.lastStopReason = nil
                // The following display operation may fail or time out. Keep
                // the owned lock and its lease recoverable before attempting it.
                nextState.updatedAt = now
                try store.save(nextState)
            }
        } else if shouldReleaseSleepDisable(
            decision: decision,
            originalState: originalState,
            liveSleepDisabled: liveSleepDisabled
        ) {
            let stopReason = ["manual_expired", "repair"].contains(nextState.lastStopReason ?? "")
                ? nextState.lastStopReason
                : decision.stopReason
            operations = try releaseSleepDisable(
                powerManager: powerManager,
                state: &nextState,
                reason: powerOperationReason(prefix: "release", decision: decision, state: nextState),
                stopReason: stopReason,
                now: now
            )
            operation = operations.first
        }

        // Cached command/deadline facts cannot establish a current lid-close
        // edge. System-lock changes remain immediate; display sleep waits for
        // a newly collected observation that is also eligible for tracking.
        if updateTracking && shouldRequestDisplaySleepNowForClosedLid(
            decision: decision,
            snapshot: snapshot,
            previousLidClosed: previousLidClosed,
            state: nextState
        ) {
            let displayOperation = try powerManager.requestDisplaySleepNow()
            if operation == nil {
                operation = displayOperation
            }
            operations.append(displayOperation)
            nextState.recordPowerOperation(
                displayOperation,
                at: now,
                reason: "closed_lid_display_sleep"
            )
        }

        if nextState != originalState {
            nextState.updatedAt = now
            try store.save(nextState)
        }

        let status = makeStatus(state: nextState, telemetry: telemetry, now: now)

        return DaemonRunReport(
            generatedAt: now,
            status: status,
            operation: operation,
            operations: operations,
            stateChanged: nextState != originalState
        )
    }

    private func makeStatus(state: DSMNState, telemetry: ControllerTelemetry, now: Date) -> StatusReport {
        var evaluationSnapshot = telemetry.snapshot
        evaluationSnapshot.now = now
        let decision = decisionEngine.evaluate(state: state, agents: telemetry.agents, snapshot: evaluationSnapshot)
        return StatusReport(
            generatedAt: now,
            state: state,
            snapshot: telemetry.snapshot,
            agents: telemetry.agents,
            decision: decision,
            manualRemainingSeconds: state.manualRemainingSeconds(at: now),
            noRouteGraceRemainingSeconds: state.noRouteGraceRemainingSeconds(
                at: now,
                graceSeconds: decisionEngine.policy.noRouteGraceSeconds
            ),
            diagnosticErrors: telemetry.diagnosticErrors.isEmpty ? nil : telemetry.diagnosticErrors
        )
    }

    private func releaseSleepDisable(
        powerManager: any PowerManaging,
        state: inout DSMNState,
        reason: String,
        stopReason: String?,
        now: Date
    ) throws -> [PowerOperationResult] {
        let release = try powerManager.setSleepDisabled(false)
        state.recordPowerOperation(release, at: now, reason: reason)
        if release.succeeded {
            state.ownsSleepDisable = false
            state.lastStopReason = stopReason
        }
        state.updatedAt = now
        // Persist both failed attempts and successful ownership changes. In
        // particular, sleepnow must never run before the release is saved.
        try store.save(state)

        return [release]
    }

    public func completeReleaseSleep(
        powerManager: any PowerManaging,
        snapshot: SystemSnapshot,
        now: Date = Date()
    ) throws -> PowerOperationResult? {
        var state = try store.load()
        guard !state.ownsSleepDisable, snapshot.lidClosed == true, snapshot.powerSource == .battery else { return nil }
        let sleep = try powerManager.requestSleepNow()
        state.recordPowerOperation(sleep, at: now, reason: "closed_lid_release")
        state.updatedAt = now
        try store.save(state)
        return sleep
    }

    private func finishRelease(
        _ report: DaemonRunReport,
        powerManager: any PowerManaging,
        telemetry: ControllerTelemetry,
        sleepSnapshot: SystemSnapshot?,
        now: Date
    ) throws -> DaemonRunReport {
        var report = report
        if report.operation?.action == .enableSleep, report.operation?.succeeded == true,
           let sleepSnapshot, sleepSnapshot.now >= report.generatedAt,
           let sleep = try completeReleaseSleep(powerManager: powerManager, snapshot: sleepSnapshot, now: now) {
            report.operations.append(sleep)
        }
        report.status = try status(telemetry: telemetry, now: now)
        return report
    }

    private func shouldRequestDisplaySleepNowForClosedLid(
        decision: PowerDecision,
        snapshot: SystemSnapshot,
        previousLidClosed: Bool?,
        state: DSMNState
    ) -> Bool {
        decision.shouldPreventSleep
            && state.ownsSleepDisable
            && snapshot.lidClosed == true
            && previousLidClosed != true
    }

    private func powerOperationReason(
        prefix: String,
        decision: PowerDecision,
        state: DSMNState
    ) -> String {
        let reason = decision.reasons.first
            ?? state.lastStopReason
            ?? decision.stopReason
            ?? "unknown"

        return "\(prefix):\(reason)"
    }

    private func shouldReleaseSleepDisable(
        decision: PowerDecision,
        originalState: DSMNState,
        liveSleepDisabled: Bool?
    ) -> Bool {
        guard !decision.shouldPreventSleep else {
            return false
        }

        if originalState.ownsSleepDisable {
            return true
        }

        return liveSleepDisabled == true && hasDsmnPowerHistory(originalState)
    }

    private func hasDsmnPowerHistory(_ state: DSMNState) -> Bool {
        state.manualUntil != nil
            || state.lastActivationReason != nil
            || state.lastRequester != nil
            || !state.recentRequesters.isEmpty
            || !state.triggerHistory.isEmpty
            || !state.triggerActivityBuckets.isEmpty
    }
}

public struct StaticSystemSnapshotProvider: SystemSnapshotProviding {
    public var value: SystemSnapshot

    public init(_ value: SystemSnapshot) {
        self.value = value
    }

    public func snapshot(now: Date) throws -> SystemSnapshot {
        var snapshot = value
        snapshot.now = now
        return snapshot
    }
}

public struct StaticProcessListing: ProcessListing {
    public var processes: [RunningProcess]

    public init(_ processes: [RunningProcess]) {
        self.processes = processes
    }

    public func listProcesses() throws -> [RunningProcess] {
        processes
    }
}
