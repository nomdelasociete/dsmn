import AppKit
import DSMNCore
import SwiftUI

struct DSMNFeedbackView: View {
    @ObservedObject var store: DSMNMenuStore
    var service = FeedbackService()
    var onClose: () -> Void

    @State private var category: FeedbackCategory = .bug
    @State private var message = ""
    @State private var email = ""
    @State private var includeDiagnostics = false
    @State private var isSubmitting = false
    @State private var didSubmit = false
    @State private var resultMessage: String?
    @State private var resultIsError = false

    private var canSubmit: Bool {
        !isSubmitting && message.trimmingCharacters(in: .whitespacesAndNewlines).count >= 5
    }

    var body: some View {
        Group {
            if didSubmit {
                successContent
            } else {
                formContent
            }
        }
        .padding(24)
        .frame(width: 580, height: 660)
        .dsmnWindowStyle()
    }

    private var formContent: some View {
        VStack(alignment: .leading, spacing: 18) {
            header

            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    Picker("Type", selection: $category) {
                        ForEach(FeedbackCategory.allCases) { category in
                            Text(category.displayName).tag(category)
                        }
                    }
                    .pickerStyle(.segmented)

                    VStack(alignment: .leading, spacing: 6) {
                        Text("Message")
                            .font(.headline)

                        TextEditor(text: $message)
                            .font(.body)
                            .scrollContentBackground(.hidden)
                            .accessibilityLabel("Message")
                            .frame(minHeight: 150)
                            .padding(8)
                            .background(DSMNBrand.field)
                            .overlay {
                                RoundedRectangle(cornerRadius: 8)
                                    .stroke(DSMNBrand.rule)
                            }
                    }

                    VStack(alignment: .leading, spacing: 6) {
                        Text("Email")
                            .font(.headline)

                        TextField("Optional", text: $email)
                            .textFieldStyle(.roundedBorder)
                    }

                    Toggle("Include diagnostics", isOn: $includeDiagnostics)

                    if includeDiagnostics {
                        Text("Includes version, helper state, power state, active agents, and last requester.")
                            .font(.footnote)
                            .foregroundStyle(DSMNBrand.muted)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }

            if let resultMessage {
                Label(resultMessage, systemImage: resultIsError ? "exclamationmark.triangle.fill" : "checkmark.circle.fill")
                    .font(.callout)
                    .foregroundStyle(resultIsError ? .orange : .green)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)

            footer
        }
    }

    private var successContent: some View {
        VStack(spacing: 18) {
            Spacer()

            ZStack {
                Circle()
                    .fill(DSMNBrand.sage.opacity(0.12))
                    .frame(width: 74, height: 74)

                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 42, weight: .semibold))
                    .foregroundStyle(DSMNBrand.sage)
            }

            VStack(spacing: 6) {
                Text("Note received.")
                    .font(DSMNBrand.display(32))

                Text("Thanks. It has been saved and the window will close automatically.")
                    .font(.callout)
                    .foregroundStyle(DSMNBrand.muted)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer()

            HStack {
                Spacer()

                Button("Done") {
                    onClose()
                }
                .buttonStyle(DSMNActionStyle(prominent: true))
                .keyboardShortcut(.defaultAction)
            }
        }
    }

    private var header: some View {
        DSMNPageHeader(
            eyebrow: "FEEDBACK",
            title: "A little note goes a long way.",
            detail: "Tell us what happened, what you expected, or what should improve."
        )
    }

    private var footer: some View {
        HStack {
            Text("\(message.count)/4000")
                .font(.caption.monospacedDigit())
                .foregroundStyle(message.count > 4000 ? .orange : .secondary)

            Spacer()

            Button("Cancel") {
                onClose()
            }
            .disabled(isSubmitting)

            Button {
                submit()
            } label: {
                if isSubmitting {
                    ProgressView()
                        .controlSize(.small)
                        .frame(width: 46)
                } else {
                    Text("Send")
                        .frame(width: 46)
                }
            }
            .buttonStyle(DSMNActionStyle(prominent: true))
            .keyboardShortcut(.defaultAction)
            .disabled(!canSubmit)
        }
    }

    private func submit() {
        guard canSubmit else {
            return
        }

        isSubmitting = true
        resultMessage = nil
        resultIsError = false

        let submission = FeedbackSubmission(
            category: category.rawValue,
            message: String(message.trimmingCharacters(in: .whitespacesAndNewlines).prefix(4000)),
            email: cleanOptional(email),
            appVersion: FeedbackService.appVersion,
            buildNumber: FeedbackService.buildNumber,
            osVersion: FeedbackService.osVersion,
            diagnostics: includeDiagnostics ? diagnostics() : [:]
        )

        Task {
            do {
                try await service.submit(submission)
                await MainActor.run {
                    isSubmitting = false
                    resultMessage = nil
                    resultIsError = false
                    didSubmit = true
                    closeAfterSuccessDelay()
                }
            } catch {
                await MainActor.run {
                    isSubmitting = false
                    resultIsError = true
                    resultMessage = error.localizedDescription
                }
            }
        }
    }

    private func closeAfterSuccessDelay() {
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(1_200))
            onClose()
        }
    }

    private func cleanOptional(_ value: String) -> String? {
        let cleaned = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return cleaned.isEmpty ? nil : cleaned
    }

    private func diagnostics() -> [String: String] {
        var values: [String: String] = [
            "status": store.statusLine,
            "helper": store.helperStatus.displayName,
            "launchAtLogin": store.launchAtLoginStatus.displayName,
            "hooks": store.hooksSummary,
            "appVersion": FeedbackService.appVersion,
            "buildNumber": FeedbackService.buildNumber,
            "osVersion": FeedbackService.osVersion
        ]

        if let report = store.report {
            values["powerLock"] = report.state.ownsSleepDisable ? "on" : "off"
            values["shouldPreventSleep"] = report.decision.shouldPreventSleep ? "true" : "false"
            values["powerSource"] = report.snapshot.powerSource.rawValue
            values["battery"] = report.snapshot.batteryPercent.map(String.init) ?? "unknown"
            values["network"] = report.snapshot.defaultRouteAvailable.map { $0 ? "default route" : "no route" } ?? "unknown"
            values["lid"] = report.snapshot.lidClosed.map { $0 ? "closed" : "open" } ?? "unknown"
            values["agents"] = report.agents.map(\.kind.displayName).joined(separator: ", ")
            values["lastRequester"] = report.state.lastRequester?.shortDisplayText(maxLength: 120)
            values["lastActivationReason"] = report.state.lastActivationReason
            values["lastStopReason"] = report.state.lastStopReason
        }

        if let errorMessage = store.errorMessage {
            values["error"] = errorMessage
        }

        return values.compactMapValues { value in
            let cleaned = value.trimmingCharacters(in: .whitespacesAndNewlines)
            return cleaned.isEmpty ? nil : cleaned
        }
    }
}
