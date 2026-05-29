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
        let safetyBlocks = safetyBlocks(for: snapshot)
        if !safetyBlocks.isEmpty {
            return PowerDecision(
                shouldPreventSleep: false,
                reasons: [],
                safetyBlocks: safetyBlocks,
                stopReason: safetyBlocks.first
            )
        }

        var reasons: [String] = []

        if state.manualIsActive(at: snapshot.now) {
            reasons.append("manual_timer")
        }

        let autoHasFreshActivity = state.autoActivityIsFresh(
            at: snapshot.now,
            maxAgeSeconds: policy.maxAutoActivityAgeSeconds
        )

        if state.autoEnabled {
            if agents.isEmpty {
                reasons.append("auto_waiting_for_agents")
            } else if autoHasFreshActivity {
                reasons.append("auto_agents_active")
            } else {
                reasons.append("auto_activity_stale")
            }
        }

        let shouldPreventSleep = state.manualIsActive(at: snapshot.now)
            || (state.autoEnabled && !agents.isEmpty && autoHasFreshActivity)

        return PowerDecision(
            shouldPreventSleep: shouldPreventSleep,
            reasons: reasons,
            safetyBlocks: [],
            stopReason: shouldPreventSleep ? nil : inactiveReason(state: state, agents: agents, at: snapshot.now)
        )
    }

    private func safetyBlocks(for snapshot: SystemSnapshot) -> [String] {
        var blocks: [String] = []

        if snapshot.powerSource == .battery,
           let batteryPercent = snapshot.batteryPercent,
           batteryPercent <= policy.minimumBatteryPercent {
            blocks.append("battery_below_threshold")
        }

        if snapshot.defaultRouteAvailable == false {
            blocks.append("network_unavailable")
        }

        return blocks
    }

    private func inactiveReason(state: DSMNState, agents: [AgentProcess], at date: Date) -> String {
        if let manualUntil = state.manualUntil, manualUntil <= date {
            return "manual_expired"
        }

        if state.autoEnabled && agents.isEmpty {
            return "auto_waiting_for_agents"
        }

        if state.autoEnabled && !state.autoActivityIsFresh(at: date, maxAgeSeconds: policy.maxAutoActivityAgeSeconds) {
            return "auto_activity_stale"
        }

        return "not_armed"
    }
}
