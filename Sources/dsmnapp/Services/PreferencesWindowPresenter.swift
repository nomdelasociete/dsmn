import AppKit
import SwiftUI

@MainActor
enum PreferencesWindowPresenter {
    private static var window: NSWindow?
    private static var delegate: PreferencesCloseDelegate?

    static func show(store: DSMNMenuStore, updateController: SoftwareUpdateController? = nil) {
        if let window {
            NSApp.activate(ignoringOtherApps: true)
            window.makeKeyAndOrderFront(nil)
            return
        }
        let content = DSMNPreferencesView(store: store, updateController: updateController) { window?.close() }
        let created = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 620, height: 680),
                               styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
        let closeDelegate = PreferencesCloseDelegate {
            window = nil
            delegate = nil
        }
        created.title = "Settings"
        created.isReleasedWhenClosed = false
        created.delegate = closeDelegate
        created.contentView = NSHostingView(rootView: content)
        created.minSize = NSSize(width: 580, height: 620)
        created.center()
        window = created
        delegate = closeDelegate
        NSApp.activate(ignoringOtherApps: true)
        created.makeKeyAndOrderFront(nil)
    }
}

private final class PreferencesCloseDelegate: NSObject, NSWindowDelegate {
    let onClose: @MainActor () -> Void
    init(onClose: @escaping @MainActor () -> Void) { self.onClose = onClose }
    func windowWillClose(_ notification: Notification) { onClose() }
}
