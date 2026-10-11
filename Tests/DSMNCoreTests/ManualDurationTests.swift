import XCTest
@testable import DSMNCore

final class ManualDurationTests: XCTestCase {
    func testHoursMinutesBoundariesAndWhitespace() throws {
        XCTAssertEqual(try ManualDuration.minutes(hours: "", minutes: "1"), 1)
        XCTAssertEqual(try ManualDuration.minutes(hours: " 1 ", minutes: "30"), 90)
        XCTAssertEqual(try ManualDuration.minutes(hours: "8", minutes: "0"), 480)
        for (h, m) in [("8", "1"), ("12", "0"), ("0", "0"), ("", ""), ("-1", "30"),
                       ("1.5", "0"), ("2h", "0"), ("1", "60"), ("1", "-1"), ("999999999999999999999", "0")] {
            XCTAssertThrowsError(try ManualDuration.minutes(hours: h, minutes: m), "\(h):\(m)")
        }
    }

    func testPresetFormatsAndOrdering() throws {
        XCTAssertEqual(try ManualDuration.presets(from: "30m, 1h30m, 2h, 480, 1m"), [30, 90, 120, 480, 1])
        XCTAssertEqual(try ManualDuration.presets(from: "90m, 1H 15M"), [90, 75])
    }

    func testInvalidPresetsDoNotSilentlyDropEntries() {
        for text in ["", "30,", "0", "481", "12h", "30,30m", "1h60m", "2hgarbage", "1:30",
                     "1,2,3,4,5,6,7", "-1", "1.5", "9999999999999999999999999h"] {
            XCTAssertThrowsError(try ManualDuration.presets(from: text), text)
        }
    }

    func testAddUsesCurrentDeadlineWithoutRoundingOrShortening() throws {
        let now = Date(timeIntervalSince1970: 1000)
        let store = temporaryStore()
        let controller = DSMNController(store: store)
        let previous = now.addingTimeInterval(125)
        try store.save(DSMNState(manualUntil: previous))
        let added = try controller.addManualTimeIntent(minutes: 30, now: now)
        XCTAssertEqual(added.manualUntil, previous.addingTimeInterval(1800))
        // A hook renewal arriving before another Add is included, never overwritten.
        try controller.enableManualIntent(minutes: 90, now: now, extendOnly: true)
        let renewed = try controller.addManualTimeIntent(minutes: 30, now: now)
        XCTAssertEqual(renewed.manualUntil, now.addingTimeInterval(7200))
        let replaced = try controller.enableManualIntent(minutes: 30, now: now)
        XCTAssertEqual(replaced.manualUntil, now.addingTimeInterval(1800))
    }

    func testAddOnExpiredOrAbsentTimerStartsFromNow() throws {
        let now = Date(timeIntervalSince1970: 1000)
        for previous in [nil, now.addingTimeInterval(-10)] {
            let store = temporaryStore()
            try store.save(DSMNState(manualUntil: previous))
            let result = try DSMNController(store: store).addManualTimeIntent(minutes: 1, now: now)
            XCTAssertEqual(result.manualUntil, now.addingTimeInterval(60))
        }
    }

    func testAddEnforcesTotalLimitAndPreservesStateOnFailure() throws {
        let now = Date(timeIntervalSince1970: 1000)
        let store = temporaryStore()
        let controller = DSMNController(store: store)
        try controller.enableManualIntent(minutes: 479, now: now)
        let atLimit = try controller.addManualTimeIntent(minutes: 1, now: now)
        XCTAssertEqual(atLimit.manualUntil, now.addingTimeInterval(480 * 60))
        for invalid in [1, 481, 720, 0, -1, Int.max] {
            XCTAssertThrowsError(try controller.addManualTimeIntent(minutes: invalid, now: now))
            XCTAssertEqual(try store.load(), atLimit)
        }
    }

    func testLegacyStatusDecodesWithoutNewCapability() throws {
        let report = try DSMNController(store: temporaryStore(), processListing: StaticProcessListing([]),
            snapshotProvider: StaticSystemSnapshotProvider(SystemSnapshot())).status()
        let data = try JSONEncoder().encode(report)
        let decoded = try JSONDecoder().decode(StatusReport.self, from: data)
        XCTAssertNil(decoded.supportsAddManualTime)
        XCTAssertNil(decoded.manualDurationLimitMinutes)
    }

    private func temporaryStore() -> StateStore {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        return StateStore(directory: url)
    }
}
