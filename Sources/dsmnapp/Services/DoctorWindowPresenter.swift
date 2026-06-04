import AppKit
import SwiftUI

@MainActor
enum DoctorWindowPresenter {
    private static var window: NSWindow?
    private static var closeDelegate: WindowCloseDelegate?

    static func show(report: String) {
        if let window {
            if let hostingView = window.contentView as? NSHostingView<DSMNDoctorView> {
                hostingView.rootView = DSMNDoctorView(report: report) {
                    Self.close()
                }
            }
            NSApp.activate(ignoringOtherApps: true)
            window.makeKeyAndOrderFront(nil)
            return
        }

        let content = DSMNDoctorView(report: report) {
            Self.close()
        }
        let hostingView = NSHostingView(rootView: content)
        let newWindow = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 560, height: 520),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        let delegate = WindowCloseDelegate {
            Self.window = nil
            Self.closeDelegate = nil
        }

        newWindow.title = "dsmn Doctor"
        newWindow.isReleasedWhenClosed = false
        newWindow.delegate = delegate
        newWindow.contentView = hostingView
        newWindow.center()

        closeDelegate = delegate
        window = newWindow
        NSApp.activate(ignoringOtherApps: true)
        newWindow.makeKeyAndOrderFront(nil)
    }

    private static func close() {
        window?.close()
        window = nil
        closeDelegate = nil
    }
}

private final class WindowCloseDelegate: NSObject, NSWindowDelegate {
    private let onClose: @MainActor () -> Void

    init(onClose: @escaping @MainActor () -> Void) {
        self.onClose = onClose
    }

    func windowWillClose(_ notification: Notification) {
        onClose()
    }
}