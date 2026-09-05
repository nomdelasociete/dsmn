import AppKit
import DSMNCore
import SwiftUI

struct DSMNMenuView: View {
    @ObservedObject var store: DSMNMenuStore
    var updateController: SoftwareUpdateController?
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Section {
                HStack {
                    DSMNWordmark(size: 24)
                    Spacer()
                    Button {
                        Task { await store.refresh() }
                    } label: {
                        Image(systemName: "arrow.clockwise").frame(width: 28, height: 28)
                    }
                    .keyboardShortcut("r")
                    .help("Refresh status (⌘R)")
                    .accessibilityLabel("Refresh Status")
                    .disabled(store.isRefreshing)
                }
                .foregroundStyle(DSMNBrand.panelMuted)
                .padding(.bottom, 20)

                Label(store.menuPanelTitle, systemImage: store.menuStatusSystemImage)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(store.menuBarIconState == .warning ? Color(hex: 0xF49B7E) : DSMNBrand.panelGreen)
                    .accessibilityIdentifier("panel.status")

                TimelineView(.periodic(from: .now, by: 1)) { context in
                    Text(store.menuPanelCountdown(at: context.date))
                        .font(.system(size: 48, weight: .regular, design: .monospaced))
                        .monospacedDigit()
                        .tracking(-2)
                        .accessibilityLabel("Time remaining")
                        .accessibilityValue(store.menuPanelCountdown(at: context.date))
                }
                .padding(.top, 8)
                .accessibilityIdentifier("panel.countdown")

                Text(store.lastRequesterLine ?? "Start a timer, or let your agents take over.")
                    .font(.system(size: 12))
                    .foregroundStyle(DSMNBrand.panelMuted)
                    .lineLimit(2)
                    .help(store.lastRequesterLine ?? "")
                    .padding(.top, 2)

                if let detail = store.menuStatusSubtitle {
                    Text(detail)
                        .font(.system(size: 11))
                        .foregroundStyle(DSMNBrand.panelMuted)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, 8)
                }

                if store.showsActivityMenu {
                    HStack(spacing: 12) {
                        Text("Activity · \(store.triggerActivitySummary.hours)h")
                            .font(.system(size: 10))
                            .foregroundStyle(DSMNBrand.panelMuted)
                        Canvas { context, size in
                            let buckets = store.triggerActivitySummary.buckets
                            let peak = max(1, buckets.max() ?? 0)
                            let step = size.width / CGFloat(max(1, buckets.count))
                            for (index, count) in buckets.enumerated() {
                                let height = max(1, size.height * CGFloat(count) / CGFloat(peak))
                                context.fill(Path(CGRect(x: CGFloat(index) * step, y: size.height - height,
                                                         width: max(1, step - 2), height: height)),
                                             with: .color(DSMNBrand.panelGreen))
                            }
                        }
                        .frame(height: 16)
                        .accessibilityLabel("\(store.triggerActivitySummary.total) triggers in the last \(store.triggerActivitySummary.hours) hours")
                    }
                    .padding(.top, 12)
                }

                if let warning = store.errorMessage ?? store.menuSetupIncompleteStatusTitle {
                    Label(warning, systemImage: "exclamationmark.circle")
                        .font(.system(size: 12))
                        .foregroundStyle(Color(hex: 0xF49B7E))
                        .lineLimit(4)
                        .help(warning)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, 10)
                }
            }

            Section {
                HStack(spacing: 0) {
                    Button("30 min") { store.keepAwake(minutes: 30) }
                        .keyboardShortcut("3")
                        .accessibilityLabel("Keep Awake for 30 Minutes")
                    Rectangle().fill(DSMNBrand.panelRule).frame(width: 1)
                    Button("90 min") { store.keepAwake(minutes: 90) }
                        .keyboardShortcut("9")
                        .accessibilityLabel("Keep Awake for 90 Minutes")
                    Rectangle().fill(DSMNBrand.panelRule).frame(width: 1)
                    Button("Custom…") { requestCustomDuration() }
                        .accessibilityLabel("Custom Duration")
                }
                .buttonStyle(PanelDurationStyle())
                .disabled(!store.canRunAwakeCommands)
                .frame(height: 38)
                .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(DSMNBrand.panelRule))
                .padding(.top, 24)

                Button { store.stop() } label: {
                    Label("Stop keeping awake", systemImage: "stop.fill")
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 11)
                        .background(Color(hex: 0x44483F), in: RoundedRectangle(cornerRadius: 6))
                        .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Color(hex: 0x62665C)))
                }
                .keyboardShortcut(".")
                .accessibilityIdentifier("panel.stop")
                .padding(.top, 12)

                Text("Sleep allowed when the timer expires.\nAgent activity can extend it.")
                    .font(.system(size: 11))
                    .foregroundStyle(DSMNBrand.panelMuted)
                    .lineSpacing(3)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 10)
            }

            Section {
                Rectangle().fill(DSMNBrand.panelRule).frame(height: 1)
                    .padding(.top, 18)

                Button {
                    SetupTroubleshootingWindowPresenter.show(store: store, updateController: updateController)
                } label: {
                    HStack {
                        Text("Setup & Troubleshooting...")
                        Spacer()
                        Image(systemName: "arrow.up.right").font(.system(size: 11))
                    }
                    .frame(maxWidth: .infinity, minHeight: 42, alignment: .leading)
                    .contentShape(Rectangle())
                }
                .accessibilityIdentifier("panel.setup")
            }

            Section {
                HStack {
                    Button("Why Awake?") {
                        NSApplication.shared.activate(ignoringOtherApps: true)
                        openWindow(id: "why-awake")
                    }
                    Spacer()
                    Button("About") { AboutPanelPresenter.show(store: store) }
                    Button("Quit") { quit() }
                        .keyboardShortcut("q")
                        .padding(.leading, 12)
                }
                .foregroundStyle(DSMNBrand.panelMuted)
                .font(.system(size: 11))
            }
        }
        .font(.system(size: 13))
        .buttonStyle(PanelActionStyle())
        .padding(20)
        .frame(width: 340)
        .foregroundStyle(DSMNBrand.panelInk)
        .background(DSMNBrand.panel)
        .environment(\.colorScheme, .dark)
    }

    // MARK: - Helpers

    private func quit() {
        guard store.isProtectingSleep || store.hasUnconfirmedStop else {
            NSApplication.shared.terminate(nil)
            return
        }

        let alert = NSAlert()
        alert.messageText = "Quit dsmn?"
        let activityDescription = store.hasUnconfirmedStop
            ? "dsmn could not confirm that the helper stopped."
            : "dsmn is currently keeping the Mac awake."
        alert.informativeText = """
        \(activityDescription) Quitting only closes the menu bar app; the helper and agent hooks can keep running.

        Stop & Quit releases the current dsmn timer first. Active \(AgentHookTarget.joinedDisplayNames(short: true, conjunction: "or")) hooks can start a new timer again later.
        """
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Stop & Quit")
        alert.addButton(withTitle: "Quit, Keep Running")
        alert.addButton(withTitle: "Cancel")

        switch alert.runModal() {
        case .alertFirstButtonReturn:
            requestQuit(.stopAndQuit)
        case .alertSecondButtonReturn:
            requestQuit(.keepRunning)
        default:
            break
        }
    }

    private func requestQuit(_ choice: AppQuitChoice) {
        Task {
            await store.quitCoordinator.request(
                choice,
                stop: { await store.stopNow() },
                terminate: { NSApplication.shared.terminate(nil) },
                presentFailure: { message in
                    let alert = NSAlert()
                    alert.messageText = "Stop was not confirmed"
                    alert.informativeText = "\(message)\n\ndsmn is still open. You can retry Stop & Quit, or choose Quit, Keep Running."
                    alert.alertStyle = .warning
                    alert.addButton(withTitle: "OK")
                    NSApplication.shared.activate(ignoringOtherApps: true)
                    alert.runModal()
                }
            )
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

}

private struct PanelDurationStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.isFocused) private var isFocused
    @State private var isHovered = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12))
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(configuration.isPressed || isHovered ? Color(hex: 0x484D40) : .clear)
            .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(DSMNBrand.panelGreen, lineWidth: isFocused ? 2 : 0))
            .contentShape(Rectangle())
            .opacity(isEnabled ? 1 : 0.4)
            .onHover { isHovered = $0 }
    }
}

private struct PanelActionStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.isFocused) private var isFocused
    @State private var isHovered = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(isHovered && isEnabled ? Color.white.opacity(0.06) : .clear, in: RoundedRectangle(cornerRadius: 4))
            .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(DSMNBrand.panelGreen, lineWidth: isFocused ? 2 : 0))
            .opacity(isEnabled ? (configuration.isPressed ? 0.65 : 1) : 0.4)
            .onHover { isHovered = $0 }
    }
}
