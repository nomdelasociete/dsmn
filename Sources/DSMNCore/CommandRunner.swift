import Foundation

public struct CommandOutput: Equatable, Sendable {
    public var executable: String
    public var arguments: [String]
    public var stdout: String
    public var stderr: String
    public var exitCode: Int32

    public init(executable: String, arguments: [String], stdout: String, stderr: String, exitCode: Int32) {
        self.executable = executable
        self.arguments = arguments
        self.stdout = stdout
        self.stderr = stderr
        self.exitCode = exitCode
    }
}

public protocol CommandRunning: Sendable {
    func run(_ executable: String, arguments: [String]) throws -> CommandOutput
}

public struct ProcessCommandRunner: CommandRunning {
    public init() {}

    public func run(_ executable: String, arguments: [String]) throws -> CommandOutput {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments

        let stdout = Pipe()
        let stderr = Pipe()
        process.standardOutput = stdout
        process.standardError = stderr

        try process.run()
        let stdoutData = stdout.fileHandleForReading.readDataToEndOfFile()
        let stderrData = stderr.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()

        return CommandOutput(
            executable: executable,
            arguments: arguments,
            stdout: String(data: stdoutData, encoding: .utf8) ?? "",
            stderr: String(data: stderrData, encoding: .utf8) ?? "",
            exitCode: process.terminationStatus
        )
    }
}

