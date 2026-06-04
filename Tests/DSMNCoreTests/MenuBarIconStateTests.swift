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
        let now = Date(timeIntervalSince1970: 1_000)
        let report = makeReport(
            ownsSleepDisable: true,
            shouldPreventSleep: true,
            manualUntil: now.addingTimeInterval(1_200)
        )

        XCTAssertEqual(MenuBarIconState.resolve(report: report, errorMessage: nil), .manualActive)
    }

    func testShowsManualWhenTimerIsActiveButPowerLockIsOff() {
        let now = Date(timeIntervalSince1970: 1_000)
        let report = makeReport(
            shouldPreventSleep: false,
            manualUntil: now.addingTimeInterval(1_200)
        )

        XCTAssertEqual(MenuBarIconState.resolve(report: report, errorMessage: nil), .manualActive)
    }

    func testShowsOffWhenNoTimerIsActive() {
        let report = makeReport()

        XCTAssertEqual(MenuBarIconState.resolve(report: report, errorMessage: nil), .off)
    }

    func testShowsWarningWhenHookFallbackIsActive() {
        let now = Date(timeIntervalSince1970: 1_000)
        let report = makeReport(
            shouldPreventSleep: false,
            manualUntil: now.addingTimeInterval(1_200)
        )

        XCTAssertEqual(
            MenuBarIconState.resolve(report: report, errorMessage: nil, hookFallbackActive: true),
            .warning
        )
    }

    private func makeReport(
        ownsSleepDisable: Bool = false,
        shouldPreventSleep: Bool = false,
        manualUntil: Date? = nil
    ) -> StatusReport {
        let now = Date(timeIntervalSince1970: 1_000)
        return StatusReport(
            generatedAt: now,
            state: DSMNState(manualUntil: manualUntil, ownsSleepDisable: ownsSleepDisable),
            snapshot: SystemSnapshot(now: now),
            agents: [],
            decision: PowerDecision(shouldPreventSleep: shouldPreventSleep, reasons: [], safetyBlocks: []),
            manualRemainingSeconds: manualUntil.map { max(0, Int($0.timeIntervalSince(now))) }
        )
    }
}
