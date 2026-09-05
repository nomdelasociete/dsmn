import AppKit
import SwiftUI

struct DSMNDoctorView: View {
    var report: String
    var onClose: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            DSMNPageHeader(
                eyebrow: "DIAGNOSTICS",
                title: "A closer look.",
                detail: "Diagnostic report from the helper and local dsmn state."
            )
            .padding(24)

            ScrollView {
                Text(report)
                    .font(DSMNBrand.mono(12))
                    .lineSpacing(4)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(20)
            }
            .background(DSMNBrand.field)

            Divider()

            HStack {
                Button("Copy Report") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(report, forType: .string)
                }

                Spacer()

                Button("Close") {
                    onClose()
                }
                .keyboardShortcut(.cancelAction)
            }
            .padding(20)
        }
        .frame(minWidth: 620, minHeight: 620)
        .dsmnWindowStyle()
    }
}
