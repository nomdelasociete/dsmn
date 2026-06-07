import XCTest
@testable import DSMNCore

final class RepairTests: XCTestCase {
    func testRepairForcesDisableWhenOwningSleepLock() throws {
        let now = Date(timeIntervalSince1970: 1_000)
        let store = try makeStore()
        try store.save(DSMNState(ownsSleepDisable: true))

        let powerManager = RecordingPowerManager(dryRun: false)
        let controller = DSMNController(
            store: store,
            processListing: StaticProcessListing([]),
            snapshotProvider: StaticSystemSnapshotProvider(SystemSnapshot(now: now, powerSource: .ac))
        )

        let report = try controller.repair(powerManager: powerManager, now: now)

        XCTAssertEqual(powerManager.requests, [false])
        XCTAssertEqual(report.operation?.requestedSleepDisabled, false)
        XCTAssertFalse(report.status.state.ownsSleepDisable)
        XCTAssertNil(report.status.state.manualUntil)
        XCTAssertEqual(report.status.state.lastStopReason, "repair")
        XCTAssertFalse(try store.load().ownsSleepDisable)
    }

    func testRepairClearsExpiredManualWithStaleOwnership() throws {
        let now = Date(timeIntervalSince1970: 2_000)
        let store = try makeStore()
        try store.save(
            DSMNState(
                manualUntil: now.addingTimeInterval(-120),
                ownsSleepDisable: true
            )
        )

        let powerManager = RecordingPowerManager(dryRun: false)
        let controller = DSMNController(
            store: store,
            processListing: StaticProcessListing([]),
            snapshotProvider: StaticSystemSnapshotProvider(SystemSnapshot(now: now, powerSource: .ac))
        )

        let report = try controller.repair(powerManager: powerManager, now: now)

        XCTAssertEqual(powerManager.requests, [false])
        XCTAssertNil(report.status.state.manualUntil)
        XCTAssertFalse(report.status.state.ownsSleepDisable)
        XCTAssertFalse(report.status.decision.shouldPreventSleep)
    }

    func testRepairWithoutOwnershipSkipsPmset() throws {
        let now = Date(timeIntervalSince1970: 1_000)
        let store = try makeStore()
        try store.save(DSMNState(manualUntil: now.addingTimeInterval(300)))

        let powerManager = RecordingPowerManager(dryRun: false)
        let controller = DSMNController(
            store: store,
            processListing: StaticProcessListing([]),
            snapshotProvider: StaticSystemSnapshotProvider(SystemSnapshot(now: now, powerSource: .ac))
        )

        let report = try controller.repair(powerManager: powerManager, now: now)

        XCTAssertTrue(powerManager.requests.isEmpty)
        XCTAssertNil(report.operation)
        XCTAssertNil(report.status.state.manualUntil)
        XCTAssertEqual(report.status.state.lastStopReason, "repair")
    }

    func testRepairReleasesLiveSleepDisabledEvenWhenStateLostOwnership() throws {
        let now = Date(timeIntervalSince1970: 1_000)
        let store = try makeStore()
        try store.save(DSMNState())

        let powerManager = RecordingPowerManager(dryRun: false)
        let controller = DSMNController(
            store: store,
            processListing: StaticProcessListing([]),
            snapshotProvider: StaticSystemSnapshotProvider(SystemSnapshot(now: now, powerSource: .ac))
        )

        let report = try controller.repair(
            powerManager: powerManager,
            liveSleepDisabled: true,
            now: now
        )

        XCTAssertEqual(powerManager.requests, [false])
        XCTAssertEqual(report.operation?.requestedSleepDisabled, false)
        XCTAssertFalse(report.status.state.ownsSleepDisable)
        XCTAssertEqual(report.status.state.lastStopReason, "repair")
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
