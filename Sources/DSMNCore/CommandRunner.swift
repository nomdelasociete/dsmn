import Darwin
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

public enum CommandRunnerError: Error, LocalizedError {
    case timedOut(executable: String, seconds: TimeInterval, processID: Int32)
    case pipeReadFailed(Int32)

    public var errorDescription: String? {
        switch self {
        case .timedOut(let executable, let seconds, _):
            "Command \(executable) timed out after \(seconds) seconds"
        case .pipeReadFailed(let code):
            "Unable to read command output (errno \(code))"
        }
    }
}

public struct ProcessCommandRunner: CommandRunning {
    public let timeout: TimeInterval
    public let terminationGrace: TimeInterval

    public init(timeout: TimeInterval = 2, terminationGrace: TimeInterval = 0.1) {
        precondition(timeout.isFinite && timeout > 0)
        precondition(terminationGrace.isFinite && terminationGrace >= 0)
        self.timeout = timeout
        self.terminationGrace = terminationGrace
    }

    public func run(_ executable: String, arguments: [String]) throws -> CommandOutput {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        process.standardInput = FileHandle.nullDevice

        let stdout = Pipe()
        let stderr = Pipe()
        process.standardOutput = stdout
        process.standardError = stderr

        defer {
            try? stdout.fileHandleForReading.close()
            try? stderr.fileHandleForReading.close()
            try? stdout.fileHandleForWriting.close()
            try? stderr.fileHandleForWriting.close()
        }
        let started = DispatchTime.now().uptimeNanoseconds
        try process.run()
        try? stdout.fileHandleForWriting.close()
        try? stderr.fileHandleForWriting.close()

        let outputFD = stdout.fileHandleForReading.fileDescriptor
        let errorFD = stderr.fileHandleForReading.fileDescriptor
        _ = fcntl(outputFD, F_SETFL, fcntl(outputFD, F_GETFL) | O_NONBLOCK)
        _ = fcntl(errorFD, F_SETFL, fcntl(errorFD, F_GETFL) | O_NONBLOCK)
        var stdoutData = Data()
        var stderrData = Data()
        var outputEnded = false
        var errorEnded = false

        do {
            // Multiplex both nonblocking descriptors. Each pass reads at most
            // one buffer from each pipe so continuous output cannot starve the
            // other pipe or the deadline. EOF shares the process time budget.
            while true {
                if !outputEnded { outputEnded = try drain(outputFD, into: &stdoutData) }
                if !errorEnded { errorEnded = try drain(errorFD, into: &stderrData) }
                if !process.isRunning && outputEnded && errorEnded { break }
                if elapsed(since: started) >= timeout {
                    throw CommandRunnerError.timedOut(
                        executable: executable, seconds: timeout, processID: process.processIdentifier
                    )
                }
                var descriptors = [
                    pollfd(fd: outputEnded ? -1 : outputFD, events: Int16(POLLIN), revents: 0),
                    pollfd(fd: errorEnded ? -1 : errorFD, events: Int16(POLLIN), revents: 0)
                ]
                _ = poll(&descriptors, nfds_t(descriptors.count), 5)
            }
        } catch {
            terminateAndReap(process)
            throw error
        }
        process.waitUntilExit()

        return CommandOutput(
            executable: executable,
            arguments: arguments,
            stdout: String(data: stdoutData, encoding: .utf8) ?? "",
            stderr: String(data: stderrData, encoding: .utf8) ?? "",
            exitCode: process.terminationStatus
        )
    }

    private func drain(_ descriptor: Int32, into data: inout Data) throws -> Bool {
        var bytes = [UInt8](repeating: 0, count: 65_536)
        let count = read(descriptor, &bytes, bytes.count)
        if count > 0 { data.append(contentsOf: bytes.prefix(count)); return false }
        if count == 0 { return true }
        if errno == EAGAIN || errno == EINTR { return false }
        throw CommandRunnerError.pipeReadFailed(errno)
    }

    private func terminateAndReap(_ process: Process) {
        if process.isRunning {
            process.terminate()
            let started = DispatchTime.now().uptimeNanoseconds
            while process.isRunning && elapsed(since: started) < terminationGrace {
                usleep(1_000)
            }
            if process.isRunning { _ = kill(process.processIdentifier, SIGKILL) }
        }
        process.waitUntilExit()
    }

    private func elapsed(since started: UInt64) -> TimeInterval {
        TimeInterval(DispatchTime.now().uptimeNanoseconds - started) / 1_000_000_000
    }
}
