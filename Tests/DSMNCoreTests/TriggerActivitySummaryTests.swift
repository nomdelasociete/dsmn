import XCTest
@testable import DSMNCore

final class TriggerActivitySummaryTests: XCTestCase {
    func testBucketsTriggersAcrossWindow() {
        let now = Date(timeIntervalSince1970: 12 * 60 * 60)
        let requesters = [
            ActivationRequester(name: "Codex", requestedAt: now.addingTimeInterval(-11 * 60 * 60)),
            ActivationRequester(name: "Claude Code", requestedAt: now.addingTimeInterval(-35 * 60)),
            ActivationRequester(name: "Pi", requestedAt: now.addingTimeInterval(-20 * 60)),
            ActivationRequester(name: "Grok Build", requestedAt: now.addingTimeInterval(-13 * 60 * 60))
        ]

        let summary = TriggerActivitySummary(requesters: requesters, now: now, hours: 12, bucketCount: 12)

        XCTAssertEqual(summary.total, 3)
        XCTAssertEqual(summary.buckets.reduce(0, +), 3)
        XCTAssertEqual(summary.buckets[1], 1)
        XCTAssertEqual(summary.buckets[11], 2)
        XCTAssertEqual(summary.sparkline, "·▄·········█")
        XCTAssertEqual(summary.menuLine, "Triggers 12h  ·▄·········█  3")
    }

    func testSparklineShowsEmptyBucketsWithoutSplittingMenuLayout() {
        let summary = TriggerActivitySummary(requesters: [], hours: 12, bucketCount: 12)

        XCTAssertEqual(summary.sparkline, "············")
        XCTAssertEqual(summary.menuLine, "Triggers 12h  ············  0")
    }

    func testBucketsUseAggregatedActivityCounts() {
        let now = Date(timeIntervalSince1970: 12 * 60 * 60)
        let activityBuckets = [
            TriggerActivityBucket(startedAt: now.addingTimeInterval(-11 * 60 * 60), count: 120),
            TriggerActivityBucket(startedAt: now.addingTimeInterval(-30 * 60), count: 250),
            TriggerActivityBucket(startedAt: now.addingTimeInterval(-15 * 60), count: 250),
            TriggerActivityBucket(startedAt: now.addingTimeInterval(-13 * 60 * 60), count: 900)
        ]

        let summary = TriggerActivitySummary(activityBuckets: activityBuckets, now: now, hours: 12, bucketCount: 12)

        XCTAssertEqual(summary.total, 620)
        XCTAssertEqual(summary.buckets.reduce(0, +), 620)
        XCTAssertEqual(summary.buckets[1], 120)
        XCTAssertEqual(summary.buckets[11], 500)
        XCTAssertEqual(summary.menuLine, "Triggers 12h  ·▂·········█  620")
    }
}
