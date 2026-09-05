import XCTest
@testable import DSMNCore

final class ReconcileScheduleTests: XCTestCase {
    func testSchedulesSleepReleaseAtManualExpirationWithGrace() {
        let now = Date(timeIntervalSince1970: 1_000)
        let manualUntil = now.addingTimeInterval(60)
        let report = makeReport(
            now: now,
            state: DSMNState(manualUntil: manualUntil, ownsSleepDisable: true),
            shouldPreventSleep: true
        )

        let schedule = ReconcileSchedule.sleepReleaseDeadline(for: report, graceSeconds: 2)

        XCTAssertEqual(schedule.deadline, manualUntil.addingTimeInterval(2))
    }

    func testSchedulesImmediateReleaseWhenOwnedWithoutManualTimer() {
        let now = Date(timeIntervalSince1970: 2_000)
        let report = makeReport(
            now: now,
            state: DSMNState(ownsSleepDisable: true),
            shouldPreventSleep: false
        )

        let schedule = ReconcileSchedule.sleepReleaseDeadline(for: report, graceSeconds: 2)

        XCTAssertEqual(schedule.deadline, now.addingTimeInterval(2))
    }

    func testSchedulesEarlierNoRouteGraceDeadline() {
        let now = Date(timeIntervalSince1970: 2_500)
        let manualUntil = now.addingTimeInterval(60 * 60)
        let report = makeReport(
            now: now,
            state: DSMNState(manualUntil: manualUntil, ownsSleepDisable: true),
            shouldPreventSleep: true,
            noRouteGraceRemainingSeconds: 45
        )

        let schedule = ReconcileSchedule.sleepReleaseDeadline(for: report, graceSeconds: 2)

        XCTAssertEqual(schedule.deadline, now.addingTimeInterval(47))
    }

    func testDoesNotScheduleReleaseWhenDsmnIsInactiveAndDoesNotOwnPowerLock() {
        let now = Date(timeIntervalSince1970: 3_000)
        let report = makeReport(
            now: now,
            state: DSMNState(),
            shouldPreventSleep: false
        )

        let schedule = ReconcileSchedule.sleepReleaseDeadline(for: report)

        XCTAssertNil(schedule.deadline)
    }

    func testOwnedLockWithoutLeaseRetriesBeforeNoRouteGrace() {
        let now = Date(timeIntervalSince1970: 3_000)
        let report = makeReport(
            now: now,
            state: DSMNState(ownsSleepDisable: true, noRouteUnavailableSince: now),
            shouldPreventSleep: false,
            noRouteGraceRemainingSeconds: 900
        )

        XCTAssertEqual(ReconcileSchedule.sleepReleaseDeadline(for: report).deadline, now.addingTimeInterval(1))
        XCTAssertEqual(ReconcileSchedule.sleepReleaseDeadline(for: report.state, now: now).deadline, now.addingTimeInterval(1))
    }

    func testSavedStateSchedulesEarlierManualOrNoRouteDeadline() {
        let now = Date(timeIntervalSince1970: 3_000)
        var state = DSMNState(
            manualUntil: now.addingTimeInterval(600),
            ownsSleepDisable: true,
            noRouteUnavailableSince: now.addingTimeInterval(-30)
        )

        XCTAssertEqual(
            ReconcileSchedule.sleepReleaseDeadline(for: state, now: now, noRouteGraceSeconds: 60).deadline,
            now.addingTimeInterval(31)
        )
        state.manualUntil = now.addingTimeInterval(10)
        XCTAssertEqual(
            ReconcileSchedule.sleepReleaseDeadline(for: state, now: now, noRouteGraceSeconds: 60).deadline,
            now.addingTimeInterval(11)
        )
        state.manualUntil = now.addingTimeInterval(-10)
        XCTAssertEqual(
            ReconcileSchedule.sleepReleaseDeadline(for: state, now: now, noRouteGraceSeconds: 60).deadline,
            now.addingTimeInterval(1)
        )
    }

    func testSavedStateDoesNotScheduleUnownedLock() {
        let now = Date(timeIntervalSince1970: 3_000)
        let state = DSMNState(manualUntil: now.addingTimeInterval(300))

        XCTAssertNil(ReconcileSchedule.sleepReleaseDeadline(for: state, now: now).deadline)
    }

    private func makeReport(
        now: Date,
        state: DSMNState,
        shouldPreventSleep: Bool,
        noRouteGraceRemainingSeconds: Int? = nil
    ) -> StatusReport {
        StatusReport(
            generatedAt: now,
            state: state,
            snapshot: SystemSnapshot(now: now),
            agents: [],
            decision: PowerDecision(
                shouldPreventSleep: shouldPreventSleep,
                reasons: shouldPreventSleep ? ["manual_timer"] : [],
                safetyBlocks: [],
                stopReason: shouldPreventSleep ? nil : "not_armed"
            ),
            manualRemainingSeconds: state.manualRemainingSeconds(at: now),
            noRouteGraceRemainingSeconds: noRouteGraceRemainingSeconds
        )
    }
}
