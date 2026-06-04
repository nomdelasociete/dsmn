import AppKit

@MainActor
enum HookUninstallResultPresenter {
    static func show(title: String, detail: String, isError: Bool = false) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = detail
        alert.alertStyle = isError ? .warning : .informational
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }
}