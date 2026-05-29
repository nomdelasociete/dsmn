import AppKit
import DSMNCore
import SwiftUI

struct DSMNMenuView: View {
    @ObservedObject var store: DSMNMenuStore

    var body: some View {
        Text(store.statusLine)

        if let errorMessage = store.errorMessage {
            Text(short(errorMessage))
        }

        Divider()

        Button("Keep Awake 30m") {
            store.keepAwake(minutes: 30)
        }
        .keyboardShortcut("3")

        Button("Keep Awake 90m") {
            store.keepAwake(minutes: 90)
        }
        .keyboardShortcut("9")

        Divider()

        Button(autoTitle) {
            store.toggleAuto()
        }
        .keyboardShortcut("a")

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

        Button("Quit") {
            NSApplication.shared.terminate(nil)
        }
        .keyboardShortcut("q")
    }

    private var autoTitle: String {
        guard let report = store.report else {
            return "Toggle Auto"
        }

        return report.state.autoEnabled ? "Auto Off" : "Auto On"
    }

    private func short(_ value: String) -> String {
        if value.count <= 30 {
            return value
        }

        return String(value.prefix(27)) + "..."
    }
}

