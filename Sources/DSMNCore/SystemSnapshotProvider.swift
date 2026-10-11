import Foundation

public protocol SystemSnapshotProviding: Sendable {
    func snapshot(now: Date) throws -> SystemSnapshot
    func sleepSnapshot(now: Date) throws -> SystemSnapshot
}

public extension SystemSnapshotProviding {
    func sleepSnapshot(now: Date) throws -> SystemSnapshot { try snapshot(now: now) }
}

public struct MacSystemSnapshotProvider: SystemSnapshotProviding {
    public var runner: any CommandRunning

    public init(runner: any CommandRunning = ProcessCommandRunner()) {
        self.runner = runner
    }

    public func snapshot(now: Date = Date()) throws -> SystemSnapshot {
        let battery = try? batterySnapshot()
        let routeAvailable = try? defaultRouteAvailable()
        let lidClosed = try? lidClosedState()

        return SystemSnapshot(
            now: now,
            powerSource: battery?.powerSource ?? .unknown,
            batteryPercent: battery?.batteryPercent,
            defaultRouteAvailable: routeAvailable,
            lidClosed: lidClosed,
            thermalCondition: .current
        )
    }

    public func sleepSnapshot(now: Date) throws -> SystemSnapshot {
        let battery = try? batterySnapshot()
        let lidClosed = try? lidClosedState()
        return SystemSnapshot(
            now: now,
            powerSource: battery?.powerSource ?? .unknown,
            batteryPercent: battery?.batteryPercent,
            lidClosed: lidClosed,
            thermalCondition: .current
        )
    }

    private func batterySnapshot() throws -> (powerSource: PowerSource, batteryPercent: Int?) {
        let output = try runner.run("/usr/bin/pmset", arguments: ["-g", "batt"])
        guard output.exitCode == 0 else { return (.unknown, nil) }
        return SystemSnapshotParsers.parseBattery(output.stdout)
    }

    private func defaultRouteAvailable() throws -> Bool? {
        let output = try runner.run("/sbin/route", arguments: ["-n", "get", "default"])
        return SystemSnapshotParsers.parseDefaultRoute(output)
    }

    private func lidClosedState() throws -> Bool? {
        let output = try runner.run("/usr/sbin/ioreg", arguments: ["-r", "-k", "AppleClamshellState", "-d", "4"])
        guard output.exitCode == 0 else { return nil }
        return SystemSnapshotParsers.parseLidClosed(output.stdout)
    }
}

enum SystemSnapshotParsers {
    static func parseBattery(_ text: String) -> (powerSource: PowerSource, batteryPercent: Int?) {
        let lower = text.lowercased()
        let powerSource: PowerSource

        if lower.contains("'ac power'") || lower.contains("\"ac power\"") {
            powerSource = .ac
        } else if lower.contains("'battery power'") || lower.contains("\"battery power\"") {
            powerSource = .battery
        } else {
            powerSource = .unknown
        }

        return (powerSource, firstPercent(in: text))
    }

    static func parseDefaultRoute(_ output: CommandOutput) -> Bool? {
        if output.exitCode != 0 {
            return output.stderr.lowercased().contains("not in table") ? false : nil
        }

        let lower = output.stdout.lowercased()
        if lower.contains("gateway:") || lower.contains("interface:") {
            return true
        }

        return nil
    }

    static func parseLidClosed(_ text: String) -> Bool? {
        for line in text.split(separator: "\n") {
            let lower = line.lowercased()
            guard lower.contains("appleclamshellstate") else {
                continue
            }

            if lower.contains("yes") {
                return true
            }

            if lower.contains("no") {
                return false
            }
        }

        return nil
    }

    private static func firstPercent(in text: String) -> Int? {
        guard let range = text.range(of: #"([0-9]{1,3})%"#, options: .regularExpression) else {
            return nil
        }

        let value = text[range].dropLast()
        return Int(value)
    }
}
