import AppKit
import SwiftUI

@MainActor
enum OnboardingWindowPresenter {
    fileprivate static var window: NSWindow?
    fileprivate static var windowDelegate: OnboardingWindowDelegate?
    private static var didAttemptAutomaticPresentation = false

    static func showIfNeeded(store: DSMNMenuStore) {
        OnboardingPreferences.migrateLegacyKeysIfNeeded()

        guard !didAttemptAutomaticPresentation else {
            return
        }

        didAttemptAutomaticPresentation = true

        guard !OnboardingPreferences.wizardDismissed else {
            return
        }

        show(store: store)
    }

    static func show(store: DSMNMenuStore) {
        OnboardingPreferences.migrateLegacyKeysIfNeeded()

        if let window {
            NSApp.activate(ignoringOtherApps: true)
            window.makeKeyAndOrderFront(nil)
            return
        }

        let content = DSMNOnboardingView(
            store: store,
            onSkip: { dismissWizard() },
            onDone: { attemptFinish(store: store) }
        )

        let hostingView = NSHostingView(rootView: content)
        let newWindow = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 720, height: 720),
            styleMask: [.titled, .closable, .miniaturizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        newWindow.title = "Welcome to dsmn"
        newWindow.titlebarAppearsTransparent = true
        newWindow.isReleasedWhenClosed = false
        newWindow.contentView = hostingView
        newWindow.center()

        let delegate = OnboardingWindowDelegate()
        newWindow.delegate = delegate
        windowDelegate = delegate

        window = newWindow
        NSApp.activate(ignoringOtherApps: true)
        newWindow.makeKeyAndOrderFront(nil)
    }

    private static func attemptFinish(store: DSMNMenuStore) {
        if store.setupIsComplete {
            dismissWizard()
            return
        }

        let alert = NSAlert()
        alert.messageText = "Setup Still Incomplete"
        alert.informativeText = """
        Helper and agent hooks are not fully ready yet. dsmn will keep setup actions visible in the menu until both are done.

        You can return here anytime from Setup Guide.
        """
        alert.alertStyle = .informational
        alert.addButton(withTitle: "Continue Anyway")
        alert.addButton(withTitle: "Stay in Setup Guide")

        guard alert.runModal() == .alertFirstButtonReturn else {
            return
        }

        dismissWizard()
    }

    private static func dismissWizard() {
        OnboardingPreferences.wizardDismissed = true
        window?.close()
    }

}

@MainActor
private final class OnboardingWindowDelegate: NSObject, NSWindowDelegate {
    func windowWillClose(_ notification: Notification) {
        OnboardingPreferences.wizardDismissed = true
        OnboardingWindowPresenter.window = nil
        OnboardingWindowPresenter.windowDelegate = nil
    }
}