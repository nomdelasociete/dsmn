import Foundation

public struct PowerDecision: Codable, Equatable, Sendable {
    public var shouldPreventSleep: Bool
    public var reasons: [String]
    public var safetyBlocks: [String]
    public var stopReason: String?

    public init(
        shouldPreventSleep: Bool,
        reasons: [String],
        safetyBlocks: [String],
        stopReason: String? = nil
    ) {
        self.shouldPreventSleep = shouldPreventSleep
        self.reasons = reasons
        self.safetyBlocks = safetyBlocks
        self.stopReason = stopReason
    }
}

public struct PowerDecisionEngine: Sendable {
    public var policy: SafetyPolicy

    public init(policy: SafetyPolicy = SafetyPolicy()) {
        self.policy = policy
    }

    public func evaluate(state: DSMNState, agents: [AgentProcess], snapshot: SystemSnapshot) -> PowerDecision {
        let safetyBlocks = safetyBlocks(state: state, snapshot: snapshot)
        if !safetyBlocks.isEmpty {
            return PowerDecision(
                shouldPreventSleep: false,
                reasons: [],
                safetyBlocks: safetyBlocks,
                stopReason: safetyBlocks.first
            )
        }

        var reasons: [String] = []
        let manualActive = state.manualIsActive(at: snapshot.now)

        if manualActive {
            reasons.append("manual_timer")
        }

        if manualActive, state.isWithinLidOpenGrace(at: snapshot.now, graceSeconds: policy.lidOpenGraceSeconds) {
            reasons.append("lid_open_grace")
        }

        let shouldPreventSleep = manualActive && shouldPreventSleepForManual(state: state, snapshot: snapshot)

        return PowerDecision(
            shouldPreventSleep: shouldPreventSleep,
            reasons: reasons,
            safetyBlocks: [],
            stopReason: shouldPreventSleep ? nil : inactiveReason(state: state, agents: agents, snapshot: snapshot)
        )
    }

    private func shouldPreventSleepForManual(state: DSMNState, snapshot: SystemSnapshot) -> Bool {
        guard state.manualIsActive(at: snapshot.now) else {
            return false
        }

        return true
    }

    private func safetyBlocks(state: DSMNState, snapshot: SystemSnapshot) -> [String] {
        var blocks: [String] = []

        if snapshot.powerSource == .battery,
           let batteryPercent = snapshot.batteryPercent,
           batteryPercent <= policy.minimumBatteryPercent {
            blocks.append("battery_below_threshold")
        }

        if snapshot.defaultRouteAvailable == false,
           shouldBlockForNoRoute(state: state, snapshot: snapshot) {
            blocks.append("network_unavailable")
        }

        return blocks
    }

    private func shouldBlockForNoRoute(state: DSMNState, snapshot: SystemSnapshot) -> Bool {
        guard state.manualIsActive(at: snapshot.now) else {
            return false
        }

        guard let since = state.noRouteUnavailableSince else {
            return false
        }

        let elapsed = snapshot.now.timeIntervalSince(since)
        return elapsed >= TimeInterval(policy.noRouteGraceSeconds)
    }

    private func inactiveReason(state: DSMNState, agents: [AgentProcess], snapshot: SystemSnapshot) -> String {
        if let manualUntil = state.manualUntil, manualUntil <= snapshot.now {
            return "manual_expired"
        }

        return "not_armed"
    }
}
