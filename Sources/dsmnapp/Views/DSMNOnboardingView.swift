import AppKit
import SwiftUI

struct DSMNOnboardingView: View {
    @ObservedObject var store: DSMNMenuStore
    var onClose: (Bool) -> Void

    var body: some View {
        VStack(spacing: 0) {
            header

            VStack(spacing: 14) {
                OnboardingStepRow(
                    systemImage: store.helperIsReady ? "checkmark.circle.fill" : "lock.shield",
                    title: "Install the helper",
                    detail: helperDetail,
                    status: store.helperStatusDisplayName,
                    isComplete: store.helperIsReady
                ) {
                    helperAction
                }

                OnboardingStepRow(
                    systemImage: store.hooksStatusIconName,
                    title: "Connect your agents",
                    detail: "Install bounded hooks for Claude Code, Codex, Grok Build, and Pi.",
                    status: store.hooksSummary,
                    isComplete: store.hooksAreReady,
                    isBusy: store.hooksAreBusy
                ) {
                    Button(store.hooksActionTitle) {
                        store.installAgentHooks()
                    }
                    .disabled(store.hooksAreBusy)
                }

                OnboardingStepRow(
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
            }
            .padding(.top, 24)

            if let errorMessage = store.errorMessage {
                Text(errorMessage)
                    .font(.footnote)
                    .foregroundStyle(.red)
                    .lineLimit(2)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.top, 12)
            }

            footer
                .padding(.top, 18)
        }
        .padding(.horizontal, 32)
        .padding(.top, 34)
        .padding(.bottom, 28)
        .frame(width: 720, height: 640, alignment: .top)
        .background(
            LinearGradient(
                colors: [
                    Color(nsColor: .windowBackgroundColor),
                    Color(nsColor: .controlBackgroundColor)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        )
        .task {
            await store.refresh()
        }
    }

    private var header: some View {
        VStack(spacing: 16) {
            ZStack {
                RoundedRectangle(cornerRadius: 28)
                    .fill(.ultraThinMaterial)
                    .frame(width: 88, height: 88)
                    .shadow(color: .black.opacity(0.16), radius: 20, y: 9)

                Image(nsImage: NSApplication.shared.applicationIconImage)
                    .resizable()
                    .interpolation(.high)
                    .frame(width: 70, height: 70)
            }

            VStack(spacing: 7) {
                Text("Don't Stop Me Now!")
                    .font(.system(size: 32, weight: .semibold, design: .rounded))

                Text("Keep Claude, Codex, Grok, and Pi working while your Mac is closed or moving with you.")
                    .font(.system(size: 15))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: 600)
            }
        }
    }

    @ViewBuilder
    private var helperAction: some View {
        if store.helperIsReady {
            Button("Ready") {}
                .disabled(true)
        } else if store.helperNeedsRepair {
            Button("Repair Helper") {
                store.updateHelper()
            }
        } else if store.helperNeedsUpdate {
            Button("Update Helper") {
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

    private var helperDetail: String {
        if store.helperNeedsRepair {
            return "The helper is registered but not responding. Repair it so hooks and closed-lid protection use the current version."
        }

        if store.helperNeedsUpdate {
            return "A newer dsmn is installed. Update the helper so hooks and sleep locks use the current version."
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
                onClose(false)
            }

            Button("Done") {
                onClose(true)
            }
            .keyboardShortcut(.defaultAction)
        }
    }
}

private struct OnboardingStepRow<Actions: View>: View {
    var systemImage: String
    var title: String
    var detail: String
    var status: String
    var isComplete: Bool
    var isBusy = false
    var isOptional = false
    @ViewBuilder var actions: Actions

    var body: some View {
        HStack(alignment: .center, spacing: 16) {
            Group {
                if isBusy {
                    ProgressView()
                        .controlSize(.small)
                } else {
                    Image(systemName: systemImage)
                        .font(.system(size: 22, weight: .semibold))
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(isComplete ? .green : .primary)
                }
            }
            .frame(width: 34, height: 34)

            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 8) {
                    Text(title)
                        .font(.system(size: 16, weight: .semibold))

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
            }

            Spacer(minLength: 16)

            actions
                .controlSize(.regular)
                .frame(minWidth: 132, alignment: .trailing)
        }
        .padding(16)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 14))
        .overlay {
            RoundedRectangle(cornerRadius: 14)
                .stroke(.quaternary, lineWidth: 1)
        }
    }
}
