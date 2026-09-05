import AppKit
import DSMNCore
import SwiftUI
import XCTest
@testable import dsmnapp

@MainActor
final class BrandPresentationTests: XCTestCase {
    func testBrandFontsAndAppIconAreBundled() throws {
        _ = DSMNBrand.display(30)
        _ = DSMNBrand.mono()
        XCTAssertNotNil(NSFont(name: "GeistPixel-Square", size: 30))
        XCTAssertNotNil(NSFont(name: "IBMPlexMono-Regular", size: 12))
        let url = try XCTUnwrap(DSMNBrand.resourceBundle.url(forResource: "dsmn", withExtension: "icns"))
        XCTAssertNotNil(NSImage(contentsOf: url))
    }

    func testMenuHeartbeatRemainsTemplateAndDistinguishesActiveState() throws {
        let idle = DSMNStatusIconImage.image(for: .off)
        let active = DSMNStatusIconImage.image(for: .manualActive)
        XCTAssertTrue(idle.isTemplate)
        XCTAssertTrue(active.isTemplate)
        XCTAssertEqual(idle.size, NSSize(width: 28, height: 20))
        XCTAssertNotEqual(try XCTUnwrap(idle.tiffRepresentation), try XCTUnwrap(active.tiffRepresentation))
    }

    func testPanelNeverClaimsProtectionWhenHelperHasNotAppliedLock() throws {
        let store = try fixtureStore(ownsLock: false, active: true)
        XCTAssertEqual(store.menuPanelTitle, "Needs attention")
        XCTAssertEqual(store.menuBarIconState, .warning)
        XCTAssertTrue(store.canRunAwakeCommands)
    }

    func testPanelCountdownExpiresWithoutWaitingForAnotherPoll() throws {
        let store = try fixtureStore(ownsLock: true, active: true)
        let until = try XCTUnwrap(store.report?.state.manualUntil)
        XCTAssertEqual(store.menuPanelCountdown(at: until.addingTimeInterval(-1)), "00:01")
        XCTAssertEqual(store.menuPanelCountdown(at: until), "00:00")
        XCTAssertEqual(store.menuPanelCountdown(at: until.addingTimeInterval(15)), "00:00")
    }

    /// Opt-in review artifacts use AppKit because ImageRenderer omits native scroll views.
    func testRenderBrandedSurfaces() throws {
        guard let directory = ProcessInfo.processInfo.environment["DSMN_DESIGN_SNAPSHOT_DIR"] else {
            throw XCTSkip("Set DSMN_DESIGN_SNAPSHOT_DIR to render offscreen review artifacts.")
        }
        let store = try fixtureStore(ownsLock: true, active: true)
        let views: [(String, AnyView)] = [
            ("panel-active", AnyView(DSMNMenuView(store: store))),
            ("panel-idle", AnyView(DSMNMenuView(store: try fixtureStore(ownsLock: false, active: false)))),
            ("panel-warning", AnyView(DSMNMenuView(store: try fixtureStore(ownsLock: false, active: true)))),
            ("onboarding", AnyView(DSMNOnboardingView(store: store, onSkip: {}, onDone: {}))),
            ("setup", AnyView(DSMNSetupTroubleshootingView(store: store, onClose: {}).frame(width: 740, height: 700))),
            ("doctor", AnyView(DSMNDoctorView(report: "Status source: helper\nPower lock: on\nmacOS SleepDisabled: on", onClose: {}).frame(width: 620, height: 620))),
            ("feedback", AnyView(DSMNFeedbackView(store: store, onClose: {}))),
            ("about", AnyView(DSMNAboutView(onRemoveHooks: {}, onClose: {})))
        ]
        for scheme in [ColorScheme.light, .dark] {
            for (name, view) in views {
                let hosted = NSHostingView(rootView: view
                    .environment(\.colorScheme, scheme)
                    .environment(\.dsmnRefreshOnAppear, false))
                hosted.appearance = NSAppearance(named: scheme == .light ? .aqua : .darkAqua)
                hosted.frame.size = hosted.fittingSize
                hosted.layoutSubtreeIfNeeded()
                let bitmap = try XCTUnwrap(hosted.bitmapImageRepForCachingDisplay(in: hosted.bounds))
                hosted.cacheDisplay(in: hosted.bounds, to: bitmap)
                XCTAssertGreaterThan(bitmap.pixelsWide, 300)
                let url = URL(fileURLWithPath: directory, isDirectory: true)
                try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
                try bitmap.representation(using: .png, properties: [:])?.write(
                    to: url.appendingPathComponent("\(name)-\(scheme == .light ? "light" : "dark").png")
                )
            }
        }
    }

    private func fixtureStore(ownsLock: Bool, active: Bool) throws -> DSMNMenuStore {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("dsmn-brand-test-\(UUID())")
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        let now = Date()
        var state = DSMNState(createdAt: now, updatedAt: now)
        state.ownsSleepDisable = ownsLock
        state.manualUntil = active ? now.addingTimeInterval(984) : nil
        state.lastRequester = ActivationRequester(name: "Codex", context: "dsmn", requestedAt: now)
        let report = StatusReport(generatedAt: now, state: state, snapshot: SystemSnapshot(now: now), agents: [],
                                  decision: PowerDecision(shouldPreventSleep: active, reasons: [], safetyBlocks: []),
                                  manualRemainingSeconds: active ? 984 : nil)
        return DSMNMenuStore(controller: DSMNController(store: StateStore(directory: directory)),
                             helperStatus: .enabled, initialReport: report, stopHelper: { report })
    }
}
