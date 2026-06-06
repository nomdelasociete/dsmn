import AppKit
import DSMNCore
import SwiftUI

struct DSMNSetupTroubleshootingView: View {
    @ObservedObject var store: DSMNMenuStore
    var onClose: () -> Void
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    header

                    if store.helperNeedsUpdate {
                        helperUpdateBanner
                    }

                    SetupPanelRow(
                        systemImage: store.helperIsReady ? "checkmark.shield.fill" : "lock.shield",
                        title: "Helper",
                        detail: helperDetail,
                        status: store.helperStatusDisplayName,
                        isComplete: store.helperIsReady
                    ) {
                        helperActions
                    }

                    SetupPanelRow(
                        systemImage: store.hooksStatusIconName,
                        title: "Agent hooks",
                        detail: "Bounded hooks connect Claude Code, Codex, Grok Build, and Pi to the dsmn timer.",
                        status: store.hooksSummary,
                        isComplete: store.hooksAreReady,
                        isBusy: store.hooksAreBusy
                    ) {
                        Button(store.hooksActionTitle) {
                            store.installAgentHooks()
                        }
                        .disabled(store.hooksAreBusy)
                    }

                    if !store.hookActionResultRows.isEmpty {
                        HookActionResultList(rows: store.hookActionResultRows)
                    }

                    SetupPanelRow(
                        systemImage: store.launchAtLoginEnabled ? "checkmark.circle.fill" : "power",
                        title: "Launch with your Mac",
                        detail: "Optional. Start dsmn automatically when you log in.",
                        status: store.launchAtLoginStatus.displayName,
                        isComplete: store.launchAtLoginEnabled,
                        isOptional: true
                    ) {
                        Toggle("Launch at Login", isOn: Binding(
                            get: { store.launchAtLoginEnabled },
                            set: { store.setLaunchAtLogin($0) }
                        ))
                        .toggleStyle(.switch)
                    }

                    SetupPanelRow(
                        systemImage: "stethoscope",
                        title: "Troubleshooting",
                        detail: troubleshootingDetail,
                        status: troubleshootingStatus,
                        isComplete: false,
                        isOptional: true
                    ) {
                        VStack(alignment: .trailing, spacing: 8) {
                            Button("Why Awake?") {
                                NSApplication.shared.activate(ignoringOtherApps: true)
                                openWindow(id: "why-awake")
                            }

                            HStack(spacing: 8) {
                                Button("Doctor") {
                                    store.runDoctor()
                                }
                                .disabled(!store.canRunDoctor)

                                Button("Repair") {
                                    store.runRepair()
                                }
                                .disabled(!store.canRunHelperRepair)
                                .help(store.repairUnavailableExplanation ?? "Clear stale state and release the macOS sleep lock.")
                            }
                        }
                    }

                    if let errorMessage = store.errorMessage {
                        Label {
                            Text(errorMessage)
                                .fixedSize(horizontal: false, vertical: true)
                        } icon: {
                            Image(systemName: "xmark.octagon.fill")
                        }
                        .font(.footnote)
                        .foregroundStyle(.red)
                        .padding(.top, 2)
                    }
                }
                .padding(.horizontal, 28)
                .padding(.top, 28)
                .padding(.bottom, 18)
            }

            Divider()

            footer
                .padding(.horizontal, 28)
                .padding(.vertical, 16)
                .background(.regularMaterial)
        }
        .frame(minWidth: 640, idealWidth: 700, minHeight: 540, idealHeight: 640)
        .task {
            await store.refresh()
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 12) {
                Image(nsImage: NSApplication.shared.applicationIconImage)
                    .resizable()
                    .interpolation(.high)
                    .frame(width: 38, height: 38)

                VStack(alignment: .leading, spacing: 3) {
                    Text("Setup & Troubleshooting")
                        .font(.title2.weight(.semibold))

                    Text(statusSummary)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }

            if let setupLine = store.setupLine {
                Label(setupLine, systemImage: store.setupLineSystemImage)
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.bottom, 4)
    }

    @ViewBuilder
    private var helperActions: some View {
        if store.helperIsReady {
            Button("Ready") {}
                .disabled(true)
        } else if store.helperNeedsRepair {
            Button("Repair Helper") {
                store.updateHelper()
            }
        } else if store.helperNeedsUpdate {
            Button(store.helperUpdateActionTitle) {
                store.updateHelper()
            }
        } else if store.helperNeedsApproval {
            Button("Open Login Items") {
                store.openHelperSettings()
            }
        } else {
            Button("Install Helper") {
                store.installHelper()
            }
        }
    }

    @ViewBuilder
    private var helperUpdateActions: some View {
        HStack(spacing: 8) {
            Button("Later") {
                store.deferHelperUpdateReminder()
                onClose()
            }
            .accessibilityIdentifier("setup.helper-update-later")

            Button(store.helperUpdateActionTitle) {
                store.updateHelper()
            }
            .accessibilityIdentifier("setup.helper-update-now")
        }
    }

    private var footer: some View {
        HStack(spacing: 10) {
            Button("Refresh") {
                Task {
                    await store.refresh()
                }
            }
            .disabled(store.isRefreshing)
            .accessibilityLabel("Refresh")
            .accessibilityIdentifier("setup.refresh")

            Button("Setup Guide") {
                OnboardingWindowPresenter.show(store: store)
            }
            .accessibilityLabel("Setup Guide")
            .accessibilityIdentifier("setup.guide")

            if store.canUnregisterHelper {
                Button("Unregister Helper") {
                    store.unregisterHelper()
                }
                .accessibilityLabel("Unregister Helper")
                .accessibilityIdentifier("setup.unregister-helper")
            }

            if store.canSuppressSetupReminders {
                Button("Hide Reminders") {
                    store.suppressSetupReminders()
                }
                .accessibilityLabel("Hide Reminders")
                .accessibilityIdentifier("setup.hide-reminders")
            }

            Spacer()

            Button("Done") {
                onClose()
            }
            .keyboardShortcut(.defaultAction)
            .accessibilityLabel("Done")
            .accessibilityIdentifier("setup.done")
        }
    }

    private var statusSummary: String {
        if store.helperNeedsUpdate {
            return "The app was updated. Refreshing the helper is recommended, but not blocking."
        }

        if store.setupIsComplete {
            return "Helper and agent hooks are ready."
        }

        return "Review helper, hooks, launch at login, and diagnostics in one place."
    }

    private var helperDetail: String {
        if store.helperNeedsRepair {
            return "The helper is registered but not responding. Repair it so hooks and closed-lid protection use the current version."
        }

        if store.helperNeedsUpdate {
            return store.helperUpdateDetail
        }

        switch store.helperStatus {
        case .enabled:
            return "The privileged helper can apply the macOS sleep lock when needed."
        case .requiresApproval:
            return "macOS needs approval in Login Items before the helper can run."
        case .notRegistered, .notFound:
            return "Required for closed-lid protection. dsmn asks macOS to register it."
        }
    }

    private var troubleshootingDetail: String {
        if let repairUnavailableExplanation = store.repairUnavailableExplanation {
            return "Doctor inspects helper source, power lock, SleepDisabled, and agents. Repair needs the helper: \(repairUnavailableExplanation)"
        }

        return "Doctor inspects helper source, power lock, SleepDisabled, and agents. Repair clears stale state via the helper."
    }

    private var troubleshootingStatus: String {
        if store.helperIsReady {
            return "Doctor and repair available"
        }

        if store.canRunDoctor {
            return "Doctor available; repair needs helper"
        }

        return "Unavailable until dsmn finishes loading"
    }

    private var helperUpdateBanner: some View {
        HStack(alignment: .center, spacing: 14) {
            Image(systemName: "arrow.triangle.2.circlepath.circle.fill")
                .font(.system(size: 28, weight: .semibold))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(.blue)
                .frame(width: 36, height: 36)

            VStack(alignment: .leading, spacing: 5) {
                Text("Helper update available")
                    .font(.system(size: 15, weight: .semibold))

                Text(store.helperUpdateDetail)
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                if let retryMessage = store.helperUpdateRetryMessage {
                    Label {
                        Text(retryMessage)
                            .fixedSize(horizontal: false, vertical: true)
                    } icon: {
                        Image(systemName: "arrow.clockwise.circle.fill")
                    }
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.orange)
                    .padding(.top, 2)
                }
            }

            Spacer(minLength: 16)

            helperUpdateActions
        }
        .padding(14)
        .background(.blue.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
        .overlay {
            RoundedRectangle(cornerRadius: 12)
                .stroke(.blue.opacity(0.22), lineWidth: 1)
        }
    }
}

private struct SetupPanelRow<Actions: View>: View {
    var systemImage: String
    var title: String
    var detail: String
    var status: String
    var isComplete: Bool
    var isBusy = false
    var isOptional = false
    @ViewBuilder var actions: Actions

    var body: some View {
        HStack(alignment: .center, spacing: 14) {
            Group {
                if isBusy {
                    ProgressView()
                        .controlSize(.small)
                } else {
                    Image(systemName: systemImage)
                        .font(.system(size: 20, weight: .semibold))
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(isComplete ? .green : .primary)
                }
            }
            .frame(width: 32, height: 32)

            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 8) {
                    Text(title)
                        .font(.system(size: 15, weight: .semibold))

                    if isOptional {
                        Text("Optional")
                            .font(.caption.weight(.medium))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 2)
                            .background(.secondary.opacity(0.12), in: Capsule())
                    }
                }

                Text(detail)
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                Text(status)
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(isComplete ? .green : .secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 14)

            actions
                .controlSize(.regular)
                .frame(minWidth: 138, alignment: .trailing)
        }
        .padding(14)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 12))
        .overlay {
            RoundedRectangle(cornerRadius: 12)
                .stroke(.quaternary, lineWidth: 1)
        }
    }
}

private struct HookActionResultList: View {
    var rows: [AgentHookActionResultRow]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(rows) { row in
                HStack(spacing: 8) {
                    Image(systemName: systemImage(for: row.state))
                        .font(.system(size: 12, weight: .semibold))
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(foregroundStyle(for: row.state))
                        .frame(width: 16, height: 16)

                    Text(row.targetDisplayName)
                        .font(.caption.weight(.semibold))

                    Text(row.message)
                        .font(.caption)
                        .foregroundStyle(row.state == .failed ? .red : .secondary)
                        .lineLimit(1)

                    Spacer(minLength: 0)
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 10))
        .overlay {
            RoundedRectangle(cornerRadius: 10)
                .stroke(.quaternary, lineWidth: 1)
        }
        .accessibilityIdentifier("setup.hook-results")
    }

    private func systemImage(for state: AgentHookActionResultState) -> String {
        switch state {
        case .updated:
            "arrow.triangle.2.circlepath.circle.fill"
        case .unchanged:
            "checkmark.circle.fill"
        case .failed:
            "exclamationmark.triangle.fill"
        }
    }

    private func foregroundStyle(for state: AgentHookActionResultState) -> AnyShapeStyle {
        switch state {
        case .updated:
            AnyShapeStyle(.blue)
        case .unchanged:
            AnyShapeStyle(.green)
        case .failed:
            AnyShapeStyle(.red)
        }
    }
}
