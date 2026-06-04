import DSMNCore
import Foundation

extension DSMNMenuStore {
    /// One glance at the menu: helper/hooks broken, or explicit setup line from the engine.
    var prefersExpandedSetup: Bool {
        if helperNeedsRepair || !helperIsReady || !hooksAreReady {
            return true
        }

        return setupLine != nil
    }

    var menuStatusSystemImage: String {
        switch menuBarIconState {
        case .loading:
            "ellipsis.circle"
        case .off:
            "moon.zzz"
        case .warning:
            "exclamationmark.triangle.fill"
        case .manualActive:
            "checkmark.circle.fill"
        }
    }

    /// Secondary status line — at most one, highest signal first.
    var menuStatusSubtitle: String? {
        if errorMessage != nil {
            return nil
        }

        if let hookFallbackLine {
            return hookFallbackLine
        }

        if let report,
           report.decision.shouldPreventSleep || report.state.manualIsActive(at: Date()) {
            if let powerLockLine {
                return powerLockLine
            }
        }

        if let lastRequesterLine,
           let report,
           report.state.manualIsActive(at: Date()) || report.decision.shouldPreventSleep {
            return lastRequesterLine
        }

        return nil
    }

    var showsActivityMenu: Bool {
        guard let report else {
            return false
        }

        if report.decision.shouldPreventSleep || report.state.manualIsActive(at: Date()) {
            return true
        }

        return report.state.triggerActivityBuckets.contains { $0.count > 0 }
    }

    var helperUpdateButtonTitle: String {
        helperNeedsRepair ? "Repair Helper" : "Update Helper"
    }
}