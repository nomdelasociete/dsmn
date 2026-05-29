import Foundation

public enum MenuBarIconState: String, Codable, Equatable, Sendable {
    case loading
    case off
    case warning
    case manualActive

    public var systemImageName: String {
        switch self {
        case .loading, .off:
            "figure.run"
        case .warning:
            "exclamationmark.triangle.fill"
        case .manualActive:
            "timer.circle.fill"
        }
    }

    public static func resolve(report: StatusReport?, errorMessage: String?) -> MenuBarIconState {
        if errorMessage != nil, report == nil {
            return .warning
        }

        guard let report else {
            return .loading
        }

        if report.decision.shouldPreventSleep && !report.state.ownsSleepDisable {
            return .warning
        }

        if report.decision.shouldPreventSleep {
            return .manualActive
        }

        return .off
    }
}
