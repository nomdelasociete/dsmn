import XCTest
@testable import DSMNCore

final class AgentDetectorTests: XCTestCase {
    func testPSListingUsesInjectedRunnerAndParsesItsOutput() throws {
        let runner = PSFixtureRunner()
        let processes = try PSProcessListing(runner: runner).listProcesses()
        XCTAssertEqual(runner.invocations, [["/bin/ps", "-axo", "pid=,ppid=,comm=,command="]])
        XCTAssertEqual(processes, [RunningProcess(pid: 42, ppid: 1, executable: "/bin/codex", command: "/bin/codex agent")])
    }

    func testPSListingMapsNonzeroResultAndPropagatesTimeout() {
        XCTAssertThrowsError(try PSProcessListing(runner: PSFixtureRunner(exitCode: 1)).listProcesses()) { error in
            XCTAssertEqual(error as? DSMNError, .processListingFailed("fixture failure"))
        }
        XCTAssertThrowsError(try PSProcessListing(runner: PSFixtureRunner(timesOut: true)).listProcesses()) { error in
            guard case CommandRunnerError.timedOut = error else { return XCTFail("Expected timeout, got \(error)") }
        }
    }

    func testDetectsGrokBuildBinary() {
        let detector = AgentDetector()
        let processes = [
            RunningProcess(
                pid: 100,
                ppid: 1,
                executable: "/Users/jb/.grok/bin/grok",
                command: "/Users/jb/.grok/bin/grok agent"
            )
        ]

        let agents = detector.detect(in: processes)

        XCTAssertEqual(agents.map(\.kind), [.grokBuild])
        XCTAssertEqual(agents.first?.pid, 100)
    }

    func testDetectsClaudeCode() {
        let detector = AgentDetector()
        let processes = [
            RunningProcess(
                pid: 101,
                ppid: 1,
                executable: "/opt/homebrew/bin/claude",
                command: "claude --dangerously-skip-permissions"
            )
        ]

        XCTAssertEqual(detector.detect(in: processes).map(\.kind), [.claudeCode])
    }

    func testDetectsCodexCLI() {
        let detector = AgentDetector()
        let processes = [
            RunningProcess(
                pid: 102,
                ppid: 1,
                executable: "/opt/homebrew/bin/codex",
                command: "codex"
            )
        ]

        XCTAssertEqual(detector.detect(in: processes).map(\.kind), [.codex])
    }

    func testDetectsPiBinary() {
        let detector = AgentDetector()
        let processes = [
            RunningProcess(
                pid: 106,
                ppid: 1,
                executable: "/Users/jb/.nvm/versions/node/v24.14.0/bin/pi",
                command: "pi"
            )
        ]

        XCTAssertEqual(detector.detect(in: processes).map(\.kind), [.pi])
    }

    func testDetectsPiNodeEntrypoint() {
        let detector = AgentDetector()
        let processes = [
            RunningProcess(
                pid: 107,
                ppid: 1,
                executable: "/Users/jb/.nvm/versions/node/v24.14.0/bin/node",
                command: "node /Users/jb/.nvm/versions/node/v24.14.0/lib/node_modules/@earendil-works/pi-coding-agent/dist/cli.js"
            )
        ]

        XCTAssertEqual(detector.detect(in: processes).map(\.kind), [.pi])
    }

    func testDetectsCursorAgentCLI() {
        let detector = AgentDetector()
        let processes = [
            RunningProcess(
                pid: 108,
                ppid: 1,
                executable: "/Users/jb/.local/bin/cursor-agent",
                command: "/Users/jb/.local/bin/cursor-agent"
            )
        ]

        XCTAssertEqual(detector.detect(in: processes).map(\.kind), [.cursor])
    }

    func testIgnoresCursorAppExecutable() {
        let detector = AgentDetector()
        let processes = [
            RunningProcess(
                pid: 109,
                ppid: 1,
                executable: "/Applications/Cursor.app/Contents/MacOS/Cursor",
                command: "/Applications/Cursor.app/Contents/MacOS/Cursor"
            )
        ]

        XCTAssertTrue(detector.detect(in: processes).isEmpty)
    }

    func testIgnoresShellWrapper() {
        let detector = AgentDetector()
        let processes = [
            RunningProcess(
                pid: 103,
                ppid: 1,
                executable: "/bin/zsh",
                command: "/bin/zsh -c /Users/jb/.grok/bin/grok agent"
            )
        ]

        XCTAssertTrue(detector.detect(in: processes).isEmpty)
    }

    func testIgnoresCodexDesktopAppExecutable() {
        let detector = AgentDetector()
        let processes = [
            RunningProcess(
                pid: 104,
                ppid: 1,
                executable: "/Applications/Codex.app/Contents/MacOS/Codex",
                command: "/Applications/Codex.app/Contents/MacOS/Codex"
            )
        ]

        XCTAssertTrue(detector.detect(in: processes).isEmpty)
    }

    func testIgnoresDevServerInsideClaudeWorktree() {
        let detector = AgentDetector()
        let processes = [
            RunningProcess(
                pid: 105,
                ppid: 1,
                executable: "node",
                command: "node /Users/jb/project/.claude/worktrees/example/node_modules/.bin/next dev"
            )
        ]

        XCTAssertTrue(detector.detect(in: processes).isEmpty)
    }
}

private final class PSFixtureRunner: CommandRunning, @unchecked Sendable {
    private(set) var invocations: [[String]] = []
    let exitCode: Int32
    let timesOut: Bool
    init(exitCode: Int32 = 0, timesOut: Bool = false) { self.exitCode = exitCode; self.timesOut = timesOut }
    func run(_ executable: String, arguments: [String]) throws -> CommandOutput {
        invocations.append([executable] + arguments)
        if timesOut { throw CommandRunnerError.timedOut(executable: executable, seconds: 2, processID: 123) }
        return CommandOutput(executable: executable, arguments: arguments, stdout: "42 1 /bin/codex /bin/codex agent\n", stderr: "fixture failure", exitCode: exitCode)
    }
}
