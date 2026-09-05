import XCTest
@testable import DSMNCore

final class RepairTests: XCTestCase {
    func testRepairCleansUpDespiteSnapshotAndAgentFailures() throws {
        let now = Date(timeIntervalSince1970: 1_000)
        let store = try makeStore()
        try store.save(DSMNState(manualUntil: now.addingTimeInterval(300), ownsSleepDisable: true))
        let power = RecordingPowerManager(dryRun: false)
        let controller = DSMNController(store: store, processListing: RepairThrowingListing(), snapshotProvider: RepairThrowingSnapshot())

        let report = try controller.repair(powerManager: power, now: now)

        XCTAssertEqual(power.actions, [.enableSleep])
        XCTAssertFalse(try store.load().ownsSleepDisable)
        XCTAssertNil(try store.load().manualUntil)
        XCTAssertEqual(report.status.snapshot.powerSource, .unknown)
        XCTAssertEqual(report.status.diagnosticErrors?.count, 2)
        XCTAssertTrue(report.status.diagnosticErrors?.contains(where: { $0.contains("Agent process listing unavailable") }) == true)
    }

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

    func testFailedRepairRetainsOwnershipAndAuditsAttempt() throws {
        try assertUnsuccessfulRepair(dryRun: false, exitCode: 1)
    }

    func testDryRunRepairRetainsOwnershipAndAuditsAttempt() throws {
        try assertUnsuccessfulRepair(dryRun: true, exitCode: nil)
    }

    func testThrownRepairClearsIntentButRetainsOwnership() throws {
        let now = Date(timeIntervalSince1970: 1_000)
        let store = try makeStore()
        try store.save(DSMNState(manualUntil: now.addingTimeInterval(300), ownsSleepDisable: true))
        let powerManager = RecordingPowerManager(dryRun: false, throwsOnRelease: true)
        let controller = makeController(store: store, now: now)

        XCTAssertThrowsError(try controller.repair(powerManager: powerManager, now: now))

        let saved = try store.load()
        XCTAssertTrue(saved.ownsSleepDisable)
        XCTAssertNil(saved.manualUntil)
        XCTAssertEqual(saved.lastStopReason, "repair")
        XCTAssertEqual(powerManager.actions, [.enableSleep])
        XCTAssertTrue(saved.powerOperationHistory.isEmpty)
    }

    func testSuccessfulRepairSavesReleaseBeforeSleepingOnClosedLidBattery() throws {
        let now = Date(timeIntervalSince1970: 1_000)
        let store = try makeStore()
        try store.save(DSMNState(manualUntil: now.addingTimeInterval(300), ownsSleepDisable: true))
        let powerManager = RecordingPowerManager(dryRun: false, beforeSleep: {
            XCTAssertFalse(try store.load().ownsSleepDisable)
            XCTAssertEqual(try store.load().lastPowerOperation?.action, .enableSleep)
        })

        let report = try makeController(store: store, now: now).repair(powerManager: powerManager, now: now)

        XCTAssertEqual(powerManager.actions, [.enableSleep, .sleepNow])
        XCTAssertEqual(report.operations.map(\.action), [.enableSleep, .sleepNow])
        XCTAssertEqual(try store.load().powerOperationHistory.map(\.action), [.enableSleep, .sleepNow])
        XCTAssertFalse(try store.load().ownsSleepDisable)
        XCTAssertEqual(try store.load().lastStopReason, "repair")
    }

    func testRepairDoesNotSleepWithoutClosedLidBatteryFacts() throws {
        let now = Date(timeIntervalSince1970: 1_000)
        for snapshot in [
            SystemSnapshot(now: now, powerSource: .ac, lidClosed: true),
            SystemSnapshot(now: now, powerSource: .battery, lidClosed: false),
            SystemSnapshot(now: now, powerSource: .unknown, lidClosed: true),
            SystemSnapshot(now: now, powerSource: .battery, lidClosed: nil)
        ] {
            let store = try makeStore()
            try store.save(DSMNState(ownsSleepDisable: true))
            let powerManager = RecordingPowerManager(dryRun: false)
            let controller = DSMNController(
                store: store,
                processListing: StaticProcessListing([]),
                snapshotProvider: StaticSystemSnapshotProvider(snapshot)
            )

            _ = try controller.repair(powerManager: powerManager, now: now)

            XCTAssertEqual(powerManager.actions, [.enableSleep])
        }
    }

    func testFailedRepairOfExternalLockDoesNotClaimOwnership() throws {
        let now = Date(timeIntervalSince1970: 1_000)
        let store = try makeStore()
        try store.save(DSMNState())
        let powerManager = RecordingPowerManager(dryRun: false, exitCode: 1)

        let report = try makeController(store: store, now: now).repair(
            powerManager: powerManager, liveSleepDisabled: true, now: now
        )

        XCTAssertEqual(report.operation?.exitCode, 1)
        XCTAssertFalse(report.status.state.ownsSleepDisable)
        XCTAssertFalse(try store.load().ownsSleepDisable)
        XCTAssertEqual(try store.load().lastPowerOperation?.exitCode, 1)
        XCTAssertEqual(powerManager.actions, [.enableSleep])
    }

    private func assertUnsuccessfulRepair(dryRun: Bool, exitCode: Int32?) throws {
        let now = Date(timeIntervalSince1970: 1_000)
        let store = try makeStore()
        try store.save(DSMNState(manualUntil: now.addingTimeInterval(300), ownsSleepDisable: true))
        let powerManager = RecordingPowerManager(dryRun: dryRun, exitCode: exitCode)

        let report = try makeController(store: store, now: now).repair(powerManager: powerManager, now: now)

        let saved = try store.load()
        XCTAssertTrue(report.status.state.ownsSleepDisable)
        XCTAssertTrue(saved.ownsSleepDisable)
        XCTAssertNil(saved.manualUntil)
        XCTAssertEqual(saved.lastStopReason, "repair")
        XCTAssertEqual(powerManager.actions, [.enableSleep])
        XCTAssertEqual(report.operations.count, 1)
        XCTAssertEqual(report.operation?.exitCode, exitCode)
        XCTAssertEqual(saved.powerOperationHistory.count, 1)
        XCTAssertEqual(saved.lastPowerOperation?.exitCode, exitCode)
        XCTAssertEqual(saved.lastPowerOperation?.dryRun, dryRun)
        XCTAssertEqual(saved.lastPowerOperation?.reason, "release:repair")
    }

    private func makeController(store: StateStore, now: Date) -> DSMNController {
        DSMNController(
            store: store,
            processListing: StaticProcessListing([]),
            snapshotProvider: StaticSystemSnapshotProvider(
                SystemSnapshot(now: now, powerSource: .battery, batteryPercent: 80, lidClosed: true)
            )
        )
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

private struct RepairThrowingSnapshot: SystemSnapshotProviding {
    func snapshot(now: Date) throws -> SystemSnapshot { throw CocoaError(.fileReadUnknown) }
}

private struct RepairThrowingListing: ProcessListing {
    func listProcesses() throws -> [RunningProcess] { throw CocoaError(.fileReadUnknown) }
}

private final class RecordingPowerManager: PowerManaging, @unchecked Sendable {
    var requests: [Bool] = []
    var actions: [PowerOperationAction] = []
    let dryRun: Bool
    let exitCode: Int32?
    let throwsOnRelease: Bool
    let beforeSleep: (() throws -> Void)?

    init(dryRun: Bool, exitCode: Int32? = 0, throwsOnRelease: Bool = false, beforeSleep: (() throws -> Void)? = nil) {
        self.dryRun = dryRun
        self.exitCode = dryRun ? nil : exitCode
        self.throwsOnRelease = throwsOnRelease
        self.beforeSleep = beforeSleep
    }

    func setSleepDisabled(_ disabled: Bool) throws -> PowerOperationResult {
        requests.append(disabled)
        actions.append(disabled ? .disableSleep : .enableSleep)
        if throwsOnRelease, !disabled {
            throw CocoaError(.executableNotLoadable)
        }
        return PowerOperationResult(
            requestedSleepDisabled: disabled,
            dryRun: dryRun,
            executedCommand: "recorded",
            exitCode: exitCode
        )
    }

    func requestSleepNow() throws -> PowerOperationResult {
        try beforeSleep?()
        actions.append(.sleepNow)
        return PowerOperationResult(
            requestedSleepDisabled: false,
            dryRun: false,
            executedCommand: "recorded sleepnow",
            exitCode: 0,
            action: .sleepNow
        )
    }
}
