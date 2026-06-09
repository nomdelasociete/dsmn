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
        guard report.state.ownsSleepDisable || report.decision.shouldPreventSleep else {
            return ReconcileSchedule(deadline: nil)
        }

        var deadlines: [Date] = []

        if let manualUntil = report.state.manualUntil {
            deadlines.append(maxDate(manualUntil, report.generatedAt))
        }

        if let noRouteGraceRemainingSeconds = report.noRouteGraceRemainingSeconds {
            deadlines.append(report.generatedAt.addingTimeInterval(TimeInterval(noRouteGraceRemainingSeconds)))
        }

        guard let deadline = deadlines.min() else {
            return ReconcileSchedule(deadline: report.generatedAt.addingTimeInterval(graceSeconds))
        }

        return ReconcileSchedule(deadline: deadline.addingTimeInterval(graceSeconds))
    }

    private static func maxDate(_ lhs: Date, _ rhs: Date) -> Date {
        lhs >= rhs ? lhs : rhs
    }
}
