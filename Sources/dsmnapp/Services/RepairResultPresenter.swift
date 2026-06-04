import AppKit

@MainActor
enum RepairResultPresenter {
    static func show(result: String, error: String? = nil) {
        let alert = NSAlert()
        alert.messageText = error == nil ? "Repair Complete" : "Repair Failed"
        alert.informativeText = error ?? result
        alert.alertStyle = error == nil ? .informational : .warning
        alert.addButton(withTitle: "OK")

        if error == nil {
            alert.showsSuppressionButton = false
        }

        alert.runModal()
    }
}