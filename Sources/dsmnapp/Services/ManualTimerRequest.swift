import DSMNCore
import Foundation

enum ManualTimerRequest {
    /// An acknowledged Add is already committed, even when protection is blocked.
    @MainActor
    static func run(
        minutes: Int, action: ManualTimerAction,
        replace: (Int) async throws -> StatusReport,
        add: (Int) async throws -> StatusReport
    ) async throws -> StatusReport {
        _ = try ManualDuration.validate(minutes)
        let report = try await (action == .add ? add(minutes) : replace(minutes))
        if action == .add, report.state.manualIsActive(at: report.generatedAt) {
            return report
        }
        guard report.state.ownsSleepDisable, report.decision.shouldPreventSleep,
              report.state.manualIsActive(at: report.generatedAt) else {
            let reasons = report.decision.safetyBlocks.joined(separator: ", ")
            throw DSMNHelperClientError.commandFailed(
                reasons.isEmpty ? "The helper did not confirm protection. Refresh status before trying again."
                    : "Protection was blocked: \(reasons)."
            )
        }
        return report
    }

    static func appliedWarning(for report: StatusReport, action: ManualTimerAction) -> String? {
        guard action == .add,
              !report.state.ownsSleepDisable || !report.decision.shouldPreventSleep else { return nil }
        let reasons = report.decision.safetyBlocks.joined(separator: ", ")
        return "Time was added, but the helper did not confirm protection. Do not add the same duration again."
            + (reasons.isEmpty ? " Refresh status to check protection." : " Safety blocks: \(reasons).")
    }
}
