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
        guard let auditTokenValue = XPCConnectionPrivateAPI.auditToken(from: connection) else {
            return .rejectedUnsupportedClient
        }

        var auditToken = auditTokenValue
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

/// Reads NSXPCConnection's private `auditToken` without declaring an `@objc auditToken` member
/// (that collides with the runtime selector and can crash when the getter is invoked).
private enum XPCConnectionPrivateAPI {
    private static let auditTokenSelector = NSSelectorFromString("auditToken")

    static func auditToken(from connection: NSXPCConnection) -> audit_token_t? {
        guard connection.responds(to: auditTokenSelector) else {
            return nil
        }

        guard let method = class_getInstanceMethod(NSXPCConnection.self, auditTokenSelector) else {
            return nil
        }

        typealias AuditTokenGetter = @convention(c) (AnyObject, Selector) -> audit_token_t
        let implementation = method_getImplementation(method)
        let getter = unsafeBitCast(implementation, to: AuditTokenGetter.self)
        return getter(connection, auditTokenSelector)
    }
}