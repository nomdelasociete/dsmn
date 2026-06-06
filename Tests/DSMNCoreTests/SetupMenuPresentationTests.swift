import XCTest
@testable import DSMNCore

final class SetupMenuPresentationTests: XCTestCase {
    func testSetupLinePrioritizesHelperRepairOverHooks() {
        let signals = SetupMenuSignals(
            helperIsReady: false,
            helperNeedsRepair: true,
            helperNeedsUpdate: false,
            helperNeedsApproval: false,
            helperNeedsInstall: false,
            hooksAreReady: false,
            hooksNeedInstall: true
        )

        XCTAssertEqual(SetupMenuPresentation.setupLine(from: signals), "Setup: repair helper")
    }

    func testSetupLineShowsHookProgressWhenHelperReady() {
        let signals = SetupMenuSignals(
            helperIsReady: true,
            helperNeedsRepair: false,
            helperNeedsUpdate: false,
            helperNeedsApproval: false,
            helperNeedsInstall: false,
            hooksAreReady: false,
            hooksPartialInstalled: 2,
            hooksPartialTotal: 4,
            hooksNeedInstall: true
        )

        XCTAssertEqual(SetupMenuPresentation.setupLine(from: signals), "Setup: hooks 2/4")
    }

    func testPrefersExpandedSetupWhenHooksIncomplete() {
        let signals = SetupMenuSignals(
            helperIsReady: true,
            helperNeedsRepair: false,
            helperNeedsUpdate: false,
            helperNeedsApproval: false,
            helperNeedsInstall: false,
            hooksAreReady: false,
            hooksNeedInstall: true
        )

        XCTAssertTrue(SetupMenuPresentation.prefersExpandedSetup(from: signals))
    }

    func testHooksUpdateAvailableBlocksSetupCompletion() {
        let signals = SetupMenuSignals(
            helperIsReady: true,
            helperNeedsRepair: false,
            helperNeedsUpdate: false,
            helperNeedsApproval: false,
            helperNeedsInstall: false,
            hooksAreReady: false,
            hooksNeedUpdate: true
        )

        XCTAssertFalse(signals.isSetupComplete)
        XCTAssertEqual(SetupMenuPresentation.setupLine(from: signals), "Hooks update available")
        XCTAssertEqual(
            SetupMenuPresentation.setupIncompleteStatusTitle(from: signals, wizardDismissed: true),
            "Setup incomplete"
        )
    }

    func testHelperUpdateIsAdvisoryWhenHooksReady() {
        let signals = SetupMenuSignals(
            helperIsReady: false,
            helperNeedsRepair: false,
            helperNeedsUpdate: true,
            helperNeedsApproval: false,
            helperNeedsInstall: false,
            hooksAreReady: true
        )

        XCTAssertTrue(signals.isSetupComplete)
        XCTAssertEqual(SetupMenuPresentation.setupLine(from: signals), "Helper update available")
        XCTAssertNil(
            SetupMenuPresentation.setupIncompleteStatusTitle(from: signals, wizardDismissed: true)
        )
    }

    func testHelperRepairStillBlocksSetupEvenWhenUpdateAvailable() {
        let signals = SetupMenuSignals(
            helperIsReady: false,
            helperNeedsRepair: true,
            helperNeedsUpdate: true,
            helperNeedsApproval: false,
            helperNeedsInstall: false,
            hooksAreReady: true
        )

        XCTAssertFalse(signals.isSetupComplete)
        XCTAssertEqual(SetupMenuPresentation.setupLine(from: signals), "Setup: repair helper")
    }

    func testPrefersCollapsedSetupWhenSuppressedAndOnlyHooksMissing() {
        let signals = SetupMenuSignals(
            helperIsReady: true,
            helperNeedsRepair: false,
            helperNeedsUpdate: false,
            helperNeedsApproval: false,
            helperNeedsInstall: false,
            hooksAreReady: false,
            hooksNeedInstall: true,
            remindersSuppressed: true
        )

        XCTAssertFalse(SetupMenuPresentation.prefersExpandedSetup(from: signals))
        XCTAssertEqual(SetupMenuPresentation.setupLine(from: signals), "Setup: install hooks")
    }

    func testIncompleteStatusOnlyAfterWizardDismissed() {
        let incomplete = SetupMenuSignals(
            helperIsReady: false,
            helperNeedsRepair: false,
            helperNeedsUpdate: false,
            helperNeedsApproval: false,
            helperNeedsInstall: true,
            hooksAreReady: false,
            hooksNeedInstall: true
        )

        XCTAssertNil(
            SetupMenuPresentation.setupIncompleteStatusTitle(from: incomplete, wizardDismissed: false)
        )
        XCTAssertEqual(
            SetupMenuPresentation.setupIncompleteStatusTitle(from: incomplete, wizardDismissed: true),
            "Setup incomplete"
        )
    }
}
