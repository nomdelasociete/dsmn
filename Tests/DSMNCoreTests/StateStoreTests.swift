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

    func testLoadsStateWrittenBeforeRecentRequesters() throws {
        let directory = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("dsmn-\(UUID().uuidString)", isDirectory: true)
        defer {
            try? FileManager.default.removeItem(at: directory)
        }

        let store = StateStore(directory: directory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try """
        {
          "createdAt" : "1970-01-01T00:16:40Z",
          "lastRequester" : {
            "context" : "dsmn-website",
            "event" : "tool_call",
            "name" : "Pi",
            "requestedAt" : "1970-01-01T00:16:41Z"
          },
          "manualUntil" : "1970-01-01T00:30:00Z",
          "ownsSleepDisable" : true,
          "updatedAt" : "1970-01-01T00:16:41Z"
        }
        """.write(to: store.stateURL, atomically: true, encoding: .utf8)

        let state = try store.load()

        XCTAssertEqual(state.lastRequester?.name, "Pi")
        XCTAssertEqual(state.recentRequesters, [try XCTUnwrap(state.lastRequester)])
    }
}
