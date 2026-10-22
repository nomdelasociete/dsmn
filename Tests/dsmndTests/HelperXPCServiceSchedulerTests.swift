import DSMNCore
import XCTest
@testable import dsmnd

final class HelperXPCServiceSchedulerTests: XCTestCase {
    func testStopReportsFailedPendingReleaseAndKeepsRecoveryResponsibility() throws {
        let store = try makeStore()
        var state = DSMNState(manualUntil: Date().addingTimeInterval(600))
        state.sleepDisablePending = true
        try store.save(state)
        let power = RecordingPowerManager(dryRun: false, defaultExitCode: 1)
        let service = DSMNHelperXPCService(
            controller: DSMNController(store: store, processListing: StaticProcessListing([]),
                snapshotProvider: StaticSystemSnapshotProvider(SystemSnapshot())),
            powerManager: power, liveSleepDisabledProvider: { nil })
        var payload = ""
        service.stop { payload = $0 }
        XCTAssertNotNil(try decode(payload).error)
        XCTAssertNil(try store.load().manualUntil)
        XCTAssertTrue(try store.load().sleepDisablePending)
        XCTAssertFalse(power.snapshot().contains(true))
    }

    func testRecoveryProbeCannotSleepUncertainRenewalInSameCommand() throws {
        let entered = expectation(description: "recovery sleep probe entered")
        let returned = expectation(description: "recovery sleep probe returned")
        let gate = ProbeGate(entered: entered)
        defer { gate.open() }
        let store = try makeStore()
        var state = DSMNState(manualUntil: Date().addingTimeInterval(600))
        state.sleepDisablePending = true
        try store.save(state)
        let power = RecordingPowerManager(dryRun: false, outcomes: [.exit(0)], defaultExitCode: 1)
        let service = DSMNHelperXPCService(
            controller: DSMNController(store: store, processListing: StaticProcessListing([]),
                snapshotProvider: GatedSleepSnapshotProvider(gate: gate, returned: returned)),
            powerManager: power, liveSleepDisabledProvider: { nil }, thermalConditionProvider: { .nominal })
        service.enableManual(minutes: 20) { _ in }
        wait(for: [entered], timeout: 1)
        XCTAssertEqual(Array(power.snapshot().prefix(2)), [false, true])
        XCTAssertTrue(try store.load().sleepDisablePending)
        gate.open()
        wait(for: [returned], timeout: 1)
        pump(for: 0.2)
        XCTAssertEqual(power.sleepCount, 0)
        withExtendedLifetime(service) {}
    }

    func testNewManualRequestsRecoverOldPendingLockBeforeCommittingLease() throws {
        for command in ["replace", "add", "hook"] {
            let store = try makeStore()
            var state = DSMNState(manualUntil: Date().addingTimeInterval(3600))
            state.sleepDisablePending = true
            try store.save(state)
            let power = RecordingPowerManager(dryRun: false)
            let service = DSMNHelperXPCService(
                controller: DSMNController(store: store, processListing: StaticProcessListing([]),
                    snapshotProvider: StaticSystemSnapshotProvider(SystemSnapshot())),
                powerManager: power, liveSleepDisabledProvider: { nil }, thermalConditionProvider: { .nominal })
            var payload = ""
            if command == "add" {
                service.addManualTime(minutes: 10) { payload = $0 }
            } else {
                service.enableManualV2(minutes: 10, extendOnly: command == "hook",
                    requesterName: nil, requesterContext: nil, requesterEvent: nil) { payload = $0 }
            }
            XCTAssertNil(try decode(payload).error)
            XCTAssertEqual(Array(power.snapshot().prefix(2)), [false, true])
            let saved = try store.load()
            XCTAssertTrue(saved.ownsSleepDisable)
            XCTAssertFalse(saved.sleepDisablePending)
            XCTAssertEqual(try XCTUnwrap(saved.manualUntil).timeIntervalSinceNow, 600, accuracy: 3)
        }
    }

    func testFailedRecoveryRejectsNewManualRequests() throws {
        for add in [false, true] {
            let store = try makeStore()
            var state = DSMNState(manualUntil: Date().addingTimeInterval(3600))
            state.sleepDisablePending = true
            try store.save(state)
            let power = RecordingPowerManager(dryRun: false, defaultExitCode: 1)
            let service = DSMNHelperXPCService(
                controller: DSMNController(store: store, processListing: StaticProcessListing([]),
                    snapshotProvider: StaticSystemSnapshotProvider(SystemSnapshot())),
                powerManager: power, liveSleepDisabledProvider: { nil })
            var payload = ""
            if add { service.addManualTime(minutes: 10) { payload = $0 } }
            else { service.enableManual(minutes: 10) { payload = $0 } }
            XCTAssertNotNil(try decode(payload).error)
            XCTAssertTrue(try store.load().sleepDisablePending)
            XCTAssertNil(try store.load().manualUntil)
            XCTAssertFalse(power.snapshot().contains(true))
        }
    }

    func testRestartRecoversPendingAcquisitionWithoutClientAndRetriesFailedRelease() throws {
        let store = try makeStore()
        var state = DSMNState(manualUntil: Date().addingTimeInterval(600))
        state.sleepDisablePending = true
        try store.save(state)
        let power = RecordingPowerManager(dryRun: false, outcomes: [.exit(1), .exit(0)])
        let service = DSMNHelperXPCService(
            controller: DSMNController(store: store, processListing: StaticProcessListing([]),
                snapshotProvider: StaticSystemSnapshotProvider(SystemSnapshot())),
            powerManager: power, liveSleepDisabledProvider: { nil })
        service.startPeriodicReconcile(interval: 3600)
        XCTAssertEqual(power.snapshot().first, false)
        let deadline = Date().addingTimeInterval(4)
        while try store.load().sleepDisablePending, Date() < deadline { pump(for: 0.02) }
        XCTAssertFalse(try store.load().sleepDisablePending)
        XCTAssertNil(try store.load().manualUntil)
        XCTAssertFalse(try store.load().ownsSleepDisable)
        XCTAssertGreaterThanOrEqual(power.snapshot().count, 2)
        XCTAssertFalse(power.snapshot().contains(true))
    }

    func testCriticalThermalNotificationReleasesWithoutPollAndCancelsLease() throws {
        let store = try makeStore()
        try store.save(DSMNState(manualUntil: Date().addingTimeInterval(600), ownsSleepDisable: true))
        let power = RecordingPowerManager(dryRun: false)
        let center = NotificationCenter()
        let controller = DSMNController(store: store, processListing: StaticProcessListing([]),
            snapshotProvider: StaticSystemSnapshotProvider(SystemSnapshot()))
        let service = DSMNHelperXPCService(controller: controller, powerManager: power,
            liveSleepDisabledProvider: { nil }, thermalConditionProvider: { .critical },
            thermalNotificationCenter: center)
        center.post(name: ProcessInfo.thermalStateDidChangeNotification, object: nil)
        XCTAssertEqual(power.snapshot(), [false])
        XCTAssertNil(try store.load().manualUntil)
        XCTAssertFalse(try store.load().ownsSleepDisable)
        XCTAssertEqual(try store.load().lastStopReason, "thermal_critical")
        // A second helper has its own lock and schedules a nominal telemetry
        // refresh. That refresh can commit the next lease while this command
        // is clearing it. Cooling is the synchronous decision, not a second daemon.
        _ = try controller.reconcile(
            powerManager: power,
            telemetry: ControllerTelemetry(snapshot: SystemSnapshot(thermalCondition: .nominal), agents: [])
        )
        XCTAssertEqual(power.snapshot(), [false], "Cooling must not reactivate an ended lease")
        service.enableManual(minutes: 20) { _ in }
        XCTAssertNil(try store.load().manualUntil, "Hooks must not bypass critical heat")
        XCTAssertEqual(power.snapshot(), [false])
    }
    func testAddAdvertisesCapabilityAndSerializesConcurrentAdditions() throws {
        let store = try makeStore()
        let until = Date(timeIntervalSince1970: floor(Date().timeIntervalSince1970) + 3600)
        try store.save(DSMNState(manualUntil: until, ownsSleepDisable: true))
        let power = RecordingPowerManager(dryRun: false)
        let service = DSMNHelperXPCService(
            controller: DSMNController(store: store, processListing: StaticProcessListing([]),
                snapshotProvider: StaticSystemSnapshotProvider(SystemSnapshot(now: Date(), powerSource: .ac, defaultRouteAvailable: true, lidClosed: false))),
            powerManager: power, liveSleepDisabledProvider: { nil }
        )
        var statusPayload = ""
        service.status { statusPayload = $0 }
        let status = try XCTUnwrap(decode(statusPayload).status)
        XCTAssertEqual(status.supportsAddManualTime, true)
        XCTAssertEqual(status.manualDurationLimitMinutes, 480)

        DispatchQueue.concurrentPerform(iterations: 6) { _ in
            service.addManualTime(minutes: 1) { _ in }
        }
        XCTAssertEqual(try store.load().manualUntil, until.addingTimeInterval(360))
        XCTAssertEqual(try store.load().lastRequester?.context, "menu")
        var failed = ""
        service.addManualTime(minutes: 480) { failed = $0 }
        XCTAssertNotNil(try decode(failed).error)
        XCTAssertEqual(try store.load().manualUntil, until.addingTimeInterval(360))

        service.stop { _ in }
        XCTAssertFalse(try store.load().ownsSleepDisable)
        XCTAssertNil(try store.load().manualUntil)
        XCTAssertEqual(power.snapshot(), [false])
    }

    func testCachedClosedLidDoesNotSleepDisplayAfterStopAndFreshOpenRenewal() throws {
        try assertRenewalDisplayUsesFreshSample(lidClosed: false)
    }

    func testClosedLidRenewalSleepsDisplayOnlyAfterFreshObservation() throws {
        try assertRenewalDisplayUsesFreshSample(lidClosed: true)
    }

    private func assertRenewalDisplayUsesFreshSample(lidClosed: Bool) throws {
        let blocked = expectation(description: "new lid observation blocked")
        let gate = ProbeGate(entered: blocked)
        defer { gate.open() }
        let store = try makeStore()
        try store.save(DSMNState(manualUntil: Date().addingTimeInterval(300), ownsSleepDisable: true, lastLidClosed: true))
        let power = RecordingPowerManager(dryRun: false)
        let service = DSMNHelperXPCService(
            controller: DSMNController(
                store: store, processListing: StaticProcessListing([]),
                snapshotProvider: FirstClosedThenGatedSnapshotProvider(gate: gate, freshLidClosed: lidClosed)
            ),
            powerManager: power,
            liveSleepDisabledProvider: { nil }
        )
        service.status { _ in }
        var status: StatusReport?
        let readyDeadline = Date().addingTimeInterval(1)
        repeat {
            pump(for: 0.01)
            service.status { status = try? self.decode($0).status }
        } while status?.snapshot.lidClosed != true && Date() < readyDeadline
        XCTAssertEqual(status?.snapshot.lidClosed, true)
        wait(for: [blocked], timeout: 1)
        XCTAssertEqual(power.displayCount, 0)

        service.stop { _ in }
        service.enableManual(minutes: 20) { _ in }

        XCTAssertEqual(power.snapshot(), [false, true])
        XCTAssertEqual(power.displayCount, 0, "Cached closed-lid data must not trigger display sleep")
        gate.open()
        let publicationDeadline = Date().addingTimeInterval(1)
        while Date() < publicationDeadline, try store.load().lastLidClosed != lidClosed { pump(for: 0.01) }

        XCTAssertEqual(try store.load().lastLidClosed, lidClosed)
        XCTAssertTrue(try store.load().ownsSleepDisable)
        XCTAssertNotNil(try store.load().manualUntil)
        XCTAssertEqual(power.displayCount, lidClosed ? 1 : 0)
        XCTAssertEqual(power.recordedActions, lidClosed ? [.enableSleep, .disableSleep, .displaySleepNow] : [.enableSleep, .disableSleep])
        withExtendedLifetime(service) {}
    }

    func testUnownedRepairFreshlyChecksLiveLockDespiteCachedOffState() throws {
        try assertFreshUnownedRepair(cached: false, fresh: true)
    }

    func testUnownedRepairDoesNotReleaseFromStaleCachedOnState() throws {
        try assertFreshUnownedRepair(cached: true, fresh: false)
    }

    private func assertFreshUnownedRepair(cached: Bool, fresh: Bool) throws {
        let first = expectation(description: "off sample collected")
        let blocked = expectation(description: "background live sample blocked")
        let gate = ProbeGate(entered: blocked)
        defer { gate.open() }
        let probe = FreshRepairProbe(first: first, gate: gate, cached: cached, fresh: fresh)
        let store = try makeStore()
        let power = RecordingPowerManager(dryRun: false)
        let service = DSMNHelperXPCService(
            controller: makeController(store: store), powerManager: power,
            liveSleepDisabledProvider: { probe.sample() }
        )
        service.status { _ in }
        wait(for: [first], timeout: 1)
        var status: StatusReport?
        let readyDeadline = Date().addingTimeInterval(1)
        repeat {
            pump(for: 0.01)
            service.status { status = try? self.decode($0).status }
        } while status?.snapshot.powerSource != .ac && Date() < readyDeadline
        wait(for: [blocked], timeout: 1)

        var payload = ""
        service.repair { payload = $0 }

        XCTAssertNil(try decode(payload).error)
        XCTAssertEqual(power.snapshot(), fresh ? [false] : [], "Explicit Repair must use fresh live state")
        XCTAssertFalse(try store.load().ownsSleepDisable)
        gate.open()
        withExtendedLifetime(service) {}
    }

    func testThrownDisplayFollowupStillArmsExpiryCleanupForNewlyAcquiredLock() throws {
        let displayAttempted = expectation(description: "fresh closed-lid display operation attempted")
        let store = try makeStore()
        try store.save(DSMNState(manualUntil: Date().addingTimeInterval(2)))
        let power = RecordingPowerManager(dryRun: false, throwsOnDisplay: true, displayAttempted: displayAttempted)
        let service = DSMNHelperXPCService(
            controller: DSMNController(
                store: store, processListing: StaticProcessListing([]),
                snapshotProvider: StaticSystemSnapshotProvider(SystemSnapshot(powerSource: .ac, lidClosed: true))
            ),
            powerManager: power,
            liveSleepDisabledProvider: { nil }
        )
        var payload = ""
        service.reconcile { payload = $0 }

        XCTAssertNil(try decode(payload).error)
        // Fresh asynchronous telemetry supplies the display edge after the
        // system lock is acquired. Its failure must preserve the expiry timer.
        wait(for: [displayAttempted], timeout: 1)
        XCTAssertTrue(try store.load().ownsSleepDisable)
        let deadline = Date().addingTimeInterval(5)
        while Date() < deadline, try store.load().ownsSleepDisable { pump(for: 0.02) }

        XCTAssertEqual(power.snapshot(), [true, false])
        XCTAssertFalse(try store.load().ownsSleepDisable)
        XCTAssertNil(try store.load().manualUntil)
        XCTAssertEqual(power.displayCount, 1)
        withExtendedLifetime(service) {}
    }

    func testSupersededRepairLiveProbeCannotClearOrReleaseNewManualIntent() throws {
        let entered = expectation(description: "repair live probe entered")
        let replied = expectation(description: "superseded repair replied")
        let gate = ProbeGate(entered: entered)
        defer { gate.open() }
        let store = try makeStore()
        try store.save(DSMNState(manualUntil: Date().addingTimeInterval(300)))
        let power = RecordingPowerManager(dryRun: false)
        let service = DSMNHelperXPCService(
            controller: makeController(store: store), powerManager: power,
            liveSleepDisabledProvider: { gate.wait(); return true }
        )
        let response = PayloadBox()
        DispatchQueue.global().async {
            service.repair { response.set($0); replied.fulfill() }
        }
        wait(for: [entered], timeout: 1)
        XCTAssertNil(try store.load().manualUntil)

        service.enableManual(minutes: 20) { _ in }
        let renewedUntil = try store.load().manualUntil
        XCTAssertNotNil(renewedUntil)
        gate.open()
        wait(for: [replied], timeout: 1)

        XCTAssertTrue(try decode(response.value).error?.contains("superseded") == true)
        XCTAssertEqual(try store.load().manualUntil, renewedUntil)
        XCTAssertFalse(power.snapshot().contains(false), "The old Repair must not release a newer lease")
        withExtendedLifetime(service) {}
    }

    func testConfirmedReleaseInvalidatesCachedAndInflightLiveOwnership() throws {
        let first = expectation(description: "first live sample")
        let blocked = expectation(description: "old live sample blocked")
        let refreshed = expectation(description: "fresh live sample")
        let gate = ProbeGate(entered: blocked)
        defer { gate.open() }
        let liveProbe = SequenceLiveProbe(first: first, gate: gate, refreshed: refreshed)
        let store = try makeStore()
        try store.save(DSMNState(manualUntil: Date().addingTimeInterval(300), ownsSleepDisable: true, lastActivationReason: "manual_timer"))
        let power = RecordingPowerManager(dryRun: false)
        let service = DSMNHelperXPCService(
            controller: makeController(store: store), powerManager: power,
            liveSleepDisabledProvider: { liveProbe.sample() }
        )
        service.status { _ in }
        wait(for: [first], timeout: 1)
        pump(for: 0.05)
        service.status { _ in }
        wait(for: [blocked], timeout: 1)

        service.stop { _ in }
        service.reconcile { _ in }
        XCTAssertEqual(power.snapshot(), [false])
        gate.open()
        wait(for: [refreshed], timeout: 1)
        pump(for: 0.05)

        XCTAssertEqual(power.snapshot(), [false], "An older live=true sample must not trigger a second release")
        XCTAssertFalse(try store.load().ownsSleepDisable)
        withExtendedLifetime(service) {}
    }

    func testPostReleaseSleepUsesFreshConfirmedFactsOnce() throws {
        let store = try makeStore()
        try store.save(DSMNState(manualUntil: Date().addingTimeInterval(300), ownsSleepDisable: true))
        let power = RecordingPowerManager(dryRun: false)
        let service = DSMNHelperXPCService(
            controller: DSMNController(
                store: store, processListing: StaticProcessListing([]),
                snapshotProvider: StaticSystemSnapshotProvider(SystemSnapshot(powerSource: .battery, batteryPercent: 80, lidClosed: true))
            ),
            powerManager: power,
            liveSleepDisabledProvider: { nil }
        )
        service.stop { _ in }
        let deadline = Date().addingTimeInterval(1)
        while power.sleepCount == 0 && Date() < deadline { pump(for: 0.01) }

        XCTAssertEqual(power.snapshot(), [false])
        XCTAssertEqual(power.sleepCount, 1)
        XCTAssertEqual(try store.load().powerOperationHistory.map(\.action), [.enableSleep, .sleepNow])
        withExtendedLifetime(service) {}
    }

    func testBlockedSnapshotProcessAndLiveProbesDoNotBlockStatusOrStop() throws {
        for kind in ["snapshot", "processes", "live"] {
            let entered = expectation(description: "\(kind) entered")
            let gate = ProbeGate(entered: entered)
            defer { gate.open() }
            let store = try makeStore()
            try store.save(DSMNState(manualUntil: Date().addingTimeInterval(300), ownsSleepDisable: true))
            let power = RecordingPowerManager(dryRun: false)
            let service = DSMNHelperXPCService(
                controller: DSMNController(
                    store: store,
                    processListing: kind == "processes" ? GatedProcessListing(gate: gate) : StaticProcessListing([]),
                    snapshotProvider: kind == "snapshot" ? GatedSnapshotProvider(gate: gate) : StaticSystemSnapshotProvider(SystemSnapshot(powerSource: .ac))
                ),
                powerManager: power,
                liveSleepDisabledProvider: { if kind == "live" { gate.wait() }; return nil }
            )
            service.status { _ in }
            wait(for: [entered], timeout: 1)

            let started = Date()
            var statusPayload = ""
            service.status { statusPayload = $0 }
            var stopPayload = ""
            service.stop { stopPayload = $0 }

            XCTAssertLessThan(Date().timeIntervalSince(started), 0.5)
            XCTAssertNil(try decode(statusPayload).error)
            XCTAssertNil(try decode(stopPayload).error)
            XCTAssertEqual(power.snapshot(), [false])
            XCTAssertFalse(try store.load().ownsSleepDisable)
            XCTAssertNil(try store.load().manualUntil)
            XCTAssertFalse(gate.isOpen)
            gate.open()
            withExtendedLifetime(service) {}
        }
    }

    func testExpiryRetriesFailedReleaseWhileOptionalProbeRemainsBlocked() throws {
        try assertBlockedProbeExpiry(firstFailure: .exit(1))
    }

    func testExpiryRetriesThrownReleaseWhileOptionalProbeRemainsBlocked() throws {
        try assertBlockedProbeExpiry(firstFailure: .launchFailure)
    }

    func testRenewalDiscardsOldTelemetryAndKeepsCollectionSingleFlight() throws {
        let entered = expectation(description: "old sample entered")
        let refreshed = expectation(description: "new sample collected")
        let gate = ProbeGate(entered: entered)
        defer { gate.open() }
        let provider = RenewalSnapshotProvider(gate: gate, refreshed: refreshed)
        let store = try makeStore()
        try store.save(DSMNState(manualUntil: Date().addingTimeInterval(300), ownsSleepDisable: true))
        let power = RecordingPowerManager(dryRun: false)
        let service = DSMNHelperXPCService(
            controller: DSMNController(store: store, processListing: StaticProcessListing([]), snapshotProvider: provider),
            powerManager: power,
            liveSleepDisabledProvider: { nil }
        )
        service.status { _ in }
        wait(for: [entered], timeout: 1)
        for _ in 0..<10 { service.status { _ in } }
        XCTAssertEqual(provider.count, 1)
        service.enableManual(minutes: 20) { _ in }
        let renewedUntil = try store.load().manualUntil

        gate.open()
        wait(for: [refreshed], timeout: 1)
        pump(for: 0.1)

        XCTAssertEqual(try store.load().manualUntil, renewedUntil)
        XCTAssertTrue(try store.load().ownsSleepDisable)
        XCTAssertNil(try store.load().noRouteUnavailableSince)
        XCTAssertTrue(power.snapshot().isEmpty, "A pre-renewal low-battery sample must not release the renewed lease")
        XCTAssertEqual(provider.count, 2)
        withExtendedLifetime(service) {}
    }

    func testLatePostReleaseFactsCannotSleepRenewalEvenWhenAcquisitionFailed() throws {
        let entered = expectation(description: "post-release probe entered")
        let returned = expectation(description: "post-release probe returned")
        let gate = ProbeGate(entered: entered)
        defer { gate.open() }
        let store = try makeStore()
        try store.save(DSMNState(manualUntil: Date().addingTimeInterval(300), ownsSleepDisable: true))
        let power = RecordingPowerManager(dryRun: false, outcomes: [.exit(0)], defaultExitCode: 1)
        let service = DSMNHelperXPCService(
            controller: DSMNController(
                store: store, processListing: StaticProcessListing([]),
                snapshotProvider: GatedSleepSnapshotProvider(gate: gate, returned: returned)
            ),
            powerManager: power,
            liveSleepDisabledProvider: { nil }
        )
        service.stop { _ in }
        wait(for: [entered], timeout: 1)
        XCTAssertEqual(power.snapshot(), [false])

        service.enableManual(minutes: 20) { _ in }
        XCTAssertTrue(try store.load().sleepDisablePending)
        XCTAssertFalse(try store.load().ownsSleepDisable)
        gate.open()
        wait(for: [returned], timeout: 1)
        pump(for: 0.2)

        XCTAssertEqual(power.sleepCount, 0)
        XCTAssertNil(try store.load().manualUntil, "Uncertain acquisition is cancelled during recovery")
        XCTAssertTrue(try store.load().sleepDisablePending, "Failed releases must retain responsibility")
        XCTAssertFalse(try store.load().ownsSleepDisable)
        withExtendedLifetime(service) {}
    }

    func testCachedStatusPreservesObservationTimeWhileEvaluatingCurrentLease() throws {
        let observed = Date(timeIntervalSince1970: 1_000)
        let store = try makeStore()
        try store.save(DSMNState(manualUntil: Date().addingTimeInterval(300)))
        let service = DSMNHelperXPCService(
            controller: DSMNController(store: store, processListing: StaticProcessListing([]), snapshotProvider: HistoricalSnapshotProvider(observed: observed)),
            powerManager: RecordingPowerManager(dryRun: false),
            liveSleepDisabledProvider: { nil }
        )
        service.status { _ in }
        var status: StatusReport?
        let deadline = Date().addingTimeInterval(1)
        repeat {
            pump(for: 0.01)
            service.status { status = try? self.decode($0).status }
        } while status?.snapshot.now != observed && Date() < deadline

        XCTAssertEqual(status?.snapshot.now, observed)
        XCTAssertGreaterThan(try XCTUnwrap(status?.generatedAt), observed)
        XCTAssertTrue(status?.decision.shouldPreventSleep == true)
        withExtendedLifetime(service) {}
    }

    private func assertBlockedProbeExpiry(firstFailure: RecordingPowerManager.Outcome) throws {
        let entered = expectation(description: "probe entered before expiry")
        let gate = ProbeGate(entered: entered)
        defer { gate.open() }
        let store = try makeStore()
        try store.save(DSMNState(manualUntil: Date().addingTimeInterval(2), ownsSleepDisable: true))
        let power = RecordingPowerManager(dryRun: false, outcomes: [firstFailure])
        let service = DSMNHelperXPCService(
            controller: DSMNController(store: store, processListing: StaticProcessListing([]), snapshotProvider: GatedSnapshotProvider(gate: gate)),
            powerManager: power,
            liveSleepDisabledProvider: { nil }
        )
        service.reconcile { _ in }
        wait(for: [entered], timeout: 1)
        let deadline = Date().addingTimeInterval(5)
        while Date() < deadline, try store.load().ownsSleepDisable { pump(for: 0.02) }

        XCTAssertEqual(power.snapshot(), [false, false])
        XCTAssertFalse(try store.load().ownsSleepDisable)
        XCTAssertNil(try store.load().manualUntil)
        XCTAssertFalse(gate.isOpen, "Cleanup must finish before optional diagnostics unblock")
        gate.open()
        withExtendedLifetime(service) {}
    }

    private func pump(for interval: TimeInterval) {
        let until = Date().addingTimeInterval(interval)
        while Date() < until { _ = RunLoop.current.run(mode: .default, before: until) }
    }

    func testStopReleasesEvenWhenStatusEnrichmentThrowsAfterIntentIsSaved() throws {
        let store = try makeStore()
        try store.save(DSMNState(manualUntil: Date().addingTimeInterval(300), ownsSleepDisable: true))
        let power = RecordingPowerManager(dryRun: false)
        let service = DSMNHelperXPCService(
            controller: DSMNController(
                store: store,
                processListing: ThrowingProcessListing(),
                snapshotProvider: StaticSystemSnapshotProvider(SystemSnapshot(powerSource: .ac))
            ),
            powerManager: power,
            liveSleepDisabledProvider: { nil }
        )

        var payload = ""
        service.stop { payload = $0 }

        XCTAssertNil(try decode(payload).error)
        XCTAssertNil(try store.load().manualUntil)
        XCTAssertFalse(try store.load().ownsSleepDisable)
        XCTAssertEqual(power.snapshot(), [false])
        withExtendedLifetime(service) {}
    }

    func testRepairReturnsFailureAndRetriesNonzeroReleaseWithoutAnotherCommand() throws {
        try assertRepairRetries(firstOutcomes: [.exit(1)])
    }

    func testRepairReturnsFailureAndRetriesThrownReleaseWithoutAnotherCommand() throws {
        try assertRepairRetries(firstOutcomes: [.launchFailure])
    }

    func testRepairRetrySurvivesAnotherThrownRelease() throws {
        try assertRepairRetries(firstOutcomes: [.launchFailure, .launchFailure])
    }

    func testDryRunRepairReportsFailureAndRetainsOwnership() throws {
        let store = try makeStore()
        try store.save(DSMNState(manualUntil: Date().addingTimeInterval(300), ownsSleepDisable: true))
        let powerManager = RecordingPowerManager(dryRun: true)
        let service = makeService(store: store, powerManager: powerManager)

        var payload = ""
        service.repair { payload = $0 }
        let response = try decode(payload)

        XCTAssertNotNil(response.error)
        XCTAssertNil(response.run)
        XCTAssertTrue(try store.load().ownsSleepDisable)
        XCTAssertNil(try store.load().manualUntil)
        XCTAssertEqual(powerManager.snapshot(), [false])
        withExtendedLifetime(service) {}
    }

    func testFailedExternalLockRepairReportsFailureWithoutClaimingOrRetrying() throws {
        let store = try makeStore()
        try store.save(DSMNState())
        let powerManager = RecordingPowerManager(dryRun: false, outcomes: [.exit(1)])
        let service = DSMNHelperXPCService(
            controller: makeController(store: store),
            powerManager: powerManager,
            liveSleepDisabledProvider: { true }
        )

        var payload = ""
        service.repair { payload = $0 }

        XCTAssertNotNil(try decode(payload).error)
        XCTAssertFalse(try store.load().ownsSleepDisable)
        XCTAssertEqual(powerManager.snapshot(), [false])
        withExtendedLifetime(service) {}
    }

    func testSleepReleaseTimerReconcilesAfterManualTimerExpiresWithoutAnotherCommand() throws {
        let now = Date()
        let store = try makeStore()
        try store.save(DSMNState(manualUntil: now.addingTimeInterval(2)))

        let powerManager = RecordingPowerManager(dryRun: false)
        let controller = DSMNController(
            store: store,
            processListing: StaticProcessListing([]),
            snapshotProvider: StaticSystemSnapshotProvider(SystemSnapshot(now: now, powerSource: .ac))
        )
        let service = DSMNHelperXPCService(
            controller: controller,
            powerManager: powerManager,
            liveSleepDisabledProvider: { nil }
        )

        var response = ""
        service.reconcile {
            response = $0
        }
        XCTAssertNil(try decode(response).error)
        XCTAssertNotNil(try decode(response).run)
        XCTAssertEqual(powerManager.snapshot(), [true])

        var finalState = try store.load()
        let deadline = Date().addingTimeInterval(5)
        while Date() < deadline,
              powerManager.snapshot() != [true, false] || finalState.ownsSleepDisable || finalState.manualUntil != nil {
            RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.02))
            finalState = try store.load()
        }

        XCTAssertEqual(powerManager.snapshot(), [true, false])
        XCTAssertFalse(finalState.ownsSleepDisable)
        XCTAssertNil(finalState.manualUntil)
        withExtendedLifetime(service) {}
    }

    private func assertRepairRetries(firstOutcomes: [RecordingPowerManager.Outcome]) throws {
        let store = try makeStore()
        try store.save(DSMNState(manualUntil: Date().addingTimeInterval(300), ownsSleepDisable: true))
        let powerManager = RecordingPowerManager(dryRun: false, outcomes: firstOutcomes)
        let service = makeService(store: store, powerManager: powerManager)

        var payload = ""
        service.repair { payload = $0 }
        let response = try decode(payload)

        XCTAssertNotNil(response.error)
        XCTAssertNil(response.run)
        XCTAssertEqual(powerManager.snapshot(), [false])
        XCTAssertTrue(try store.load().ownsSleepDisable)
        XCTAssertNil(try store.load().manualUntil)

        let deadline = Date().addingTimeInterval(6)
        while Date() < deadline, try store.load().ownsSleepDisable {
            _ = RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.02))
        }

        XCTAssertEqual(powerManager.snapshot(), Array(repeating: false, count: firstOutcomes.count + 1))
        XCTAssertFalse(try store.load().ownsSleepDisable)
        XCTAssertNil(try store.load().manualUntil)
        XCTAssertEqual(try store.load().lastStopReason, "repair")
        XCTAssertEqual(try store.load().lastPowerOperation?.exitCode, 0)
        withExtendedLifetime(service) {}
    }

    private func makeController(store: StateStore) -> DSMNController {
        DSMNController(
            store: store,
            processListing: StaticProcessListing([]),
            snapshotProvider: StaticSystemSnapshotProvider(SystemSnapshot(powerSource: .ac))
        )
    }

    private func makeService(store: StateStore, powerManager: RecordingPowerManager) -> DSMNHelperXPCService {
        DSMNHelperXPCService(
            controller: makeController(store: store),
            powerManager: powerManager,
            liveSleepDisabledProvider: { nil }
        )
    }

    private func decode(_ payload: String) throws -> DSMNHelperCommandResponse {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(DSMNHelperCommandResponse.self, from: Data(payload.utf8))
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

private struct ThrowingProcessListing: ProcessListing {
    func listProcesses() throws -> [RunningProcess] { throw CocoaError(.fileReadUnknown) }
}

private final class RecordingPowerManager: PowerManaging, @unchecked Sendable {
    enum Outcome {
        case exit(Int32)
        case launchFailure
    }

    private let lock = NSLock()
    private var requests: [Bool] = []
    private var outcomes: [Outcome]
    private var sleepRequests = 0
    private var displayRequests = 0
    private var actions: [PowerOperationAction] = []
    private let defaultExitCode: Int32
    private let throwsOnDisplay: Bool
    private let displayAttempted: XCTestExpectation?
    let dryRun: Bool

    init(dryRun: Bool, outcomes: [Outcome] = [], defaultExitCode: Int32 = 0, throwsOnDisplay: Bool = false, displayAttempted: XCTestExpectation? = nil) {
        self.dryRun = dryRun
        self.outcomes = outcomes
        self.defaultExitCode = defaultExitCode
        self.throwsOnDisplay = throwsOnDisplay
        self.displayAttempted = displayAttempted
    }

    func setSleepDisabled(_ disabled: Bool) throws -> PowerOperationResult {
        lock.lock()
        requests.append(disabled)
        actions.append(disabled ? .disableSleep : .enableSleep)
        let outcome = outcomes.isEmpty ? .exit(defaultExitCode) : outcomes.removeFirst()
        lock.unlock()

        guard case .exit(let exitCode) = outcome else {
            throw CocoaError(.executableNotLoadable)
        }

        return PowerOperationResult(
            requestedSleepDisabled: disabled,
            dryRun: dryRun,
            executedCommand: "recorded",
            exitCode: dryRun ? nil : exitCode
        )
    }

    func snapshot() -> [Bool] {
        lock.lock()
        defer {
            lock.unlock()
        }
        return requests
    }

    var sleepCount: Int { lock.withLock { sleepRequests } }
    var displayCount: Int { lock.withLock { displayRequests } }
    var recordedActions: [PowerOperationAction] { lock.withLock { actions } }
    func requestSleepNow() throws -> PowerOperationResult {
        lock.withLock { sleepRequests += 1; actions.append(.sleepNow) }
        return PowerOperationResult(requestedSleepDisabled: false, dryRun: false, executedCommand: "fake sleep", exitCode: 0, action: .sleepNow)
    }

    func requestDisplaySleepNow() throws -> PowerOperationResult {
        lock.withLock { displayRequests += 1; actions.append(.displaySleepNow) }
        displayAttempted?.fulfill()
        if throwsOnDisplay { throw CocoaError(.executableNotLoadable) }
        return PowerOperationResult(requestedSleepDisabled: false, dryRun: false, executedCommand: "fake display sleep", exitCode: 0, action: .displaySleepNow)
    }
}

private final class ProbeGate: @unchecked Sendable {
    private let condition = NSCondition()
    private var opened = false
    private var signaled = false
    private let entered: XCTestExpectation
    init(entered: XCTestExpectation) { self.entered = entered }
    var isOpen: Bool { condition.withLock { opened } }
    func wait() {
        condition.lock()
        if !signaled { signaled = true; entered.fulfill() }
        while !opened { condition.wait() }
        condition.unlock()
    }
    func open() { condition.withLock { opened = true; condition.broadcast() } }
}

private final class PayloadBox: @unchecked Sendable {
    private let lock = NSLock()
    private var payload = ""
    var value: String { lock.withLock { payload } }
    func set(_ value: String) { lock.withLock { payload = value } }
}

private struct GatedSnapshotProvider: SystemSnapshotProviding {
    let gate: ProbeGate
    func snapshot(now: Date) throws -> SystemSnapshot {
        gate.wait()
        return SystemSnapshot(now: now, powerSource: .ac)
    }
    func sleepSnapshot(now: Date) throws -> SystemSnapshot { SystemSnapshot(now: now, powerSource: .ac) }
}

private final class FirstClosedThenGatedSnapshotProvider: SystemSnapshotProviding, @unchecked Sendable {
    private let lock = NSLock()
    private var calls = 0
    let gate: ProbeGate
    let freshLidClosed: Bool
    init(gate: ProbeGate, freshLidClosed: Bool = true) { self.gate = gate; self.freshLidClosed = freshLidClosed }
    func snapshot(now: Date) throws -> SystemSnapshot {
        let call = lock.withLock { calls += 1; return calls }
        if call > 1 { gate.wait() }
        return SystemSnapshot(now: now, powerSource: .ac, lidClosed: call == 1 ? true : freshLidClosed)
    }
    func sleepSnapshot(now: Date) throws -> SystemSnapshot { SystemSnapshot(now: now, powerSource: .ac) }
}

private struct GatedProcessListing: ProcessListing {
    let gate: ProbeGate
    func listProcesses() throws -> [RunningProcess] { gate.wait(); return [] }
}

private final class RenewalSnapshotProvider: SystemSnapshotProviding, @unchecked Sendable {
    let gate: ProbeGate
    let refreshed: XCTestExpectation
    private let lock = NSLock()
    private var calls = 0
    var count: Int { lock.withLock { calls } }
    init(gate: ProbeGate, refreshed: XCTestExpectation) { self.gate = gate; self.refreshed = refreshed }
    func snapshot(now: Date) throws -> SystemSnapshot {
        let call = lock.withLock { calls += 1; return calls }
        if call == 1 {
            gate.wait()
            return SystemSnapshot(now: now, powerSource: .battery, batteryPercent: 1, defaultRouteAvailable: false)
        }
        if call == 2 { refreshed.fulfill() }
        return SystemSnapshot(now: now, powerSource: .ac, defaultRouteAvailable: true)
    }
}

private struct GatedSleepSnapshotProvider: SystemSnapshotProviding {
    let gate: ProbeGate
    let returned: XCTestExpectation
    func snapshot(now: Date) throws -> SystemSnapshot { SystemSnapshot(now: now, powerSource: .ac) }
    func sleepSnapshot(now: Date) throws -> SystemSnapshot {
        gate.wait()
        returned.fulfill()
        return SystemSnapshot(now: Date(), powerSource: .battery, lidClosed: true)
    }
}

private struct HistoricalSnapshotProvider: SystemSnapshotProviding {
    let observed: Date
    func snapshot(now: Date) throws -> SystemSnapshot { SystemSnapshot(now: observed, powerSource: .ac) }
}

private final class SequenceLiveProbe: @unchecked Sendable {
    private let lock = NSLock()
    private var calls = 0
    let first: XCTestExpectation
    let gate: ProbeGate
    let refreshed: XCTestExpectation
    init(first: XCTestExpectation, gate: ProbeGate, refreshed: XCTestExpectation) {
        self.first = first; self.gate = gate; self.refreshed = refreshed
    }
    func sample() -> Bool? {
        let call = lock.withLock { calls += 1; return calls }
        if call == 1 { first.fulfill(); return true }
        if call == 2 { gate.wait(); return true }
        if call == 3 { refreshed.fulfill() }
        return false
    }
}

private final class FreshRepairProbe: @unchecked Sendable {
    private let lock = NSLock()
    private var calls = 0
    let first: XCTestExpectation
    let gate: ProbeGate
    let cached: Bool
    let fresh: Bool
    init(first: XCTestExpectation, gate: ProbeGate, cached: Bool, fresh: Bool) {
        self.first = first; self.gate = gate; self.cached = cached; self.fresh = fresh
    }
    func sample() -> Bool? {
        let call = lock.withLock { calls += 1; return calls }
        if call == 1 { first.fulfill(); return cached }
        if call == 2 { gate.wait(); return cached }
        return call == 3 ? fresh : false
    }
}
