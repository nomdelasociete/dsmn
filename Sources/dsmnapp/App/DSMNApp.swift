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
    @AppStorage("showMenuBarCountdown") private var showMenuBarCountdown = true

    var body: some Scene {
        MenuBarExtra {
            DSMNMenuView(store: store)
                .task {
                    await store.refresh()
                }
        } label: {
            TimelineView(.periodic(from: .now, by: 1)) { context in
                HStack(spacing: 4) {
                    Image(systemName: store.menuBarSystemImage)
                        .symbolRenderingMode(.hierarchical)
                        .id(store.menuBarIconState.rawValue)

                    if showMenuBarCountdown, let countdown = store.menuBarCountdownText(at: context.date) {
                        Text(countdown)
                            .monospacedDigit()
                    }
                }
                .task {
                    store.startRefreshLoop()
                }
                .accessibilityLabel(store.menuBarAccessibilityLabel(at: context.date))
            }
        }
        .menuBarExtraStyle(.menu)
    }
}
