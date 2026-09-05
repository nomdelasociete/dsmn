import DSMNCore
import Foundation

enum StopOutcome: Equatable {
    case helperConfirmed(StatusReport)
    case localOnly(StatusReport, helperError: String)
    case unconfirmed(report: StatusReport?, message: String)

    var isHelperConfirmed: Bool {
        if case .helperConfirmed = self { return true }
        return false
    }

    var report: StatusReport? {
        switch self {
        case let .helperConfirmed(report), let .localOnly(report, _): report
        case let .unconfirmed(report, _): report
        }
    }

    var failureMessage: String? {
        switch self {
        case .helperConfirmed: nil
        case let .localOnly(_, helperError):
            "Could not confirm the helper stopped. \(helperError) The local timer was cleared, but the helper may still be keeping the Mac awake."
        case let .unconfirmed(_, message): message
        }
    }
}

@MainActor
enum StopRequest {
    static func run(
        helper: () async throws -> StatusReport,
        local: () async throws -> StatusReport
    ) async -> StopOutcome {
        do {
            let report = try await helper()
            guard !report.state.ownsSleepDisable else {
                return .unconfirmed(report: report, message: "The helper still owns the power lock. Stop was not confirmed; try Stop again or run Repair.")
            }
            guard report.state.manualUntil == nil,
                  (report.manualRemainingSeconds ?? 0) <= 0,
                  !report.decision.shouldPreventSleep else {
                return .unconfirmed(report: report, message: "The helper still reports an active timer. Stop was not confirmed; try Stop again.")
            }
            return .helperConfirmed(report)
        } catch {
            let helperError = error.localizedDescription
            guard let failure = error as? DSMNHelperClientError,
                  case .unavailable = failure else {
                return .unconfirmed(report: nil, message: "Could not confirm the helper stopped. \(helperError)")
            }
            do {
                return .localOnly(try await local(), helperError: helperError)
            } catch {
                return .unconfirmed(report: nil, message: "Could not confirm the helper stopped. \(helperError) Local cleanup also failed: \(error.localizedDescription)")
            }
        }
    }
}
