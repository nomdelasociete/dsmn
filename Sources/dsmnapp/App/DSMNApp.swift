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
        MenuBarExtra("", systemImage: store.menuBarSystemImage) {
            DSMNMenuView(store: store)
                .task {
                    await store.refresh()
                }
        }
        .menuBarExtraStyle(.menu)
    }
}

