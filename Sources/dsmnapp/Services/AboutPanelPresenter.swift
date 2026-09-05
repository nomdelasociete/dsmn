import AppKit
import DSMNCore
import SwiftUI

@MainActor
enum AboutPanelPresenter {
    private static var window: NSWindow?

    static func show(store: DSMNMenuStore) {
        if let window {
            NSApp.activate(ignoringOtherApps: true)
            window.makeKeyAndOrderFront(nil)
            return
        }

        let content = DSMNAboutView(
            onRemoveHooks: { confirmRemoveAgentHooks(store: store) },
            onClose: { window?.close(); window = nil }
        )
        let newWindow = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 500, height: 490),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered, defer: false
        )
        newWindow.title = "About dsmn"
        newWindow.titlebarAppearsTransparent = true
        newWindow.isReleasedWhenClosed = false
        newWindow.contentView = NSHostingView(rootView: content)
        newWindow.center()
        window = newWindow
        NSApp.activate(ignoringOtherApps: true)
        newWindow.makeKeyAndOrderFront(nil)
    }

    private static func confirmRemoveAgentHooks(store: DSMNMenuStore) {
        let confirm = NSAlert()
        confirm.messageText = "Remove Agent Hooks?"
        confirm.informativeText = """
        This removes dsmn hook entries from \(AgentHookTarget.joinedDisplayNames()), and deletes ~/.dsmn/dsmn-agent-hook.sh.

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
