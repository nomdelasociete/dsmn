import DSMNCore
import SwiftUI

struct DurationSettingsView: View {
    @ObservedObject var preferences = DurationPreferences.shared
    @State private var rows: [PresetDraft] = []
    @State private var feedback: String?
    @State private var hasError = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Timer presets").font(.headline)
            Text("Keep 1–6 shortcuts in the timer panel. Each duration can be between 1 minute and \(ManualDuration.label(ManualDuration.maximumMinutes)).")
                .foregroundStyle(.secondary)
            ForEach(Array(rows.enumerated()), id: \.element.id) { index, row in
                HStack(spacing: 10) {
                    Text("\(index + 1)").foregroundStyle(.secondary).frame(width: 20)
                    TextField("0", text: $rows[index].hours)
                        .accessibilityLabel("Preset \(index + 1) hours")
                        .accessibilityIdentifier("settings.preset.\(index).hours").frame(width: 60)
                    Text("h")
                    TextField("0", text: $rows[index].minutes)
                        .accessibilityLabel("Preset \(index + 1) minutes")
                        .accessibilityIdentifier("settings.preset.\(index).minutes").frame(width: 60)
                    Text("min")
                    Spacer()
                    Button("Remove") { rows.removeAll { $0.id == row.id } }
                        .disabled(rows.count == 1)
                        .accessibilityLabel("Remove preset \(index + 1)")
                        .accessibilityIdentifier("settings.preset.\(index).remove")
                }.textFieldStyle(.roundedBorder)
            }
            Button("Add Preset") { rows.append(PresetDraft(minutes: 30)) }
                .disabled(rows.count >= 6).accessibilityIdentifier("settings.add-preset")
            Divider()
            Text("Panel preview").font(.subheadline.weight(.semibold))
            if let values = try? PresetDraft.validatedMinutes(rows) {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 72))], alignment: .leading) {
                    ForEach(values, id: \.self) { value in
                        Text(ManualDuration.label(value)).padding(.vertical, 8).frame(maxWidth: .infinity)
                            .background(DSMNBrand.field, in: RoundedRectangle(cornerRadius: 8))
                    }
                }.accessibilityIdentifier("settings.preset-preview")
            } else {
                Text("Enter distinct, valid durations to preview your shortcuts.").font(.caption).foregroundStyle(.secondary)
            }
            HStack {
                Button("Save Presets") {
                    do {
                        try preferences.savePresets(rows)
                        hasError = false
                        feedback = "Saved. The timer panel uses these presets immediately."
                    } catch {
                        hasError = true
                        feedback = error.localizedDescription
                    }
                }.accessibilityIdentifier("settings.save-duration-presets")
                Button("Revert Changes") { reload() }.accessibilityIdentifier("settings.revert-presets")
            }
            if let feedback {
                Text(feedback).font(.caption).foregroundStyle(hasError ? .red : .secondary)
                    .accessibilityIdentifier("settings.duration-feedback")
            }
            Text("Save to apply your edits. Closing Settings discards unsaved changes.").font(.caption).foregroundStyle(.secondary)
            Text("Custom remembers your last successful duration: \(ManualDuration.label(preferences.lastCustomMinutes)).")
                .font(.caption).foregroundStyle(.secondary)
        }
        .onAppear { if rows.isEmpty { reload() } }
        .onChange(of: rows) { _ in feedback = nil }
    }

    private func reload() {
        rows = preferences.presets.map(PresetDraft.init(minutes:))
        feedback = nil
    }
}
