import DSMNCore
import SwiftUI

struct DSMNAboutView: View {
    var onRemoveHooks: () -> Void
    var onClose: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            DSMNPageHeader(
                eyebrow: "DON’T STOP ME NOW",
                title: "Small enough to forget.",
                detail: "A little utility for your Mac. Free, native, and here to keep your agents working."
            )

            VStack(alignment: .leading, spacing: 8) {
                Text("Version \(FeedbackService.appVersion) (\(FeedbackService.buildNumber))")
                    .font(DSMNBrand.mono(12))
                Text("Published by NOM DE LA SOCIETE\nDeveloped by Jb Ronssin")
                    .font(.system(size: 12))
                    .lineSpacing(5)
                    .foregroundStyle(DSMNBrand.muted)
                Link("dsmn.app ↗", destination: URL(string: "https://dsmn.app")!)
                    .font(DSMNBrand.mono(12))
            }

            Divider()

            Text("Agent hooks connect \(AgentHookTarget.joinedDisplayNames(short: true)) to the timer. Removing hooks leaves an active timer running until it expires or you choose Stop.")
                .font(.system(size: 12))
                .foregroundStyle(DSMNBrand.muted)
                .fixedSize(horizontal: false, vertical: true)

            HStack {
                Button("Remove Agent Hooks…", action: onRemoveHooks)
                Spacer()
                Button("Done", action: onClose)
                    .buttonStyle(DSMNActionStyle(prominent: true))
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(28)
        .frame(width: 500, height: 490)
        .dsmnWindowStyle()
    }
}
