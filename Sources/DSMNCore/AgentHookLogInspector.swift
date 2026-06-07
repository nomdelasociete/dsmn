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
    public static let fallbackResolvedMarker = "fallback resolved"
    public static let activeMarker = "dsmn active"
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

        if let resolvedAt = latestResolvedEvent(in: logContents), resolvedAt >= event.startedAt {
            return AgentHookFallbackStatus(
                isActive: false,
                logPath: logPath,
                lastStartedAt: event.startedAt,
                fallbackSeconds: event.fallbackSeconds
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

    public static func markFallbackResolved(
        logPath: String? = nil,
        reason: String,
        now: Date = Date(),
        environment: [String: String] = ProcessInfo.processInfo.environment,
        fileManager: FileManager = .default
    ) {
        let resolvedPath = logPath ?? Self.logPath(environment: environment)
        let line = "\(timestampString(for: now)) \(fallbackResolvedMarker) reason=\(sanitize(reason))\n"

        do {
            let url = URL(fileURLWithPath: resolvedPath)
            let directory = url.deletingLastPathComponent()
            try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)

            guard let data = line.data(using: .utf8) else {
                return
            }

            if fileManager.fileExists(atPath: resolvedPath) {
                let handle = try FileHandle(forWritingTo: url)
                try handle.seekToEnd()
                handle.write(data)
                try? handle.close()
            } else {
                try data.write(to: url, options: .atomic)
            }
        } catch {
            return
        }
    }

    public static func doctorWarning(
        for status: AgentHookFallbackStatus,
        ownsSleepDisable: Bool = false
    ) -> String? {
        guard status.isActive, !ownsSleepDisable else {
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

    static func latestActiveEvent(in logContents: String) -> Date? {
        latestEvent(in: logContents, containing: activeMarker)
    }

    static func latestResolvedEvent(in logContents: String) -> Date? {
        let activeAt = latestActiveEvent(in: logContents)
        let fallbackResolvedAt = latestEvent(in: logContents, containing: fallbackResolvedMarker)

        switch (activeAt, fallbackResolvedAt) {
        case let (.some(activeAt), .some(fallbackResolvedAt)):
            return max(activeAt, fallbackResolvedAt)
        case let (.some(activeAt), .none):
            return activeAt
        case let (.none, .some(fallbackResolvedAt)):
            return fallbackResolvedAt
        case (.none, .none):
            return nil
        }
    }

    private static func latestEvent(in logContents: String, containing marker: String) -> Date? {
        let formatter = timestampFormatter()
        var latest: Date?

        for line in logContents.split(whereSeparator: \.isNewline) {
            let text = String(line)
            guard text.contains(marker),
                  let activeAt = parseTimestamp(from: text, formatter: formatter)
            else {
                continue
            }

            latest = activeAt
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

    private static func timestampString(for date: Date) -> String {
        timestampFormatter().string(from: date)
    }

    private static func sanitize(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "\r", with: " ")
            .replacingOccurrences(of: "\t", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .prefix(80)
            .description
    }
}

public enum HookFallbackRecoveryPolicy {
    public static func remainingMinutes(
        for status: AgentHookFallbackStatus,
        now: Date = Date()
    ) -> Int? {
        guard status.isActive, let lastStartedAt = status.lastStartedAt else {
            return nil
        }

        let expiresAt = lastStartedAt.addingTimeInterval(TimeInterval(status.fallbackSeconds))
        let remainingSeconds = expiresAt.timeIntervalSince(now)
        guard remainingSeconds > 0 else {
            return nil
        }

        return max(1, Int(ceil(remainingSeconds / 60)))
    }
}
