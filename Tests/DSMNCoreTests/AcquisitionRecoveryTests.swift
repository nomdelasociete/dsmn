import XCTest
@testable import DSMNCore

final class AcquisitionRecoveryTests: XCTestCase {
    func testInterruptedAcquisitionIsJournaledBeforePowerChangeAndRecovered() throws {
        try assertRecovery(failOwnershipSave: false)
    }

    func testSuccessfulPowerChangeWithFailedOwnershipSaveIsRecovered() throws {
        try assertRecovery(failOwnershipSave: true)
    }

    private func assertRecovery(failOwnershipSave: Bool) throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = StateStore(directory: directory)
        let now = Date()
        try store.save(DSMNState(manualUntil: now.addingTimeInterval(600)))
        let controller = DSMNController(store: store)
        let power = InterruptedAcquisitionPower(store: store, failOwnershipSave: failOwnershipSave)
        XCTAssertThrowsError(try controller.reconcile(powerManager: power, telemetry: .unavailable(at: now), now: now))
        XCTAssertTrue(power.lockEnabled)
        XCTAssertTrue(power.observedPendingBeforeCommand)
        if failOwnershipSave {
            // Restore the last durable bytes after a simulated storage failure.
            try FileManager.default.removeItem(at: store.stateURL)
            try XCTUnwrap(power.durableJournal).write(to: store.stateURL)
        }
        XCTAssertTrue(try store.load().sleepDisablePending)
        XCTAssertFalse(try store.load().ownsSleepDisable)
        XCTAssertNotNil(ReconcileSchedule.sleepReleaseDeadline(for: try store.load(), now: now).deadline)
        // A fresh controller, without system probes or another manual command.
        let restarted = DSMNController(store: store)
        XCTAssertTrue(try restarted.needsMandatoryRelease(now: now))
        _ = try restarted.reconcile(powerManager: power, telemetry: .unavailable(at: now), now: now)
        XCTAssertFalse(power.lockEnabled)
        XCTAssertEqual(power.commands, [true, false])
        XCTAssertFalse(try store.load().sleepDisablePending)
        XCTAssertFalse(try store.load().ownsSleepDisable)
        XCTAssertNil(try store.load().manualUntil)
        XCTAssertEqual(try store.load().lastStopReason, "interrupted_acquisition")
    }

    func testOldStateHasNoPendingAcquisition() throws {
        let data = Data("{\"ownsSleepDisable\":false}".utf8)
        XCTAssertFalse(try JSONDecoder().decode(DSMNState.self, from: data).sleepDisablePending)
    }
}

private final class InterruptedAcquisitionPower: PowerManaging, @unchecked Sendable {
    let store: StateStore
    let failOwnershipSave: Bool
    var lockEnabled = false
    var commands: [Bool] = []
    var observedPendingBeforeCommand = false
    var durableJournal: Data?

    init(store: StateStore, failOwnershipSave: Bool) {
        self.store = store
        self.failOwnershipSave = failOwnershipSave
    }

    func setSleepDisabled(_ disabled: Bool) throws -> PowerOperationResult {
        commands.append(disabled)
        if disabled {
            observedPendingBeforeCommand = try store.load().sleepDisablePending
            durableJournal = try Data(contentsOf: store.stateURL)
            lockEnabled = true
            if failOwnershipSave {
                try FileManager.default.removeItem(at: store.stateURL)
                try FileManager.default.createDirectory(at: store.stateURL, withIntermediateDirectories: false)
            } else {
                throw CocoaError(.executableNotLoadable)
            }
        } else {
            lockEnabled = false
        }
        return PowerOperationResult(requestedSleepDisabled: disabled, dryRun: false,
                                    executedCommand: "mock pmset", exitCode: 0)
    }
}
