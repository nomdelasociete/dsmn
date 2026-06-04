import Foundation
import Security

public enum DSMNXPCClientAuthentication {
    public enum ValidationResult: Equatable, Sendable {
        case accepted
        case rejectedUnsigned
        case rejectedRequirement(OSStatus)
        case rejectedAPIFailure(OSStatus)
        case rejectedUnsupportedClient
    }

    /// Code signing requirement for trusted dsmn XPC clients (app + embedded CLI).
    public static var codeSigningRequirement: String {
        let identifiers = DSMNServiceConstants.trustedXPCClientBundleIdentifiers
            .map { #"identifier "\#($0)""# }
            .joined(separator: " or ")

        return "(anchor apple generic and certificate leaf[subject.OU] = \"\(DSMNServiceConstants.developmentTeamID)\") and (\(identifiers))"
    }

    public static func validate(connection: NSXPCConnection) -> ValidationResult {
        let auditTokenSelector = NSSelectorFromString("auditToken")
        guard connection.responds(to: auditTokenSelector) else {
            return .rejectedUnsupportedClient
        }

        var auditToken = connection.auditToken
        let auditTokenData = Data(bytes: &auditToken, count: MemoryLayout<audit_token_t>.size)
        let attributes: [String: Any] = [
            kSecGuestAttributeAudit as String: auditTokenData
        ]

        var guestCode: SecCode?
        let guestStatus = SecCodeCopyGuestWithAttributes(
            nil,
            attributes as CFDictionary,
            SecCSFlags(),
            &guestCode
        )
        guard guestStatus == errSecSuccess, let guestCode else {
            return guestStatus == errSecCSUnsigned ? .rejectedUnsigned : .rejectedAPIFailure(guestStatus)
        }

        var requirement: SecRequirement?
        let requirementStatus = SecRequirementCreateWithString(
            codeSigningRequirement as CFString,
            SecCSFlags(),
            &requirement
        )
        guard requirementStatus == errSecSuccess, let requirement else {
            return .rejectedAPIFailure(requirementStatus)
        }

        var cfError: Unmanaged<CFError>?
        let validityStatus = SecCodeCheckValidityWithErrors(
            guestCode,
            SecCSFlags(),
            requirement,
            &cfError
        )
        guard validityStatus == errSecSuccess else {
            if validityStatus == errSecCSUnsigned {
                return .rejectedUnsigned
            }
            return .rejectedRequirement(validityStatus)
        }

        return .accepted
    }

    public static func rejectionLogMessage(for result: ValidationResult) -> String? {
        switch result {
        case .accepted:
            return nil
        case .rejectedUnsigned:
            return "dsmnd: rejected unsigned XPC client"
        case .rejectedRequirement(let status):
            return "dsmnd: rejected XPC client (code signing status \(status)); requirement: \(codeSigningRequirement)"
        case .rejectedAPIFailure(let status):
            return "dsmnd: rejected XPC client (SecCode API status \(status))"
        case .rejectedUnsupportedClient:
            return "dsmnd: rejected XPC client (audit token unavailable)"
        }
    }

    public static func logRejection(_ result: ValidationResult, to output: UnsafeMutablePointer<FILE>? = stderr) {
        guard let message = rejectionLogMessage(for: result) else {
            return
        }
        fputs("\(message)\n", output)
    }
}

private extension NSXPCConnection {
    @objc var auditToken: audit_token_t {
        typealias AuditTokenGetter = @convention(c) (NSXPCConnection, Selector) -> audit_token_t
        let selector = NSSelectorFromString("auditToken")
        let implementation = class_getMethodImplementation(NSXPCConnection.self, selector)
        let getter = unsafeBitCast(implementation, to: AuditTokenGetter.self)
        return getter(self, selector)
    }
}