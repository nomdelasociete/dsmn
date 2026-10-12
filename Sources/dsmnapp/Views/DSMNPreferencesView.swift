import DSMNCore
import SwiftUI

struct DSMNPreferencesView: View {
    @ObservedObject var store: DSMNMenuStore
    var updateController: SoftwareUpdateController?
    var onClose: () -> Void
    @AppStorage("showMenuBarCountdown") private var showCountdown = true

    var body: some View {
        VStack(spacing: 16) {
            TabView {
                ScrollView {
                    VStack(alignment: .leading, spacing: 22) {
                        Text("Make dsmn fit your day.").font(.title2)
                        Toggle("Launch at Login", isOn: Binding(
                            get: { store.launchAtLoginEnabled }, set: { store.setLaunchAtLogin($0) }))
                        Text(store.launchAtLoginStatus.displayName).font(.caption).foregroundStyle(.secondary)
                        Toggle("Show countdown in menu bar", isOn: $showCountdown)
                        Text("Turn this off to keep only the icon in a crowded menu bar.")
                            .font(.caption).foregroundStyle(.secondary)
                        CheckForUpdatesView(updateController: updateController)
                        Button("Send Feedback") { FeedbackWindowPresenter.show(store: store) }
                        if let error = store.errorMessage { Text(error).foregroundStyle(.red) }
                    }.frame(maxWidth: .infinity, alignment: .leading).padding(24)
                }.tabItem { Label("General", systemImage: "gearshape") }
                ScrollView { DurationSettingsView().padding(24) }
                    .tabItem { Label("Durations", systemImage: "timer") }
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        Text("Automatic protection").font(.title2)
                        Text("These rules are automatic, not switches. Keep the helper up to date to use the latest protections.")
                            .foregroundStyle(.secondary)
                        rule("Timer ends", "Sleep is allowed when the timer expires. Agent hooks can extend it, up to the duration limit.")
                        rule("Low battery", "On battery, sleep prevention stops at \(SafetyPolicy().minimumBatteryPercent)% or below.")
                        rule("Network unavailable", "Sleep prevention stops after \(SafetyPolicy().noRouteGraceSeconds / 60) minutes without a confirmed default network route.")
                        rule("Critical heat", "Critical macOS thermal state cancels the timer. Cooling down does not restart it.")
                        rule("Closed lid", "The screen is turned off while protection continues. After releasing protection on battery, dsmn also requests sleep.")
                        Button("Setup & Troubleshooting…") {
                            SetupTroubleshootingWindowPresenter.show(store: store, updateController: updateController)
                        }
                    }.frame(maxWidth: .infinity, alignment: .leading).padding(24)
                }.tabItem { Label("Protection", systemImage: "shield") }
            }
            HStack { Spacer(); Button("Done", action: onClose).accessibilityIdentifier("settings.done") }
        }
        .padding(20).frame(minWidth: 580, minHeight: 580).dsmnWindowStyle()
        .task { await store.refresh() }
    }

    private func rule(_ title: String, _ detail: String) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title).font(.headline)
            Text(detail).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }
    }
}
