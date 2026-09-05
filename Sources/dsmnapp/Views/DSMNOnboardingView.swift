import AppKit
import DSMNCore
import SwiftUI

struct DSMNOnboardingView: View {
    @ObservedObject var store: DSMNMenuStore
    @Environment(\.dsmnRefreshOnAppear) private var refreshOnAppear
    var onSkip: () -> Void
    var onDone: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(spacing: 0) {
                    header

                    VStack(spacing: 0) {
                        DSMNSettingsRow(
                            systemImage: store.helperIsReady ? "checkmark.circle.fill" : "lock.shield",
                            title: "Install the helper",
                            detail: helperDetail,
                            status: store.helperStatusDisplayName,
                            isComplete: store.helperIsReady
                        ) {
                            helperAction
                        }

                        DSMNSettingsRow(
                            systemImage: store.hooksStatusIconName,
                            title: "Connect your agents",
                            detail: "Install bounded hooks for \(AgentHookTarget.joinedDisplayNames()).",
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
                            OnboardingHookActionResultList(rows: store.hookActionResultRows)
                        }

                        DSMNSettingsRow(
                            systemImage: store.launchAtLoginEnabled ? "checkmark.circle.fill" : "power",
                            title: "Launch with your Mac",
                            detail: "Optional. Starts the menu bar app automatically when you log in.",
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

                        DSMNSettingsRow(
                            systemImage: "stethoscope",
                            title: "Troubleshooting",
                            detail: troubleshootingDetail,
                            status: troubleshootingStatus,
                            isComplete: store.helperIsReady,
                            isOptional: true
                        ) {
                            HStack(spacing: 8) {
                                Button("Doctor") {
                                    store.runDoctor()
                                }
                                .disabled(!store.canRunDoctor)

                                Button("Repair") {
                                    store.runRepair()
                                }
                                .disabled(!store.canRunHelperRepair)
                                .help(store.repairUnavailableExplanation ?? "Repair helper state and release stuck sleep locks.")
                            }
                        }
                    }
                    .padding(.top, 24)

                    if let errorMessage = store.errorMessage {
                        Text(errorMessage)
                            .font(.footnote)
                            .foregroundStyle(.red)
                            .fixedSize(horizontal: false, vertical: true)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.top, 12)
                    }
                }
                .padding(.horizontal, 32)
                .padding(.top, 34)
                .padding(.bottom, 18)
            }

            footer
                .padding(.horizontal, 32)
                .padding(.vertical, 16)
                .background(DSMNBrand.paper)
        }
        .frame(width: 720, height: 720, alignment: .top)
        .dsmnWindowStyle()
        .task {
            if refreshOnAppear { await store.refresh() }
        }
    }

    private var header: some View {
        DSMNPageHeader(
            eyebrow: "01 / GETTING STARTED",
            title: "Set it up. Then step away.",
            detail: "Keep your Mac awake while your local AI agents work. Even with the lid closed."
        )
    }

    @ViewBuilder
    private var helperAction: some View {
        if store.helperIsReady {
            Label("Ready", systemImage: "checkmark").foregroundStyle(DSMNBrand.sage)
        } else if store.helperNeedsRepair {
            Button("Repair Helper") {
                store.updateHelper()
            }
        } else if store.helperNeedsUpdate {
            VStack(alignment: .trailing, spacing: 6) {
                Button(store.helperUpdateActionTitle) {
                    store.updateHelper()
                }

                if let retryMessage = store.helperUpdateRetryMessage {
                    Text(retryMessage)
                        .font(.caption)
                        .foregroundStyle(DSMNBrand.orange)
                        .multilineTextAlignment(.trailing)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: 190, alignment: .trailing)
                }
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

    private var troubleshootingDetail: String {
        if let repairUnavailableExplanation = store.repairUnavailableExplanation {
            return "Run Doctor to inspect helper source, power lock, SleepDisabled, and agents. Repair needs the helper: \(repairUnavailableExplanation)"
        }

        return "Run Doctor to inspect helper source, power lock, SleepDisabled, and agents. Repair clears stale state via the helper."
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

    private var footer: some View {
        HStack {
            Button("Refresh") {
                Task {
                    await store.refresh()
                }
            }
            .disabled(store.isRefreshing)

            Spacer()

            Button("Skip for Now") {
                onSkip()
            }
            .help("Close the guide. Setup stays visible in the menu until helper and hooks are ready.")

            Button(store.setupIsComplete ? "Done" : "Finish Later") {
                onDone()
            }
            .buttonStyle(DSMNActionStyle(prominent: true))
            .keyboardShortcut(.defaultAction)
        }
    }
}

private struct OnboardingHookActionResultList: View {
    var rows: [AgentHookActionResultRow]

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
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
        .padding(.horizontal, 18)
        .padding(.vertical, 10)
        .background(DSMNBrand.field)
        .overlay {
            RoundedRectangle(cornerRadius: 12)
                .stroke(.quaternary, lineWidth: 1)
        }
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
            AnyShapeStyle(DSMNBrand.sage)
        case .unchanged:
            AnyShapeStyle(DSMNBrand.sage)
        case .failed:
            AnyShapeStyle(.red)
        }
    }
}
