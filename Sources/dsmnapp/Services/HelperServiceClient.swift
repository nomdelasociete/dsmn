import DSMNCore
import Foundation
import ServiceManagement

enum HelperRegistrationStatus: String, Equatable {
    case notRegistered
    case enabled
    case requiresApproval
    case notFound

    var displayName: String {
        switch self {
        case .notRegistered:
            "not installed"
        case .enabled:
            "enabled"
        case .requiresApproval:
            "approval required"
        case .notFound:
            "not found"
        }
    }
}

@MainActor
final class HelperServiceClient {
    private let helperClient = DSMNHelperXPCClient()

    var registrationStatus: HelperRegistrationStatus {
        HelperRegistrationStatus(SMAppService.daemon(plistName: DSMNServiceConstants.helperPlistName).status)
    }

    func register() throws -> HelperRegistrationStatus {
        try SMAppService.daemon(plistName: DSMNServiceConstants.helperPlistName).register()
        return registrationStatus
    }

    func unregister() throws -> HelperRegistrationStatus {
        try SMAppService.daemon(plistName: DSMNServiceConstants.helperPlistName).unregister()
        return registrationStatus
    }

    func openLoginItemsSettings() {
        SMAppService.openSystemSettingsLoginItems()
    }

    func status() async throws -> StatusReport {
        let client = helperClient
        return try await Task.detached {
            try client.status()
        }.value
    }

    func enableManual(minutes: Int, requester: ActivationRequester? = nil) async throws -> StatusReport {
        let client = helperClient
        return try await Task.detached {
            try client.enableManual(minutes: minutes, requester: requester)
        }.value
    }

    func setAuto(_ enabled: Bool) async throws -> StatusReport {
        let client = helperClient
        return try await Task.detached {
            try client.setAuto(enabled)
        }.value
    }

    func toggleAuto() async throws -> StatusReport {
        let client = helperClient
        return try await Task.detached {
            try client.toggleAuto()
        }.value
    }

    func stop() async throws -> StatusReport {
        let client = helperClient
        return try await Task.detached {
            try client.stop()
        }.value
    }
}

private extension HelperRegistrationStatus {
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
