import AppKit
import DSMNCore
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
    }
}

@main
struct DSMNApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var store = DSMNMenuStore()

    var body: some Scene {
        MenuBarExtra {
            DSMNMenuView(store: store)
                .task {
                    await store.refresh()
                }
        } label: {
            Image(systemName: store.menuBarSystemImage)
                .symbolRenderingMode(.hierarchical)
                .id(store.menuBarIconState.rawValue)
                .accessibilityLabel(store.statusLine)
        }
        .menuBarExtraStyle(.menu)
    }
}
