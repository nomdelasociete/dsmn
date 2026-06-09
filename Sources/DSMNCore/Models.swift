import Foundation

public enum AgentKind: String, Codable, CaseIterable, Sendable {
    case claudeCode
    case codex
    case grokBuild
    case pi
    case perplexityDesktop

    public var displayName: String {
        switch self {
        case .claudeCode:
            "Claude Code"
        case .codex:
            "Codex"
        case .grokBuild:
            "Grok Build"
        case .pi:
            "Pi"
        case .perplexityDesktop:
            "Perplexity Desktop"
        }
    }
}

public struct RunningProcess: Equatable, Sendable {
    public var pid: Int32
    public var ppid: Int32?
    public var executable: String
    public var command: String

    public init(pid: Int32, ppid: Int32?, executable: String, command: String) {
        self.pid = pid
        self.ppid = ppid
        self.executable = executable
        self.command = command
    }
}

public struct AgentProcess: Codable, Equatable, Sendable {
    public var pid: Int32
    public var ppid: Int32?
    public var executable: String
    public var command: String
    public var kind: AgentKind

    public init(pid: Int32, ppid: Int32?, executable: String, command: String, kind: AgentKind) {
        self.pid = pid
        self.ppid = ppid
        self.executable = executable
        self.command = command
        self.kind = kind
    }
}

public struct ActivationRequester: Codable, Equatable, Sendable {
    public var name: String
    public var context: String?
    public var event: String?
    public var requestedAt: Date

    public init(name: String, context: String? = nil, event: String? = nil, requestedAt: Date = Date()) {
        self.name = Self.clean(name) ?? "Unknown"
        self.context = Self.clean(context)
        self.event = Self.clean(event)
        self.requestedAt = requestedAt
    }

    public func requested(at date: Date) -> ActivationRequester {
        ActivationRequester(name: name, context: context, event: event, requestedAt: date)
    }

    public var displayText: String {
        if let context {
            return "\(name) - \(context)"
        }

        return name
    }

    public func shortDisplayText(maxLength: Int = 36) -> String {
        Self.truncate(displayText, maxLength: maxLength)
    }

    private static func clean(_ value: String?) -> String? {
        guard let value else {
            return nil
        }

        let cleaned = value
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "\r", with: " ")
            .replacingOccurrences(of: "\t", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard !cleaned.isEmpty else {
            return nil
        }

        return truncate(cleaned, maxLength: 120)
    }

    private static func truncate(_ value: String, maxLength: Int) -> String {
        guard value.count > maxLength else {
            return value
        }

        guard maxLength > 3 else {
            return String(value.prefix(maxLength))
        }

        return String(value.prefix(maxLength - 3)) + "..."
    }
}

public struct TriggerActivityBucket: Codable, Equatable, Sendable {
    public var startedAt: Date
    public var count: Int

    public init(startedAt: Date, count: Int) {
        self.startedAt = startedAt
        self.count = max(0, count)
    }
}

public enum PowerSource: String, Codable, Sendable {
    case ac
    case battery
    case unknown
}

public struct SystemSnapshot: Codable, Equatable, Sendable {
    public var now: Date
    public var powerSource: PowerSource
    public var batteryPercent: Int?
    public var defaultRouteAvailable: Bool?
    public var lidClosed: Bool?

    public init(
        now: Date = Date(),
        powerSource: PowerSource = .unknown,
        batteryPercent: Int? = nil,
        defaultRouteAvailable: Bool? = nil,
        lidClosed: Bool? = nil
    ) {
        self.now = now
        self.powerSource = powerSource
        self.batteryPercent = batteryPercent
        self.defaultRouteAvailable = defaultRouteAvailable
        self.lidClosed = lidClosed
    }
}

public struct SafetyPolicy: Codable, Equatable, Sendable {
    public var minimumBatteryPercent: Int
    public var maxManualDurationMinutes: Int
    public var lidOpenGraceSeconds: Int
    public var noRouteGraceSeconds: Int

    public init(
        minimumBatteryPercent: Int = 20,
        maxManualDurationMinutes: Int = 8 * 60,
        lidOpenGraceSeconds: Int = 5 * 60,
        noRouteGraceSeconds: Int = 15 * 60
    ) {
        self.minimumBatteryPercent = minimumBatteryPercent
        self.maxManualDurationMinutes = maxManualDurationMinutes
        self.lidOpenGraceSeconds = lidOpenGraceSeconds
        self.noRouteGraceSeconds = noRouteGraceSeconds
    }
}

public struct DSMNState: Codable, Equatable, Sendable {
    public var manualUntil: Date?
    public var ownsSleepDisable: Bool
    public var lastActivationReason: String?
    public var lastStopReason: String?
    public var lastRequester: ActivationRequester?
    public var recentRequesters: [ActivationRequester]
    public var triggerHistory: [ActivationRequester]
    public var triggerActivityBuckets: [TriggerActivityBucket]
    public var noRouteUnavailableSince: Date?
    /// When the lid last transitioned from closed to open; anchors lid-open grace.
    public var lidOpenedAt: Date?
    /// Previous reconcile snapshot of `SystemSnapshot.lidClosed` for edge detection.
    public var lastLidClosed: Bool?
    public var createdAt: Date
    public var updatedAt: Date

    public init(
        manualUntil: Date? = nil,
        ownsSleepDisable: Bool = false,
        lastActivationReason: String? = nil,
        lastStopReason: String? = nil,
        lastRequester: ActivationRequester? = nil,
        recentRequesters: [ActivationRequester] = [],
        triggerHistory: [ActivationRequester] = [],
        triggerActivityBuckets: [TriggerActivityBucket] = [],
        noRouteUnavailableSince: Date? = nil,
        lidOpenedAt: Date? = nil,
        lastLidClosed: Bool? = nil,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.manualUntil = manualUntil
        self.ownsSleepDisable = ownsSleepDisable
        self.lastActivationReason = lastActivationReason
        self.lastStopReason = lastStopReason
        self.lastRequester = lastRequester
        self.recentRequesters = recentRequesters
        self.triggerHistory = triggerHistory
        self.triggerActivityBuckets = triggerActivityBuckets
        self.noRouteUnavailableSince = noRouteUnavailableSince
        self.lidOpenedAt = lidOpenedAt
        self.lastLidClosed = lastLidClosed
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    private enum CodingKeys: String, CodingKey {
        case manualUntil
        case ownsSleepDisable
        case lastActivationReason
        case lastStopReason
        case lastRequester
        case recentRequesters
        case triggerHistory
        case triggerActivityBuckets
        case noRouteUnavailableSince
        case lidOpenedAt
        case lastLidClosed
        case createdAt
        case updatedAt
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        manualUntil = try container.decodeIfPresent(Date.self, forKey: .manualUntil)
        ownsSleepDisable = try container.decodeIfPresent(Bool.self, forKey: .ownsSleepDisable) ?? false
        lastActivationReason = try container.decodeIfPresent(String.self, forKey: .lastActivationReason)
        lastStopReason = try container.decodeIfPresent(String.self, forKey: .lastStopReason)
        lastRequester = try container.decodeIfPresent(ActivationRequester.self, forKey: .lastRequester)
        recentRequesters = try container.decodeIfPresent([ActivationRequester].self, forKey: .recentRequesters)
            ?? lastRequester.map { [$0] }
            ?? []
        let decodedTriggerHistory = try container.decodeIfPresent([ActivationRequester].self, forKey: .triggerHistory)
        if let decodedTriggerHistory, !decodedTriggerHistory.isEmpty {
            triggerHistory = decodedTriggerHistory
        } else {
            triggerHistory = recentRequesters
        }
        let decodedActivityBuckets = try container.decodeIfPresent([TriggerActivityBucket].self, forKey: .triggerActivityBuckets)
        if let decodedActivityBuckets, !decodedActivityBuckets.isEmpty {
            triggerActivityBuckets = Self.normalizedTriggerActivityBuckets(decodedActivityBuckets)
        } else {
            triggerActivityBuckets = Self.makeTriggerActivityBuckets(from: triggerHistory)
        }
        noRouteUnavailableSince = try container.decodeIfPresent(Date.self, forKey: .noRouteUnavailableSince)
        lidOpenedAt = try container.decodeIfPresent(Date.self, forKey: .lidOpenedAt)
        lastLidClosed = try container.decodeIfPresent(Bool.self, forKey: .lastLidClosed)
        createdAt = try container.decodeIfPresent(Date.self, forKey: .createdAt) ?? Date()
        updatedAt = try container.decodeIfPresent(Date.self, forKey: .updatedAt) ?? createdAt
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)

        try container.encodeIfPresent(manualUntil, forKey: .manualUntil)
        try container.encode(ownsSleepDisable, forKey: .ownsSleepDisable)
        try container.encodeIfPresent(lastActivationReason, forKey: .lastActivationReason)
        try container.encodeIfPresent(lastStopReason, forKey: .lastStopReason)
        try container.encodeIfPresent(lastRequester, forKey: .lastRequester)
        try container.encode(recentRequesters, forKey: .recentRequesters)
        try container.encode(triggerHistory, forKey: .triggerHistory)
        try container.encode(triggerActivityBuckets, forKey: .triggerActivityBuckets)
        try container.encodeIfPresent(noRouteUnavailableSince, forKey: .noRouteUnavailableSince)
        try container.encodeIfPresent(lidOpenedAt, forKey: .lidOpenedAt)
        try container.encodeIfPresent(lastLidClosed, forKey: .lastLidClosed)
        try container.encode(createdAt, forKey: .createdAt)
        try container.encode(updatedAt, forKey: .updatedAt)
    }

    public mutating func syncSnapshotTracking(with snapshot: SystemSnapshot) {
        syncLidOpenGrace(with: snapshot)
        updateNoRouteTracking(snapshot: snapshot)
    }

    public mutating func updateNoRouteTracking(snapshot: SystemSnapshot) {
        let now = snapshot.now
        if manualIsActive(at: now), snapshot.defaultRouteAvailable == false {
            if noRouteUnavailableSince == nil {
                noRouteUnavailableSince = now
            }
        } else {
            noRouteUnavailableSince = nil
        }
    }

    public func noRouteGraceRemainingSeconds(at date: Date, graceSeconds: Int) -> Int? {
        guard manualIsActive(at: date), let since = noRouteUnavailableSince else {
            return nil
        }

        let elapsed = Int(date.timeIntervalSince(since).rounded(.down))
        return max(0, graceSeconds - elapsed)
    }

    /// Updates lid-open grace anchors from the latest snapshot. Call before power evaluation.
    public mutating func syncLidOpenGrace(with snapshot: SystemSnapshot) {
        let lidClosed = snapshot.lidClosed

        if lidClosed == true {
            lidOpenedAt = nil
        } else if lidClosed == false, lastLidClosed == true {
            lidOpenedAt = snapshot.now
        }

        lastLidClosed = lidClosed
    }

    public func lidOpenGraceRemainingSeconds(at date: Date, graceSeconds: Int) -> Int? {
        guard let lidOpenedAt else {
            return nil
        }

        let remaining = Int(lidOpenedAt.addingTimeInterval(TimeInterval(graceSeconds)).timeIntervalSince(date).rounded(.down))
        return max(0, remaining)
    }

    public func isWithinLidOpenGrace(at date: Date, graceSeconds: Int) -> Bool {
        guard let remaining = lidOpenGraceRemainingSeconds(at: date, graceSeconds: graceSeconds) else {
            return false
        }

        return remaining > 0
    }

    public mutating func recordRequester(
        _ requester: ActivationRequester,
        at date: Date,
        maxRecentCount: Int = 6,
        maxTriggerHistoryCount: Int = 500
    ) {
        let requested = requester.requested(at: date)
        lastRequester = requested
        recordTriggerActivity(at: date)
        triggerHistory.append(requested)
        pruneTriggerHistory(now: date, maxCount: maxTriggerHistoryCount)

        recentRequesters.removeAll { existing in
            existing.name == requested.name && existing.context == requested.context
        }
        recentRequesters.insert(requested, at: 0)

        if recentRequesters.count > maxRecentCount {
            recentRequesters = Array(recentRequesters.prefix(maxRecentCount))
        }
    }

    private mutating func pruneTriggerHistory(now: Date, maxCount: Int) {
        let cutoff = now.addingTimeInterval(-12 * 60 * 60)
        triggerHistory = triggerHistory.filter { $0.requestedAt >= cutoff && $0.requestedAt <= now }

        if triggerHistory.count > maxCount {
            triggerHistory = Array(triggerHistory.suffix(maxCount))
        }
    }

    private mutating func recordTriggerActivity(at date: Date) {
        let bucketStart = Self.triggerBucketStart(for: date)
        if let index = triggerActivityBuckets.firstIndex(where: { $0.startedAt == bucketStart }) {
            triggerActivityBuckets[index].count += 1
        } else {
            triggerActivityBuckets.append(TriggerActivityBucket(startedAt: bucketStart, count: 1))
        }

        triggerActivityBuckets = Self.prunedTriggerActivityBuckets(triggerActivityBuckets, now: date)
    }

    public static func makeTriggerActivityBuckets(
        from requesters: [ActivationRequester],
        now: Date? = nil
    ) -> [TriggerActivityBucket] {
        let effectiveNow = now ?? requesters.map(\.requestedAt).max() ?? Date()
        let cutoff = effectiveNow.addingTimeInterval(-triggerActivityRetention)
        var counts: [Date: Int] = [:]

        for requester in requesters where requester.requestedAt >= cutoff && requester.requestedAt <= effectiveNow {
            counts[triggerBucketStart(for: requester.requestedAt), default: 0] += 1
        }

        return counts
            .map { TriggerActivityBucket(startedAt: $0.key, count: $0.value) }
            .sorted { $0.startedAt < $1.startedAt }
    }

    private static func normalizedTriggerActivityBuckets(_ buckets: [TriggerActivityBucket]) -> [TriggerActivityBucket] {
        var counts: [Date: Int] = [:]
        for bucket in buckets where bucket.count > 0 {
            counts[triggerBucketStart(for: bucket.startedAt), default: 0] += bucket.count
        }

        let normalized = counts
            .map { TriggerActivityBucket(startedAt: $0.key, count: $0.value) }
            .sorted { $0.startedAt < $1.startedAt }

        if normalized.count > maxTriggerActivityBucketCount {
            return Array(normalized.suffix(maxTriggerActivityBucketCount))
        }

        return normalized
    }

    private static func prunedTriggerActivityBuckets(
        _ buckets: [TriggerActivityBucket],
        now: Date
    ) -> [TriggerActivityBucket] {
        let cutoff = now.addingTimeInterval(-triggerActivityRetention)
        let pruned = buckets
            .filter { $0.count > 0 && $0.startedAt.addingTimeInterval(triggerActivityBucketDuration) > cutoff && $0.startedAt <= now }
            .sorted { $0.startedAt < $1.startedAt }

        if pruned.count > maxTriggerActivityBucketCount {
            return Array(pruned.suffix(maxTriggerActivityBucketCount))
        }

        return pruned
    }

    private static func triggerBucketStart(for date: Date) -> Date {
        Date(timeIntervalSince1970: floor(date.timeIntervalSince1970 / triggerActivityBucketDuration) * triggerActivityBucketDuration)
    }

    private static let triggerActivityBucketDuration: TimeInterval = 60
    private static let triggerActivityRetention: TimeInterval = 12 * 60 * 60
    private static let maxTriggerActivityBucketCount = 12 * 60

    public func manualRemainingSeconds(at date: Date) -> Int? {
        guard let manualUntil else {
            return nil
        }

        return max(0, Int(manualUntil.timeIntervalSince(date).rounded(.down)))
    }

    public func manualIsActive(at date: Date) -> Bool {
        guard let remaining = manualRemainingSeconds(at: date) else {
            return false
        }

        return remaining > 0
    }
}
