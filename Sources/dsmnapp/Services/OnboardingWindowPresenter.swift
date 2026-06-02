import AppKit
import SwiftUI

@MainActor
enum OnboardingWindowPresenter {
    private static var window: NSWindow?
    private static var didAttemptAutomaticPresentation = false
    private static let hasSeenOnboardingKey = "hasSeenOnboarding"

    static func showIfNeeded(store: DSMNMenuStore) {
        guard !didAttemptAutomaticPresentation else {
            return
        }

        didAttemptAutomaticPresentation = true

        guard !UserDefaults.standard.bool(forKey: hasSeenOnboardingKey) else {
            return
        }

        show(store: store)
    }

    static func show(store: DSMNMenuStore) {
        if let window {
            NSApp.activate(ignoringOtherApps: true)
            window.makeKeyAndOrderFront(nil)
            return
        }

        let content = DSMNOnboardingView(store: store) { markAsSeen in
            if markAsSeen {
                UserDefaults.standard.set(true, forKey: hasSeenOnboardingKey)
            }
            Self.window?.close()
            Self.window = nil
        }

        let hostingView = NSHostingView(rootView: content)
        let newWindow = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 720, height: 600),
            styleMask: [.titled, .closable, .miniaturizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        newWindow.title = "Welcome to dsmn"
        newWindow.titlebarAppearsTransparent = true
        newWindow.isReleasedWhenClosed = false
        newWindow.contentView = hostingView
        newWindow.center()

        window = newWindow
        NSApp.activate(ignoringOtherApps: true)
        newWindow.makeKeyAndOrderFront(nil)
    }
}
