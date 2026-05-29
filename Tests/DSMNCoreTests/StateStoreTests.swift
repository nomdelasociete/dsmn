import XCTest
@testable import DSMNCore

final class StateStoreTests: XCTestCase {
    func testRoundTripsState() throws {
        let directory = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("dsmn-\(UUID().uuidString)", isDirectory: true)
        defer {
            try? FileManager.default.removeItem(at: directory)
        }

        let store = StateStore(directory: directory)
        let createdAt = Date(timeIntervalSince1970: 1_000)
        let updatedAt = Date(timeIntervalSince1970: 2_000)
        let state = DSMNState(
            manualUntil: Date(timeIntervalSince1970: 3_000),
            ownsSleepDisable: true,
            lastActivationReason: "manual_timer",
            lastStopReason: nil,
            createdAt: createdAt,
            updatedAt: updatedAt
        )

        try store.save(state)

        XCTAssertEqual(try store.load(), state)
    }

    func testMissingStateReturnsDefaultState() throws {
        let directory = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("dsmn-\(UUID().uuidString)", isDirectory: true)
        defer {
            try? FileManager.default.removeItem(at: directory)
        }

        let store = StateStore(directory: directory)

        XCTAssertNil(try store.load().manualUntil)
        XCTAssertFalse(try store.load().ownsSleepDisable)
    }
}
