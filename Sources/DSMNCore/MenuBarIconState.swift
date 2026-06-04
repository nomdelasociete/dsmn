import Foundation

public enum MenuBarIconState: String, Codable, Equatable, Sendable {
    case loading
    case off
    case warning
    case manualActive

    public static func resolve(
        report: StatusReport?,
        errorMessage: String?,
        hookFallbackActive: Bool = false,
        setupNeedsAttention: Bool = false
    ) -> MenuBarIconState {
        if errorMessage != nil, report == nil {
            return .warning
        }

        guard let report else {
            return .loading
        }

        if hookFallbackActive && !report.state.ownsSleepDisable {
            return .warning
        }

        if report.decision.shouldPreventSleep && !report.state.ownsSleepDisable {
            return .warning
        }

        if report.decision.shouldPreventSleep || report.state.manualIsActive(at: report.generatedAt) {
            return .manualActive
        }

        if setupNeedsAttention {
            return .warning
        }

        return .off
    }
}
