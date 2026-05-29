import XCTest
@testable import DSMNCore

final class ManualLeaseTests: XCTestCase {
    func testExtendOnlyDoesNotShortenLongerManualTimer() throws {
        let now = Date(timeIntervalSince1970: 1_000)
        let store = try makeStore()
        let controller = DSMNController(
            store: store,
            processListing: StaticProcessListing([]),
            snapshotProvider: StaticSystemSnapshotProvider(SystemSnapshot(now: now))
        )

        let long = try controller.enableManual(minutes: 90, now: now)
        let hook = try controller.enableManual(minutes: 20, now: now.addingTimeInterval(60), extendOnly: true)

        XCTAssertEqual(hook.state.manualUntil, long.state.manualUntil)
        XCTAssertEqual(hook.manualRemainingSeconds, 89 * 60)
    }

    func testExtendOnlyExtendsShorterManualTimer() throws {
        let now = Date(timeIntervalSince1970: 1_000)
        let store = try makeStore()
        let controller = DSMNController(
            store: store,
            processListing: StaticProcessListing([]),
            snapshotProvider: StaticSystemSnapshotProvider(SystemSnapshot(now: now))
        )

        _ = try controller.enableManual(minutes: 5, now: now)
        let hook = try controller.enableManual(minutes: 20, now: now.addingTimeInterval(60), extendOnly: true)

        XCTAssertEqual(hook.manualRemainingSeconds, 20 * 60)
        XCTAssertEqual(hook.state.lastActivationReason, "manual_lease")
    }

    func testRegularManualCanShortenExistingTimer() throws {
        let now = Date(timeIntervalSince1970: 1_000)
        let store = try makeStore()
        let controller = DSMNController(
            store: store,
            processListing: StaticProcessListing([]),
            snapshotProvider: StaticSystemSnapshotProvider(SystemSnapshot(now: now))
        )

        _ = try controller.enableManual(minutes: 90, now: now)
        let shorter = try controller.enableManual(minutes: 20, now: now.addingTimeInterval(60))

        XCTAssertEqual(shorter.manualRemainingSeconds, 20 * 60)
        XCTAssertEqual(shorter.state.lastActivationReason, "manual_timer")
    }

    private func makeStore() throws -> StateStore {
        let directory = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("dsmn-manual-\(UUID().uuidString)", isDirectory: true)
        addTeardownBlock {
            try? FileManager.default.removeItem(at: directory)
        }
        return StateStore(directory: directory)
    }
}
