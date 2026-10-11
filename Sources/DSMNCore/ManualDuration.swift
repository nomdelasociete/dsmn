import Foundation

public enum ManualTimerAction: String, CaseIterable, Sendable {
    case replace
    case add
}

/// Shared validation for timer input, preferences, and helper commands.
public enum ManualDuration {
    public static var maximumMinutes: Int { SafetyPolicy().maxManualDurationMinutes }

    public static func validate(_ minutes: Int, maximum: Int = maximumMinutes) throws -> Int {
        guard (1...maximum).contains(minutes) else {
            throw DSMNError.invalidDuration("Enter between 1 and \(maximum) minutes (\(label(maximum)) maximum).")
        }
        return minutes
    }

    public static func minutes(hours: String, minutes: String) throws -> Int {
        let h = hours.trimmingCharacters(in: .whitespacesAndNewlines)
        let m = minutes.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let hoursValue = Int(h.isEmpty ? "0" : h),
              let minutesValue = Int(m.isEmpty ? "0" : m),
              (0...(maximumMinutes / 60)).contains(hoursValue),
              (0...59).contains(minutesValue) else {
            throw DSMNError.invalidDuration("Use whole hours and minutes; minutes must be between 0 and 59.")
        }
        return try validate(hoursValue * 60 + minutesValue)
    }

    public static func presets(from text: String) throws -> [Int] {
        let entries = text.split(separator: ",", omittingEmptySubsequences: false)
        guard (1...6).contains(entries.count) else {
            throw DSMNError.invalidDuration("Choose between 1 and 6 presets, separated by commas.")
        }
        let values = try entries.map { entry -> Int in
            let value = entry.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                .replacingOccurrences(of: " ", with: "")
            if let number = Int(value) { return try validate(number) }
            let pattern = #"^(?:([0-9]+)h)?(?:([0-9]+)m)?$"#
            let regex = try NSRegularExpression(pattern: pattern)
            let range = NSRange(value.startIndex..., in: value)
            guard !value.isEmpty, let match = regex.firstMatch(in: value, range: range) else {
                throw DSMNError.invalidDuration("Use durations such as 30m, 1h30m, or 2h.")
            }
            func part(_ index: Int) -> String {
                Range(match.range(at: index), in: value).map { String(value[$0]) } ?? "0"
            }
            if match.range(at: 1).location == NSNotFound, let minutes = Int(part(2)) {
                return try validate(minutes)
            }
            return try minutes(hours: part(1), minutes: part(2))
        }
        guard Set(values).count == values.count else {
            throw DSMNError.invalidDuration("Each preset must have a different duration.")
        }
        return values
    }

    public static func label(_ minutes: Int) -> String {
        let hours = minutes / 60
        let remainder = minutes % 60
        if hours == 0 { return "\(minutes)m" }
        return remainder == 0 ? "\(hours)h" : "\(hours)h\(remainder)m"
    }
}
