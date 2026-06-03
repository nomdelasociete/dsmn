import Foundation

public struct TriggerActivitySummary: Equatable, Sendable {
    public var total: Int
    public var buckets: [Int]
    public var hours: Int

    public init(
        requesters: [ActivationRequester],
        now: Date = Date(),
        hours: Int = 12,
        bucketCount: Int = 24
    ) {
        let safeHours = max(1, hours)
        let safeBucketCount = max(1, bucketCount)
        let window = TimeInterval(safeHours * 60 * 60)
        let start = now.addingTimeInterval(-window)
        let bucketDuration = window / Double(safeBucketCount)
        let recent = requesters.filter { requester in
            requester.requestedAt >= start && requester.requestedAt <= now
        }

        var buckets = Array(repeating: 0, count: safeBucketCount)
        for requester in recent {
            let offset = requester.requestedAt.timeIntervalSince(start)
            let rawIndex = Int(offset / bucketDuration)
            let index = min(max(rawIndex, 0), safeBucketCount - 1)
            buckets[index] += 1
        }

        self.total = recent.count
        self.buckets = buckets
        self.hours = safeHours
    }
}
