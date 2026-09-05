import DSMNCore
import XCTest
@testable import dsmnapp

@MainActor
final class AppQuitCoordinatorTests: XCTestCase {
    func testConfirmedStopTerminatesExactlyOnceAfterResponse() async {
        let fixture = Fixture()
        await fixture.request(.stopAndQuit)
        await fixture.request(.stopAndQuit)
        XCTAssertEqual(fixture.events, ["stop", "response", "terminate"])
        XCTAssertEqual(fixture.terminations, 1)
        XCTAssertTrue(fixture.failures.isEmpty)
    }

    func testEveryUnconfirmedOutcomeKeepsAppOpen() async {
        let report = Fixture.report()
        let outcomes: [StopOutcome] = [
            .localOnly(report, helperError: "helper unavailable"),
            .unconfirmed(report: nil, message: "helper timed out"),
            .unconfirmed(report: report, message: "power lock still owned")
        ]
        for outcome in outcomes {
            let fixture = Fixture(outcome: outcome)
            await fixture.request(.stopAndQuit)
            XCTAssertEqual(fixture.terminations, 0)
            XCTAssertEqual(fixture.failures, [outcome.failureMessage!])
            XCTAssertEqual(fixture.events, ["stop", "response", "failure"])
        }
    }

    func testDelayedStopAndDuplicateRequestWaitForSingleConfirmation() async {
        let fixture = Fixture()
        let started = expectation(description: "Stop entered")
        var continuation: CheckedContinuation<StopOutcome, Never>?
        fixture.stopOperation = {
            await withCheckedContinuation {
                continuation = $0
                started.fulfill()
            }
        }
        let first = Task { await fixture.request(.stopAndQuit) }
        await fulfillment(of: [started], timeout: 1)
        XCTAssertEqual(fixture.terminations, 0)
        await fixture.request(.stopAndQuit)
        XCTAssertEqual(fixture.events, ["stop"])
        XCTAssertEqual(fixture.terminations, 0)
        continuation?.resume(returning: .helperConfirmed(Fixture.report()))
        await first.value
        XCTAssertEqual(fixture.events, ["stop", "response", "terminate"])
        XCTAssertEqual(fixture.terminations, 1)
    }

    func testFailedStopCanBeRetried() async {
        let fixture = Fixture(outcome: .unconfirmed(report: nil, message: "release failed"))
        await fixture.request(.stopAndQuit)
        fixture.stopOperation = { .helperConfirmed(Fixture.report()) }
        await fixture.request(.stopAndQuit)
        XCTAssertEqual(fixture.events, ["stop", "response", "failure", "stop", "response", "terminate"])
        XCTAssertEqual(fixture.terminations, 1)
    }

    func testKeepRunningQuitsWithoutRequestingStop() async {
        let fixture = Fixture()
        await fixture.request(.keepRunning)
        await fixture.request(.keepRunning)
        XCTAssertEqual(fixture.events, ["terminate"])
        XCTAssertEqual(fixture.terminations, 1)
    }

    func testCancelDoesNotStopOrTerminate() async {
        let fixture = Fixture()
        await fixture.request(.cancel)
        XCTAssertTrue(fixture.events.isEmpty)
        XCTAssertEqual(fixture.terminations, 0)
        XCTAssertTrue(fixture.failures.isEmpty)
    }

    func testExplicitKeepRunningDuringPendingStopDoesNotTerminateTwice() async {
        let fixture = Fixture()
        let started = expectation(description: "Stop entered")
        var continuation: CheckedContinuation<StopOutcome, Never>?
        fixture.stopOperation = {
            await withCheckedContinuation {
                continuation = $0
                started.fulfill()
            }
        }
        let pending = Task { await fixture.request(.stopAndQuit) }
        await fulfillment(of: [started], timeout: 1)
        await fixture.request(.keepRunning)
        continuation?.resume(returning: .unconfirmed(report: nil, message: "too late"))
        await pending.value
        XCTAssertEqual(fixture.terminations, 1)
        XCTAssertTrue(fixture.failures.isEmpty)
        XCTAssertEqual(fixture.events, ["stop", "terminate", "response"])
    }
}

@MainActor
private final class Fixture {
    let coordinator = AppQuitCoordinator()
    var stopOperation: () async -> StopOutcome
    var events: [String] = []
    var terminations = 0
    var failures: [String] = []

    init(outcome: StopOutcome? = nil) {
        stopOperation = { outcome ?? .helperConfirmed(Self.report()) }
    }

    func request(_ choice: AppQuitChoice) async {
        await coordinator.request(choice, stop: {
            self.events.append("stop")
            let outcome = await self.stopOperation()
            self.events.append("response")
            return outcome
        }, terminate: {
            self.events.append("terminate")
            self.terminations += 1
        }, presentFailure: {
            self.events.append("failure")
            self.failures.append($0)
        })
    }

    static func report() -> StatusReport {
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
