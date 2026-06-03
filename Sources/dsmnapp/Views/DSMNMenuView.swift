import AppKit
import DSMNCore
import Sparkle
import SwiftUI

struct DSMNMenuView: View {
    @ObservedObject var store: DSMNMenuStore
    var updater: SPUUpdater?
    @AppStorage("showMenuBarCountdown") private var showMenuBarCountdown = true
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Text(store.statusLine)

        if let setupLine = store.setupLine {
            Text(setupLine)
        }

        if let powerLockLine = store.powerLockLine {
            Text(powerLockLine)
        }

        if let lastRequesterLine = store.lastRequesterLine {
            Text(lastRequesterLine)
        }

        if let errorMessage = store.errorMessage {
            Text(short(errorMessage))
        }

        Text(store.helperStatusLine)
        Text(store.launchAtLoginStatusLine)

        Divider()

        Toggle("Show Countdown", isOn: $showMenuBarCountdown)

        Toggle("Launch at Login", isOn: Binding(
            get: { store.launchAtLoginEnabled },
            set: { store.setLaunchAtLogin($0) }
        ))

        if store.loginItemNeedsApproval {
            Button("Open Login Items") {
                store.openLoginItemsSettings()
            }
        }

        Divider()

        Button("Keep Awake 30m") {
            store.keepAwake(minutes: 30)
        }
        .keyboardShortcut("3")
        .disabled(!store.canRunAwakeCommands)

        Button("Keep Awake 90m") {
            store.keepAwake(minutes: 90)
        }
        .keyboardShortcut("9")
        .disabled(!store.canRunAwakeCommands)

        Button("Stop") {
            store.stop()
        }
        .keyboardShortcut(".")

        Divider()

        CheckForUpdatesView(updater: updater)

        Divider()

        Button("Send Feedback") {
            FeedbackWindowPresenter.show(store: store)
        }

        Button("About dsmn") {
            AboutPanelPresenter.show()
        }

        Button("Why Awake?") {
            NSApplication.shared.activate(ignoringOtherApps: true)
            openWindow(id: "why-awake")
        }

        Button("Setup Guide") {
            OnboardingWindowPresenter.show(store: store)
        }

        Button("Refresh") {
            Task {
                await store.refresh()
            }
        }
        .keyboardShortcut("r")

        Divider()

        if store.canInstallHelper {
            Button("1. Install Helper") {
                store.installHelper()
            }
        }

        if store.helperNeedsApproval {
            Button("2. Open Login Items") {
                store.openHelperSettings()
            }
        }

        if store.canUnregisterHelper {
            Button("Unregister Helper") {
                store.unregisterHelper()
            }
        }

        Divider()

        Button("Quit") {
            quit()
        }
        .keyboardShortcut("q")
    }

    private func quit() {
        guard store.isProtectingSleep else {
            NSApplication.shared.terminate(nil)
            return
        }

        let alert = NSAlert()
        alert.messageText = "Quit dsmn?"
        alert.informativeText = """
        dsmn is currently keeping the Mac awake. Quitting only closes the menu bar app; the helper and agent hooks can keep running.

        Stop & Quit releases the current dsmn timer first. Active Claude, Codex, Grok, or Pi hooks can start a new timer again later.
        """
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Stop & Quit")
        alert.addButton(withTitle: "Quit, Keep Running")
        alert.addButton(withTitle: "Cancel")

        switch alert.runModal() {
        case .alertFirstButtonReturn:
            Task {
                await store.stopNow()
                NSApplication.shared.terminate(nil)
            }
        case .alertSecondButtonReturn:
            NSApplication.shared.terminate(nil)
        default:
            break
        }
    }

    private func short(_ value: String) -> String {
        if value.count <= 30 {
            return value
        }

        return String(value.prefix(27)) + "..."
    }
}
