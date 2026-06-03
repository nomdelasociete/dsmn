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
    }
}
