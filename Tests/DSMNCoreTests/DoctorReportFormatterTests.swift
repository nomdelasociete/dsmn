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
        let text = DoctorReportFormatter.format(
            report: report,
            source: .local,
            liveSleepDisabled: nil
        )

        XCTAssertTrue(text.contains("Status source: local fallback"))
        XCTAssertTrue(text.contains("macOS SleepDisabled: unknown"))
        XCTAssertTrue(text.contains("Warning: helper unavailable"))
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