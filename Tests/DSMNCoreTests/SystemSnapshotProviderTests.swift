import XCTest
@testable import DSMNCore

final class SystemSnapshotProviderTests: XCTestCase {
    func testFailedRouteProbeDoesNotDiscardBatteryOrLidFacts() throws {
        let snapshot = try MacSystemSnapshotProvider(runner: PartialSnapshotRunner()).snapshot()
        XCTAssertEqual(snapshot.powerSource, .battery)
        XCTAssertEqual(snapshot.batteryPercent, 12)
        XCTAssertEqual(snapshot.lidClosed, true)
        XCTAssertNil(snapshot.defaultRouteAvailable)
    }

    func testFailedBatteryProbeDoesNotDiscardRouteOrLidFacts() throws {
        let snapshot = try MacSystemSnapshotProvider(runner: PartialSnapshotRunner(failingExecutable: "/usr/bin/pmset")).snapshot()
        XCTAssertEqual(snapshot.powerSource, .unknown)
        XCTAssertNil(snapshot.batteryPercent)
        XCTAssertEqual(snapshot.lidClosed, true)
        XCTAssertEqual(snapshot.defaultRouteAvailable, true)
    }

    func testUnexpectedRouteExitIsUnknown() {
        XCTAssertNil(SystemSnapshotParsers.parseDefaultRoute(CommandOutput(
            executable: "/sbin/route", arguments: [], stdout: "", stderr: "permission denied", exitCode: 1
        )))
    }

    func testParsesBatteryPowerAndPercent() {
        let parsed = SystemSnapshotParsers.parseBattery(
            """
            Now drawing from 'Battery Power'
             -InternalBattery-0 (id=1234567)\t84%; discharging; 3:12 remaining present: true
            """
        )

        XCTAssertEqual(parsed.powerSource, .battery)
        XCTAssertEqual(parsed.batteryPercent, 84)
    }

    func testParsesACPowerAndPercent() {
        let parsed = SystemSnapshotParsers.parseBattery(
            """
            Now drawing from 'AC Power'
             -InternalBattery-0 (id=1234567)\t100%; charged; 0:00 remaining present: true
            """
        )

        XCTAssertEqual(parsed.powerSource, .ac)
        XCTAssertEqual(parsed.batteryPercent, 100)
    }

    func testParsesDefaultRouteAvailable() {
        let output = CommandOutput(
            executable: "/sbin/route",
            arguments: ["-n", "get", "default"],
            stdout: """
               route to: default
            destination: default
                   mask: default
                gateway: 192.168.1.1
              interface: en0
            """,
            stderr: "",
            exitCode: 0
        )

        XCTAssertEqual(SystemSnapshotParsers.parseDefaultRoute(output), true)
    }

    func testParsesDefaultRouteMissing() {
        let output = CommandOutput(
            executable: "/sbin/route",
            arguments: ["-n", "get", "default"],
            stdout: "",
            stderr: "route: writing to routing socket: not in table",
            exitCode: 1
        )

        XCTAssertEqual(SystemSnapshotParsers.parseDefaultRoute(output), false)
    }

    func testParsesLidClosed() {
        XCTAssertEqual(
            SystemSnapshotParsers.parseLidClosed("""
            | |   "AppleClamshellState" = Yes
            | |   "AppleClamshellCausesSleep" = Yes
            """),
            true
        )

        XCTAssertEqual(
            SystemSnapshotParsers.parseLidClosed("""
            | |   "AppleClamshellState" = No
            | |   "AppleClamshellCausesSleep" = Yes
            """),
            false
        )
    }
}

private struct PartialSnapshotRunner: CommandRunning {
    var failingExecutable = "/sbin/route"
    func run(_ executable: String, arguments: [String]) throws -> CommandOutput {
        if executable == failingExecutable { throw CocoaError(.fileReadUnknown) }
        let text = executable == "/usr/bin/pmset" ? "Now drawing from 'Battery Power' 12%;" :
            executable == "/sbin/route" ? "gateway: 192.168.1.1" : "AppleClamshellState = Yes"
        return CommandOutput(executable: executable, arguments: arguments, stdout: text, stderr: "", exitCode: 0)
    }
}
