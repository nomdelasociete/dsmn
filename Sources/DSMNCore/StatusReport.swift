import Foundation

public struct StatusReport: Codable, Equatable, Sendable {
    public var generatedAt: Date
    public var state: DSMNState
    public var snapshot: SystemSnapshot
    public var agents: [AgentProcess]
    public var decision: PowerDecision
    public var manualRemainingSeconds: Int?
    public var noRouteGraceRemainingSeconds: Int?

    public init(
        generatedAt: Date,
        state: DSMNState,
        snapshot: SystemSnapshot,
        agents: [AgentProcess],
        decision: PowerDecision,
        manualRemainingSeconds: Int?,
        noRouteGraceRemainingSeconds: Int? = nil
    ) {
        self.generatedAt = generatedAt
        self.state = state
        self.snapshot = snapshot
        self.agents = agents
        self.decision = decision
        self.manualRemainingSeconds = manualRemainingSeconds
        self.noRouteGraceRemainingSeconds = noRouteGraceRemainingSeconds
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
        let state = try store.load()
        return try makeStatus(state: state, now: now)
    }

    public func enableManual(
        minutes: Int,
        now: Date = Date(),
        extendOnly: Bool = false,
        requester: ActivationRequester? = nil
    ) throws -> StatusReport {
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

            return try makeStatus(state: state, now: now)
        }

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
        return try makeStatus(state: state, now: now)
    }

    public func stop(now: Date = Date()) throws -> StatusReport {
        var state = try store.load()
        state.manualUntil = nil
        state.noRouteUnavailableSince = nil
        state.lidOpenedAt = nil
        state.lastLidClosed = nil
        state.lastStopReason = "user_stop"
        state.updatedAt = now
        try store.save(state)
        return try makeStatus(state: state, now: now)
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
        return try makeStatus(state: state, now: now)
    }

    public func repair(
        powerManager: any PowerManaging,
        liveSleepDisabled: Bool? = nil,
        now: Date = Date()
    ) throws -> DaemonRunReport {
        let originalState = try store.load()
        var forcedRelease: PowerOperationResult?

        if originalState.ownsSleepDisable || liveSleepDisabled == true {
            forcedRelease = try powerManager.setSleepDisabled(false)
        }

        _ = try repairState(now: now)
        var report = try reconcile(powerManager: powerManager, now: now)

        if let forcedRelease {
            report = DaemonRunReport(
                generatedAt: report.generatedAt,
                status: report.status,
                operation: forcedRelease,
                operations: [forcedRelease] + report.operations,
                stateChanged: report.stateChanged || originalState != report.status.state
            )
        }

        return report
    }

    public func reconcile(
        powerManager: any PowerManaging,
        liveSleepDisabled: Bool? = nil,
        now: Date = Date()
    ) throws -> DaemonRunReport {
        let originalState = try store.load()
        let agents = try detector.detect(using: processListing)
        let snapshot = try snapshotProvider.snapshot(now: now)
        let previousLidClosed = originalState.lastLidClosed
        var evaluatedState = originalState
        evaluatedState.syncSnapshotTracking(with: snapshot)

        if let manualUntil = evaluatedState.manualUntil, manualUntil <= now {
            evaluatedState.manualUntil = nil
            evaluatedState.lastStopReason = "manual_expired"
        }

        let decision = decisionEngine.evaluate(state: evaluatedState, agents: agents, snapshot: snapshot)

        var nextState = evaluatedState
        var operation: PowerOperationResult?
        var operations: [PowerOperationResult] = []
        var shouldRequestSleepNowAfterRelease = false

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
            if operationSucceeded(operation) {
                nextState.ownsSleepDisable = true
                nextState.lastActivationReason = decision.reasons.joined(separator: ",")
                nextState.lastStopReason = nil
            }
        } else if shouldReleaseSleepDisable(
            decision: decision,
            originalState: originalState,
            liveSleepDisabled: liveSleepDisabled
        ) {
            operation = try powerManager.setSleepDisabled(false)
            if let operation {
                operations.append(operation)
                nextState.recordPowerOperation(
                    operation,
                    at: now,
                    reason: powerOperationReason(prefix: "release", decision: decision, state: nextState)
                )
            }
            if operationSucceeded(operation) {
                nextState.ownsSleepDisable = false
                nextState.lastStopReason = nextState.lastStopReason == "manual_expired"
                    ? "manual_expired"
                    : decision.stopReason
                shouldRequestSleepNowAfterRelease = shouldRequestSleepNowAfterReleasing(
                    snapshot: snapshot
                )
            }
        }

        if shouldRequestDisplaySleepNowForClosedLid(
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

        if shouldRequestSleepNowAfterRelease {
            let sleepOperation = try powerManager.requestSleepNow()
            operations.append(sleepOperation)

            var savedState = try store.load()
            savedState.recordPowerOperation(
                sleepOperation,
                at: now,
                reason: "closed_lid_release"
            )
            savedState.updatedAt = now
            try store.save(savedState)
            nextState = savedState
        }

        let finalDecision = decisionEngine.evaluate(state: nextState, agents: agents, snapshot: snapshot)
        let status = makeStatusReport(
            state: nextState,
            snapshot: snapshot,
            agents: agents,
            decision: finalDecision,
            now: now
        )

        return DaemonRunReport(
            generatedAt: now,
            status: status,
            operation: operation,
            operations: operations,
            stateChanged: nextState != originalState
        )
    }

    private func makeStatus(state: DSMNState, now: Date) throws -> StatusReport {
        let agents = try detector.detect(using: processListing)
        let snapshot = try snapshotProvider.snapshot(now: now)
        var evaluatedState = state
        evaluatedState.syncSnapshotTracking(with: snapshot)
        let decision = decisionEngine.evaluate(state: evaluatedState, agents: agents, snapshot: snapshot)
        return makeStatusReport(
            state: evaluatedState,
            snapshot: snapshot,
            agents: agents,
            decision: decision,
            now: now
        )
    }

    private func makeStatusReport(
        state: DSMNState,
        snapshot: SystemSnapshot,
        agents: [AgentProcess],
        decision: PowerDecision,
        now: Date
    ) -> StatusReport {
        StatusReport(
            generatedAt: now,
            state: state,
            snapshot: snapshot,
            agents: agents,
            decision: decision,
            manualRemainingSeconds: state.manualRemainingSeconds(at: now),
            noRouteGraceRemainingSeconds: state.noRouteGraceRemainingSeconds(
                at: now,
                graceSeconds: decisionEngine.policy.noRouteGraceSeconds
            )
        )
    }

    private func operationSucceeded(_ operation: PowerOperationResult?) -> Bool {
        guard let operation else {
            return false
        }

        return !operation.dryRun && operation.exitCode == 0
    }

    private func shouldRequestSleepNowAfterReleasing(snapshot: SystemSnapshot) -> Bool {
        snapshot.lidClosed == true && snapshot.powerSource == .battery
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
