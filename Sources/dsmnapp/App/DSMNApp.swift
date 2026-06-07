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
    private let softwareUpdateController = SoftwareUpdateController()

    private let menuBarTimer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some Scene {
        MenuBarExtra {
            DSMNMenuView(store: store, updateController: softwareUpdateController)
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
                    try? await Task.sleep(for: .milliseconds(600))
                    await store.refresh()

                    if store.shouldPresentHelperUpdateReminder {
                        SetupTroubleshootingWindowPresenter.show(store: store)
                        store.deferHelperUpdateReminder()
                    } else if store.shouldPresentSetupAttentionReminder {
                        SetupTroubleshootingWindowPresenter.show(store: store)
                    } else {
                        OnboardingWindowPresenter.showIfNeeded(store: store)
                    }
                }
        }
        .menuBarExtraStyle(.menu)

        WindowGroup("Why Awake?", id: "why-awake") {
            WhyAwakeView(store: store)
        }
        .defaultSize(width: 580, height: 560)
    }
}

private struct DSMNMenuBarLabel: View {
    @ObservedObject var store: DSMNMenuStore
    var showCountdown: Bool
    var date: Date

    var body: some View {
        HStack(spacing: 4) {
            if showCountdown, let countdown = store.menuBarCountdownText(at: date) {
                icon

                Text(countdown)
                    .monospacedDigit()
            } else {
                icon
            }
        }
        .fixedSize()
        .accessibilityLabel(store.menuBarAccessibilityLabel(at: date))
    }

    private var icon: some View {
        DSMNMenuBarIcon(state: store.menuBarIconState)
    }
}
