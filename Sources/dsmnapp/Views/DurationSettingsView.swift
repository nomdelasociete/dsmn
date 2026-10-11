import DSMNCore
import SwiftUI

struct DurationSettingsView: View {
    @ObservedObject var preferences = DurationPreferences.shared
    @State private var draft = ""
    @State private var feedback: String?
    @State private var hasError = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Timer presets").font(.headline)
            Text("Choose 1–6 menu shortcuts, separated by commas. Maximum: \(ManualDuration.label(ManualDuration.maximumMinutes)) per timer.")
                .font(.callout).foregroundStyle(.secondary)
            HStack {
                TextField("30m, 1h30m, 2h", text: $draft)
                    .textFieldStyle(.roundedBorder)
                    .accessibilityIdentifier("settings.duration-presets")
                    .onChange(of: draft) { _ in feedback = nil }
                Button("Save Presets") {
                    do {
                        try preferences.savePresets(draft)
                        hasError = false
                        feedback = "Saved. The menu uses these presets immediately."
                    } catch {
                        hasError = true
                        feedback = error.localizedDescription
                    }
                }
                .accessibilityIdentifier("settings.save-duration-presets")
            }
            if let feedback {
                Text(feedback).font(.caption).foregroundStyle(hasError ? .red : .secondary)
                    .accessibilityIdentifier("settings.duration-feedback")
            }
            Text("Custom remembers your last successful duration: \(ManualDuration.label(preferences.lastCustomMinutes)).")
                .font(.caption).foregroundStyle(.secondary)
        }
        .onAppear { draft = preferences.presets.map(ManualDuration.label).joined(separator: ", ") }
    }
}
