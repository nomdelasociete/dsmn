import Foundation

public struct PowerOperationResult: Codable, Equatable, Sendable {
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
        stderr: String = ""
    ) {
        self.requestedSleepDisabled = requestedSleepDisabled
        self.dryRun = dryRun
        self.executedCommand = executedCommand
        self.exitCode = exitCode
        self.stdout = stdout
        self.stderr = stderr
    }
}

public protocol PowerManaging: Sendable {
    func setSleepDisabled(_ disabled: Bool) throws -> PowerOperationResult
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
}

