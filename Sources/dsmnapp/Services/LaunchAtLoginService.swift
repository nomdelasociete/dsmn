import Foundation
import ServiceManagement

enum LaunchAtLoginStatus: String, Equatable {
    case notRegistered
    case enabled
    case requiresApproval
    case notFound

    var isEnabled: Bool {
        self == .enabled
    }

    var displayName: String {
        switch self {
        case .notRegistered:
            "off"
        case .enabled:
            "on"
        case .requiresApproval:
            "approval required"
        case .notFound:
            "not found"
        }
    }
}

@MainActor
final class LaunchAtLoginService {
    var status: LaunchAtLoginStatus {
        LaunchAtLoginStatus(SMAppService.mainApp.status)
    }

    func setEnabled(_ isEnabled: Bool) throws -> LaunchAtLoginStatus {
        if isEnabled {
            try SMAppService.mainApp.register()
        } else {
            try SMAppService.mainApp.unregister()
        }

        return status
    }

    func openSettings() {
        SMAppService.openSystemSettingsLoginItems()
    }
}

private extension LaunchAtLoginStatus {
    init(_ status: SMAppService.Status) {
        switch status {
        case .notRegistered:
            self = .notRegistered
        case .enabled:
            self = .enabled
        case .requiresApproval:
            self = .requiresApproval
        case .notFound:
            self = .notFound
        @unknown default:
            self = .notFound
        }
    }
}
