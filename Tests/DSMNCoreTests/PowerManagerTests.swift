import XCTest
@testable import DSMNCore

final class PowerManagerTests: XCTestCase {
    func testPMSetDryRunDoesNotExecuteCommand() throws {
        let runner = RecordingCommandRunner()
        let manager = PMSetPowerManager(runner: runner, dryRun: true)

        let result = try manager.setSleepDisabled(true)

        XCTAssertTrue(result.dryRun)
        XCTAssertEqual(result.executedCommand, "/usr/bin/pmset -a disablesleep 1")
        XCTAssertTrue(runner.commands.isEmpty)
    }

    func testPMSetExecutesWhenDryRunIsFalse() throws {
        let runner = RecordingCommandRunner()
        let manager = PMSetPowerManager(runner: runner, dryRun: false)

        let result = try manager.setSleepDisabled(false)

        XCTAssertFalse(result.dryRun)
        XCTAssertEqual(result.exitCode, 0)
        XCTAssertEqual(runner.commands, ["/usr/bin/pmset -a disablesleep 0"])
    }

    func testPMSetRequestsSleepNow() throws {
        let runner = RecordingCommandRunner()
        let manager = PMSetPowerManager(runner: runner, dryRun: false)

        let result = try manager.requestSleepNow()

        XCTAssertEqual(result.action, .sleepNow)
        XCTAssertFalse(result.dryRun)
        XCTAssertEqual(result.exitCode, 0)
        XCTAssertEqual(runner.commands, ["/usr/bin/pmset sleepnow"])
    }

    func testPMSetRequestsDisplaySleepNow() throws {
        let runner = RecordingCommandRunner()
        let manager = PMSetPowerManager(runner: runner, dryRun: false)

        let result = try manager.requestDisplaySleepNow()

        XCTAssertEqual(result.action, .displaySleepNow)
        XCTAssertFalse(result.dryRun)
        XCTAssertEqual(result.exitCode, 0)
        XCTAssertEqual(runner.commands, ["/usr/bin/pmset displaysleepnow"])
    }
}

private final class RecordingCommandRunner: CommandRunning, @unchecked Sendable {
    var commands: [String] = []

    func run(_ executable: String, arguments: [String]) throws -> CommandOutput {
        commands.append(([executable] + arguments).joined(separator: " "))
        return CommandOutput(
            executable: executable,
            arguments: arguments,
            stdout: "",
            stderr: "",
            exitCode: 0
        )
    }
}
