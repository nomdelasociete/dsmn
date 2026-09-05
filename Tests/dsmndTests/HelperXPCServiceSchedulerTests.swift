import DSMNCore
import XCTest
@testable import dsmnd

final class HelperXPCServiceSchedulerTests: XCTestCase {
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

private final class RecordingPowerManager: PowerManaging, @unchecked Sendable {
    enum Outcome {
        case exit(Int32)
        case launchFailure
    }

    private let lock = NSLock()
    private var requests: [Bool] = []
    private var outcomes: [Outcome]
    let dryRun: Bool

    init(dryRun: Bool, outcomes: [Outcome] = []) {
        self.dryRun = dryRun
        self.outcomes = outcomes
    }

    func setSleepDisabled(_ disabled: Bool) throws -> PowerOperationResult {
        lock.lock()
        requests.append(disabled)
        let outcome = outcomes.isEmpty ? .exit(0) : outcomes.removeFirst()
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
}
