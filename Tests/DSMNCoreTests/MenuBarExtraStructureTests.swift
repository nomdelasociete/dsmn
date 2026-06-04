import Foundation
import XCTest

final class MenuBarExtraStructureTests: XCTestCase {
    func testMenuBarViewAvoidsNestedSwiftUIMenus() throws {
        let repositoryRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let menuViewPath = repositoryRoot
            .appendingPathComponent("Sources/dsmnapp/Views/DSMNMenuView.swift")
        let menuViewSource = try String(contentsOf: menuViewPath)
        let hasNestedMenu = menuViewSource
            .components(separatedBy: .newlines)
            .contains { $0.trimmingCharacters(in: .whitespaces).hasPrefix("Menu {") }

        XCTAssertFalse(
            hasNestedMenu,
            "Do not put nested SwiftUI Menu controls inside the MenuBarExtra menu. Use direct Section rows instead."
        )
    }
}
