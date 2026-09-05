import Darwin
import XCTest
@testable import DSMNCore

final class CommandRunnerTests: XCTestCase {
    func testDefaultTimeoutIncludesFiniteTerminationAndReapingBudget() throws {
        try assertTimeout("/bin/sleep", arguments: ["10"], timeout: 2, limit: 3)
    }

    func testCapturesOutputAndNonzeroExit() throws {
        let output = try ProcessCommandRunner().run("/bin/sh", arguments: ["-c", "printf out; printf err >&2; exit 7"])
        XCTAssertEqual(output.stdout, "out")
        XCTAssertEqual(output.stderr, "err")
        XCTAssertEqual(output.exitCode, 7)
    }

    func testDrainsBothLargeOutputStreamsCompletely() throws {
        let output = try ProcessCommandRunner().run("/usr/bin/perl", arguments: [
            "-e", "$| = 1; for (1..64) { print STDOUT 'a' x 16384; print STDERR 'b' x 16384; }"
        ])
        XCTAssertEqual(output.exitCode, 0)
        XCTAssertEqual(output.stdout, String(repeating: "a", count: 1_048_576))
        XCTAssertEqual(output.stderr, String(repeating: "b", count: 1_048_576))
    }

    func testTimeoutTerminatesAndReapsSleepingChildRepeatedly() throws {
        for _ in 0..<3 {
            try assertTimeout("/bin/sleep", arguments: ["10"])
        }
    }

    func testTimeoutKillsChildThatIgnoresTermination() throws {
        try assertTimeout("/usr/bin/perl", arguments: ["-e", "$SIG{TERM} = 'IGNORE'; sleep 10;"])
    }

    func testDeadlineIncludesInheritedOpenOutputPipesAfterChildExit() throws {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer {
            if let text = try? String(contentsOf: file, encoding: .utf8), let pid = Int32(text.trimmingCharacters(in: .whitespacesAndNewlines)) {
                _ = kill(pid, SIGKILL)
            }
            try? FileManager.default.removeItem(at: file)
        }
        // The runner owns and reaps the shell. This fixture separately cleans up
        // its background descendant, whose inherited pipe must not defeat EOF timeout.
        try assertTimeout("/bin/sh", arguments: ["-c", "sleep 10 & echo $! > \"$1\"; exit 0", "fixture", file.path])
    }

    private func assertTimeout(_ executable: String, arguments: [String], timeout: TimeInterval = 0.08, limit: TimeInterval = 1) throws {
        let started = Date()
        XCTAssertThrowsError(try ProcessCommandRunner(timeout: timeout, terminationGrace: 0.1).run(executable, arguments: arguments)) { error in
            guard case CommandRunnerError.timedOut(_, _, let pid) = error else {
                return XCTFail("Expected timeout, got \(error)")
            }
            XCTAssertEqual(kill(pid, 0), -1)
            XCTAssertEqual(errno, ESRCH)
        }
        XCTAssertLessThan(Date().timeIntervalSince(started), limit)
    }
}
