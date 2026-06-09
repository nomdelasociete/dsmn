import DSMNCore
import XCTest
@testable import dsmnd

final class HelperXPCServiceSchedulerTests: XCTestCase {
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
        XCTAssertTrue(response.contains(#""success""#) || response.contains(#""status""#), response)
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
    private let lock = NSLock()
    private var requests: [Bool] = []
    let dryRun: Bool

    init(dryRun: Bool) {
        self.dryRun = dryRun
    }

    func setSleepDisabled(_ disabled: Bool) throws -> PowerOperationResult {
        lock.lock()
        requests.append(disabled)
        lock.unlock()

        return PowerOperationResult(
            requestedSleepDisabled: disabled,
            dryRun: dryRun,
            executedCommand: "recorded",
            exitCode: dryRun ? nil : 0
        )
    }

    func snapshot() -> [Bool] {
        lock.lock()
        defer {
            lock.unlock()
        }
        return requests
    }
}
