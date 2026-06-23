import Foundation

public enum PowerOperationAction: String, Codable, Equatable, Sendable {
    case disableSleep = "disable_sleep"
    case enableSleep = "enable_sleep"
    case sleepNow = "sleep_now"
    case displaySleepNow = "display_sleep_now"
}

public struct PowerOperationResult: Codable, Equatable, Sendable {
    public var action: PowerOperationAction
    public var requestedSleepDisabled: Bool
    public var dryRun: Bool
    public var executedCommand: String?
    public var exitCode: Int32?
    public var stdout: String
    public var stderr: String

    public init(
        requestedSleepDisabled: Bool,
        dryRun: Bool,
        executedCommand: String?,
        exitCode: Int32?,
        stdout: String = "",
        stderr: String = "",
        action: PowerOperationAction? = nil
    ) {
        self.action = action ?? (requestedSleepDisabled ? .disableSleep : .enableSleep)
        self.requestedSleepDisabled = requestedSleepDisabled
        self.dryRun = dryRun
        self.executedCommand = executedCommand
        self.exitCode = exitCode
        self.stdout = stdout
        self.stderr = stderr
    }

    private enum CodingKeys: String, CodingKey {
        case action
        case requestedSleepDisabled
        case dryRun
        case executedCommand
        case exitCode
        case stdout
        case stderr
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        requestedSleepDisabled = try container.decode(Bool.self, forKey: .requestedSleepDisabled)
        action = try container.decodeIfPresent(PowerOperationAction.self, forKey: .action)
            ?? (requestedSleepDisabled ? .disableSleep : .enableSleep)
        dryRun = try container.decode(Bool.self, forKey: .dryRun)
        executedCommand = try container.decodeIfPresent(String.self, forKey: .executedCommand)
        exitCode = try container.decodeIfPresent(Int32.self, forKey: .exitCode)
        stdout = try container.decodeIfPresent(String.self, forKey: .stdout) ?? ""
        stderr = try container.decodeIfPresent(String.self, forKey: .stderr) ?? ""
    }
}

public protocol PowerManaging: Sendable {
    func setSleepDisabled(_ disabled: Bool) throws -> PowerOperationResult
    func requestSleepNow() throws -> PowerOperationResult
    func requestDisplaySleepNow() throws -> PowerOperationResult
}

public extension PowerManaging {
    func requestSleepNow() throws -> PowerOperationResult {
        PowerOperationResult(
            requestedSleepDisabled: false,
            dryRun: true,
            executedCommand: nil,
            exitCode: nil,
            action: .sleepNow
        )
    }

    func requestDisplaySleepNow() throws -> PowerOperationResult {
        PowerOperationResult(
            requestedSleepDisabled: false,
            dryRun: true,
            executedCommand: nil,
            exitCode: nil,
            action: .displaySleepNow
        )
    }
}

public struct PMSetPowerManager: PowerManaging {
    public var runner: any CommandRunning
    public var dryRun: Bool

    public init(runner: any CommandRunning = ProcessCommandRunner(), dryRun: Bool = true) {
        self.runner = runner
        self.dryRun = dryRun
    }

    public func setSleepDisabled(_ disabled: Bool) throws -> PowerOperationResult {
        let value = disabled ? "1" : "0"
        let command = "/usr/bin/pmset -a disablesleep \(value)"

        if dryRun {
            return PowerOperationResult(
                requestedSleepDisabled: disabled,
                dryRun: true,
                executedCommand: command,
                exitCode: nil
            )
        }

        let output = try runner.run("/usr/bin/pmset", arguments: ["-a", "disablesleep", value])
        return PowerOperationResult(
            requestedSleepDisabled: disabled,
            dryRun: false,
            executedCommand: command,
            exitCode: output.exitCode,
            stdout: output.stdout,
            stderr: output.stderr
        )
    }

    public func requestSleepNow() throws -> PowerOperationResult {
        let command = "/usr/bin/pmset sleepnow"

        if dryRun {
            return PowerOperationResult(
                requestedSleepDisabled: false,
                dryRun: true,
                executedCommand: command,
                exitCode: nil,
                action: .sleepNow
            )
        }

        let output = try runner.run("/usr/bin/pmset", arguments: ["sleepnow"])
        return PowerOperationResult(
            requestedSleepDisabled: false,
            dryRun: false,
            executedCommand: command,
            exitCode: output.exitCode,
            stdout: output.stdout,
            stderr: output.stderr,
            action: .sleepNow
        )
    }

    public func requestDisplaySleepNow() throws -> PowerOperationResult {
        let command = "/usr/bin/pmset displaysleepnow"

        if dryRun {
            return PowerOperationResult(
                requestedSleepDisabled: false,
                dryRun: true,
                executedCommand: command,
                exitCode: nil,
                action: .displaySleepNow
            )
        }

        let output = try runner.run("/usr/bin/pmset", arguments: ["displaysleepnow"])
        return PowerOperationResult(
            requestedSleepDisabled: false,
            dryRun: false,
            executedCommand: command,
            exitCode: output.exitCode,
            stdout: output.stdout,
            stderr: output.stderr,
            action: .displaySleepNow
        )
    }
}

public struct NoopPowerManager: PowerManaging {
    public init() {}

    public func setSleepDisabled(_ disabled: Bool) throws -> PowerOperationResult {
        PowerOperationResult(
            requestedSleepDisabled: disabled,
            dryRun: true,
            executedCommand: nil,
            exitCode: nil
        )
    }

    public func requestSleepNow() throws -> PowerOperationResult {
        PowerOperationResult(
            requestedSleepDisabled: false,
            dryRun: true,
            executedCommand: nil,
            exitCode: nil,
            action: .sleepNow
        )
    }

    public func requestDisplaySleepNow() throws -> PowerOperationResult {
        PowerOperationResult(
            requestedSleepDisabled: false,
            dryRun: true,
            executedCommand: nil,
            exitCode: nil,
            action: .displaySleepNow
        )
    }
}
