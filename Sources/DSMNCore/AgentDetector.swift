import Foundation

public protocol ProcessListing: Sendable {
    func listProcesses() throws -> [RunningProcess]
}

public struct PSProcessListing: ProcessListing {
    public var runner: any CommandRunning

    public init(runner: any CommandRunning = ProcessCommandRunner()) {
        self.runner = runner
    }

    public func listProcesses() throws -> [RunningProcess] {
        let output = try runner.run("/bin/ps", arguments: ["-axo", "pid=,ppid=,comm=,command="])
        guard output.exitCode == 0 else {
            throw DSMNError.processListingFailed(output.stderr)
        }

        return output.stdout.split(separator: "\n").compactMap { parsePSLine(String($0)) }
    }

    private func parsePSLine(_ line: String) -> RunningProcess? {
        let parts = line.split(separator: " ", maxSplits: 3, omittingEmptySubsequences: true)
        guard parts.count >= 3, let pid = Int32(parts[0]), let ppid = Int32(parts[1]) else {
            return nil
        }

        let executable = String(parts[2])
        let command = parts.count == 4 ? String(parts[3]) : executable
        return RunningProcess(pid: pid, ppid: ppid, executable: executable, command: command)
    }
}

public struct AgentDetector: Sendable {
    public init() {}

    public func detect(using listing: any ProcessListing = PSProcessListing()) throws -> [AgentProcess] {
        try detect(in: listing.listProcesses())
    }

    public func detect(in processes: [RunningProcess]) -> [AgentProcess] {
        processes.compactMap { process in
            guard let kind = classify(process) else {
                return nil
            }

            return AgentProcess(
                pid: process.pid,
                ppid: process.ppid,
                executable: process.executable,
                command: process.command,
                kind: kind
            )
        }
    }

    public func classify(_ process: RunningProcess) -> AgentKind? {
        if isShellWrapper(process) || isSelfProcess(process) {
            return nil
        }

        let executableName = basename(process.executable)
        let command = process.command.lowercased()
        let executable = process.executable.lowercased()

        if matchesClaudeCode(executableName: executableName, executable: executable, command: command) {
            return .claudeCode
        }

        if matchesCursor(executableName: executableName, executable: executable, command: command) {
            return .cursor
        }

        if matchesCodex(executableName: executableName, executable: executable, command: command) {
            return .codex
        }

        if matchesGrokBuild(executableName: executableName, executable: executable, command: command) {
            return .grokBuild
        }

        if matchesPi(executableName: executableName, command: command) {
            return .pi
        }

        return nil
    }

    private func matchesClaudeCode(executableName: String, executable: String, command: String) -> Bool {
        executableName == "claude"
            || executableName == "claude-code"
            || command.contains("claude-code")
    }

    private func matchesCursor(executableName: String, executable: String, command: String) -> Bool {
        if executable.contains(".app/contents/macos") || command.contains(".app/contents/macos") {
            return false
        }

        return executableName == "cursor-agent"
            || command.contains("/cursor-agent")
            || command.contains(" @cursor/agent")
    }

    private func matchesCodex(executableName: String, executable: String, command: String) -> Bool {
        if executable.contains(".app/contents/macos") || command.contains(".app/contents/macos") {
            return false
        }

        return executableName == "codex"
            || command.contains("/.codex/bin/codex")
            || command.contains("openai codex")
    }

    private func matchesGrokBuild(executableName: String, executable: String, command: String) -> Bool {
        command.contains("/.grok/bin/grok")
            || command.contains("/.grok/downloads/grok-")
            || (executableName == "grok" && grokCommandLooksInteractive(command))
    }

    private func grokCommandLooksInteractive(_ command: String) -> Bool {
        command.contains(" agent")
            || command.contains(" sessions")
            || command.contains(" leader")
            || command.hasSuffix("/grok")
            || command.hasSuffix(" grok")
    }

    private func matchesPi(executableName: String, command: String) -> Bool {
        executableName == "pi"
            || command == "pi"
            || command.hasPrefix("pi ")
            || command.hasSuffix("/bin/pi")
            || command.contains("/bin/pi ")
            || command.contains("@earendil-works/pi-coding-agent")
    }

    private func isShellWrapper(_ process: RunningProcess) -> Bool {
        let name = basename(process.executable)
        guard ["sh", "bash", "zsh", "fish"].contains(name) else {
            return false
        }

        return process.command.contains(" -c ") || process.command.hasSuffix(" -c")
    }

    private func isSelfProcess(_ process: RunningProcess) -> Bool {
        let name = basename(process.executable)
        return name == "dsmnctl" || name == "dsmnd"
    }

    private func basename(_ path: String) -> String {
        URL(fileURLWithPath: path).lastPathComponent.lowercased()
    }
}
