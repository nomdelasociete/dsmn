import Foundation

public struct SetupMenuSignals: Equatable, Sendable {
    public var helperIsReady: Bool
    public var helperNeedsRepair: Bool
    public var helperNeedsUpdate: Bool
    public var helperNeedsApproval: Bool
    public var helperNeedsInstall: Bool
    public var hooksAreReady: Bool
    public var hooksPartialInstalled: Int?
    public var hooksPartialTotal: Int?
    public var hooksFailed: Bool
    public var hooksNeedInstall: Bool
    public var remindersSuppressed: Bool
    public var powerLockPending: Bool

    public init(
        helperIsReady: Bool,
        helperNeedsRepair: Bool,
        helperNeedsUpdate: Bool,
        helperNeedsApproval: Bool,
        helperNeedsInstall: Bool,
        hooksAreReady: Bool,
        hooksPartialInstalled: Int? = nil,
        hooksPartialTotal: Int? = nil,
        hooksFailed: Bool = false,
        hooksNeedInstall: Bool = false,
        remindersSuppressed: Bool = false,
        powerLockPending: Bool = false
    ) {
        self.helperIsReady = helperIsReady
        self.helperNeedsRepair = helperNeedsRepair
        self.helperNeedsUpdate = helperNeedsUpdate
        self.helperNeedsApproval = helperNeedsApproval
        self.helperNeedsInstall = helperNeedsInstall
        self.hooksAreReady = hooksAreReady
        self.hooksPartialInstalled = hooksPartialInstalled
        self.hooksPartialTotal = hooksPartialTotal
        self.hooksFailed = hooksFailed
        self.hooksNeedInstall = hooksNeedInstall
        self.remindersSuppressed = remindersSuppressed
        self.powerLockPending = powerLockPending
    }

    public var isSetupComplete: Bool {
        helperIsOperational && hooksAreReady
    }

    public var isSetupIncomplete: Bool {
        !isSetupComplete
    }

    public var helperIsOperational: Bool {
        if helperIsReady {
            return true
        }

        return helperNeedsUpdate
            && !helperNeedsRepair
            && !helperNeedsApproval
            && !helperNeedsInstall
    }
}

public enum SetupMenuPresentation: Sendable {
    public static func setupLine(from signals: SetupMenuSignals) -> String? {
        if signals.helperNeedsRepair {
            return "Setup: repair helper"
        }

        if signals.helperNeedsUpdate {
            return "Helper update available"
        }

        if signals.helperNeedsInstall {
            return "Setup: install helper"
        }

        if signals.helperNeedsApproval {
            return "Setup: approve Login Items"
        }

        if signals.powerLockPending {
            return "Power lock: pending"
        }

        if !signals.hooksAreReady {
            if let installed = signals.hooksPartialInstalled,
               let total = signals.hooksPartialTotal,
               total > 0 {
                return "Setup: hooks \(installed)/\(total)"
            }

            if signals.hooksFailed {
                return "Setup: hooks failed"
            }

            if signals.hooksNeedInstall {
                return "Setup: install hooks"
            }
        }

        return nil
    }

    public static func prefersExpandedSetup(from signals: SetupMenuSignals) -> Bool {
        if signals.remindersSuppressed {
            return false
        }

        if signals.isSetupIncomplete {
            return true
        }

        return setupLine(from: signals) != nil
    }

    public static func setupIncompleteStatusTitle(
        from signals: SetupMenuSignals,
        wizardDismissed: Bool
    ) -> String? {
        guard wizardDismissed, signals.isSetupIncomplete, !signals.remindersSuppressed else {
            return nil
        }

        return "Setup incomplete"
    }
}
