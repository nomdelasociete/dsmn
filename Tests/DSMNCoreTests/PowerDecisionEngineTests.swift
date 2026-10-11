import XCTest
@testable import DSMNCore

final class PowerDecisionEngineTests: XCTestCase {
    func testCriticalThermalBlocksOnBatteryAndACRegardlessOfLid() {
        for source in [PowerSource.ac, .battery] {
            for closed in [false, true] {
                let now = Date()
                let state = DSMNState(manualUntil: now.addingTimeInterval(600))
                for thermal in ThermalCondition.allCases {
                    let snapshot = SystemSnapshot(now: now, powerSource: source, batteryPercent: 80,
                        defaultRouteAvailable: true, lidClosed: closed, thermalCondition: thermal)
                    let decision = PowerDecisionEngine().evaluate(state: state, agents: [], snapshot: snapshot)
                    XCTAssertEqual(decision.shouldPreventSleep, thermal != .critical)
                    XCTAssertEqual(decision.safetyBlocks, thermal == .critical ? ["thermal_critical"] : [])
                }
            }
        }
    }

    func testLegacySnapshotWithoutThermalFieldStillDecodes() throws {
        // Literal pre-thermal payload: synthesized Codable uses decodeIfPresent
        // for Optional properties, so no custom decoder is needed.
        let data = Data(#"{"now":0,"powerSource":"unknown"}"#.utf8)
        XCTAssertNil(try JSONDecoder().decode(SystemSnapshot.self, from: data).thermalCondition)
    }
    func testUnknownRoutePreservesKnownOutageUntilConfirmedRestoration() {
        let now = Date(timeIntervalSince1970: 2_000)
        var state = DSMNState(manualUntil: now.addingTimeInterval(300), noRouteUnavailableSince: now.addingTimeInterval(-1_000))
        let unknown = SystemSnapshot(now: now)
        state.updateNoRouteTracking(snapshot: unknown)
        XCTAssertNotNil(state.noRouteUnavailableSince)
        XCTAssertEqual(PowerDecisionEngine().evaluate(state: state, agents: [], snapshot: unknown).stopReason, "network_unavailable")

        let restored = SystemSnapshot(now: now, defaultRouteAvailable: true)
        state.updateNoRouteTracking(snapshot: restored)
        XCTAssertNil(state.noRouteUnavailableSince)
        XCTAssertTrue(PowerDecisionEngine().evaluate(state: state, agents: [], snapshot: restored).shouldPreventSleep)
    }

    func testUnknownRouteDoesNotInventAnOutageAndInactiveLeaseClearsOldOutage() {
        let now = Date(timeIntervalSince1970: 2_000)
        var state = DSMNState(manualUntil: now.addingTimeInterval(300))
        let unknown = SystemSnapshot(now: now)
        state.updateNoRouteTracking(snapshot: unknown)
        XCTAssertNil(state.noRouteUnavailableSince)
        XCTAssertTrue(PowerDecisionEngine().evaluate(state: state, agents: [], snapshot: unknown).shouldPreventSleep)
        state.manualUntil = nil
        state.noRouteUnavailableSince = now.addingTimeInterval(-1_000)
        state.updateNoRouteTracking(snapshot: unknown)
        XCTAssertNil(state.noRouteUnavailableSince)
    }

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

    func testLidOpenGraceElapsedKeepsSleepPreventionWhileManualTimerRuns() {
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

        XCTAssertTrue(decision.shouldPreventSleep)
        XCTAssertEqual(decision.reasons, ["manual_timer"])
        XCTAssertNil(decision.stopReason)
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
