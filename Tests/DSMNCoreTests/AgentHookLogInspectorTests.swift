import XCTest
@testable import DSMNCore

final class AgentHookLogInspectorTests: XCTestCase {
    func testDetectsRecentFallbackWithinWindow() {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let startedAt = now.addingTimeInterval(-120)
        let log = sampleLog(startedAt: startedAt, seconds: 600)

        let status = AgentHookLogInspector.recentFallbackStatus(
            logContents: log,
            logPath: "/tmp/custom-hook.log",
            now: now
        )

        XCTAssertTrue(status.isActive)
        XCTAssertEqual(status.logPath, "/tmp/custom-hook.log")
        XCTAssertEqual(status.fallbackSeconds, 600)
        XCTAssertEqual(status.lastStartedAt, startedAt)
    }

    func testIgnoresExpiredFallback() {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let startedAt = now.addingTimeInterval(-700)
        let log = sampleLog(startedAt: startedAt, seconds: 600)

        let status = AgentHookLogInspector.recentFallbackStatus(logContents: log, now: now)

        XCTAssertFalse(status.isActive)
        XCTAssertEqual(status.lastStartedAt, startedAt)
    }

    func testUsesLatestFallbackEvent() {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let old = now.addingTimeInterval(-3_600)
        let recent = now.addingTimeInterval(-60)
        let log = """
        \(timestamp(old)) dsmn active minutes=20 requester=Codex
        \(timestamp(recent)) fallback caffeinate started seconds=300
        """

        let status = AgentHookLogInspector.recentFallbackStatus(logContents: log, now: now)

        XCTAssertTrue(status.isActive)
        XCTAssertEqual(status.fallbackSeconds, 300)
        XCTAssertEqual(status.lastStartedAt, recent)
    }

    func testInactiveWhenLogHasNoFallbackMarker() {
        let status = AgentHookLogInspector.recentFallbackStatus(
            logContents: "2026-06-04 10:00:00 dsmn active minutes=20 requester=Codex\n",
            now: Date(timeIntervalSince1970: 1_700_000_000)
        )

        XCTAssertFalse(status.isActive)
        XCTAssertNil(status.lastStartedAt)
    }

    func testResolvesLogPathFromEnvironment() {
        XCTAssertEqual(
            AgentHookLogInspector.logPath(environment: [:]),
            AgentHookLogInspector.defaultLogPath
        )
        XCTAssertEqual(
            AgentHookLogInspector.logPath(environment: ["DSMN_HOOK_LOG": "/var/tmp/hook.log"]),
            "/var/tmp/hook.log"
        )
    }

    func testDoctorWarningOnlyWhenActive() {
        let active = AgentHookFallbackStatus(
            isActive: true,
            logPath: "/tmp/dsmn-agent-hook.log",
            lastStartedAt: Date(),
            fallbackSeconds: 600
        )
        let inactive = AgentHookFallbackStatus(
            isActive: false,
            logPath: "/tmp/dsmn-agent-hook.log",
            lastStartedAt: Date(),
            fallbackSeconds: 600
        )

        XCTAssertNotNil(AgentHookLogInspector.doctorWarning(for: active))
        XCTAssertNil(AgentHookLogInspector.doctorWarning(for: inactive))
    }

    private func sampleLog(startedAt: Date, seconds: Int) -> String {
        "\(timestamp(startedAt)) fallback caffeinate started seconds=\(seconds)\n"
    }

    private func timestamp(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone.current
        formatter.dateFormat = AgentHookLogInspector.timestampFormat
        return formatter.string(from: date)
    }
}