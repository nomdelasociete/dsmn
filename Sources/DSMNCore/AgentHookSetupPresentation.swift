import Foundation

public enum AgentHookSetupAction: String, Codable, Equatable, Sendable {
    case install
    case update
    case reinstall

    public var buttonTitle: String {
        switch self {
        case .install:
            "Install Hooks"
        case .update:
            "Update Hooks"
        case .reinstall:
            "Reinstall"
        }
    }

    public var busyTitle: String {
        switch self {
        case .install:
            "Installing..."
        case .update:
            "Updating..."
        case .reinstall:
            "Reinstalling..."
        }
    }

    public var busyStatusTitle: String {
        switch self {
        case .install:
            "Installing hooks"
        case .update:
            "Updating hooks"
        case .reinstall:
            "Reinstalling hooks"
        }
    }

    public var failureStatusTitle: String {
        switch self {
        case .install:
            "Hook install failed"
        case .update:
            "Hook update failed"
        case .reinstall:
            "Hook reinstall failed"
        }
    }
}

public enum AgentHooksSetupStatus: Equatable, Sendable {
    case checking
    case installing(AgentHookSetupAction)
    case ready(String)
    case outdated(String)
    case partial(Int, Int)
    case failed(String)

    public var displayName: String {
        switch self {
        case .checking:
            "Checking hooks"
        case let .installing(action):
            action.busyStatusTitle
        case let .ready(message):
            message
        case let .outdated(message):
            message
        case let .partial(installedCount, total):
            "\(installedCount)/\(total) hook targets installed"
        case let .failed(message):
            message
        }
    }

    public var isReady: Bool {
        if case .ready = self {
            return true
        }

        return false
    }

    public var isBusy: Bool {
        if case .checking = self {
            return true
        }

        if case .installing = self {
            return true
        }

        return false
    }

    public var isInstalling: Bool {
        if case .installing = self {
            return true
        }

        return false
    }

    public var needsUpdate: Bool {
        if case .outdated = self {
            return true
        }

        return false
    }
}

public enum AgentHookActionResultState: String, Codable, Equatable, Sendable {
    case updated
    case unchanged
    case failed

    public var displayName: String {
        switch self {
        case .updated:
            "updated"
        case .unchanged:
            "unchanged"
        case .failed:
            "failed"
        }
    }
}

public struct AgentHookActionResultRow: Identifiable, Codable, Equatable, Sendable {
    public var id: String {
        target
    }

    public var target: String
    public var targetDisplayName: String
    public var state: AgentHookActionResultState
    public var message: String

    public init(
        target: String,
        targetDisplayName: String,
        state: AgentHookActionResultState,
        message: String
    ) {
        self.target = target
        self.targetDisplayName = targetDisplayName
        self.state = state
        self.message = message
    }
}

public enum AgentHookSetupPresentation: Sendable {
    public static func action(for status: AgentHooksSetupStatus) -> AgentHookSetupAction? {
        switch status {
        case .checking, .installing:
            nil
        case .ready:
            .reinstall
        case .outdated:
            .update
        case .partial, .failed:
            .install
        }
    }

    public static func actionTitle(for status: AgentHooksSetupStatus) -> String {
        switch status {
        case .checking:
            "Checking..."
        case let .installing(action):
            action.busyTitle
        case .ready:
            AgentHookSetupAction.reinstall.buttonTitle
        case .outdated:
            AgentHookSetupAction.update.buttonTitle
        case .partial, .failed:
            AgentHookSetupAction.install.buttonTitle
        }
    }

    public static func startedStatus(for action: AgentHookSetupAction) -> AgentHooksSetupStatus {
        .installing(action)
    }

    public static func completedStatus(
        for action: AgentHookSetupAction,
        reports: [AgentHookInstallReport]
    ) -> AgentHooksSetupStatus {
        let rows = resultRows(for: action, reports: reports)
        if rows.contains(where: { $0.state == .failed }) {
            return .failed(action.failureStatusTitle)
        }

        let changedTargets = rows
            .filter { $0.state == .updated }
            .map(\.targetDisplayName)

        guard !changedTargets.isEmpty else {
            return .ready("Hooks already current")
        }

        let targetList = list(changedTargets)
        switch action {
        case .install:
            return .ready("Hooks installed for \(targetList)")
        case .update:
            return .ready("Hooks updated for \(targetList)")
        case .reinstall:
            return .ready("Hooks reinstalled for \(targetList)")
        }
    }

    public static func resultRows(
        for action: AgentHookSetupAction,
        reports: [AgentHookInstallReport]
    ) -> [AgentHookActionResultRow] {
        reports
            .filter { AgentHookTarget(rawValue: $0.target) != nil }
            .map { report in
                let target = AgentHookTarget(rawValue: report.target)
                let state: AgentHookActionResultState = report.succeeded
                    ? (report.changed ? .updated : .unchanged)
                    : .failed

                return AgentHookActionResultRow(
                    target: report.target,
                    targetDisplayName: target?.displayName ?? report.target,
                    state: state,
                    message: message(for: action, report: report, state: state)
                )
            }
    }

    private static func message(
        for action: AgentHookSetupAction,
        report: AgentHookInstallReport,
        state: AgentHookActionResultState
    ) -> String {
        switch state {
        case .updated:
            switch action {
            case .install:
                "installed"
            case .update:
                "updated"
            case .reinstall:
                "reinstalled"
            }
        case .unchanged:
            "unchanged"
        case .failed:
            report.error ?? report.message
        }
    }

    private static func list(_ values: [String]) -> String {
        switch values.count {
        case 0:
            ""
        case 1:
            values[0]
        case 2:
            values.joined(separator: " and ")
        default:
            "\(values.dropLast().joined(separator: ", ")), and \(values.last ?? "")"
        }
    }
}
