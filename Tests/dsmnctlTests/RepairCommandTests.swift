import DSMNCore
import XCTest
@testable import dsmnctl

final class RepairCommandTests: XCTestCase {
    func testHelperSuccessDoesNotRunFallbackOrWarn() throws {
        let expected = makeStatus()
        var fallbackCalls = 0
        var warnings: [String] = []

        let result = try DSMNCTL.runRepair(
            { expected },
            fallback: { fallbackCalls += 1; return expected },
            writeWarning: { warnings.append($0) }
        )

        XCTAssertEqual(result, expected)
        XCTAssertEqual(fallbackCalls, 0)
        XCTAssertTrue(warnings.isEmpty)
    }

    func testHelperCommandFailureDoesNotBecomeLocalSuccess() {
        assertDoesNotFallback(DSMNHelperClientError.commandFailed("pmset exited 1"))
    }

    func testInvalidResponseDoesNotBecomeLocalSuccess() {
        assertDoesNotFallback(DSMNHelperClientError.invalidResponse("missing status"))
    }

    func testAmbiguousTimeoutDoesNotBecomeLocalSuccess() {
        assertDoesNotFallback(DSMNHelperClientError.timedOut)
    }

    func testUnknownErrorDoesNotBecomeLocalSuccess() {
        assertDoesNotFallback(CocoaError(.fileReadCorruptFile))
    }

    func testUnavailableTransportRepairsLocalStateOnceWithExplicitWarning() throws {
        let expected = makeStatus()
        var fallbackCalls = 0
        var warnings: [String] = []

        let result = try DSMNCTL.runRepair(
            { throw DSMNHelperClientError.unavailable("connection invalidated") },
            fallback: { fallbackCalls += 1; return expected },
            writeWarning: { warnings.append($0) }
        )

        XCTAssertEqual(result, expected)
        XCTAssertEqual(fallbackCalls, 1)
        XCTAssertEqual(warnings.count, 1)
        XCTAssertTrue(warnings.first?.contains("only local state was repaired") == true)
        XCTAssertTrue(warnings.first?.contains("system power lock was not changed") == true)
    }

    func testFailedLocalFallbackDoesNotAnnounceSuccessfulRepair() {
        var warnings: [String] = []

        XCTAssertThrowsError(try DSMNCTL.runRepair(
            { throw DSMNHelperClientError.unavailable("connection invalidated") },
            fallback: { throw CocoaError(.fileWriteNoPermission) },
            writeWarning: { warnings.append($0) }
        ))

        XCTAssertTrue(warnings.isEmpty)
    }

    private func assertDoesNotFallback(_ error: Error, file: StaticString = #filePath, line: UInt = #line) {
        var fallbackCalls = 0
        var warnings: [String] = []
        XCTAssertThrowsError(try DSMNCTL.runRepair(
            { throw error },
            fallback: { fallbackCalls += 1; return self.makeStatus() },
            writeWarning: { warnings.append($0) }
        ), file: file, line: line) { actual in
            XCTAssertEqual(actual.localizedDescription, error.localizedDescription, file: file, line: line)
        }
        XCTAssertEqual(fallbackCalls, 0, file: file, line: line)
        XCTAssertTrue(warnings.isEmpty, file: file, line: line)
    }

    private func makeStatus() -> StatusReport {
        let now = Date(timeIntervalSince1970: 1_000)
        return StatusReport(
            generatedAt: now,
            state: DSMNState(),
            snapshot: SystemSnapshot(now: now),
            agents: [],
            decision: PowerDecision(shouldPreventSleep: false, reasons: [], safetyBlocks: [], stopReason: "repair"),
            manualRemainingSeconds: nil
        )
    }
}
