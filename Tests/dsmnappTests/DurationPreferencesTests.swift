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

    func testEditorAddsEditsRemovesAndPersistsInOrderWithoutChangingCustom() throws {
        let defaults = isolatedDefaults()
        let prefs = DurationPreferences(defaults: defaults)
        try prefs.rememberCustom(minutes: 125)
        var rows = prefs.presets.map(PresetDraft.init(minutes:))
        rows[0].minutes = "15"
        rows.append(PresetDraft(minutes: 480))
        rows.remove(at: 1)
        XCTAssertEqual(prefs.presets, [30, 90], "Draft changes are not saved automatically")
        try prefs.savePresets(rows)
        let reopened = DurationPreferences(defaults: defaults)
        XCTAssertEqual(reopened.presets, [15, 480])
        XCTAssertEqual(reopened.lastCustomMinutes, 125)
    }

    func testEditorRejectsEmptyDuplicateOverflowAndMalformedDraftsAtomically() throws {
        let defaults = isolatedDefaults()
        let prefs = DurationPreferences(defaults: defaults)
        var invalid = PresetDraft(minutes: 60)
        invalid.minutes = "60"
        var malformed = PresetDraft(minutes: 60)
        malformed.hours = "oops"
        for rows in [[], [PresetDraft(minutes: 0)], [PresetDraft(minutes: 481)],
                     [PresetDraft(minutes: 30), PresetDraft(minutes: 30)],
                     (1...7).map(PresetDraft.init(minutes:)), [invalid], [malformed]] {
            XCTAssertThrowsError(try prefs.savePresets(rows))
            XCTAssertEqual(DurationPreferences(defaults: defaults).presets, [30, 90])
        }
        try prefs.savePresets((1...6).map(PresetDraft.init(minutes:)))
        XCTAssertEqual(prefs.presets, [1, 2, 3, 4, 5, 6])
    }

    private func isolatedDefaults() -> UserDefaults {
        let name = "dsmn-duration-tests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        addTeardownBlock { UserDefaults(suiteName: name)?.removePersistentDomain(forName: name) }
        return defaults
    }
}
