import XCTest
@testable import DSMNCore

final class PowerDecisionEngineTests: XCTestCase {
    private let policy = SafetyPolicy(lidOpenGraceSeconds: 300)

    func testManualTimerPreventsSleep() {
        let now = Date(timeIntervalSince1970: 1_000)
        let state = DSMNState(manualUntil: now.addingTimeInterval(60))
        let decision = PowerDecisionEngine(policy: policy).evaluate(
            state: state,
            agents: [],
            snapshot: SystemSnapshot(now: now)
        )

        XCTAssertTrue(decision.shouldPreventSleep)
        XCTAssertEqual(decision.reasons, ["manual_timer"])
    }

    func testManualTimerWithLidClosedPreventsSleep() {
        let now = Date(timeIntervalSince1970: 1_000)
        let state = DSMNState(manualUntil: now.addingTimeInterval(60), lastLidClosed: true)
        let decision = PowerDecisionEngine(policy: policy).evaluate(
            state: state,
            agents: [],
            snapshot: SystemSnapshot(now: now, lidClosed: true)
        )

        XCTAssertTrue(decision.shouldPreventSleep)
        XCTAssertEqual(decision.reasons, ["manual_timer"])
    }

    func testLidOpenDuringManualLeaseStaysActiveDuringGrace() {
        let openedAt = Date(timeIntervalSince1970: 1_000)
        let now = openedAt.addingTimeInterval(60)
        var state = DSMNState(manualUntil: now.addingTimeInterval(600))
        state.lidOpenedAt = openedAt
        state.lastLidClosed = false

        let decision = PowerDecisionEngine(policy: policy).evaluate(
            state: state,
            agents: [],
            snapshot: SystemSnapshot(now: now, lidClosed: false)
        )

        XCTAssertTrue(decision.shouldPreventSleep)
        XCTAssertEqual(decision.reasons, ["manual_timer", "lid_open_grace"])
    }

    func testLidOpenGraceElapsedReleasesSleepPreventionWhileManualTimerRuns() {
        let openedAt = Date(timeIntervalSince1970: 1_000)
        let now = openedAt.addingTimeInterval(TimeInterval(policy.lidOpenGraceSeconds + 1))
        var state = DSMNState(manualUntil: now.addingTimeInterval(600))
        state.lidOpenedAt = openedAt
        state.lastLidClosed = false

        let decision = PowerDecisionEngine(policy: policy).evaluate(
            state: state,
            agents: [],
            snapshot: SystemSnapshot(now: now, lidClosed: false)
        )

        XCTAssertFalse(decision.shouldPreventSleep)
        XCTAssertEqual(decision.reasons, ["manual_timer"])
        XCTAssertEqual(decision.stopReason, "lid_open_grace_elapsed")
    }

    func testLidOpenTransitionSetsAnchorAndKeepsSleepPrevention() {
        let now = Date(timeIntervalSince1970: 1_000)
        var state = DSMNState(manualUntil: now.addingTimeInterval(600), lastLidClosed: true)
        state.syncLidOpenGrace(with: SystemSnapshot(now: now, lidClosed: false))

        XCTAssertEqual(state.lidOpenedAt, now)

        let decision = PowerDecisionEngine(policy: policy).evaluate(
            state: state,
            agents: [],
            snapshot: SystemSnapshot(now: now, lidClosed: false)
        )

        XCTAssertTrue(decision.shouldPreventSleep)
        XCTAssertEqual(decision.reasons, ["manual_timer", "lid_open_grace"])
    }

    func testAgentProcessAloneDoesNotPreventSleep() {
        let now = Date(timeIntervalSince1970: 1_000)
        let agents = [
            AgentProcess(
                pid: 200,
                ppid: 1,
                executable: "/opt/homebrew/bin/codex",
                command: "codex",
                kind: .codex
            )
        ]
        let decision = PowerDecisionEngine(policy: policy).evaluate(
            state: DSMNState(),
            agents: agents,
            snapshot: SystemSnapshot(now: now)
        )

        XCTAssertFalse(decision.shouldPreventSleep)
        XCTAssertEqual(decision.reasons, [])
        XCTAssertEqual(decision.stopReason, "not_armed")
    }

    func testLowBatteryBlocksSleepPrevention() {
        let now = Date(timeIntervalSince1970: 1_000)
        let state = DSMNState(manualUntil: now.addingTimeInterval(60))
        let decision = PowerDecisionEngine(policy: policy).evaluate(
            state: state,
            agents: [],
            snapshot: SystemSnapshot(now: now, powerSource: .battery, batteryPercent: 10)
        )

        XCTAssertFalse(decision.shouldPreventSleep)
        XCTAssertEqual(decision.safetyBlocks, ["battery_below_threshold"])
        XCTAssertEqual(decision.stopReason, "battery_below_threshold")
    }
}