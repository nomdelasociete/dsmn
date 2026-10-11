import DSMNCore
import XCTest
@testable import dsmnapp

@MainActor
final class ManualTimerRequestTests: XCTestCase {
    func testAddIsSentExactlyOnceAndNeverReplaced() async throws {
        var calls = 0
        let expected = protectedReport()
        let result = try await ManualTimerRequest.run(minutes: 90, action: .add, replace: { _ in
            XCTFail("Add must never be implemented as a read/replace sequence")
            return expected
        }, add: { minutes in
            calls += 1
            XCTAssertEqual(minutes, 90)
            return expected
        })
        XCTAssertEqual(calls, 1)
        XCTAssertEqual(result, expected)
    }

    func testTimedOutAddIsNotRetriedOrReplaced() async {
        var calls = 0
        do {
            _ = try await ManualTimerRequest.run(minutes: 30, action: .add, replace: { _ in
                XCTFail("No fallback after an ambiguous response")
                return self.protectedReport()
            }, add: { _ in
                calls += 1
                throw DSMNHelperClientError.timedOut
            })
            XCTFail("Must report the failure")
        } catch {
            XCTAssertEqual(calls, 1)
        }
    }

    func testUnconfirmedProtectionIsNotSuccess() async {
        for ownsLock in [false, true] {
            var report = protectedReport()
            report.state.ownsSleepDisable = ownsLock
            report.decision.shouldPreventSleep = false
            do {
                _ = try await ManualTimerRequest.run(minutes: 30, action: .replace,
                    replace: { _ in report }, add: { _ in XCTFail(); return report })
                XCTFail("An unconfirmed timer must keep Custom open with an error")
            } catch {}
        }
    }

    func testInvalidDurationNeverReachesHelper() async {
        do {
            _ = try await ManualTimerRequest.run(minutes: 481, action: .replace,
                replace: { _ in XCTFail(); return self.protectedReport() },
                add: { _ in XCTFail(); return self.protectedReport() })
            XCTFail("Must reject values beyond the shared limit")
        } catch {}
    }

    func testCommittedAddReturnsReportWithWarningWhenProtectionIsBlocked() async throws {
        for ownsLock in [false, true] {
            var report = protectedReport()
            report.state.ownsSleepDisable = ownsLock
            report.decision.shouldPreventSleep = false
            report.decision.safetyBlocks = ["low_battery"]
            var calls = 0
            let result = try await ManualTimerRequest.run(minutes: 30, action: .add,
                replace: { _ in XCTFail("Must not replace a committed Add"); return report },
                add: { _ in calls += 1; return report })
            XCTAssertEqual(calls, 1)
            XCTAssertEqual(result, report)
            XCTAssertTrue(ManualTimerRequest.appliedWarning(for: result, action: .add)?.contains("Time was added") == true)
            XCTAssertTrue(ManualTimerRequest.appliedWarning(for: result, action: .add)?.contains("low_battery") == true)
        }
    }

    func testCommittedAddWithoutPowerLockStillWarns() async throws {
        var report = protectedReport()
        report.state.ownsSleepDisable = false
        let result = try await ManualTimerRequest.run(minutes: 30, action: .add,
            replace: { _ in XCTFail(); return report }, add: { _ in report })
        XCTAssertNotNil(ManualTimerRequest.appliedWarning(for: result, action: .add))
        XCTAssertNil(ManualTimerRequest.appliedWarning(for: protectedReport(), action: .add))
    }

    private func protectedReport() -> StatusReport {
        let now = Date()
        return StatusReport(generatedAt: now,
            state: DSMNState(manualUntil: now.addingTimeInterval(1800), ownsSleepDisable: true),
            snapshot: SystemSnapshot(now: now), agents: [],
            decision: PowerDecision(shouldPreventSleep: true, reasons: ["manual_timer"], safetyBlocks: []),
            manualRemainingSeconds: 1800)
    }
}
