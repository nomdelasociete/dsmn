import XCTest
@testable import DSMNCore

final class SleepDiagnosticsInspectorTests: XCTestCase {
    func testParsesLiveSleepDisabledAndAssertionBlockers() {
        let live = """
        System-wide power settings:
         SleepDisabled        1
        Currently in use:
         sleep                1 (sleep prevented by Codex, Claude, powerd)
         displaysleep         10 (display sleep prevented by CEPHtmlEngine)
        """

        let assertions = """
        Assertion status system-wide:
           PreventUserIdleDisplaySleep    1
           PreventUserIdleSystemSleep     1
        Listed by owning process:
           pid 81942(Codex): [0x0007f53500018e5e] 03:43:54 NoIdleSleepAssertion named: "Electron"
           pid 42929(CEPHtmlEngine): [0x0008203200059fdc] 00:40:30 NoDisplaySleepAssertion named: "Video Wake Lock"
        """

        let report = SleepDiagnosticsInspector.parse(
            liveOutput: live,
            assertionsOutput: assertions,
            generatedAt: Date(timeIntervalSince1970: 1_000)
        )

        XCTAssertEqual(report.sleepDisabled, true)
        XCTAssertEqual(report.sleepLine, "sleep                1 (sleep prevented by Codex, Claude, powerd)")
        XCTAssertEqual(report.displaySleepLine, "displaysleep         10 (display sleep prevented by CEPHtmlEngine)")
        XCTAssertEqual(report.assertionStatuses["PreventUserIdleSystemSleep"], true)
        XCTAssertEqual(report.assertionStatuses["PreventUserIdleDisplaySleep"], true)
        XCTAssertEqual(report.blockers.count, 2)
        XCTAssertEqual(report.blockers[0].pid, 81_942)
        XCTAssertEqual(report.blockers[0].processName, "Codex")
        XCTAssertEqual(report.blockers[0].assertionType, "NoIdleSleepAssertion")
        XCTAssertEqual(report.blockers[0].assertionName, "Electron")
        XCTAssertEqual(report.blockers[0].scope, .systemSleep)
        XCTAssertEqual(report.blockers[1].scope, .displaySleep)
    }

    func testParsesSleepDisabledOff() {
        let report = SleepDiagnosticsInspector.parse(
            liveOutput: " SleepDisabled\t\t0\n",
            assertionsOutput: "Assertion status system-wide:\n   PreventUserIdleSystemSleep     0\nListed by owning process:\n",
            generatedAt: Date(timeIntervalSince1970: 1_000)
        )

        XCTAssertEqual(report.sleepDisabled, false)
        XCTAssertEqual(report.assertionStatuses["PreventUserIdleSystemSleep"], false)
        XCTAssertEqual(report.blockers, [])
    }
}
