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
    @State private var menuBarDate = Date()

    private let menuBarTimer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some Scene {
        MenuBarExtra {
            DSMNMenuView(store: store)
                .task {
                    await store.refresh()
                }
        } label: {
            DSMNMenuBarLabel(store: store, showCountdown: showMenuBarCountdown, date: menuBarDate)
                .onReceive(menuBarTimer) { date in
                    menuBarDate = date
                }
                .task {
                    store.startRefreshLoop()
                }
        }
        .menuBarExtraStyle(.menu)
    }
}

private struct DSMNMenuBarLabel: View {
    @ObservedObject var store: DSMNMenuStore
    var showCountdown: Bool
    var date: Date

    var body: some View {
        Group {
            if showCountdown, let countdown = store.menuBarCountdownText(at: date) {
                Label {
                    Text(countdown)
                        .monospacedDigit()
                } icon: {
                    icon
                }
            } else {
                icon
            }
        }
        .accessibilityLabel(store.menuBarAccessibilityLabel(at: date))
    }

    private var icon: some View {
        Image(systemName: store.menuBarSystemImage)
            .symbolRenderingMode(.hierarchical)
            .id(store.menuBarIconState.rawValue)
    }
}
