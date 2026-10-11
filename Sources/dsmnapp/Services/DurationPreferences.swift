import DSMNCore
import Foundation

@MainActor
final class DurationPreferences: ObservableObject {
    static let shared = DurationPreferences()
    @Published private(set) var presets: [Int]
    @Published private(set) var lastCustomMinutes: Int
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let stored = defaults.array(forKey: "durationPresets") as? [Int] ?? [30, 90]
        presets = (try? ManualDuration.presets(from: stored.map(String.init).joined(separator: ","))) ?? [30, 90]
        lastCustomMinutes = (try? ManualDuration.validate(defaults.integer(forKey: "lastCustomMinutes"))) ?? 45
    }

    func savePresets(_ text: String) throws {
        let parsed = try ManualDuration.presets(from: text)
        defaults.set(parsed, forKey: "durationPresets")
        presets = parsed
    }

    func rememberCustom(minutes: Int) throws {
        let validated = try ManualDuration.validate(minutes)
        defaults.set(validated, forKey: "lastCustomMinutes")
        lastCustomMinutes = validated
    }
}
