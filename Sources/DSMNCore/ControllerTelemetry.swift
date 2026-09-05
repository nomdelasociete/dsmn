import Foundation

/// Diagnostic observations are immutable and retain their observation time.
/// They do not own or extend the persisted manual lease.
public struct ControllerTelemetry: Sendable {
    public let snapshot: SystemSnapshot
    public let agents: [AgentProcess]
    public let diagnosticErrors: [String]

    public init(snapshot: SystemSnapshot, agents: [AgentProcess], diagnosticErrors: [String] = []) {
        self.snapshot = snapshot
        self.agents = agents
        self.diagnosticErrors = diagnosticErrors
    }

    public static func unavailable(at date: Date) -> ControllerTelemetry {
        ControllerTelemetry(
            snapshot: SystemSnapshot(now: date),
            agents: [],
            diagnosticErrors: ["System snapshot unavailable", "Agent process listing unavailable"]
        )
    }
}
