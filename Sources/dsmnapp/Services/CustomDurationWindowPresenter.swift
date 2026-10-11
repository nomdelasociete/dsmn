import AppKit
import DSMNCore
import SwiftUI

@MainActor
enum CustomDurationWindowPresenter {
    private static var window: NSWindow?

    static func show(store: DSMNMenuStore, action: ManualTimerAction) {
        if let window, window.isVisible {
            NSApp.activate(ignoringOtherApps: true)
            window.makeKeyAndOrderFront(nil)
            return
        }
        let next = NSWindow(contentRect: .zero, styleMask: [.titled, .closable], backing: .buffered, defer: false)
        let content = CustomDurationView(store: store, action: action) { [weak next] in next?.close() }
        let hosting = NSHostingController(rootView: content)
        hosting.sizingOptions = [.preferredContentSize]
        next.contentViewController = hosting
        next.setContentSize(hosting.view.fittingSize)
        next.title = "Keep Awake"
        next.styleMask = [.titled, .closable]
        next.level = .floating
        next.isReleasedWhenClosed = false
        next.center()
        window = next
        NSApp.activate(ignoringOtherApps: true)
        next.makeKeyAndOrderFront(nil)
    }
}
