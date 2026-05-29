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

    func testAutoWaitsWhenNoAgentsAreActive() {
        let now = Date(timeIntervalSince1970: 1_000)
        let state = DSMNState(autoEnabled: true)
        let decision = PowerDecisionEngine().evaluate(
            state: state,
            agents: [],
            snapshot: SystemSnapshot(now: now)
        )

        XCTAssertFalse(decision.shouldPreventSleep)
        XCTAssertEqual(decision.reasons, ["auto_waiting_for_agents"])
        XCTAssertEqual(decision.stopReason, "auto_waiting_for_agents")
    }

    func testAutoPreventsSleepWhenAgentIsActive() {
        let now = Date(timeIntervalSince1970: 1_000)
        let state = DSMNState(autoEnabled: true, autoEnabledAt: now)
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
            state: state,
            agents: agents,
            snapshot: SystemSnapshot(now: now)
        )

        XCTAssertTrue(decision.shouldPreventSleep)
        XCTAssertEqual(decision.reasons, ["auto_agents_active"])
    }

    func testAutoPreventsSleepWhenHookActivityIsFresh() {
        let now = Date(timeIntervalSince1970: 3_000)
        let state = DSMNState(
            autoEnabled: true,
            autoEnabledAt: now.addingTimeInterval(-3_600),
            lastRequester: ActivationRequester(
                name: "Codex",
                context: "dsmn - session abc12345",
                requestedAt: now.addingTimeInterval(-60)
            )
        )
        let agents = [
            AgentProcess(pid: 200, ppid: 1, executable: "/opt/homebrew/bin/codex", command: "codex", kind: .codex)
        ]

        let decision = PowerDecisionEngine().evaluate(
            state: state,
            agents: agents,
            snapshot: SystemSnapshot(now: now)
        )

        XCTAssertTrue(decision.shouldPreventSleep)
        XCTAssertEqual(decision.reasons, ["auto_agents_active"])
    }

    func testAutoDoesNotPreventSleepWhenOnlyAgentProcessIsStale() {
        let now = Date(timeIntervalSince1970: 3_000)
        let state = DSMNState(
            autoEnabled: true,
            autoEnabledAt: now.addingTimeInterval(-3_600),
            lastRequester: ActivationRequester(
                name: "Claude Code",
                context: "jb - session abc12345",
                requestedAt: now.addingTimeInterval(-3_600)
            )
        )
        let agents = [
            AgentProcess(
                pid: 201,
                ppid: 1,
                executable: "/Users/jb/Library/Application Support/Claude/claude-code/claude",
                command: "claude --dangerously-skip-permissions",
                kind: .claudeCode
            )
        ]

        let decision = PowerDecisionEngine().evaluate(
            state: state,
            agents: agents,
            snapshot: SystemSnapshot(now: now)
        )

        XCTAssertFalse(decision.shouldPreventSleep)
        XCTAssertEqual(decision.reasons, ["auto_activity_stale"])
        XCTAssertEqual(decision.stopReason, "auto_activity_stale")
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
}
