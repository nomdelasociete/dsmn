import Foundation

public struct AgentHookFallbackStatus: Equatable, Sendable {
    public var isActive: Bool
    public var logPath: String
    public var lastStartedAt: Date?
    public var fallbackSeconds: Int

    public init(isActive: Bool, logPath: String, lastStartedAt: Date?, fallbackSeconds: Int) {
        self.isActive = isActive
        self.logPath = logPath
        self.lastStartedAt = lastStartedAt
        self.fallbackSeconds = fallbackSeconds
    }
}

public enum AgentHookLogInspector {
    public static let fallbackStartedMarker = "fallback caffeinate started"
    public static let defaultLogPath = "/tmp/dsmn-agent-hook.log"
    public static let defaultFallbackSeconds = 600
    public static let timestampFormat = "yyyy-MM-dd HH:mm:ss"

    public static func logPath(environment: [String: String] = ProcessInfo.processInfo.environment) -> String {
        let configured = environment["DSMN_HOOK_LOG"]?.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let configured, !configured.isEmpty else {
            return defaultLogPath
        }

        return configured
    }

    public static func recentFallbackStatus(
        logPath: String? = nil,
        now: Date = Date(),
        environment: [String: String] = ProcessInfo.processInfo.environment,
        fileManager: FileManager = .default
    ) -> AgentHookFallbackStatus {
        let resolvedPath = logPath ?? Self.logPath(environment: environment)
        let contents = (try? String(contentsOfFile: resolvedPath, encoding: .utf8)) ?? ""
        return recentFallbackStatus(logContents: contents, logPath: resolvedPath, now: now)
    }

    public static func recentFallbackStatus(
        logContents: String,
        logPath: String = defaultLogPath,
        now: Date = Date()
    ) -> AgentHookFallbackStatus {
        guard let event = latestFallbackEvent(in: logContents) else {
            return AgentHookFallbackStatus(
                isActive: false,
                logPath: logPath,
                lastStartedAt: nil,
                fallbackSeconds: defaultFallbackSeconds
            )
        }

        let expiresAt = event.startedAt.addingTimeInterval(TimeInterval(event.fallbackSeconds))
        let isActive = now < expiresAt

        return AgentHookFallbackStatus(
            isActive: isActive,
            logPath: logPath,
            lastStartedAt: event.startedAt,
            fallbackSeconds: event.fallbackSeconds
        )
    }

    public static func doctorWarning(for status: AgentHookFallbackStatus) -> String? {
        guard status.isActive else {
            return nil
        }

        return "Warning: agent hook recently started fallback caffeinate (\(status.logPath)); closed-lid sleep prevention is unavailable."
    }

    static func latestFallbackEvent(in logContents: String) -> (startedAt: Date, fallbackSeconds: Int)? {
        let formatter = timestampFormatter()
        var latest: (startedAt: Date, fallbackSeconds: Int)?

        for line in logContents.split(whereSeparator: \.isNewline) {
            let text = String(line)
            guard text.contains(fallbackStartedMarker) else {
                continue
            }

            guard let startedAt = parseTimestamp(from: text, formatter: formatter) else {
                continue
            }

            latest = (startedAt, parseFallbackSeconds(from: text))
        }

        return latest
    }

    private static func parseTimestamp(from line: String, formatter: DateFormatter) -> Date? {
        let prefix = String(line.prefix(timestampFormat.count))
        return formatter.date(from: prefix)
    }

    private static func parseFallbackSeconds(from line: String) -> Int {
        guard let range = line.range(of: "seconds=") else {
            return defaultFallbackSeconds
        }

        let suffix = line[range.upperBound...]
        let digits = suffix.prefix { $0.isNumber }
        guard let value = Int(digits), value > 0 else {
            return defaultFallbackSeconds
        }

        return value
    }

    private static func timestampFormatter() -> DateFormatter {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone.current
        formatter.dateFormat = timestampFormat
        return formatter
    }
}