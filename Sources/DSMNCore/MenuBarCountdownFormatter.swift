import Foundation

public enum MenuBarCountdownFormatter {
    /// Full countdown for the compact panel, including seconds for short leases.
    public static func panelText(remainingSeconds: Int) -> String {
        let seconds = max(0, remainingSeconds)
        if seconds >= 3600 {
            return String(format: "%d:%02d:%02d", seconds / 3600, (seconds / 60) % 60, seconds % 60)
        }
        return String(format: "%02d:%02d", seconds / 60, seconds % 60)
    }

    public static func text(report: StatusReport?, at date: Date = Date()) -> String? {
        guard let report else {
            return nil
        }

        guard let remaining = report.state.manualRemainingSeconds(at: date), remaining > 0 else {
            return nil
        }

        return compactDuration(seconds: remaining)
    }

    public static func compactDuration(seconds: Int) -> String {
        let seconds = max(0, seconds)

        if seconds < 60 {
            return "\(seconds)s"
        }

        let minutes = seconds / 60
        if minutes < 60 {
            return "\(minutes)m"
        }

        let hours = minutes / 60
        let leftoverMinutes = minutes % 60
        return leftoverMinutes == 0 ? "\(hours)h" : "\(hours)h\(leftoverMinutes)m"
    }
}
