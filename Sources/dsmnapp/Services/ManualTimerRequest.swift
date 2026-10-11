import DSMNCore
import Foundation

enum ManualTimerRequest {
    /// Only a helper-confirmed power lock is a successful timer request.
    @MainActor
    static func run(
        minutes: Int, action: ManualTimerAction,
        replace: (Int) async throws -> StatusReport,
        add: (Int) async throws -> StatusReport
    ) async throws -> StatusReport {
        _ = try ManualDuration.validate(minutes)
        let report = try await (action == .add ? add(minutes) : replace(minutes))
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
}
