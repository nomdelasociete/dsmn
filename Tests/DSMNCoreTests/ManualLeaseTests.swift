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

    func testManualStoresRequester() throws {
        let now = Date(timeIntervalSince1970: 1_000)
        let store = try makeStore()
        let controller = DSMNController(
            store: store,
            processListing: StaticProcessListing([]),
            snapshotProvider: StaticSystemSnapshotProvider(SystemSnapshot(now: now))
        )

        let report = try controller.enableManual(
            minutes: 20,
            now: now,
            requester: ActivationRequester(name: "Codex", context: "dsmn - session abc12345", event: "PreToolUse")
        )

        XCTAssertEqual(report.state.lastRequester?.name, "Codex")
        XCTAssertEqual(report.state.lastRequester?.context, "dsmn - session abc12345")
        XCTAssertEqual(report.state.lastRequester?.event, "PreToolUse")
        XCTAssertEqual(report.state.lastRequester?.requestedAt, now)
    }

    func testExtendOnlyUpdatesRequesterWithoutShorteningLongerTimer() throws {
        let now = Date(timeIntervalSince1970: 1_000)
        let store = try makeStore()
        let controller = DSMNController(
            store: store,
            processListing: StaticProcessListing([]),
            snapshotProvider: StaticSystemSnapshotProvider(SystemSnapshot(now: now))
        )

        let long = try controller.enableManual(
            minutes: 90,
            now: now,
            requester: ActivationRequester(name: "dsmn", context: "menu")
        )
        let hook = try controller.enableManual(
            minutes: 20,
            now: now.addingTimeInterval(60),
            extendOnly: true,
            requester: ActivationRequester(name: "Codex", context: "dsmn - session abc12345")
        )

        XCTAssertEqual(hook.state.manualUntil, long.state.manualUntil)
        XCTAssertEqual(hook.state.lastRequester?.name, "Codex")
        XCTAssertEqual(hook.state.lastRequester?.context, "dsmn - session abc12345")
        XCTAssertEqual(hook.state.lastRequester?.requestedAt, now.addingTimeInterval(60))
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
