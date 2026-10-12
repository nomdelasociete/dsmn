import DSMNCore
import Foundation

struct PresetDraft: Identifiable, Equatable {
    let id = UUID()
    var hours: String
    var minutes: String

    init(minutes: Int) {
        hours = String(minutes / 60)
        self.minutes = String(minutes % 60)
    }

    static func validatedMinutes(_ rows: [PresetDraft]) throws -> [Int] {
        guard (1...6).contains(rows.count) else {
            throw DSMNError.invalidDuration("Keep between 1 and 6 presets.")
        }
        let values = try rows.map { try ManualDuration.minutes(hours: $0.hours, minutes: $0.minutes) }
        guard Set(values).count == values.count else {
            throw DSMNError.invalidDuration("Each preset must have a different duration.")
        }
        return values
    }
}
