import Foundation
import XCTest

final class HelperPackagingTests: XCTestCase {
    func testLaunchDaemonPlistUsesLaunchServicesBundleProgram() throws {
        let plistURL = repositoryRoot()
            .appendingPathComponent("macos/LaunchDaemons/com.nomdelasociete.dsmn.helper.plist")
        let plistData = try Data(contentsOf: plistURL)
        let plist = try XCTUnwrap(
            PropertyListSerialization.propertyList(from: plistData, format: nil) as? [String: Any]
        )

        XCTAssertEqual(plist["Label"] as? String, "com.nomdelasociete.dsmn.helper")
        XCTAssertEqual(plist["RunAtLoad"] as? Bool, true)
        XCTAssertEqual(plist["KeepAlive"] as? Bool, true)
        XCTAssertEqual(plist["BundleProgram"] as? String, "Contents/Library/LaunchServices/dsmnd")

        let arguments = try XCTUnwrap(plist["ProgramArguments"] as? [String])
        XCTAssertEqual(arguments.first, "Contents/Library/LaunchServices/dsmnd")
        XCTAssertEqual(arguments.dropFirst().first, "serve")
    }

    func testXcodeProjectCopiesHelperExecutableOutsideLaunchDaemonsDirectory() throws {
        let projectSource = try sourceFile(at: "project.yml")

        XCTAssertTrue(projectSource.contains("- target: dsmnd"))
        XCTAssertTrue(projectSource.contains("subpath: Contents/Library/LaunchServices"))
        XCTAssertFalse(projectSource.contains("""
          - target: dsmnd
            embed: true
            link: false
            codeSign: true
            copy:
              destination: wrapper
              subpath: Contents/Library/LaunchDaemons
        """))
    }

    func testReleaseValidationChecksHelperExecutablePath() throws {
        let verifyBundleSource = try sourceFile(at: "scripts/verify_bundle.sh")
        let notarizeSource = try sourceFile(at: "scripts/notarize.sh")
        let releaseRunbookSource = try sourceFile(at: ".claude/commands/release-dsmn.md")

        for source in [verifyBundleSource, notarizeSource, releaseRunbookSource] {
            XCTAssertTrue(source.contains("Contents/Library/LaunchServices/dsmnd"))
        }

        XCTAssertTrue(verifyBundleSource.contains("helper executable must not be copied beside the LaunchDaemon plist"))
        XCTAssertTrue(releaseRunbookSource.contains("test ! -e \"$app/Contents/Library/LaunchDaemons/dsmnd\""))
    }

    private func sourceFile(at relativePath: String) throws -> String {
        try String(contentsOf: repositoryRoot().appendingPathComponent(relativePath))
    }

    private func repositoryRoot() -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }
}
