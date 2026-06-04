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

        if store.prefersExpandedSetup {
            setupExpandedSection
        } else {
            setupTroubleshootingMenu
        }

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
    private var setupExpandedSection: some View {
        Section {
            setupActionItems
        } header: {
            Text("Setup")
        }
    }

    @ViewBuilder
    private var setupTroubleshootingMenu: some View {
        Menu {
            setupStatusItems
            Divider()
            setupActionItems
        } label: {
            Label("Setup & Troubleshooting", systemImage: "wrench.and.screwdriver")
        }
    }

    @ViewBuilder
    private var setupStatusItems: some View {
        MenuStatusRow(
            title: store.helperStatusLine,
            systemImage: store.helperIsReady ? "checkmark.shield.fill" : "shield.slash",
            prominent: false
        )

        MenuStatusRow(
            title: "Hooks: \(store.hooksSummary)",
            systemImage: store.hooksStatusIconName,
            prominent: false
        )
    }

    @ViewBuilder
    private var setupActionItems: some View {
        if let setupLine = store.setupLine {
            MenuStatusRow(title: setupLine, systemImage: "exclamationmark.circle", prominent: false)
        }

        if store.canInstallHelper {
            Button {
                store.installHelper()
            } label: {
                Label("Install Helper", systemImage: "arrow.down.app")
            }
        }

        if store.canUpdateHelper {
            Button {
                store.updateHelper()
            } label: {
                Label(store.helperUpdateButtonTitle, systemImage: "arrow.triangle.2.circlepath")
            }
        }

        if store.helperNeedsApproval {
            Button {
                store.openHelperSettings()
            } label: {
                Label("Approve Helper in Login Items", systemImage: "person.crop.circle.badge.checkmark")
            }
        }

        if store.loginItemNeedsApproval {
            Button {
                store.openLoginItemsSettings()
            } label: {
                Label("Approve Launch at Login", systemImage: "power")
            }
        }

        Button {
            store.installAgentHooks()
        } label: {
            Label(store.hooksActionTitle, systemImage: "link")
        }
        .disabled(store.hooksAreBusy)

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
        .help(store.repairUnavailableExplanation ?? "Clear stale state and release the macOS sleep lock.")

        if store.canUnregisterHelper {
            Button {
                store.unregisterHelper()
            } label: {
                Label("Unregister Helper", systemImage: "trash")
            }
        }

        Button {
            OnboardingWindowPresenter.show(store: store)
        } label: {
            Label("Setup Guide", systemImage: "book")
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

            Menu {
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
            } label: {
                Label("Diagnostics", systemImage: "waveform.path.ecg")
            }

            Button {
                FeedbackWindowPresenter.show(store: store)
            } label: {
                Label("Send Feedback", systemImage: "envelope")
            }

            Button {
                AboutPanelPresenter.show()
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
