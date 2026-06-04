import AppKit
import DSMNCore
import SwiftUI

struct DSMNMenuView: View {
    @ObservedObject var store: DSMNMenuStore
    var updateController: SoftwareUpdateController?
    @AppStorage("showMenuBarCountdown") private var showMenuBarCountdown = true
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        statusSection
        controlSection

        setupSection

        diagnosticsSection
        moreSection
    }

    // MARK: - Status

    @ViewBuilder
    private var statusSection: some View {
        Section {
            MenuStatusRow(
                title: store.statusLine,
                systemImage: store.menuStatusSystemImage,
                prominent: true
            )

            if let subtitle = store.menuStatusSubtitle {
                MenuStatusRow(title: subtitle, systemImage: "info.circle", prominent: false)
            }

            if let setupStatus = store.menuSetupIncompleteStatusTitle {
                MenuStatusRow(
                    title: setupStatus,
                    systemImage: "exclamationmark.circle",
                    prominent: false
                )
            }

            if let errorMessage = store.errorMessage {
                menuErrorText(errorMessage)
            }
        } header: {
            Text("Status")
        }
    }

    // MARK: - Control

    @ViewBuilder
    private var controlSection: some View {
        Section {
            Button {
                store.keepAwake(minutes: 30)
            } label: {
                Label("Keep Awake for 30 Minutes", systemImage: "clock")
            }
            .keyboardShortcut("3")
            .disabled(!store.canRunAwakeCommands)

            Button {
                store.keepAwake(minutes: 90)
            } label: {
                Label("Keep Awake for 90 Minutes", systemImage: "clock.badge.checkmark")
            }
            .keyboardShortcut("9")
            .disabled(!store.canRunAwakeCommands)

            Button {
                requestCustomDuration()
            } label: {
                Label("Custom Duration...", systemImage: "slider.horizontal.3")
            }
            .disabled(!store.canRunAwakeCommands)

            Button {
                store.stop()
            } label: {
                Label("Stop", systemImage: "stop.circle")
            }
            .keyboardShortcut(".")
        } header: {
            Text("Control")
        }
    }

    // MARK: - Setup

    @ViewBuilder
    private var setupSection: some View {
        Section {
            if let setupLine = store.setupLine {
                MenuStatusRow(title: setupLine, systemImage: "exclamationmark.circle", prominent: false)
            }

            Button {
                SetupTroubleshootingWindowPresenter.show(store: store)
            } label: {
                Label("Setup & Troubleshooting...", systemImage: "wrench.and.screwdriver")
            }
        } header: {
            Text("Setup")
        }
    }

    // MARK: - Diagnostics

    @ViewBuilder
    private var diagnosticsSection: some View {
        Section {
            Button {
                NSApplication.shared.activate(ignoringOtherApps: true)
                openWindow(id: "why-awake")
            } label: {
                Label("Why Awake?", systemImage: "questionmark.circle")
            }

            if store.showsActivityMenu {
                MenuStatusRow(
                    title: store.triggerActivityLine,
                    systemImage: "waveform.path",
                    prominent: false
                )
            }

            Button {
                store.runDoctor()
            } label: {
                Label("Run Doctor", systemImage: "stethoscope")
            }
            .disabled(!store.canRunDoctor)

            Button {
                store.runRepair()
            } label: {
                Label("Run Repair", systemImage: "bandage")
            }
            .disabled(!store.canRunHelperRepair)
        } header: {
            Text("Diagnostics")
        }
    }

    // MARK: - More

    @ViewBuilder
    private var moreSection: some View {
        Section {
            Toggle(isOn: $showMenuBarCountdown) {
                Label("Show Countdown in Menu Bar", systemImage: "timer")
            }

            Toggle(isOn: Binding(
                get: { store.launchAtLoginEnabled },
                set: { store.setLaunchAtLogin($0) }
            )) {
                Label("Launch at Login", systemImage: "power")
            }

            CheckForUpdatesView(updateController: updateController)

            Button {
                FeedbackWindowPresenter.show(store: store)
            } label: {
                Label("Send Feedback", systemImage: "envelope")
            }

            Button {
                AboutPanelPresenter.show(store: store)
            } label: {
                Label("About dsmn", systemImage: "info.circle")
            }

            Button {
                Task {
                    await store.refresh()
                }
            } label: {
                Label("Refresh Status", systemImage: "arrow.clockwise")
            }
            .keyboardShortcut("r")

            Divider()

            Button {
                quit()
            } label: {
                Label("Quit", systemImage: "power")
            }
            .keyboardShortcut("q")
        } header: {
            Text("More")
        }
    }

    // MARK: - Helpers

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

    private func requestCustomDuration() {
        NSApplication.shared.activate(ignoringOtherApps: true)

        let input = NSTextField(string: "45")
        input.frame = NSRect(x: 0, y: 0, width: 160, height: 24)
        input.alignment = .right
        input.placeholderString = "Minutes"

        let alert = NSAlert()
        alert.messageText = "Keep Awake"
        alert.informativeText = "Enter a duration between 1 and 720 minutes."
        alert.accessoryView = input
        alert.addButton(withTitle: "Start Timer")
        alert.addButton(withTitle: "Cancel")
        alert.window.level = .floating

        guard alert.runModal() == .alertFirstButtonReturn else {
            return
        }

        let minutes = Int(input.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)) ?? 0
        guard (1...720).contains(minutes) else {
            return
        }

        store.keepAwake(minutes: minutes)
    }

    private func menuErrorText(_ message: String) -> some View {
        Label {
            Text(message)
                .fixedSize(horizontal: false, vertical: true)
        } icon: {
            Image(systemName: "xmark.octagon.fill")
        }
        .foregroundStyle(.red)
        .font(.footnote)
    }
}

// MARK: - Menu status row

private struct MenuStatusRow: View {
    let title: String
    let systemImage: String
    let prominent: Bool

    var body: some View {
        Label {
            Text(title)
                .font(prominent ? .body.weight(.semibold) : .footnote)
                .foregroundStyle(prominent ? .primary : .secondary)
                .fixedSize(horizontal: false, vertical: true)
        } icon: {
            Image(systemName: systemImage)
                .symbolRenderingMode(.hierarchical)
        }
    }
}
