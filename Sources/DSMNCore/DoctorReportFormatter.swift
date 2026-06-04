import Foundation

public enum DoctorStatusSource: String, Codable, Equatable, Sendable {
    case helper
    case local

    public var displayName: String {
        switch self {
        case .helper:
            "helper"
        case .local:
            "local fallback"
        }
    }
}

public struct DoctorReportFormatter: Sendable {
    public static func format(
        report: StatusReport,
        source: DoctorStatusSource,
        liveSleepDisabled: Bool?,
        hookFallback: AgentHookFallbackStatus? = nil
    ) -> String {
        var lines: [String] = []
        lines.append("dsmn doctor")
        lines.append("Status source: \(source.displayName)")
        lines.append("Status: \(statusLabel(for: report))")
        lines.append("Timer: \(timerLabel(for: report))")
        lines.append("Power lock: \(report.state.ownsSleepDisable ? "on" : "off")")
        if let hookFallback {
            lines.append("Hook fallback: \(hookFallback.isActive ? "active" : "inactive")")
        }
        lines.append("macOS SleepDisabled: \(formatOptionalFlag(liveSleepDisabled))")
        if let hookFallbackWarning = hookFallback.flatMap({
            AgentHookLogInspector.doctorWarning(
                for: $0,
                ownsSleepDisable: report.state.ownsSleepDisable
            )
        }) {
            lines.append(hookFallbackWarning)
        }

        if let requester = report.state.lastRequester {
            lines.append("Last request: \(requester.displayText)")
            if let event = requester.event {
                lines.append("Last event: \(event)")
            }
        }

        if report.state.recentRequesters.count > 1 {
            lines.append("Recent requests:")
            for requester in report.state.recentRequesters.prefix(6) {
                if let event = requester.event {
                    lines.append("- \(requester.displayText) (\(event))")
                } else {
                    lines.append("- \(requester.displayText)")
                }
            }
        }

        lines.append("Agents detected: \(report.agents.count)")
        for agent in report.agents {
            lines.append("- \(agent.kind.displayName) pid=\(agent.pid) executable=\(agent.executable)")
        }

        lines.append("Decision: \(report.decision.shouldPreventSleep ? "prevent sleep" : "allow sleep")")
        lines.append(readinessMessage(report: report, source: source, liveSleepDisabled: liveSleepDisabled))

        return lines.joined(separator: "\n")
    }

    public static func formatRepairResult(_ report: StatusReport, source: DoctorStatusSource) -> String {
        var lines: [String] = []
        lines.append("Repair finished via \(source.displayName).")
        lines.append("Status: \(statusLabel(for: report))")
        lines.append("Power lock: \(report.state.ownsSleepDisable ? "on" : "off")")
        lines.append("Timer: \(timerLabel(for: report))")

        if let stopReason = report.state.lastStopReason {
            lines.append("Last stop reason: \(stopReason)")
        }

        if report.decision.shouldPreventSleep {
            lines.append("dsmn still wants to prevent sleep.")
        } else {
            lines.append("dsmn is not preventing sleep.")
        }

        return lines.joined(separator: "\n")
    }

    private static func statusLabel(for report: StatusReport) -> String {
        report.decision.shouldPreventSleep || manualTimerIsActive(report) ? "active" : "inactive"
    }

    private static func timerLabel(for report: StatusReport) -> String {
        guard let remaining = report.manualRemainingSeconds, remaining > 0 else {
            return "off"
        }

        return "\(formatDuration(seconds: remaining)) remaining"
    }

    private static func manualTimerIsActive(_ report: StatusReport) -> Bool {
        guard let remaining = report.manualRemainingSeconds else {
            return false
        }

        return remaining > 0
    }

    private static func formatOptionalFlag(_ value: Bool?) -> String {
        guard let value else {
            return "unknown"
        }

        return value ? "on" : "off"
    }

    private static func formatDuration(seconds: Int) -> String {
        let minutes = seconds / 60
        let remainingSeconds = seconds % 60

        if minutes >= 60 {
            let hours = minutes / 60
            let leftoverMinutes = minutes % 60
            return "\(hours)h \(leftoverMinutes)m"
        }

        if minutes > 0 {
            return "\(minutes)m \(remainingSeconds)s"
        }

        return "\(remainingSeconds)s"
    }

    private static func readinessMessage(
        report: StatusReport,
        source: DoctorStatusSource,
        liveSleepDisabled: Bool?
    ) -> String {
        if source == .local {
            return "Warning: helper unavailable; closed-lid prevention will not work."
        }

        if report.decision.shouldPreventSleep && !report.state.ownsSleepDisable {
            return "Warning: dsmn wants to prevent sleep, but the power lock is off."
        }

        if report.state.ownsSleepDisable && liveSleepDisabled == false {
            return "Warning: dsmn state says locked, but macOS SleepDisabled is off."
        }

        if report.state.ownsSleepDisable {
            return "Ready: dsmn owns the macOS power lock."
        }

        if manualTimerIsActive(report) {
            return "Ready: timer active; power lock is off until dsmn needs to prevent sleep."
        }

        return "Ready: helper works; enable a manual timer or run an agent hook to test."
    }
}
