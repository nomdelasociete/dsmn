import Foundation
import XCTest

final class MenuBarExtraStructureTests: XCTestCase {
    func testMenuBarViewAvoidsNestedSwiftUIMenus() throws {
        let menuViewSource = try sourceFile(at: "Sources/dsmnapp/Views/DSMNMenuView.swift")
        let hasNestedMenu = menuViewSource
            .components(separatedBy: .newlines)
            .contains { $0.trimmingCharacters(in: .whitespaces).hasPrefix("Menu {") }

        XCTAssertFalse(
            hasNestedMenu,
            "Do not put nested SwiftUI Menu controls inside the MenuBarExtra menu. Use direct Section rows instead."
        )
    }

    func testSetupTroubleshootingMenuEntryOpensDedicatedWindow() throws {
        let menuViewSource = try sourceFile(at: "Sources/dsmnapp/Views/DSMNMenuView.swift")

        XCTAssertTrue(menuViewSource.contains("Setup & Troubleshooting..."))
        XCTAssertTrue(menuViewSource.contains("SetupTroubleshootingWindowPresenter.show(store: store)"))
        XCTAssertFalse(menuViewSource.contains("Label(\"Setup Guide\", systemImage: \"book\")"))
    }

    func testSetupTroubleshootingWindowContainsOperationalActions() throws {
        let windowSource = try sourceFile(at: "Sources/dsmnapp/Views/DSMNSetupTroubleshootingView.swift")
        let presenterSource = try sourceFile(at: "Sources/dsmnapp/Services/SetupTroubleshootingWindowPresenter.swift")

        XCTAssertTrue(presenterSource.contains("newWindow.title = \"Setup & Troubleshooting\""))
        XCTAssertTrue(windowSource.contains("Install Helper"))
        XCTAssertTrue(windowSource.contains("Update Helper"))
        XCTAssertTrue(windowSource.contains("Repair Helper"))
        XCTAssertTrue(windowSource.contains("Helper update available"))
        XCTAssertTrue(windowSource.contains("setup.helper-update-later"))
        XCTAssertTrue(windowSource.contains("setup.helper-update-now"))
        XCTAssertTrue(windowSource.contains("store.installAgentHooks()"))
        XCTAssertTrue(windowSource.contains("Why Awake?"))
        XCTAssertTrue(windowSource.contains("Doctor"))
        XCTAssertTrue(windowSource.contains("Repair"))
        XCTAssertTrue(windowSource.contains("Setup Guide"))
        XCTAssertTrue(windowSource.contains(".accessibilityIdentifier(\"setup.refresh\")"))
        XCTAssertTrue(windowSource.contains(".accessibilityIdentifier(\"setup.guide\")"))
        XCTAssertTrue(windowSource.contains(".accessibilityIdentifier(\"setup.done\")"))
    }

    func testAppLaunchSurfacesVoluntaryHelperUpdateReminder() throws {
        let appSource = try sourceFile(at: "Sources/dsmnapp/App/DSMNApp.swift")

        XCTAssertTrue(appSource.contains("store.shouldPresentHelperUpdateReminder"))
        XCTAssertTrue(appSource.contains("SetupTroubleshootingWindowPresenter.show(store: store)"))
        XCTAssertTrue(appSource.contains("OnboardingWindowPresenter.showIfNeeded(store: store)"))
    }

    private func sourceFile(at relativePath: String) throws -> String {
        let repositoryRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let path = repositoryRoot.appendingPathComponent(relativePath)

        return try String(contentsOf: path)
    }
}
