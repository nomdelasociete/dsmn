import XCTest
@testable import dsmnapp

@MainActor
final class DurationPreferencesTests: XCTestCase {
    func testPresetsAndLastCustomSurviveRelaunch() throws {
        let defaults = isolatedDefaults()
        let first = DurationPreferences(defaults: defaults)
        XCTAssertEqual(first.presets, [30, 90])
        XCTAssertEqual(first.lastCustomMinutes, 45)
        try first.savePresets("2h, 45m, 8h")
        try first.rememberCustom(minutes: 125)
        let relaunched = DurationPreferences(defaults: defaults)
        XCTAssertEqual(relaunched.presets, [120, 45, 480])
        XCTAssertEqual(relaunched.lastCustomMinutes, 125)
    }

    func testInvalidEditsPreserveSavedPreferences() throws {
        let defaults = isolatedDefaults()
        let prefs = DurationPreferences(defaults: defaults)
        try prefs.savePresets("1h, 2h")
        try prefs.rememberCustom(minutes: 480)
        XCTAssertThrowsError(try prefs.savePresets("12h"))
        XCTAssertThrowsError(try prefs.rememberCustom(minutes: 481))
        let reopened = DurationPreferences(defaults: defaults)
        XCTAssertEqual(reopened.presets, [60, 120])
        XCTAssertEqual(reopened.lastCustomMinutes, 480)
    }

    func testCorruptPreferencesUseSafeDefaults() {
        let defaults = isolatedDefaults()
        defaults.set([0, 900], forKey: "durationPresets")
        defaults.set(Int.max, forKey: "lastCustomMinutes")
        let prefs = DurationPreferences(defaults: defaults)
        XCTAssertEqual(prefs.presets, [30, 90])
        XCTAssertEqual(prefs.lastCustomMinutes, 45)
    }

    private func isolatedDefaults() -> UserDefaults {
        let name = "dsmn-duration-tests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        addTeardownBlock { UserDefaults(suiteName: name)?.removePersistentDomain(forName: name) }
        return defaults
    }
}
