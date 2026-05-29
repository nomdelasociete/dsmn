import XCTest
@testable import DSMNCore

final class SystemSnapshotProviderTests: XCTestCase {
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

