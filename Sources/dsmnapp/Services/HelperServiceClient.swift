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

struct HelperRuntimeInfo: Equatable {
    var parentBundleVersion: Int?
    var isRunning: Bool
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

    func updateRegistration() throws -> HelperRegistrationStatus {
        let service = SMAppService.daemon(plistName: DSMNServiceConstants.helperPlistName)
        try service.unregister()
        try service.register()
        return registrationStatus
    }

    func openLoginItemsSettings() {
        SMAppService.openSystemSettingsLoginItems()
    }

    func runtimeInfo() async -> HelperRuntimeInfo {
        await Task.detached(priority: .utility) {
            Self.readRuntimeInfo()
        }.value
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

    func stop() async throws -> StatusReport {
        let client = helperClient
        return try await Task.detached {
            try client.stop()
        }.value
    }

    func addManualTime(minutes: Int) async throws -> StatusReport {
        let client = helperClient
        return try await Task.detached {
            try client.addManualTime(minutes: minutes)
        }.value
    }

    func repair() async throws -> StatusReport {
        let client = helperClient
        return try await Task.detached {
            try client.repair()
        }.value
    }

    nonisolated private static func readRuntimeInfo() -> HelperRuntimeInfo {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        process.arguments = ["print", "system/\(DSMNServiceConstants.helperLabel)"]

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()

        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            return HelperRuntimeInfo(parentBundleVersion: nil, isRunning: false)
        }

        guard process.terminationStatus == 0 else {
            return HelperRuntimeInfo(parentBundleVersion: nil, isRunning: false)
        }

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        guard let output = String(data: data, encoding: .utf8) else {
            return HelperRuntimeInfo(parentBundleVersion: nil, isRunning: false)
        }

        let parentBundleVersion = output
            .split(separator: "\n")
            .first { $0.contains("parent bundle version =") }
            .flatMap { line -> Int? in
                line.split(separator: "=")
                    .last
                    .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                    .flatMap(Int.init)
            }
        let isRunning = output.contains("state = running")
            || output.contains("job state = running")

        return HelperRuntimeInfo(parentBundleVersion: parentBundleVersion, isRunning: isRunning)
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
