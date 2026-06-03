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
        XCTAssertEqual(report.state.recentRequesters, [try XCTUnwrap(report.state.lastRequester)])
        XCTAssertEqual(report.state.triggerHistory, [try XCTUnwrap(report.state.lastRequester)])
        XCTAssertEqual(report.state.triggerActivityBuckets.map(\.count), [1])
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

    func testRecentRequestersKeepConcurrentAgentsVisible() throws {
        let now = Date(timeIntervalSince1970: 1_000)
        let store = try makeStore()
        let controller = DSMNController(
            store: store,
            processListing: StaticProcessListing([]),
            snapshotProvider: StaticSystemSnapshotProvider(SystemSnapshot(now: now))
        )

        _ = try controller.enableManual(
            minutes: 20,
            now: now,
            extendOnly: true,
            requester: ActivationRequester(name: "Pi", context: "dsmn-website", event: "tool_call")
        )
        _ = try controller.enableManual(
            minutes: 20,
            now: now.addingTimeInterval(1),
            extendOnly: true,
            requester: ActivationRequester(name: "Codex", context: "dsmn - session abc12345", event: "PreToolUse")
        )
        let report = try controller.enableManual(
            minutes: 20,
            now: now.addingTimeInterval(2),
            extendOnly: true,
            requester: ActivationRequester(name: "Claude Code", context: "dsmn-website - session deadbeef", event: "PreToolUse")
        )

        XCTAssertEqual(report.state.lastRequester?.name, "Claude Code")
        XCTAssertEqual(report.state.recentRequesters.map(\.name), ["Claude Code", "Codex", "Pi"])
        XCTAssertEqual(report.state.recentRequesters.map(\.context), [
            "dsmn-website - session deadbeef",
            "dsmn - session abc12345",
            "dsmn-website"
        ])
        XCTAssertEqual(report.state.triggerHistory.map(\.name), ["Pi", "Codex", "Claude Code"])
        XCTAssertEqual(report.state.triggerActivityBuckets.map(\.count).reduce(0, +), 3)
    }

    func testRecentRequestersReplaceSameAgentSession() throws {
        let now = Date(timeIntervalSince1970: 1_000)
        let store = try makeStore()
        let controller = DSMNController(
            store: store,
            processListing: StaticProcessListing([]),
            snapshotProvider: StaticSystemSnapshotProvider(SystemSnapshot(now: now))
        )

        _ = try controller.enableManual(
            minutes: 20,
            now: now,
            extendOnly: true,
            requester: ActivationRequester(name: "Pi", context: "dsmn-website", event: "tool_call")
        )
        let report = try controller.enableManual(
            minutes: 20,
            now: now.addingTimeInterval(1),
            extendOnly: true,
            requester: ActivationRequester(name: "Pi", context: "dsmn-website", event: "tool_result")
        )

        XCTAssertEqual(report.state.recentRequesters.count, 1)
        XCTAssertEqual(report.state.recentRequesters.first?.name, "Pi")
        XCTAssertEqual(report.state.recentRequesters.first?.event, "tool_result")
        XCTAssertEqual(report.state.recentRequesters.first?.requestedAt, now.addingTimeInterval(1))
        XCTAssertEqual(report.state.triggerHistory.map(\.event), ["tool_call", "tool_result"])
        XCTAssertEqual(report.state.triggerActivityBuckets.map(\.count).reduce(0, +), 2)
    }

    func testTriggerHistoryPrunesOutsideTwelveHours() throws {
        let now = Date(timeIntervalSince1970: 50_000)
        var state = DSMNState()

        state.recordRequester(
            ActivationRequester(name: "Codex", context: "old"),
            at: now.addingTimeInterval(-13 * 60 * 60)
        )
        state.recordRequester(
            ActivationRequester(name: "Claude Code", context: "recent"),
            at: now.addingTimeInterval(-11 * 60 * 60)
        )
        state.recordRequester(
            ActivationRequester(name: "Pi", context: "now"),
            at: now
        )

        XCTAssertEqual(state.triggerHistory.map(\.name), ["Claude Code", "Pi"])
        XCTAssertEqual(state.triggerActivityBuckets.map(\.count).reduce(0, +), 2)
    }

    func testTriggerActivityBucketsKeepCountingAfterDetailedHistoryCap() {
        let now = Date(timeIntervalSince1970: 50_000)
        var state = DSMNState()

        for index in 0..<620 {
            state.recordRequester(
                ActivationRequester(name: "Codex", context: "session-\(index)", event: "PreToolUse"),
                at: now.addingTimeInterval(TimeInterval(index))
            )
        }

        XCTAssertEqual(state.triggerHistory.count, 500)
        XCTAssertEqual(state.triggerActivityBuckets.map(\.count).reduce(0, +), 620)
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
