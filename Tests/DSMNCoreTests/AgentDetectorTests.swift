import XCTest
@testable import DSMNCore

final class AgentDetectorTests: XCTestCase {
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
