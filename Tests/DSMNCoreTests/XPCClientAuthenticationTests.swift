import Security
import XCTest
@testable import DSMNCore

final class XPCClientAuthenticationTests: XCTestCase {
    func testCodeSigningRequirementIncludesTeamAndBundleIdentifiers() {
        let requirement = DSMNXPCClientAuthentication.codeSigningRequirement

        XCTAssertTrue(requirement.contains(DSMNServiceConstants.developmentTeamID))
        XCTAssertTrue(requirement.contains(DSMNServiceConstants.appBundleIdentifier))
        XCTAssertTrue(requirement.contains(DSMNServiceConstants.ctlBundleIdentifier))
    }

    func testCodeSigningRequirementParsesWithSecurityFramework() {
        var requirement: SecRequirement?
        let status = SecRequirementCreateWithString(
            DSMNXPCClientAuthentication.codeSigningRequirement as CFString,
            SecCSFlags(),
            &requirement
        )

        XCTAssertEqual(status, errSecSuccess)
        XCTAssertNotNil(requirement)
    }

    func testRejectionLogMessageForUnsignedClient() {
        XCTAssertEqual(
            DSMNXPCClientAuthentication.rejectionLogMessage(for: .rejectedUnsigned),
            "dsmnd: rejected unsigned XPC client"
        )
        XCTAssertNil(DSMNXPCClientAuthentication.rejectionLogMessage(for: .accepted))
    }
}