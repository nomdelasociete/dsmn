import Darwin
import DSMNCore
import Foundation

@main
struct DSMNCTL {
    static func main() {
        do {
            try run()
        } catch {
            fputs("dsmnctl: \(error.localizedDescription)\n", stderr)
            exit(1)
        }
    }

    private static func run() throws {
        var arguments = Array(CommandLine.arguments.dropFirst())
        let json = arguments.contains("--json")
        arguments.removeAll { $0 == "--json" }

        let store = try StateStore.defaultStore()
        let controller = DSMNController(store: store)
        let helper = DSMNHelperXPCClient()

        guard let command = arguments.first else {
            let report = try controller.status()
            try printReport(report, json: json)
            return
        }

        switch command {
        case "status":
            let report = try preferHelper({ try helper.status() }, fallback: { try controller.status() })
            try printReport(report, json: json)
        case "manual":
            let minutes = try parseMinutes(arguments: Array(arguments.dropFirst()))
            let report = try preferHelper(
                { try helper.enableManual(minutes: minutes) },
                fallback: { try controller.enableManual(minutes: minutes) }
            )
            try printReport(report, json: json)
        case "auto":
            let action = try parseAutoAction(arguments: Array(arguments.dropFirst()))
            let report = try runAuto(action, helper: helper, controller: controller)
            try printReport(report, json: json)
        case "stop":
            let report = try preferHelper({ try helper.stop() }, fallback: { try controller.stop() })
            try printReport(report, json: json)
        case "doctor":
            let status = try readStatus(helper: helper, controller: controller)
            printDoctor(status.report, source: status.source)
        case "repair":
            let report = try controller.repairState()
            try printReport(report, json: json)
            print("repair: dry-run state repaired; helper power cleanup is not implemented yet")
        case "help", "--help", "-h":
            printHelp()
        default:
            throw DSMNError.invalidCommand(command)
        }
    }

    private static func preferHelper(
        _ helperOperation: () throws -> StatusReport,
        fallback: () throws -> StatusReport
    ) throws -> StatusReport {
        if let report = try? helperOperation() {
            return report
        }

        return try fallback()
    }

    private enum StatusSource {
        case helper
        case local
    }

    private static func readStatus(
        helper: DSMNHelperXPCClient,
        controller: DSMNController
    ) throws -> (report: StatusReport, source: StatusSource) {
        if let report = try? helper.status() {
            return (report, .helper)
        }

        return (try controller.status(), .local)
    }

    private static func runAuto(
        _ action: AutoAction,
        helper: DSMNHelperXPCClient,
        controller: DSMNController
    ) throws -> StatusReport {
        switch action {
        case .on:
            return try preferHelper({ try helper.setAuto(true) }, fallback: { try controller.setAuto(.on) })
        case .off:
            return try preferHelper({ try helper.setAuto(false) }, fallback: { try controller.setAuto(.off) })
        case .toggle:
            return try preferHelper({ try helper.toggleAuto() }, fallback: { try controller.setAuto(.toggle) })
        }
    }

    private static func parseMinutes(arguments: [String]) throws -> Int {
        if let index = arguments.firstIndex(of: "--minutes"), arguments.indices.contains(index + 1) {
            guard let minutes = Int(arguments[index + 1]) else {
                throw DSMNError.invalidDuration(arguments[index + 1])
            }

            return minutes
        }

        if let first = arguments.first, let minutes = Int(first) {
            return minutes
        }

        throw DSMNError.invalidDuration("use dsmnctl manual --minutes <n>")
    }

    private static func parseAutoAction(arguments: [String]) throws -> AutoAction {
        guard let first = arguments.first else {
            return .toggle
        }

        guard let action = AutoAction(rawValue: first) else {
            throw DSMNError.invalidCommand("auto \(first)")
        }

        return action
    }

    private static func printReport(_ report: StatusReport, json: Bool) throws {
        if json {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(report)
            print(String(data: data, encoding: .utf8) ?? "{}")
            return
        }

        print("Status: \(report.decision.shouldPreventSleep ? "active" : "inactive")")
        print("Auto: \(report.state.autoEnabled ? "on" : "off")")
        print("Power: \(report.snapshot.powerSource.rawValue)")

        if let batteryPercent = report.snapshot.batteryPercent {
            print("Battery: \(batteryPercent)%")
        }

        if let defaultRouteAvailable = report.snapshot.defaultRouteAvailable {
            print("Network: \(defaultRouteAvailable ? "default route" : "no default route")")
        }

        if let lidClosed = report.snapshot.lidClosed {
            print("Lid: \(lidClosed ? "closed" : "open")")
        }

        if let remaining = report.manualRemainingSeconds, remaining > 0 {
            print("Manual: \(formatDuration(seconds: remaining)) remaining")
        } else {
            print("Manual: off")
        }

        if report.agents.isEmpty {
            print("Agents: none")
        } else {
            print("Agents:")
            for agent in report.agents {
                print("- \(agent.kind.displayName) pid=\(agent.pid)")
            }
        }

        if !report.decision.reasons.isEmpty {
            print("Reasons: \(report.decision.reasons.joined(separator: ", "))")
        }

        if !report.decision.safetyBlocks.isEmpty {
            print("Safety blocks: \(report.decision.safetyBlocks.joined(separator: ", "))")
        }

        if let stopReason = report.decision.stopReason {
            print("Stop reason: \(stopReason)")
        }
    }

    private static func printDoctor(_ report: StatusReport, source: StatusSource) {
        print("dsmn doctor")
        print("Status source: \(source == .helper ? "helper" : "local fallback")")
        print("Status: \(report.decision.shouldPreventSleep ? "active" : "inactive")")
        print("Auto: \(report.state.autoEnabled ? "on" : "off")")
        print("Power lock: \(report.state.ownsSleepDisable ? "on" : "off")")
        print("Agents detected: \(report.agents.count)")
        for agent in report.agents {
            print("- \(agent.kind.displayName) pid=\(agent.pid) executable=\(agent.executable)")
        }
        print("Decision: \(report.decision.shouldPreventSleep ? "prevent sleep" : "allow sleep")")

        if source == .local {
            print("Warning: helper unavailable; closed-lid prevention will not work.")
        } else if report.decision.shouldPreventSleep && !report.state.ownsSleepDisable {
            print("Warning: dsmn wants to prevent sleep, but the power lock is off.")
        } else if report.state.ownsSleepDisable {
            print("Ready: dsmn owns the macOS power lock.")
        } else {
            print("Ready: helper works; enable manual or auto mode to test.")
        }
    }

    private static func formatDuration(seconds: Int) -> String {
        let minutes = seconds / 60
        let remainingSeconds = seconds % 60

        if minutes >= 60 {
            let hours = minutes / 60
            let leftoverMinutes = minutes % 60
            return "\(hours)h \(leftoverMinutes)m"
        }

        if minutes > 0 {
            return "\(minutes)m \(remainingSeconds)s"
        }

        return "\(remainingSeconds)s"
    }

    private static func printHelp() {
        print(
            """
            dsmnctl

            Commands:
              status [--json]
              manual --minutes <n> [--json]
              auto [on|off|toggle] [--json]
              stop [--json]
              doctor
              repair
            """
        )
    }
}
