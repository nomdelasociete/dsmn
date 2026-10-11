import Foundation

public struct ReconcileSchedule: Equatable, Sendable {
    public var deadline: Date?

    public init(deadline: Date?) {
        self.deadline = deadline
    }

    public static func sleepReleaseDeadline(
        for report: StatusReport,
        graceSeconds: TimeInterval = 1
    ) -> ReconcileSchedule {
        guard report.state.ownsSleepDisable || report.state.sleepDisablePending || report.decision.shouldPreventSleep else {
            return ReconcileSchedule(deadline: nil)
        }

        return sleepReleaseDeadline(
            state: report.state,
            now: report.generatedAt,
            noRouteGraceRemainingSeconds: report.noRouteGraceRemainingSeconds,
            graceSeconds: graceSeconds
        )
    }

    /// Rearm cleanup after a command throws without depending on system probes.
    public static func sleepReleaseDeadline(
        for state: DSMNState,
        now: Date,
        noRouteGraceSeconds: Int = SafetyPolicy().noRouteGraceSeconds,
        graceSeconds: TimeInterval = 1
    ) -> ReconcileSchedule {
        guard state.ownsSleepDisable || state.sleepDisablePending else {
            return ReconcileSchedule(deadline: nil)
        }

        return sleepReleaseDeadline(
            state: state,
            now: now,
            noRouteGraceRemainingSeconds: state.noRouteGraceRemainingSeconds(at: now, graceSeconds: noRouteGraceSeconds),
            graceSeconds: graceSeconds
        )
    }

    private static func sleepReleaseDeadline(
        state: DSMNState,
        now: Date,
        noRouteGraceRemainingSeconds: Int?,
        graceSeconds: TimeInterval
    ) -> ReconcileSchedule {
        if state.sleepDisablePending {
            return ReconcileSchedule(deadline: now.addingTimeInterval(graceSeconds))
        }
        if state.ownsSleepDisable, state.manualUntil == nil {
            return ReconcileSchedule(deadline: now.addingTimeInterval(graceSeconds))
        }

        var deadlines: [Date] = []

        if let manualUntil = state.manualUntil {
            deadlines.append(maxDate(manualUntil, now))
        }

        if let noRouteGraceRemainingSeconds {
            deadlines.append(now.addingTimeInterval(TimeInterval(noRouteGraceRemainingSeconds)))
        }

        guard let deadline = deadlines.min() else {
            return ReconcileSchedule(deadline: now.addingTimeInterval(graceSeconds))
        }

        return ReconcileSchedule(deadline: deadline.addingTimeInterval(graceSeconds))
    }

    private static func maxDate(_ lhs: Date, _ rhs: Date) -> Date {
        lhs >= rhs ? lhs : rhs
    }
}
