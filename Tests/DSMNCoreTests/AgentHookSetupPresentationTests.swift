import XCTest
@testable import DSMNCore

final class AgentHookSetupPresentationTests: XCTestCase {
    func testOutdatedStatusUsesGuidedUpdateActionAndBusyState() {
        let status = AgentHooksSetupStatus.outdated("Hooks update available")

        XCTAssertEqual(AgentHookSetupPresentation.action(for: status), .update)
        XCTAssertEqual(AgentHookSetupPresentation.actionTitle(for: status), "Update Hooks")
        XCTAssertEqual(
            AgentHookSetupPresentation.startedStatus(for: .update).displayName,
            "Updating hooks"
        )
        XCTAssertEqual(
            AgentHookSetupPresentation.actionTitle(for: .installing(.update)),
            "Updating..."
        )
    }

    func testReadyStatusKeepsReinstallSeparateFromUpdate() {
        let status = AgentHooksSetupStatus.ready("Claude, Codex, Grok, and Pi ready")

        XCTAssertEqual(AgentHookSetupPresentation.action(for: status), .reinstall)
        XCTAssertEqual(AgentHookSetupPresentation.actionTitle(for: status), "Reinstall")
    }

    func testSuccessfulUpdateClearsOutdatedState() {
        let reports = [
            AgentHookInstallReport(target: "claude", path: "/tmp/claude", changed: false, message: "already installed"),
            AgentHookInstallReport(target: "codex", path: "/tmp/codex", changed: false, message: "already installed"),
            AgentHookInstallReport(target: "grok", path: "/tmp/grok", changed: false, message: "already installed"),
            AgentHookInstallReport(target: "pi", path: "/tmp/pi", changed: true, message: "installed")
        ]

        let completed = AgentHookSetupPresentation.completedStatus(for: .update, reports: reports)

        XCTAssertTrue(completed.isReady)
        XCTAssertFalse(completed.needsUpdate)
        XCTAssertEqual(completed.displayName, "Hooks updated for Pi")
    }

    func testResultRowsShowUpdatedUnchangedAndFailedTargets() {
        let reports = [
            AgentHookInstallReport(target: "claude", path: "/tmp/claude", changed: true, message: "installed"),
            AgentHookInstallReport(target: "codex", path: "/tmp/codex", changed: false, message: "already installed"),
            AgentHookInstallReport(
                target: "grok",
                path: "/tmp/grok",
                changed: false,
                message: "failed",
                error: "permission denied"
            )
        ]

        let rows = AgentHookSetupPresentation.resultRows(for: .update, reports: reports)

        XCTAssertEqual(rows.map(\.targetDisplayName), ["Claude Code", "Codex", "Grok Build"])
        XCTAssertEqual(rows.map(\.state), [.updated, .unchanged, .failed])
        XCTAssertEqual(rows.last?.message, "permission denied")
        XCTAssertEqual(
            AgentHookSetupPresentation.completedStatus(for: .update, reports: reports).displayName,
            "Hook update failed"
        )
    }
}
