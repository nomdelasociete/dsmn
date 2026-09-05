import XCTest
@testable import DSMNCore

final class HelperCommandResponseTests: XCTestCase {
    func testHelperErrorEnvelopeIsACommandFailure() throws {
        XCTAssertThrowsError(try DSMNHelperXPCClient.decodeResponse(#"{"error":"pmset failed"}"#)) { error in
            guard case DSMNHelperClientError.commandFailed(let message) = error else {
                return XCTFail("Expected command failure, received \(error)")
            }
            XCTAssertEqual(message, "pmset failed")
        }
    }

    func testMalformedEnvelopeIsAnInvalidResponse() {
        for payload in ["not json", #"{"error":5}"#] {
            XCTAssertThrowsError(try DSMNHelperXPCClient.decodeResponse(payload)) { error in
                guard case DSMNHelperClientError.invalidResponse = error else {
                    return XCTFail("Expected invalid response, received \(error)")
                }
            }
        }
    }

    func testSuccessfulStatusEnvelopeStillDecodes() throws {
        let now = Date(timeIntervalSince1970: 1_000)
        let status = StatusReport(
            generatedAt: now,
            state: DSMNState(createdAt: now, updatedAt: now),
            snapshot: SystemSnapshot(now: now),
            agents: [],
            decision: PowerDecision(shouldPreventSleep: false, reasons: [], safetyBlocks: [], stopReason: "repair"),
            manualRemainingSeconds: nil
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(DSMNHelperCommandResponse.success(status: status))

        let response = try DSMNHelperXPCClient.decodeResponse(String(decoding: data, as: UTF8.self))

        XCTAssertEqual(response.status, status)
        XCTAssertNil(response.error)
    }
}
