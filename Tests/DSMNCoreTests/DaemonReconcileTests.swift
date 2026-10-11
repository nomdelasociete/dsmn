import XCTest
@testable import DSMNCore

final class DaemonReconcileTests: XCTestCase {
    func testCriticalHeatWithoutLeasePreservesPreviousStopReason() throws {
        let now = Date()
        for reason in ["user_stop", "repair", "manual_expired"] {
            let store = try makeStore()
            try store.save(DSMNState(lastStopReason: reason))
            let controller = DSMNController(store: store)
            let power = RecordingPowerManager(dryRun: false)
            let telemetry = ControllerTelemetry(snapshot: SystemSnapshot(now: now, thermalCondition: .critical),
                                                 agents: [], diagnosticErrors: [])
            _ = try controller.reconcile(powerManager: power, telemetry: telemetry, now: now)
            XCTAssertEqual(try store.load().lastStopReason, reason)
            XCTAssertTrue(power.requests.isEmpty)
        }
    }
    func testThrownDisplaySleepPreservesSuccessfulAcquisitionAndAudit() throws {
        let now = Date(timeIntervalSince1970: 1_000)
        let store = try makeStore()
        try store.save(DSMNState(manualUntil: now.addingTimeInterval(300)))
        let power = RecordingPowerManager(dryRun: false, throwsOnDisplay: true)
        let controller = DSMNController(
            store: store,
            processListing: StaticProcessListing([]),
            snapshotProvider: StaticSystemSnapshotProvider(SystemSnapshot(now: now, powerSource: .ac, lidClosed: true))
        )

        XCTAssertThrowsError(try controller.reconcile(powerManager: power, now: now))

        XCTAssertEqual(power.requests, [true])
        XCTAssertTrue(try store.load().ownsSleepDisable)
        XCTAssertNotNil(try store.load().manualUntil)
        XCTAssertEqual(try store.load().lastPowerOperation?.action, .disableSleep)
        XCTAssertEqual(try store.load().lastPowerOperation?.exitCode, 0)
    }

    func testOwnedCleanupPrecedesThrowingDiagnosticsForExpiredAndStoppedLeases() throws {
        let now = Date(timeIntervalSince1970: 1_000)
        for expired in [true, false] {
            for failures in [(true, false), (false, true), (true, true)] {
                let events = DiagnosticEvents()
                let store = try makeStore()
                try store.save(DSMNState(
                    manualUntil: expired ? now.addingTimeInterval(-5) : nil,
                    ownsSleepDisable: true,
                    lastStopReason: expired ? nil : "user_stop"
                ))
                let power = RecordingPowerManager(dryRun: false, beforeSet: { events.append("release") })
                let controller = DSMNController(
                    store: store,
                    processListing: FaultingProcessListing(fails: failures.0, events: events),
                    snapshotProvider: FaultingSnapshotProvider(fails: failures.1, events: events)
                )

                XCTAssertNoThrow(try controller.reconcile(powerManager: power, now: now))

                XCTAssertEqual(power.requests, [false])
                XCTAssertFalse(try store.load().ownsSleepDisable)
                XCTAssertEqual(events.values.first, "release")
            }
        }
    }

    func testUnknownRoutePreservesAndEnforcesRecordedOutage() throws {
        let now = Date(timeIntervalSince1970: 1_000)
        let store = try makeStore()
        let since = now.addingTimeInterval(-1_000)
        try store.save(DSMNState(
            manualUntil: now.addingTimeInterval(300), ownsSleepDisable: true, noRouteUnavailableSince: since
        ))
        let controller = DSMNController(
            store: store,
            processListing: StaticProcessListing([]),
            snapshotProvider: StaticSystemSnapshotProvider(SystemSnapshot(now: now, powerSource: .ac))
        )
        let power = RecordingPowerManager(dryRun: false)

        let report = try controller.reconcile(powerManager: power, now: now)

        XCTAssertEqual(power.requests, [false])
        XCTAssertFalse(report.status.state.ownsSleepDisable)
        XCTAssertEqual(try store.load().noRouteUnavailableSince, since)
        XCTAssertEqual(report.status.decision.stopReason, "network_unavailable")
    }

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

    func testReconcileReleasesLiveSleepDisabledWhenOwnershipStateWasLost() throws {
        let now = Date(timeIntervalSince1970: 1_000)
        let store = try makeStore()
        try store.save(DSMNState(lastActivationReason: "manual_lease"))

        let powerManager = RecordingPowerManager(dryRun: false)
        let controller = DSMNController(
            store: store,
            processListing: StaticProcessListing([]),
            snapshotProvider: StaticSystemSnapshotProvider(SystemSnapshot(now: now, powerSource: .ac))
        )

        let report = try controller.reconcile(
            powerManager: powerManager,
            liveSleepDisabled: true,
            now: now
        )

        XCTAssertEqual(powerManager.requests, [false])
        XCTAssertEqual(report.operation?.requestedSleepDisabled, false)
        XCTAssertFalse(report.status.state.ownsSleepDisable)
        XCTAssertFalse(report.status.decision.shouldPreventSleep)
        XCTAssertEqual(report.status.state.lastStopReason, "not_armed")
    }

    func testReconcileDoesNotReleaseLiveSleepDisabledWithoutDsmnPowerHistory() throws {
        let now = Date(timeIntervalSince1970: 1_000)
        let store = try makeStore()
        try store.save(DSMNState())

        let powerManager = RecordingPowerManager(dryRun: false)
        let controller = DSMNController(
            store: store,
            processListing: StaticProcessListing([]),
            snapshotProvider: StaticSystemSnapshotProvider(SystemSnapshot(now: now, powerSource: .ac))
        )

        let report = try controller.reconcile(
            powerManager: powerManager,
            liveSleepDisabled: true,
            now: now
        )

        XCTAssertTrue(powerManager.requests.isEmpty)
        XCTAssertNil(report.operation)
        XCTAssertFalse(report.status.state.ownsSleepDisable)
        XCTAssertFalse(report.status.decision.shouldPreventSleep)
    }

    func testReconcileReleasesExpiredManualTimerImmediately() throws {
        let now = Date(timeIntervalSince1970: 1_000)
        let store = try makeStore()
        try store.save(
            DSMNState(
                manualUntil: now.addingTimeInterval(-1),
                ownsSleepDisable: true
            )
        )

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
        XCTAssertNil(report.status.state.manualUntil)
        XCTAssertFalse(report.status.decision.shouldPreventSleep)
        XCTAssertEqual(report.status.state.lastStopReason, "manual_expired")
    }

    func testReconcileRequestsSleepNowAfterReleaseWhenLidIsClosedOnBattery() throws {
        let now = Date(timeIntervalSince1970: 1_000)
        let store = try makeStore()
        try store.save(
            DSMNState(
                manualUntil: now.addingTimeInterval(-1),
                ownsSleepDisable: true
            )
        )

        let powerManager = RecordingPowerManager(dryRun: false)
        let controller = DSMNController(
            store: store,
            processListing: StaticProcessListing([]),
            snapshotProvider: StaticSystemSnapshotProvider(
                SystemSnapshot(now: now, powerSource: .battery, batteryPercent: 80, lidClosed: true)
            )
        )

        let report = try controller.reconcile(powerManager: powerManager, now: now)
        let state = try store.load()

        XCTAssertEqual(powerManager.requests, [false])
        XCTAssertEqual(powerManager.sleepNowRequests, 1)
        XCTAssertEqual(report.operations.map(\.action), [.enableSleep, .sleepNow])
        XCTAssertFalse(report.status.state.ownsSleepDisable)
        XCTAssertNil(report.status.state.manualUntil)
        XCTAssertEqual(state.lastPowerOperation?.action, .sleepNow)
        XCTAssertEqual(state.lastPowerOperation?.reason, "closed_lid_release")
    }

    func testSafetyReleaseSleepsClosedLidOnBatteryDespiteUnexpiredTimer() throws {
        for lowBattery in [true, false] {
            let now = Date(timeIntervalSince1970: 1_000)
            let store = try makeStore()
            try store.save(DSMNState(
                manualUntil: now.addingTimeInterval(600), ownsSleepDisable: true,
                noRouteUnavailableSince: lowBattery ? nil : now.addingTimeInterval(-1_000)))
            let power = RecordingPowerManager(dryRun: false)
            let controller = DSMNController(
                store: store, processListing: StaticProcessListing([]),
                snapshotProvider: StaticSystemSnapshotProvider(SystemSnapshot(
                    now: now, powerSource: .battery, batteryPercent: lowBattery ? 1 : 80,
                    defaultRouteAvailable: lowBattery, lidClosed: true)))
            let report = try controller.reconcile(powerManager: power, now: now)
            XCTAssertEqual(power.requests, [false])
            XCTAssertEqual(power.sleepNowRequests, 1)
            XCTAssertEqual(report.operations.map(\.action), [.enableSleep, .sleepNow])
            XCTAssertTrue(try store.load().manualIsActive(at: now))
        }
    }

    func testReconcileDoesNotRequestSleepNowAfterReleaseWhenLidIsOpen() throws {
        let now = Date(timeIntervalSince1970: 1_000)
        let store = try makeStore()
        try store.save(
            DSMNState(
                manualUntil: now.addingTimeInterval(-1),
                ownsSleepDisable: true
            )
        )

        let powerManager = RecordingPowerManager(dryRun: false)
        let controller = DSMNController(
            store: store,
            processListing: StaticProcessListing([]),
            snapshotProvider: StaticSystemSnapshotProvider(
                SystemSnapshot(now: now, powerSource: .battery, batteryPercent: 80, lidClosed: false)
            )
        )

        let report = try controller.reconcile(powerManager: powerManager, now: now)

        XCTAssertEqual(powerManager.requests, [false])
        XCTAssertEqual(powerManager.sleepNowRequests, 0)
        XCTAssertEqual(report.operations.map(\.action), [.enableSleep])
    }

    func testReconcileDoesNotRequestSleepNowAfterReleaseOnACPower() throws {
        let now = Date(timeIntervalSince1970: 1_000)
        let store = try makeStore()
        try store.save(
            DSMNState(
                manualUntil: now.addingTimeInterval(-1),
                ownsSleepDisable: true
            )
        )

        let powerManager = RecordingPowerManager(dryRun: false)
        let controller = DSMNController(
            store: store,
            processListing: StaticProcessListing([]),
            snapshotProvider: StaticSystemSnapshotProvider(
                SystemSnapshot(now: now, powerSource: .ac, batteryPercent: 80, lidClosed: true)
            )
        )

        let report = try controller.reconcile(powerManager: powerManager, now: now)

        XCTAssertEqual(powerManager.requests, [false])
        XCTAssertEqual(powerManager.sleepNowRequests, 0)
        XCTAssertEqual(report.operations.map(\.action), [.enableSleep])
    }

    func testReconcileRequestsDisplaySleepNowWhenProtectedLidCloses() throws {
        let now = Date(timeIntervalSince1970: 1_000)
        let store = try makeStore()
        try store.save(
            DSMNState(
                manualUntil: now.addingTimeInterval(60),
                ownsSleepDisable: true,
                lastLidClosed: false
            )
        )

        let powerManager = RecordingPowerManager(dryRun: false)
        let controller = DSMNController(
            store: store,
            processListing: StaticProcessListing([]),
            snapshotProvider: StaticSystemSnapshotProvider(
                SystemSnapshot(now: now, powerSource: .battery, batteryPercent: 80, lidClosed: true)
            )
        )

        let report = try controller.reconcile(powerManager: powerManager, now: now)
        let state = try store.load()

        XCTAssertEqual(powerManager.requests, [])
        XCTAssertEqual(powerManager.sleepNowRequests, 0)
        XCTAssertEqual(powerManager.displaySleepNowRequests, 1)
        XCTAssertEqual(report.operation?.action, .displaySleepNow)
        XCTAssertEqual(report.operations.map(\.action), [.displaySleepNow])
        XCTAssertEqual(state.lastLidClosed, true)
        XCTAssertEqual(state.lastPowerOperation?.action, .displaySleepNow)
        XCTAssertEqual(state.lastPowerOperation?.reason, "closed_lid_display_sleep")
    }

    func testReconcileDoesNotRepeatDisplaySleepNowWhileLidStaysClosed() throws {
        let now = Date(timeIntervalSince1970: 1_000)
        let store = try makeStore()
        try store.save(
            DSMNState(
                manualUntil: now.addingTimeInterval(60),
                ownsSleepDisable: true,
                lastLidClosed: true
            )
        )

        let powerManager = RecordingPowerManager(dryRun: false)
        let controller = DSMNController(
            store: store,
            processListing: StaticProcessListing([]),
            snapshotProvider: StaticSystemSnapshotProvider(
                SystemSnapshot(now: now, powerSource: .battery, batteryPercent: 80, lidClosed: true)
            )
        )

        let report = try controller.reconcile(powerManager: powerManager, now: now)

        XCTAssertEqual(powerManager.requests, [])
        XCTAssertEqual(powerManager.displaySleepNowRequests, 0)
        XCTAssertNil(report.operation)
        XCTAssertTrue(report.operations.isEmpty)
    }

    func testReconcileRequestsDisplaySleepNowWhenEnablingAlreadyClosed() throws {
        let now = Date(timeIntervalSince1970: 1_000)
        let store = try makeStore()
        try store.save(
            DSMNState(
                manualUntil: now.addingTimeInterval(60),
                ownsSleepDisable: false,
                lastLidClosed: nil
            )
        )

        let powerManager = RecordingPowerManager(dryRun: false)
        let controller = DSMNController(
            store: store,
            processListing: StaticProcessListing([]),
            snapshotProvider: StaticSystemSnapshotProvider(
                SystemSnapshot(now: now, powerSource: .battery, batteryPercent: 80, lidClosed: true)
            )
        )

        let report = try controller.reconcile(powerManager: powerManager, now: now)
        let state = try store.load()

        XCTAssertEqual(powerManager.requests, [true])
        XCTAssertEqual(powerManager.displaySleepNowRequests, 1)
        XCTAssertEqual(report.operation?.action, .disableSleep)
        XCTAssertEqual(report.operations.map(\.action), [.disableSleep, .displaySleepNow])
        XCTAssertTrue(state.ownsSleepDisable)
        XCTAssertEqual(state.lastPowerOperation?.action, .displaySleepNow)
        XCTAssertEqual(state.lastPowerOperation?.reason, "closed_lid_display_sleep")
    }

    func testReconcilePersistsNoRouteUnavailableSinceDuringGrace() throws {
        let now = Date(timeIntervalSince1970: 40_000)
        let store = try makeStore()
        try store.save(DSMNState(manualUntil: now.addingTimeInterval(60 * 60)))

        let controller = DSMNController(
            store: store,
            processListing: StaticProcessListing([]),
            snapshotProvider: StaticSystemSnapshotProvider(
                SystemSnapshot(now: now, powerSource: .ac, defaultRouteAvailable: false)
            )
        )

        let report = try controller.reconcile(powerManager: RecordingPowerManager(dryRun: true), now: now)

        XCTAssertEqual(try store.load().noRouteUnavailableSince, now)
        XCTAssertTrue(report.status.decision.shouldPreventSleep)
        XCTAssertEqual(report.status.noRouteGraceRemainingSeconds, 15 * 60)
    }

    func testReconcileClearsNoRouteUnavailableSinceWhenRouteReturns() throws {
        let now = Date(timeIntervalSince1970: 50_000)
        let store = try makeStore()
        try store.save(
            DSMNState(
                manualUntil: now.addingTimeInterval(60 * 60),
                noRouteUnavailableSince: now.addingTimeInterval(-120)
            )
        )

        let controller = DSMNController(
            store: store,
            processListing: StaticProcessListing([]),
            snapshotProvider: StaticSystemSnapshotProvider(
                SystemSnapshot(now: now, powerSource: .ac, defaultRouteAvailable: true)
            )
        )

        _ = try controller.reconcile(powerManager: RecordingPowerManager(dryRun: true), now: now)

        XCTAssertNil(try store.load().noRouteUnavailableSince)
    }

    func testReconcilePersistsLidOpenGraceAcrossTicks() throws {
        let openedAt = Date(timeIntervalSince1970: 1_000)
        let midGrace = openedAt.addingTimeInterval(120)
        let store = try makeStore()
        try store.save(
            DSMNState(
                manualUntil: openedAt.addingTimeInterval(3_600),
                ownsSleepDisable: true,
                lidOpenedAt: openedAt,
                lastLidClosed: false
            )
        )

        let powerManager = RecordingPowerManager(dryRun: false)
        let controller = DSMNController(
            store: store,
            processListing: StaticProcessListing([]),
            snapshotProvider: StaticSystemSnapshotProvider(
                SystemSnapshot(now: midGrace, powerSource: .ac, lidClosed: false)
            ),
            decisionEngine: PowerDecisionEngine(policy: SafetyPolicy(lidOpenGraceSeconds: 300))
        )

        let report = try controller.reconcile(powerManager: powerManager, now: midGrace)

        XCTAssertTrue(report.status.decision.shouldPreventSleep)
        XCTAssertEqual(report.status.decision.reasons, ["manual_timer", "lid_open_grace"])
        XCTAssertEqual(try store.load().lidOpenedAt, openedAt)
        XCTAssertEqual(powerManager.requests, [])
    }

    func testReconcileKeepsSleepPreventionAfterLidOpenGraceWhileManualTimerStillActive() throws {
        let openedAt = Date(timeIntervalSince1970: 1_000)
        let afterGrace = openedAt.addingTimeInterval(301)
        let store = try makeStore()
        try store.save(
            DSMNState(
                manualUntil: afterGrace.addingTimeInterval(3_600),
                ownsSleepDisable: true,
                lidOpenedAt: openedAt,
                lastLidClosed: false
            )
        )

        let powerManager = RecordingPowerManager(dryRun: false)
        let controller = DSMNController(
            store: store,
            processListing: StaticProcessListing([]),
            snapshotProvider: StaticSystemSnapshotProvider(
                SystemSnapshot(now: afterGrace, powerSource: .ac, lidClosed: false)
            ),
            decisionEngine: PowerDecisionEngine(policy: SafetyPolicy(lidOpenGraceSeconds: 300))
        )

        let report = try controller.reconcile(powerManager: powerManager, now: afterGrace)

        XCTAssertTrue(report.status.decision.shouldPreventSleep)
        XCTAssertNil(report.status.decision.stopReason)
        XCTAssertEqual(powerManager.requests, [])
        XCTAssertTrue(report.status.state.ownsSleepDisable)
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
    var sleepNowRequests = 0
    var displaySleepNowRequests = 0
    let dryRun: Bool
    let beforeSet: (() -> Void)?
    let throwsOnDisplay: Bool

    init(dryRun: Bool, beforeSet: (() -> Void)? = nil, throwsOnDisplay: Bool = false) {
        self.dryRun = dryRun
        self.beforeSet = beforeSet
        self.throwsOnDisplay = throwsOnDisplay
    }

    func setSleepDisabled(_ disabled: Bool) throws -> PowerOperationResult {
        beforeSet?()
        requests.append(disabled)
        return PowerOperationResult(
            requestedSleepDisabled: disabled,
            dryRun: dryRun,
            executedCommand: "recorded",
            exitCode: dryRun ? nil : 0
        )
    }

    func requestSleepNow() throws -> PowerOperationResult {
        sleepNowRequests += 1
        return PowerOperationResult(
            requestedSleepDisabled: false,
            dryRun: dryRun,
            executedCommand: "recorded sleepnow",
            exitCode: dryRun ? nil : 0,
            action: .sleepNow
        )
    }

    func requestDisplaySleepNow() throws -> PowerOperationResult {
        displaySleepNowRequests += 1
        if throwsOnDisplay { throw CocoaError(.executableNotLoadable) }
        return PowerOperationResult(
            requestedSleepDisabled: false,
            dryRun: dryRun,
            executedCommand: "recorded displaysleepnow",
            exitCode: dryRun ? nil : 0,
            action: .displaySleepNow
        )
    }
}

private final class DiagnosticEvents: @unchecked Sendable {
    private let lock = NSLock()
    private var recorded: [String] = []
    var values: [String] { lock.withLock { recorded } }
    func append(_ value: String) { lock.withLock { recorded.append(value) } }
}

private struct FaultingProcessListing: ProcessListing {
    let fails: Bool
    let events: DiagnosticEvents
    func listProcesses() throws -> [RunningProcess] {
        events.append("processes")
        if fails { throw CocoaError(.fileReadUnknown) }
        return []
    }
}

private struct FaultingSnapshotProvider: SystemSnapshotProviding {
    let fails: Bool
    let events: DiagnosticEvents
    func snapshot(now: Date) throws -> SystemSnapshot {
        events.append("snapshot")
        if fails { throw CocoaError(.fileReadUnknown) }
        return SystemSnapshot(now: now, powerSource: .ac)
    }
}
