import XCTest
@testable import DSMNCore

final class DoctorReportFormatterTests: XCTestCase {
    func testFormatIncludesHelperSourcePowerLockSleepDisabledAndAgents() throws {
        let report = sampleReport(ownsSleepDisable: true, agentCount: 2)
        let text = DoctorReportFormatter.format(
            report: report,
            source: .helper,
            liveSleepDisabled: true
        )

        XCTAssertTrue(text.contains("Status source: helper"))
        XCTAssertTrue(text.contains("Power lock: on"))
        XCTAssertTrue(text.contains("macOS SleepDisabled: on"))
        XCTAssertTrue(text.contains("Agents detected: 2"))
        XCTAssertTrue(text.contains("- Claude Code pid=42 executable=/usr/bin/claude"))
    }

    func testFormatWarnsWhenUsingLocalFallback() throws {
        let report = sampleReport(ownsSleepDisable: false, agentCount: 0)
        let hookFallback = AgentHookFallbackStatus(
            isActive: true,
            logPath: "/tmp/dsmn-agent-hook.log",
            lastStartedAt: Date(timeIntervalSince1970: 1_000),
            fallbackSeconds: 600
        )
        let text = DoctorReportFormatter.format(
            report: report,
            source: .local,
            liveSleepDisabled: nil,
            hookFallback: hookFallback
        )

        XCTAssertTrue(text.contains("Status source: local fallback"))
        XCTAssertTrue(text.contains("Hook fallback: active"))
        XCTAssertTrue(text.contains("macOS SleepDisabled: unknown"))
        XCTAssertTrue(text.contains("fallback caffeinate"))
        XCTAssertTrue(text.contains("Warning: helper unavailable"))
    }

    func testFormatSuppressesFallbackWarningWhenPowerLockIsOn() throws {
        let report = sampleReport(ownsSleepDisable: true, agentCount: 0)
        let hookFallback = AgentHookFallbackStatus(
            isActive: true,
            logPath: "/tmp/dsmn-agent-hook.log",
            lastStartedAt: Date(timeIntervalSince1970: 1_000),
            fallbackSeconds: 600
        )
        let text = DoctorReportFormatter.format(
            report: report,
            source: .helper,
            liveSleepDisabled: true,
            hookFallback: hookFallback
        )

        XCTAssertTrue(text.contains("Hook fallback: active"))
        XCTAssertFalse(text.contains("closed-lid sleep prevention is unavailable"))
        XCTAssertTrue(text.contains("Ready: dsmn owns the macOS power lock."))
    }

    func testFormatIncludesHookInspectionFingerprints() throws {
        let report = sampleReport(ownsSleepDisable: true, agentCount: 0)
        let hookInspection = AgentHookSetupInspection(
            hookScriptPath: "/Users/jb/.dsmn/dsmn-agent-hook.sh",
            hookScriptStatus: .outdated,
            expectedHookScriptFingerprint: "expected123",
            installedHookScriptFingerprint: "installed456",
            targets: [
                AgentHookTargetInspection(target: .claude, path: "/Users/jb/.claude/settings.json", status: .current),
                AgentHookTargetInspection(target: .codex, path: "/Users/jb/.codex/hooks.json", status: .outdated)
            ]
        )

        let text = DoctorReportFormatter.format(
            report: report,
            source: .helper,
            liveSleepDisabled: true,
            hookInspection: hookInspection
        )

        XCTAssertTrue(text.contains("Hook script: outdated"))
        XCTAssertTrue(text.contains("Hook script expected fingerprint: expected123"))
        XCTAssertTrue(text.contains("Hook script installed fingerprint: installed456"))
        XCTAssertTrue(text.contains("Hook targets: 1/2 current"))
        XCTAssertTrue(text.contains("- Claude Code: current (/Users/jb/.claude/settings.json)"))
        XCTAssertTrue(text.contains("- Codex: outdated (/Users/jb/.codex/hooks.json)"))
    }

    func testFormatRepairResultSummarizesStatus() throws {
        let report = sampleReport(ownsSleepDisable: false, agentCount: 0)
        let text = DoctorReportFormatter.formatRepairResult(report, source: .helper)

        XCTAssertTrue(text.contains("Repair finished via helper."))
        XCTAssertTrue(text.contains("Power lock: off"))
        XCTAssertTrue(text.contains("dsmn is not preventing sleep."))
    }

    private func sampleReport(ownsSleepDisable: Bool, agentCount: Int) -> StatusReport {
        var state = DSMNState()
        state.ownsSleepDisable = ownsSleepDisable
        state.lastRequester = ActivationRequester(name: "Codex", context: "session")
        state.lastStopReason = ownsSleepDisable ? nil : "repair"

        let agents = (0..<agentCount).map { index in
            AgentProcess(
                pid: Int32(42 + index),
                ppid: nil,
                executable: "/usr/bin/claude",
                command: "claude",
                kind: .claudeCode
            )
        }

        return StatusReport(
            generatedAt: Date(timeIntervalSince1970: 1_000),
            state: state,
            snapshot: SystemSnapshot(
                now: Date(timeIntervalSince1970: 1_000),
                powerSource: .ac,
                batteryPercent: nil,
                defaultRouteAvailable: true,
                lidClosed: false
            ),
            agents: agents,
            decision: PowerDecision(
                shouldPreventSleep: ownsSleepDisable,
                reasons: [],
                safetyBlocks: []
            ),
            manualRemainingSeconds: ownsSleepDisable ? 1_200 : nil
        )
    }
}
