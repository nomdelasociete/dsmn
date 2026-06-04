import AppKit

@MainActor
enum AboutPanelPresenter {
    static func show(store: DSMNMenuStore) {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "Unknown"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? ""
        let versionLine = build.isEmpty ? version : "\(version) (\(build))"

        NSApplication.shared.activate(ignoringOtherApps: true)

        let alert = NSAlert()
        alert.messageText = "dsmn"
        alert.informativeText = """
        Version \(versionLine)

        Published by NOM DE LA SOCIETE
        Developed by Jb Ronssin

        Agent hooks keep Claude, Codex, Grok, and Pi sessions on the dsmn timer. Removing hooks does not quit dsmn or stop an active timer.
        """
        alert.alertStyle = .informational
        alert.addButton(withTitle: "OK")
        alert.addButton(withTitle: "Remove Agent Hooks…")

        guard alert.runModal() == .alertSecondButtonReturn else {
            return
        }

        confirmRemoveAgentHooks(store: store)
    }

    private static func confirmRemoveAgentHooks(store: DSMNMenuStore) {
        let confirm = NSAlert()
        confirm.messageText = "Remove Agent Hooks?"
        confirm.informativeText = """
        This removes dsmn hook entries from Claude Code, Codex, Grok Build, and Pi, and deletes ~/.dsmn/dsmn-agent-hook.sh.

        The menu bar app and privileged helper are unchanged. An active manual timer keeps running until it expires or you choose Stop.
        """
        confirm.alertStyle = .warning
        confirm.addButton(withTitle: "Remove Hooks")
        confirm.addButton(withTitle: "Cancel")

        guard confirm.runModal() == .alertFirstButtonReturn else {
            return
        }

        store.uninstallAgentHooks()
    }
}