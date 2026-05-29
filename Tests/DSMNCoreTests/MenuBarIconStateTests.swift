import XCTest
@testable import DSMNCore

final class MenuBarIconStateTests: XCTestCase {
    func testShowsWarningWhenInitialLoadHasError() {
        XCTAssertEqual(
            MenuBarIconState.resolve(report: nil, errorMessage: "helper failed"),
            .warning
        )
    }

    func testShowsManualWhenOnlyManualTimerIsActive() {
        let report = makeReport(
            ownsSleepDisable: true,
            shouldPreventSleep: true,
            manualRemainingSeconds: 1_200
        )

        XCTAssertEqual(MenuBarIconState.resolve(report: report, errorMessage: nil), .manualActive)
    }

    func testShowsOffWhenNoTimerIsActive() {
        let report = makeReport()

        XCTAssertEqual(MenuBarIconState.resolve(report: report, errorMessage: nil), .off)
    }

    private func makeReport(
        ownsSleepDisable: Bool = false,
        shouldPreventSleep: Bool = false,
        manualRemainingSeconds: Int? = nil
    ) -> StatusReport {
        let now = Date(timeIntervalSince1970: 1_000)
        return StatusReport(
            generatedAt: now,
            state: DSMNState(ownsSleepDisable: ownsSleepDisable),
            snapshot: SystemSnapshot(now: now),
            agents: [],
            decision: PowerDecision(shouldPreventSleep: shouldPreventSleep, reasons: [], safetyBlocks: []),
            manualRemainingSeconds: manualRemainingSeconds
        )
    }
}
