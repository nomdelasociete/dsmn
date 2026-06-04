import XCTest
@testable import DSMNCore

final class PowerDecisionEngineTests: XCTestCase {
    func testManualTimerPreventsSleep() {
        let now = Date(timeIntervalSince1970: 1_000)
        let state = DSMNState(manualUntil: now.addingTimeInterval(60))
        let decision = PowerDecisionEngine().evaluate(
            state: state,
            agents: [],
            snapshot: SystemSnapshot(now: now)
        )

        XCTAssertTrue(decision.shouldPreventSleep)
        XCTAssertEqual(decision.reasons, ["manual_timer"])
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
        let decision = PowerDecisionEngine().evaluate(
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
        let decision = PowerDecisionEngine().evaluate(
            state: state,
            agents: [],
            snapshot: SystemSnapshot(now: now, powerSource: .battery, batteryPercent: 10)
        )

        XCTAssertFalse(decision.shouldPreventSleep)
        XCTAssertEqual(decision.safetyBlocks, ["battery_below_threshold"])
        XCTAssertEqual(decision.stopReason, "battery_below_threshold")
    }

    func testNoRouteAtStartOfGraceDoesNotBlockActiveManual() {
        let now = Date(timeIntervalSince1970: 10_000)
        let state = DSMNState(
            manualUntil: now.addingTimeInterval(60 * 60),
            noRouteUnavailableSince: now
        )
        let decision = PowerDecisionEngine().evaluate(
            state: state,
            agents: [],
            snapshot: SystemSnapshot(now: now, defaultRouteAvailable: false)
        )

        XCTAssertTrue(decision.shouldPreventSleep)
        XCTAssertEqual(decision.safetyBlocks, [])
        XCTAssertEqual(decision.reasons, ["manual_timer"])
    }

    func testNoRouteAfterGraceBlocksActiveManual() {
        let now = Date(timeIntervalSince1970: 20_000)
        let graceSeconds = 15 * 60
        let state = DSMNState(
            manualUntil: now.addingTimeInterval(60 * 60),
            noRouteUnavailableSince: now.addingTimeInterval(-TimeInterval(graceSeconds))
        )
        let decision = PowerDecisionEngine().evaluate(
            state: state,
            agents: [],
            snapshot: SystemSnapshot(now: now, defaultRouteAvailable: false)
        )

        XCTAssertFalse(decision.shouldPreventSleep)
        XCTAssertEqual(decision.safetyBlocks, ["network_unavailable"])
        XCTAssertEqual(decision.stopReason, "network_unavailable")
    }

    func testNoRouteWithoutManualTimerDoesNotAddSafetyBlock() {
        let now = Date(timeIntervalSince1970: 30_000)
        let state = DSMNState(
            noRouteUnavailableSince: now.addingTimeInterval(-60 * 60)
        )
        let decision = PowerDecisionEngine().evaluate(
            state: state,
            agents: [],
            snapshot: SystemSnapshot(now: now, defaultRouteAvailable: false)
        )

        XCTAssertFalse(decision.shouldPreventSleep)
        XCTAssertEqual(decision.safetyBlocks, [])
    }
}
