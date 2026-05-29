import Foundation

public struct StatusReport: Codable, Equatable, Sendable {
    public var generatedAt: Date
    public var state: DSMNState
    public var snapshot: SystemSnapshot
    public var agents: [AgentProcess]
    public var decision: PowerDecision
    public var manualRemainingSeconds: Int?

    public init(
        generatedAt: Date,
        state: DSMNState,
        snapshot: SystemSnapshot,
        agents: [AgentProcess],
        decision: PowerDecision,
        manualRemainingSeconds: Int?
    ) {
        self.generatedAt = generatedAt
        self.state = state
        self.snapshot = snapshot
        self.agents = agents
        self.decision = decision
        self.manualRemainingSeconds = manualRemainingSeconds
    }
}

public struct DaemonRunReport: Codable, Equatable, Sendable {
    public var generatedAt: Date
    public var status: StatusReport
    public var operation: PowerOperationResult?
    public var stateChanged: Bool

    public init(generatedAt: Date, status: StatusReport, operation: PowerOperationResult?, stateChanged: Bool) {
        self.generatedAt = generatedAt
        self.status = status
        self.operation = operation
        self.stateChanged = stateChanged
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
                state.lastRequester = requester.requested(at: now)
                state.updatedAt = now
                try store.save(state)
            }

            return try makeStatus(state: state, now: now)
        }

        state.manualUntil = requestedUntil
        state.lastActivationReason = extendOnly ? "manual_lease" : "manual_timer"
        state.lastRequester = requester?.requested(at: now)
        state.lastStopReason = nil
        state.updatedAt = now
        try store.save(state)
        return try makeStatus(state: state, now: now)
    }

    public func stop(now: Date = Date()) throws -> StatusReport {
        var state = try store.load()
        state.manualUntil = nil
        state.lastStopReason = "user_stop"
        state.updatedAt = now
        try store.save(state)
        return try makeStatus(state: state, now: now)
    }

    public func repairState(now: Date = Date()) throws -> StatusReport {
        var state = try store.load()
        state.manualUntil = nil
        state.ownsSleepDisable = false
        state.lastStopReason = "repair"
        state.updatedAt = now
        try store.save(state)
        return try makeStatus(state: state, now: now)
    }

    public func reconcile(powerManager: any PowerManaging, now: Date = Date()) throws -> DaemonRunReport {
        let originalState = try store.load()
        let agents = try detector.detect(using: processListing)
        let snapshot = try snapshotProvider.snapshot(now: now)
        let decision = decisionEngine.evaluate(state: originalState, agents: agents, snapshot: snapshot)

        var nextState = originalState
        var operation: PowerOperationResult?

        if let manualUntil = nextState.manualUntil, manualUntil <= now {
            nextState.manualUntil = nil
            nextState.lastStopReason = "manual_expired"
        }

        if decision.shouldPreventSleep && !originalState.ownsSleepDisable {
            operation = try powerManager.setSleepDisabled(true)
            if operationSucceeded(operation) {
                nextState.ownsSleepDisable = true
                nextState.lastActivationReason = decision.reasons.joined(separator: ",")
                nextState.lastStopReason = nil
            }
        } else if !decision.shouldPreventSleep && originalState.ownsSleepDisable {
            operation = try powerManager.setSleepDisabled(false)
            if operationSucceeded(operation) {
                nextState.ownsSleepDisable = false
                nextState.lastStopReason = decision.stopReason
            }
        }

        if nextState != originalState {
            nextState.updatedAt = now
            try store.save(nextState)
        }

        let finalDecision = decisionEngine.evaluate(state: nextState, agents: agents, snapshot: snapshot)
        let status = StatusReport(
            generatedAt: now,
            state: nextState,
            snapshot: snapshot,
            agents: agents,
            decision: finalDecision,
            manualRemainingSeconds: nextState.manualRemainingSeconds(at: now)
        )

        return DaemonRunReport(
            generatedAt: now,
            status: status,
            operation: operation,
            stateChanged: nextState != originalState
        )
    }

    private func makeStatus(state: DSMNState, now: Date) throws -> StatusReport {
        let agents = try detector.detect(using: processListing)
        let snapshot = try snapshotProvider.snapshot(now: now)
        let decision = decisionEngine.evaluate(state: state, agents: agents, snapshot: snapshot)
        return StatusReport(
            generatedAt: now,
            state: state,
            snapshot: snapshot,
            agents: agents,
            decision: decision,
            manualRemainingSeconds: state.manualRemainingSeconds(at: now)
        )
    }

    private func operationSucceeded(_ operation: PowerOperationResult?) -> Bool {
        guard let operation else {
            return false
        }

        return !operation.dryRun && operation.exitCode == 0
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
