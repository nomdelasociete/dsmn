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
            let options = try parseManualOptions(arguments: Array(arguments.dropFirst()))
            let report = try runManual(options, helper: helper, controller: controller)
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
            printDoctor(status.report, source: status.source, liveSleepDisabled: readLiveSleepDisabled())
        case "install-hooks":
            let targets = try parseHookTargets(arguments: Array(arguments.dropFirst()))
            let installer = AgentHookInstaller(dsmnctlPath: executablePath())
            let reports = try installer.install(targets: targets)
            try printHookInstallReports(reports, json: json)
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

    private struct ManualOptions {
        var minutes: Int
        var extendOnly: Bool
        var requester: ActivationRequester
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

    private static func runManual(
        _ options: ManualOptions,
        helper: DSMNHelperXPCClient,
        controller: DSMNController
    ) throws -> StatusReport {
        try validateManualDuration(options.minutes, maxMinutes: controller.decisionEngine.policy.maxManualDurationMinutes)

        return try preferHelper(
            {
                try helper.enableManual(
                    minutes: options.minutes,
                    extendOnly: options.extendOnly,
                    requester: options.requester
                )
            },
            fallback: {
                try controller.enableManual(
                    minutes: options.minutes,
                    extendOnly: options.extendOnly,
                    requester: options.requester
                )
            }
        )
    }

    private static func validateManualDuration(_ minutes: Int, maxMinutes: Int) throws {
        guard minutes > 0 else {
            throw DSMNError.invalidDuration("minutes must be greater than 0")
        }

        guard minutes <= maxMinutes else {
            throw DSMNError.invalidDuration("minutes must be <= \(maxMinutes)")
        }
    }

    private static func parseManualOptions(arguments: [String]) throws -> ManualOptions {
        var minutes: Int?
        var extendOnly = false
        var requesterName = "Terminal"
        var requesterContext: String?
        var requesterEvent: String?
        var index = 0

        while index < arguments.count {
            let argument = arguments[index]

            switch argument {
            case "--extend-only":
                extendOnly = true
                index += 1
            case "--minutes":
                guard arguments.indices.contains(index + 1) else {
                    throw DSMNError.invalidDuration("use dsmnctl manual --minutes <n>")
                }
                guard let parsed = Int(arguments[index + 1]) else {
                    throw DSMNError.invalidDuration(arguments[index + 1])
                }
                minutes = parsed
                index += 2
            case "--requester", "--source":
                guard arguments.indices.contains(index + 1) else {
                    throw DSMNError.invalidCommand("\(argument) requires a value")
                }
                requesterName = arguments[index + 1]
                index += 2
            case "--context":
                guard arguments.indices.contains(index + 1) else {
                    throw DSMNError.invalidCommand("\(argument) requires a value")
                }
                requesterContext = arguments[index + 1]
                index += 2
            case "--event":
                guard arguments.indices.contains(index + 1) else {
                    throw DSMNError.invalidCommand("\(argument) requires a value")
                }
                requesterEvent = arguments[index + 1]
                index += 2
            default:
                if minutes == nil, let parsed = Int(argument) {
                    minutes = parsed
                    index += 1
                } else {
                    throw DSMNError.invalidCommand("manual \(argument)")
                }
            }
        }

        guard let minutes else {
            throw DSMNError.invalidDuration("use dsmnctl manual --minutes <n>")
        }

        return ManualOptions(
            minutes: minutes,
            extendOnly: extendOnly,
            requester: ActivationRequester(name: requesterName, context: requesterContext, event: requesterEvent)
        )
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

    private static func parseHookTargets(arguments: [String]) throws -> [AgentHookTarget] {
        var targets: [AgentHookTarget] = []
        var values = arguments
        values.removeAll { $0 == "--target" || $0 == "--targets" }

        if values.isEmpty || values.contains("all") {
            return AgentHookTarget.allCases
        }

        for value in values {
            targets.append(try AgentHookTarget.parse(value))
        }

        return Array(Set(targets)).sorted { $0.rawValue < $1.rawValue }
    }

    private static func executablePath() -> String? {
        guard let first = CommandLine.arguments.first, !first.isEmpty else {
            return nil
        }

        if first.hasPrefix("/") {
            return first
        }

        return URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent(first)
            .standardizedFileURL
            .path
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

        if let requester = report.state.lastRequester {
            print("Last request: \(requester.displayText)")
            if let event = requester.event {
                print("Last event: \(event)")
            }
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

    private static func printHookInstallReports(_ reports: [AgentHookInstallReport], json: Bool) throws {
        if json {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(reports)
            print(String(data: data, encoding: .utf8) ?? "[]")
            return
        }

        for report in reports {
            print("\(report.target): \(report.message) at \(report.path)")
        }
    }

    private static func readLiveSleepDisabled() -> Bool? {
        guard let output = try? ProcessCommandRunner().run("/usr/bin/pmset", arguments: ["-g", "live"]),
              output.exitCode == 0
        else {
            return nil
        }

        for line in output.stdout.components(separatedBy: .newlines) {
            let parts = line.split(whereSeparator: { $0 == " " || $0 == "\t" })
            if parts.first == "SleepDisabled", let value = parts.dropFirst().first {
                return value == "1"
            }
        }

        return nil
    }

    private static func printDoctor(_ report: StatusReport, source: StatusSource, liveSleepDisabled: Bool?) {
        print("dsmn doctor")
        print("Status source: \(source == .helper ? "helper" : "local fallback")")
        print("Status: \(report.decision.shouldPreventSleep ? "active" : "inactive")")
        print("Auto: \(report.state.autoEnabled ? "on" : "off")")
        print("Power lock: \(report.state.ownsSleepDisable ? "on" : "off")")
        print("macOS SleepDisabled: \(formatOptionalFlag(liveSleepDisabled))")
        if let requester = report.state.lastRequester {
            print("Last request: \(requester.displayText)")
            if let event = requester.event {
                print("Last event: \(event)")
            }
        }
        print("Agents detected: \(report.agents.count)")
        for agent in report.agents {
            print("- \(agent.kind.displayName) pid=\(agent.pid) executable=\(agent.executable)")
        }
        print("Decision: \(report.decision.shouldPreventSleep ? "prevent sleep" : "allow sleep")")

        if source == .local {
            print("Warning: helper unavailable; closed-lid prevention will not work.")
        } else if report.decision.shouldPreventSleep && !report.state.ownsSleepDisable {
            print("Warning: dsmn wants to prevent sleep, but the power lock is off.")
        } else if report.state.ownsSleepDisable && liveSleepDisabled == false {
            print("Warning: dsmn state says locked, but macOS SleepDisabled is off.")
        } else if report.state.ownsSleepDisable {
            print("Ready: dsmn owns the macOS power lock.")
        } else {
            print("Ready: helper works; enable manual or auto mode to test.")
        }
    }

    private static func formatOptionalFlag(_ value: Bool?) -> String {
        guard let value else {
            return "unknown"
        }

        return value ? "on" : "off"
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
              manual --minutes <n> [--extend-only] [--requester <name>] [--context <text>] [--event <name>] [--json]
              auto [on|off|toggle] [--json]
              stop [--json]
              doctor
              install-hooks [all|claude|codex|grok|pi] [--json]
              repair
            """
        )
    }
}
