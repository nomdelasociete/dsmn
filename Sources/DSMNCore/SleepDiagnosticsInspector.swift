import Foundation

public enum SleepBlockerScope: String, Codable, Equatable, Sendable {
    case systemSleep
    case displaySleep
    case other
}

public struct SleepBlocker: Codable, Equatable, Identifiable, Sendable {
    public var id: String {
        "\(pid)-\(assertionType)-\(assertionName)"
    }

    public var pid: Int
    public var processName: String
    public var duration: String
    public var assertionType: String
    public var assertionName: String
    public var scope: SleepBlockerScope
    public var rawLine: String

    public init(
        pid: Int,
        processName: String,
        duration: String,
        assertionType: String,
        assertionName: String,
        scope: SleepBlockerScope,
        rawLine: String
    ) {
        self.pid = pid
        self.processName = processName
        self.duration = duration
        self.assertionType = assertionType
        self.assertionName = assertionName
        self.scope = scope
        self.rawLine = rawLine
    }
}

public struct SleepDiagnosticsReport: Codable, Equatable, Sendable {
    public var generatedAt: Date
    public var sleepDisabled: Bool?
    public var sleepLine: String?
    public var displaySleepLine: String?
    public var assertionStatuses: [String: Bool]
    public var blockers: [SleepBlocker]

    public init(
        generatedAt: Date,
        sleepDisabled: Bool?,
        sleepLine: String?,
        displaySleepLine: String?,
        assertionStatuses: [String: Bool],
        blockers: [SleepBlocker]
    ) {
        self.generatedAt = generatedAt
        self.sleepDisabled = sleepDisabled
        self.sleepLine = sleepLine
        self.displaySleepLine = displaySleepLine
        self.assertionStatuses = assertionStatuses
        self.blockers = blockers
    }
}

public struct SleepDiagnosticsInspector: Sendable {
    public var runner: any CommandRunning

    public init(runner: any CommandRunning = ProcessCommandRunner()) {
        self.runner = runner
    }

    public func report(now: Date = Date()) throws -> SleepDiagnosticsReport {
        let liveOutput = try runner.run("/usr/bin/pmset", arguments: ["-g", "live"])
        let assertionsOutput = try runner.run("/usr/bin/pmset", arguments: ["-g", "assertions"])

        return Self.parse(
            liveOutput: liveOutput.stdout,
            assertionsOutput: assertionsOutput.stdout,
            generatedAt: now
        )
    }

    public func liveSleepDisabled() throws -> Bool? {
        let output = try runner.run("/usr/bin/pmset", arguments: ["-g", "live"])
        guard output.exitCode == 0 else { return nil }
        return Self.parseSleepDisabled(output.stdout)
    }

    public static func parse(
        liveOutput: String,
        assertionsOutput: String,
        generatedAt: Date
    ) -> SleepDiagnosticsReport {
        SleepDiagnosticsReport(
            generatedAt: generatedAt,
            sleepDisabled: parseSleepDisabled(liveOutput),
            sleepLine: parseLiveLine(named: "sleep", in: liveOutput),
            displaySleepLine: parseLiveLine(named: "displaysleep", in: liveOutput),
            assertionStatuses: parseAssertionStatuses(assertionsOutput),
            blockers: parseBlockers(assertionsOutput)
        )
    }

    private static func parseSleepDisabled(_ output: String) -> Bool? {
        for line in output.components(separatedBy: .newlines) {
            let parts = line.split(whereSeparator: { $0 == " " || $0 == "\t" })
            if parts.first == "SleepDisabled", let value = parts.dropFirst().first {
                return value == "1"
            }
        }

        return nil
    }

    private static func parseLiveLine(named name: String, in output: String) -> String? {
        for line in output.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard trimmed.hasPrefix("\(name) ") || trimmed.hasPrefix("\(name)\t") else {
                continue
            }

            return trimmed
        }

        return nil
    }

    private static func parseAssertionStatuses(_ output: String) -> [String: Bool] {
        var statuses: [String: Bool] = [:]
        var inStatusBlock = false

        for line in output.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            if trimmed == "Assertion status system-wide:" {
                inStatusBlock = true
                continue
            }

            if trimmed == "Listed by owning process:" {
                break
            }

            guard inStatusBlock else {
                continue
            }

            let parts = trimmed.split(whereSeparator: { $0 == " " || $0 == "\t" })
            if parts.count == 2, let value = parts.last {
                statuses[String(parts[0])] = value == "1"
            }
        }

        return statuses
    }

    private static func parseBlockers(_ output: String) -> [SleepBlocker] {
        var blockers: [SleepBlocker] = []

        for line in output.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard trimmed.hasPrefix("pid ") else {
                continue
            }

            blockers.append(parseBlockerLine(trimmed))
        }

        return blockers
    }

    private static func parseBlockerLine(_ line: String) -> SleepBlocker {
        let pattern = #"pid\s+(\d+)\(([^)]+)\):\s+\[[^\]]+\]\s+([0-9:]+)\s+([A-Za-z0-9]+)\s+named:\s+"([^"]*)""#

        if let match = try? NSRegularExpression(pattern: pattern).firstMatch(
            in: line,
            range: NSRange(line.startIndex..<line.endIndex, in: line)
        ) {
            let pid = Int(capture(1, in: line, match: match) ?? "") ?? 0
            let processName = capture(2, in: line, match: match) ?? "unknown"
            let duration = capture(3, in: line, match: match) ?? ""
            let assertionType = capture(4, in: line, match: match) ?? "Unknown"
            let assertionName = capture(5, in: line, match: match) ?? ""

            return SleepBlocker(
                pid: pid,
                processName: processName,
                duration: duration,
                assertionType: assertionType,
                assertionName: assertionName,
                scope: classify(assertionType: assertionType),
                rawLine: line
            )
        }

        return SleepBlocker(
            pid: 0,
            processName: "unknown",
            duration: "",
            assertionType: "Unknown",
            assertionName: "",
            scope: .other,
            rawLine: line
        )
    }

    private static func capture(_ index: Int, in line: String, match: NSTextCheckingResult) -> String? {
        guard let range = Range(match.range(at: index), in: line) else {
            return nil
        }

        return String(line[range])
    }

    private static func classify(assertionType: String) -> SleepBlockerScope {
        switch assertionType {
        case "NoDisplaySleepAssertion", "PreventUserIdleDisplaySleep":
            return .displaySleep
        case "NoIdleSleepAssertion", "PreventUserIdleSystemSleep", "PreventSystemSleep":
            return .systemSleep
        default:
            return .other
        }
    }
}
