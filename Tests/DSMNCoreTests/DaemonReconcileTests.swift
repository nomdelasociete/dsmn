import XCTest
@testable import DSMNCore

final class DaemonReconcileTests: XCTestCase {
    func testSelfUpdateRelaunchPreservesCurrentTimerState() throws {
        let now = Date(timeIntervalSince1970: 1_000)
        let later = now.addingTimeInterval(15)
        let store = try makeStore()
        let requester = ActivationRequester(name: "Codex", context: "session update-test")
        let controller = DSMNController(
            store: store,
            processListing: StaticProcessListing([]),
            snapshotProvider: StaticSystemSnapshotProvider(SystemSnapshot(now: now, powerSource: .ac))
        )

        _ = try controller.enableManual(minutes: 30, now: now, requester: requester)
        let active = try controller.reconcile(powerManager: RecordingPowerManager(dryRun: false), now: now)

        let relaunchedController = DSMNController(
            store: store,
            processListing: StaticProcessListing([]),
            snapshotProvider: StaticSystemSnapshotProvider(SystemSnapshot(now: later, powerSource: .ac))
        )
        let afterRelaunch = try relaunchedController.status(now: later)

        XCTAssertEqual(afterRelaunch.state.manualUntil, active.status.state.manualUntil)
        XCTAssertEqual(afterRelaunch.state.lastRequester, active.status.state.lastRequester)
        XCTAssertTrue(afterRelaunch.state.ownsSleepDisable)
        XCTAssertEqual(afterRelaunch.manualRemainingSeconds, 30 * 60 - 15)
    }

    func testReconcileRequestsEnableWhenManualTimerIsActive() throws {
        let now = Date(timeIntervalSince1970: 1_000)
        let store = try makeStore()
        try store.save(DSMNState(manualUntil: now.addingTimeInterval(60)))

        let powerManager = RecordingPowerManager(dryRun: false)
        let controller = DSMNController(
            store: store,
            processListing: StaticProcessListing([]),
            snapshotProvider: StaticSystemSnapshotProvider(SystemSnapshot(now: now, powerSource: .ac))
        )

        let report = try controller.reconcile(powerManager: powerManager, now: now)

        XCTAssertEqual(powerManager.requests, [true])
        XCTAssertEqual(report.operation?.requestedSleepDisabled, true)
        XCTAssertTrue(report.status.state.ownsSleepDisable)
        XCTAssertTrue(try store.load().ownsSleepDisable)
    }

    func testDryRunDoesNotMarkSleepDisableAsOwned() throws {
        let now = Date(timeIntervalSince1970: 1_000)
        let store = try makeStore()
        try store.save(DSMNState(manualUntil: now.addingTimeInterval(60)))

        let powerManager = RecordingPowerManager(dryRun: true)
        let controller = DSMNController(
            store: store,
            processListing: StaticProcessListing([]),
            snapshotProvider: StaticSystemSnapshotProvider(SystemSnapshot(now: now, powerSource: .ac))
        )

        let report = try controller.reconcile(powerManager: powerManager, now: now)

        XCTAssertEqual(powerManager.requests, [true])
        XCTAssertFalse(report.status.state.ownsSleepDisable)
        XCTAssertFalse(try store.load().ownsSleepDisable)
    }

    func testReconcileRequestsDisableWhenNoLongerActiveAndOwned() throws {
        let now = Date(timeIntervalSince1970: 1_000)
        let store = try makeStore()
        try store.save(DSMNState(ownsSleepDisable: true))

        let powerManager = RecordingPowerManager(dryRun: false)
        let controller = DSMNController(
            store: store,
            processListing: StaticProcessListing([]),
            snapshotProvider: StaticSystemSnapshotProvider(SystemSnapshot(now: now, powerSource: .ac))
        )

        let report = try controller.reconcile(powerManager: powerManager, now: now)

        XCTAssertEqual(powerManager.requests, [false])
        XCTAssertEqual(report.operation?.requestedSleepDisabled, false)
        XCTAssertFalse(report.status.state.ownsSleepDisable)
        XCTAssertFalse(try store.load().ownsSleepDisable)
    }

    func testStopPreservesOwnershipUntilReconcileReleasesPower() throws {
        let now = Date(timeIntervalSince1970: 1_000)
        let store = try makeStore()
        try store.save(DSMNState(ownsSleepDisable: true))
        let controller = DSMNController(
            store: store,
            processListing: StaticProcessListing([]),
            snapshotProvider: StaticSystemSnapshotProvider(SystemSnapshot(now: now, powerSource: .ac))
        )

        let stopped = try controller.stop(now: now)

        XCTAssertTrue(stopped.state.ownsSleepDisable)

        let powerManager = RecordingPowerManager(dryRun: false)
        let report = try controller.reconcile(powerManager: powerManager, now: now)

        XCTAssertEqual(powerManager.requests, [false])
        XCTAssertFalse(report.status.state.ownsSleepDisable)
    }

    private func makeStore() throws -> StateStore {
        let directory = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("dsmn-\(UUID().uuidString)", isDirectory: true)
        addTeardownBlock {
            try? FileManager.default.removeItem(at: directory)
        }
        return StateStore(directory: directory)
    }
}

private final class RecordingPowerManager: PowerManaging, @unchecked Sendable {
    var requests: [Bool] = []
    let dryRun: Bool

    init(dryRun: Bool) {
        self.dryRun = dryRun
    }

    func setSleepDisabled(_ disabled: Bool) throws -> PowerOperationResult {
        requests.append(disabled)
        return PowerOperationResult(
            requestedSleepDisabled: disabled,
            dryRun: dryRun,
            executedCommand: "recorded",
            exitCode: dryRun ? nil : 0
        )
    }
}
