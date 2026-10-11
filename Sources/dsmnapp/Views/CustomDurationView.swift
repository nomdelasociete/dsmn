import DSMNCore
import SwiftUI

struct CustomDurationView: View {
    @ObservedObject var store: DSMNMenuStore
    @State var action: ManualTimerAction
    @State private var hours: String
    @State private var minutes: String
    @State private var error: String?
    @State private var submitting = false
    private let preferences: DurationPreferences
    var onClose: () -> Void

    init(store: DSMNMenuStore, action: ManualTimerAction,
         preferences: DurationPreferences = .shared, onClose: @escaping () -> Void) {
        self.store = store
        self.action = action
        self.preferences = preferences
        self.onClose = onClose
        _hours = State(initialValue: String(preferences.lastCustomMinutes / 60))
        _minutes = State(initialValue: String(preferences.lastCustomMinutes % 60))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Keep Awake").font(.title2.bold())
            Picker("Timer action", selection: $action) {
                Text("Replace timer").tag(ManualTimerAction.replace)
                Text("Add time").tag(ManualTimerAction.add)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            Text(action == .add ? "Add to the current timer, or start one if none is running."
                 : "Start a timer from now, replacing any remaining time.")
                .font(.callout).foregroundStyle(.secondary)
            HStack {
                TextField("Hours", text: $hours)
                    .accessibilityIdentifier("duration.hours")
                Text("hours")
                TextField("Minutes", text: $minutes)
                    .accessibilityIdentifier("duration.minutes")
                Text("minutes")
            }
            .textFieldStyle(.roundedBorder)
            Text("1 minute to \(ManualDuration.label(ManualDuration.maximumMinutes)). Minutes: 0–59. Adding time must stay within the same limit.")
                .font(.caption).foregroundStyle(.secondary)
            if let error {
                Text(error).foregroundStyle(.red).fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("duration.error")
            }
            HStack {
                Button("Cancel", action: onClose).keyboardShortcut(.cancelAction)
                    .accessibilityIdentifier("duration.cancel")
                Spacer()
                Button(submitting ? "Applying…" : action == .add ? "Add Time" : "Start / Replace Timer") {
                    submit()
                }
                .keyboardShortcut(.defaultAction)
                .accessibilityIdentifier("duration.submit")
            }
        }
        .padding(24)
        .frame(width: 430)
        .dsmnWindowStyle()
        .disabled(submitting)
    }

    private func submit() {
        do {
            let duration = try ManualDuration.minutes(hours: hours, minutes: minutes)
            error = nil
            submitting = true
            Task {
                defer { submitting = false }
                do {
                    try await store.setManualTimer(minutes: duration, action: action)
                    try preferences.rememberCustom(minutes: duration)
                    onClose()
                } catch {
                    self.error = error.localizedDescription
                }
            }
        } catch {
            self.error = error.localizedDescription
        }
    }
}
