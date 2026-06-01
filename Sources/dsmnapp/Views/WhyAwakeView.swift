import DSMNCore
import SwiftUI

struct WhyAwakeView: View {
    @ObservedObject var store: DSMNMenuStore
    @Environment(\.dismiss) private var dismiss

    @State private var diagnostics: SleepDiagnosticsReport?
    @State private var errorMessage: String?
    @State private var isRefreshing = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    dsmnSection
                    systemSection
                    blockersSection(title: "System Sleep Blockers", blockers: systemSleepBlockers)
                    blockersSection(title: "Display Sleep Blockers", blockers: displaySleepBlockers)
                    blockersSection(title: "Other Assertions", blockers: otherBlockers)
                }
                .padding(20)
            }

            Divider()

            footer
        }
        .frame(width: 580, height: 560)
        .task {
            await refreshAll()
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            Image(systemName: store.menuBarSystemImage)
                .font(.system(size: 22, weight: .semibold))

            VStack(alignment: .leading, spacing: 2) {
                Text("Why Awake?")
                    .font(.title3.weight(.semibold))

                Text(statusSummary)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()
        }
        .padding(20)
    }

    private var dsmnSection: some View {
        DiagnosticSection(title: "dsmn") {
            DiagnosticRow(label: "State", value: store.statusLine)
            DiagnosticRow(label: "Power lock", value: store.report?.state.ownsSleepDisable == true ? "on" : "off")

            if let remaining = store.report?.manualRemainingSeconds, remaining > 0 {
                DiagnosticRow(label: "Timer", value: formatDuration(remaining))
            } else {
                DiagnosticRow(label: "Timer", value: "off")
            }

            DiagnosticRow(label: "Last request", value: store.report?.state.lastRequester?.displayText ?? "none")
        }
    }

    private var systemSection: some View {
        DiagnosticSection(title: "macOS") {
            DiagnosticRow(label: "SleepDisabled", value: formatFlag(diagnostics?.sleepDisabled))

            if let sleepLine = diagnostics?.sleepLine {
                DiagnosticRow(label: "Sleep", value: sleepLine)
            }

            if let displaySleepLine = diagnostics?.displaySleepLine {
                DiagnosticRow(label: "Display", value: displaySleepLine)
            }

            if let diagnostics {
                DiagnosticRow(
                    label: "Idle system sleep",
                    value: diagnostics.assertionStatuses["PreventUserIdleSystemSleep"] == true ? "blocked" : "not blocked"
                )
            }
        }
    }

    private func blockersSection(title: String, blockers: [SleepBlocker]) -> some View {
        DiagnosticSection(title: title) {
            if blockers.isEmpty {
                Text("None")
                    .foregroundStyle(.secondary)
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(blockers) { blocker in
                        VStack(alignment: .leading, spacing: 2) {
                            HStack(alignment: .firstTextBaseline) {
                                Text(blocker.processName)
                                    .font(.body.weight(.medium))

                                Text("pid \(blocker.pid)")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)

                                Spacer()

                                Text(blocker.duration)
                                    .font(.caption.monospacedDigit())
                                    .foregroundStyle(.secondary)
                            }

                            Text("\(blocker.assertionType): \(blocker.assertionName)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(2)
                        }
                    }
                }
            }
        }
    }

    private var footer: some View {
        HStack {
            if let errorMessage {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .lineLimit(1)
            } else if let diagnostics {
                Text("Updated \(diagnostics.generatedAt.formatted(date: .omitted, time: .standard))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button("Refresh") {
                Task {
                    await refreshAll()
                }
            }
            .disabled(isRefreshing)

            Button("Stop dsmn") {
                Task {
                    await store.stopNow()
                    await refreshAll()
                }
            }
            .disabled(!store.isProtectingSleep || isRefreshing)

            Button("Done") {
                dismiss()
            }
            .keyboardShortcut(.defaultAction)
        }
        .padding(20)
    }

    private var statusSummary: String {
        if store.isProtectingSleep {
            return "dsmn is currently keeping the Mac awake."
        }

        if systemSleepBlockers.isEmpty {
            return "No system sleep blockers detected."
        }

        return "macOS has external sleep blockers."
    }

    private var systemSleepBlockers: [SleepBlocker] {
        diagnostics?.blockers.filter { $0.scope == .systemSleep } ?? []
    }

    private var displaySleepBlockers: [SleepBlocker] {
        diagnostics?.blockers.filter { $0.scope == .displaySleep } ?? []
    }

    private var otherBlockers: [SleepBlocker] {
        diagnostics?.blockers.filter { $0.scope == .other } ?? []
    }

    private func refreshAll() async {
        isRefreshing = true
        defer {
            isRefreshing = false
        }

        await store.refresh()

        do {
            diagnostics = try await Task.detached {
                try SleepDiagnosticsInspector().report()
            }.value
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func formatFlag(_ value: Bool?) -> String {
        guard let value else {
            return "unknown"
        }

        return value ? "on" : "off"
    }

    private func formatDuration(_ seconds: Int) -> String {
        let minutes = max(0, seconds / 60)
        if minutes < 60 {
            return "\(minutes)m remaining"
        }

        let hours = minutes / 60
        let leftoverMinutes = minutes % 60
        return leftoverMinutes == 0 ? "\(hours)h remaining" : "\(hours)h \(leftoverMinutes)m remaining"
    }
}

private struct DiagnosticSection<Content: View>: View {
    var title: String
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.headline)

            VStack(alignment: .leading, spacing: 6) {
                content
            }
        }
    }
}

private struct DiagnosticRow: View {
    var label: String
    var value: String

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(label)
                .foregroundStyle(.secondary)
                .frame(width: 110, alignment: .leading)

            Text(value)
                .textSelection(.enabled)
                .lineLimit(3)

            Spacer(minLength: 0)
        }
    }
}
