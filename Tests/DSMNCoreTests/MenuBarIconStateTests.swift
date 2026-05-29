import XCTest
@testable import DSMNCore

final class MenuBarIconStateTests: XCTestCase {
    func testShowsWarningWhenInitialLoadHasError() {
        XCTAssertEqual(
            MenuBarIconState.resolve(report: nil, errorMessage: "helper failed"),
            .warning
        )
    }

    func testShowsAutoArmedWhenAutoIsOnAndNoAgentIsActive() {
        let report = makeReport(autoEnabled: true, shouldPreventSleep: false)

        XCTAssertEqual(MenuBarIconState.resolve(report: report, errorMessage: nil), .autoArmed)
        XCTAssertEqual(MenuBarIconState.resolve(report: report, errorMessage: nil).systemImageName, "figure.run.circle")
    }

    func testShowsAutoActiveWhenAutoIsOnAndPreventingSleep() {
        let report = makeReport(autoEnabled: true, ownsSleepDisable: true, shouldPreventSleep: true)

        XCTAssertEqual(MenuBarIconState.resolve(report: report, errorMessage: nil), .autoActive)
        XCTAssertEqual(MenuBarIconState.resolve(report: report, errorMessage: nil).systemImageName, "figure.run.circle.fill")
    }

    func testAutoStateWinsOverManualTimerSoTogglingAutoChangesTheIcon() {
        let report = makeReport(
            autoEnabled: true,
            ownsSleepDisable: true,
            shouldPreventSleep: true,
            manualRemainingSeconds: 1_200
        )

        XCTAssertEqual(MenuBarIconState.resolve(report: report, errorMessage: nil), .autoActive)
    }

    func testShowsManualWhenOnlyManualTimerIsActive() {
        let report = makeReport(
            autoEnabled: false,
            ownsSleepDisable: true,
            shouldPreventSleep: true,
            manualRemainingSeconds: 1_200
        )

        XCTAssertEqual(MenuBarIconState.resolve(report: report, errorMessage: nil), .manualActive)
    }

    private func makeReport(
        autoEnabled: Bool = false,
        ownsSleepDisable: Bool = false,
        shouldPreventSleep: Bool = false,
        manualRemainingSeconds: Int? = nil
    ) -> StatusReport {
        let now = Date(timeIntervalSince1970: 1_000)
        return StatusReport(
            generatedAt: now,
            state: DSMNState(autoEnabled: autoEnabled, ownsSleepDisable: ownsSleepDisable),
            snapshot: SystemSnapshot(now: now),
            agents: [],
            decision: PowerDecision(shouldPreventSleep: shouldPreventSleep, reasons: [], safetyBlocks: []),
            manualRemainingSeconds: manualRemainingSeconds
        )
    }
}
