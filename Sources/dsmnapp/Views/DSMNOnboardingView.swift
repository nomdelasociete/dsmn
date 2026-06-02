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
                    status: store.helperStatus.displayName,
                    isComplete: store.helperIsReady
                ) {
                    helperAction
                }

                OnboardingStepRow(
                    systemImage: "terminal",
                    title: "Connect your agents",
                    detail: "Install bounded hooks for Claude Code, Codex, Grok Build, and Pi.",
                    status: store.hooksSummary,
                    isComplete: store.hookInstallSummary?.contains("installed") == true
                        || store.hookInstallSummary?.contains("Installed") == true
                ) {
                    Button("Install Hooks") {
                        store.installAgentHooks()
                    }
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
            .padding(.horizontal, 28)
            .padding(.top, 22)

            if let errorMessage = store.errorMessage {
                Text(errorMessage)
                    .font(.footnote)
                    .foregroundStyle(.red)
                    .lineLimit(2)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 30)
                    .padding(.top, 12)
            }

            Spacer(minLength: 18)

            footer
        }
        .frame(width: 720, height: 600)
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
                    .frame(width: 96, height: 96)
                    .shadow(color: .black.opacity(0.18), radius: 22, y: 10)

                Image(nsImage: NSApplication.shared.applicationIconImage)
                    .resizable()
                    .interpolation(.high)
                    .frame(width: 76, height: 76)
            }

            VStack(spacing: 7) {
                Text("Don't Stop Me Now!")
                    .font(.system(size: 34, weight: .semibold, design: .rounded))

                Text("Keep Claude, Codex, Grok, and Pi working while your Mac is closed or moving with you.")
                    .font(.system(size: 15))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .frame(maxWidth: 540)
            }
        }
        .padding(.top, 38)
        .padding(.horizontal, 28)
    }

    @ViewBuilder
    private var helperAction: some View {
        if store.helperIsReady {
            Button("Ready") {}
                .disabled(true)
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
        switch store.helperStatus {
        case .enabled:
            "The privileged helper can apply the macOS sleep lock when needed."
        case .requiresApproval:
            "macOS needs approval in Login Items before the helper can run."
        case .notRegistered, .notFound:
            "Required for closed-lid protection. dsmn asks macOS to register it."
        }
    }

    private var footer: some View {
        HStack {
            Button("Refresh") {
                Task {
                    await store.refresh()
                }
            }

            Spacer()

            Button("Skip for Now") {
                onClose(false)
            }

            Button("Done") {
                onClose(true)
            }
            .keyboardShortcut(.defaultAction)
        }
        .padding(.horizontal, 28)
        .padding(.vertical, 22)
        .background(.regularMaterial)
    }
}

private struct OnboardingStepRow<Actions: View>: View {
    var systemImage: String
    var title: String
    var detail: String
    var status: String
    var isComplete: Bool
    var isOptional = false
    @ViewBuilder var actions: Actions

    var body: some View {
        HStack(alignment: .center, spacing: 16) {
            Image(systemName: systemImage)
                .font(.system(size: 22, weight: .semibold))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(isComplete ? .green : .primary)
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
                .frame(minWidth: 120, alignment: .trailing)
        }
        .padding(16)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 14))
        .overlay {
            RoundedRectangle(cornerRadius: 14)
                .stroke(.quaternary, lineWidth: 1)
        }
    }
}
