import DSMNCore
import XCTest
@testable import dsmnapp

@MainActor
final class StopOutcomeTests: XCTestCase {
    func testConfirmedHelperStopDoesNotUseLocalCleanup() async {
        let report = stoppedReport()
        var helperCalls = 0
        var localCalls = 0
        let outcome = await StopRequest.run(helper: {
            helperCalls += 1
            return report
        }, local: {
            localCalls += 1
            return report
        })
        XCTAssertEqual(outcome, .helperConfirmed(report))
        XCTAssertEqual(helperCalls, 1)
        XCTAssertEqual(localCalls, 0)
    }

    func testUnavailableHelperCanClearOnlyLocalIntent() async {
        let report = stoppedReport()
        let outcome = await StopRequest.run(helper: {
            throw DSMNHelperClientError.unavailable("test connection")
        }, local: { report })
        XCTAssertEqual(outcome, .localOnly(report, helperError: "Helper unavailable: test connection"))
        XCTAssertFalse(outcome.isHelperConfirmed)
        XCTAssertTrue(outcome.failureMessage?.contains("test connection") == true)
    }

    func testStillOwnedHelperResponseIsUnconfirmed() async {
        var report = stoppedReport()
        report.state.ownsSleepDisable = true
        let outcome = await StopRequest.run(helper: { report }, local: {
            XCTFail("A helper response must not trigger local cleanup")
            return self.stoppedReport()
        })
        XCTAssertFalse(outcome.isHelperConfirmed)
        XCTAssertEqual(outcome.report, report)
        XCTAssertNotNil(outcome.failureMessage)
    }

    func testStillArmedHelperResponseIsUnconfirmedEvenWithExpiredDate() async {
        var report = stoppedReport()
        report.state.manualUntil = report.generatedAt.addingTimeInterval(-1)
        let outcome = await StopRequest.run(helper: { report }, local: { self.stoppedReport() })
        XCTAssertFalse(outcome.isHelperConfirmed)
        XCTAssertNotNil(outcome.failureMessage)
    }

    func testCommandFailureDoesNotFallBackToLocalCleanup() async {
        var localCalls = 0
        let outcome = await StopRequest.run(helper: {
            throw DSMNHelperClientError.commandFailed("release rejected")
        }, local: {
            localCalls += 1
            return self.stoppedReport()
        })
        guard case .unconfirmed = outcome else {
            return XCTFail("Command failure must remain unconfirmed")
        }
        XCTAssertEqual(localCalls, 0)
        XCTAssertTrue(outcome.failureMessage?.contains("release rejected") == true)
    }

    func testTimeoutInvalidResponseAndUnexpectedErrorsDoNotRetryOrClearLocally() async {
        let errors: [Error] = [
            DSMNHelperClientError.timedOut,
            DSMNHelperClientError.invalidResponse("missing status"),
            TestFailure.failed
        ]
        for error in errors {
            var helperCalls = 0
            var localCalls = 0
            let outcome = await StopRequest.run(helper: {
                helperCalls += 1
                throw error
            }, local: {
                localCalls += 1
                return self.stoppedReport()
            })
            guard case .unconfirmed = outcome else {
                XCTFail("Expected unconfirmed result for \(error)")
                continue
            }
            XCTAssertEqual(helperCalls, 1)
            XCTAssertEqual(localCalls, 0)
            XCTAssertTrue(outcome.failureMessage?.contains(error.localizedDescription) == true)
        }
    }

    func testUnavailableHelperAndFailedLocalCleanupRetainBothErrors() async {
        let outcome = await StopRequest.run(helper: {
            throw DSMNHelperClientError.unavailable("test connection")
        }, local: { throw TestFailure.failed })
        guard case .unconfirmed = outcome else {
            return XCTFail("Local cleanup failure cannot confirm a helper stop")
        }
        XCTAssertTrue(outcome.failureMessage?.contains("test connection") == true)
        XCTAssertTrue(outcome.failureMessage?.contains(TestFailure.failed.localizedDescription) == true)
    }

    func testStoreAttemptsHelperOnceDespiteMisleadingRegistration() async throws {
        for registration in [HelperRegistrationStatus.notRegistered, .notFound, .requiresApproval] {
            let controller = try temporaryController()
            let report = stoppedReport()
            var helperCalls = 0
            let store = DSMNMenuStore(controller: controller, helperStatus: registration, stopHelper: {
                helperCalls += 1
                return report
            })
            let outcome = await store.stopNow()
            XCTAssertEqual(outcome, .helperConfirmed(report))
            XCTAssertEqual(helperCalls, 1)
            XCTAssertEqual(store.helperStatus, .enabled)
            XCTAssertNil(store.errorMessage)
            XCTAssertFalse(store.hasUnconfirmedStop)
        }
    }

    func testStoreLocalCleanupDoesNotEraseHelperFailure() async throws {
        let controller = try temporaryController()
        var state = try controller.store.load()
        state.manualUntil = Date().addingTimeInterval(600)
        try controller.store.save(state)
        var helperCalls = 0
        let store = DSMNMenuStore(controller: controller, helperStatus: .enabled, stopHelper: {
            helperCalls += 1
            throw DSMNHelperClientError.unavailable("isolated helper unavailable")
        })
        let outcome = await store.stopNow()
        guard case .localOnly = outcome else { return XCTFail("Expected local-only cleanup") }
        XCTAssertEqual(helperCalls, 1)
        XCTAssertNil(try controller.store.load().manualUntil)
        XCTAssertEqual(store.errorMessage, outcome.failureMessage)
        XCTAssertTrue(store.errorMessage?.contains("isolated helper unavailable") == true)
        XCTAssertTrue(store.hasUnconfirmedStop)
    }

    func testConfirmedRetryClearsPreviousUnconfirmedMessage() async throws {
        let controller = try temporaryController()
        let report = stoppedReport()
        var helperCalls = 0
        let store = DSMNMenuStore(controller: controller, helperStatus: .notFound, stopHelper: {
            helperCalls += 1
            if helperCalls == 1 { throw DSMNHelperClientError.timedOut }
            return report
        })
        _ = await store.stopNow()
        XCTAssertTrue(store.hasUnconfirmedStop)
        XCTAssertNotNil(store.errorMessage)
        let retry = await store.stopNow()
        XCTAssertTrue(retry.isHelperConfirmed)
        XCTAssertFalse(store.hasUnconfirmedStop)
        XCTAssertNil(store.errorMessage)
        XCTAssertEqual(helperCalls, 2)
    }

    func testFailedStopKeepsKnownHelperProtectionVisible() async throws {
        let controller = try temporaryController()
        var protected = stoppedReport()
        protected.state.ownsSleepDisable = true
        protected.state.manualUntil = Date().addingTimeInterval(600)
        let store = DSMNMenuStore(
            controller: controller,
            helperStatus: .notFound,
            initialReport: protected,
            stopHelper: { throw DSMNHelperClientError.commandFailed("injected release failure") }
        )
        let outcome = await store.stopNow()
        XCTAssertFalse(outcome.isHelperConfirmed)
        XCTAssertEqual(store.report, protected)
        XCTAssertTrue(store.isProtectingSleep)
        XCTAssertTrue(store.hasUnconfirmedStop)
        XCTAssertTrue(store.errorMessage?.contains("injected release failure") == true)
    }

    private func temporaryController() throws -> DSMNController {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("dsmn-stop-test-\(UUID())")
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        return DSMNController(
            store: StateStore(directory: directory),
            processListing: EmptyProcessListing(),
            snapshotProvider: UnknownSnapshotProvider()
        )
    }

    private func stoppedReport() -> StatusReport {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        return StatusReport(
            generatedAt: now,
            state: DSMNState(createdAt: now, updatedAt: now),
            snapshot: SystemSnapshot(now: now),
            agents: [],
            decision: PowerDecision(shouldPreventSleep: false, reasons: [], safetyBlocks: []),
            manualRemainingSeconds: nil
        )
    }
}

private enum TestFailure: Error { case failed }

private struct EmptyProcessListing: ProcessListing {
    func listProcesses() throws -> [RunningProcess] { [] }
}

private struct UnknownSnapshotProvider: SystemSnapshotProviding {
    func snapshot(now: Date) throws -> SystemSnapshot { SystemSnapshot(now: now) }
}
