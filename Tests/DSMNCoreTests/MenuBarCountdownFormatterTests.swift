import XCTest
@testable import DSMNCore

final class MenuBarCountdownFormatterTests: XCTestCase {
    func testFormatsCountdownWhenPowerLockIsOffDuringLidOpenGrace() {
        let report = makeReport(manualUntil: Date(timeIntervalSince1970: 2_200), shouldPreventSleep: false)

        XCTAssertEqual(MenuBarCountdownFormatter.text(report: report, at: Date(timeIntervalSince1970: 1_000)), "20m")
    }

    func testReturnsNilWhenNoManualTimerExists() {
        let report = makeReport(shouldPreventSleep: true)

        XCTAssertNil(MenuBarCountdownFormatter.text(report: report, at: Date(timeIntervalSince1970: 1_000)))
    }

    func testFormatsManualCountdownForMenuBar() {
        let now = Date(timeIntervalSince1970: 1_000)
        let report = makeReport(manualUntil: now.addingTimeInterval(5_390), shouldPreventSleep: true)

        XCTAssertEqual(MenuBarCountdownFormatter.text(report: report, at: now), "1h29m")
    }

    func testFormatsSecondsWhenLessThanOneMinuteRemains() {
        let now = Date(timeIntervalSince1970: 1_000)
        let report = makeReport(manualUntil: now.addingTimeInterval(45), shouldPreventSleep: true)

        XCTAssertEqual(MenuBarCountdownFormatter.text(report: report, at: now), "45s")
    }

    private func makeReport(
        manualUntil: Date? = nil,
        shouldPreventSleep: Bool
    ) -> StatusReport {
        let now = Date(timeIntervalSince1970: 1_000)
        return StatusReport(
            generatedAt: now,
            state: DSMNState(manualUntil: manualUntil, ownsSleepDisable: shouldPreventSleep),
            snapshot: SystemSnapshot(now: now),
            agents: [],
            decision: PowerDecision(shouldPreventSleep: shouldPreventSleep, reasons: [], safetyBlocks: []),
            manualRemainingSeconds: nil
        )
    }
}
