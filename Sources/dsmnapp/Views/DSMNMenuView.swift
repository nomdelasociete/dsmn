import AppKit
import DSMNCore
import SwiftUI

struct DSMNMenuView: View {
    @ObservedObject var store: DSMNMenuStore
    @AppStorage("showMenuBarCountdown") private var showMenuBarCountdown = true

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

        Divider()

        Toggle("Show Countdown", isOn: $showMenuBarCountdown)

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
            NSApplication.shared.terminate(nil)
        }
        .keyboardShortcut("q")
    }

    private func short(_ value: String) -> String {
        if value.count <= 30 {
            return value
        }

        return String(value.prefix(27)) + "..."
    }
}
