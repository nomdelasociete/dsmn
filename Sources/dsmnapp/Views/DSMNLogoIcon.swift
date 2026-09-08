import AppKit
import DSMNCore
import SwiftUI

struct DSMNMenuBarIcon: View {
    var state: MenuBarIconState
    var protectionIsActive: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var scanStep = 0

    private var shouldAnimate: Bool {
        state == .manualActive && protectionIsActive && !reduceMotion
    }

    var body: some View {
        Group {
            if state == .warning {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 13, weight: .semibold))
            } else {
                Image(nsImage: DSMNStatusIconImage.image(for: state, scanStep: shouldAnimate ? scanStep : 0))
                    .renderingMode(.template)
            }
        }
        .frame(width: 22, height: 16)
        .accessibilityHidden(true)
        .task(id: shouldAnimate) {
            scanStep = 0
            guard shouldAnimate else { return }
            do {
                while !Task.isCancelled {
                    // Match the website's 4.8 s cycle: rest, a stepped scan, then fade.
                    // Sleep between scans rather than running a continuous display timer.
                    try await Task.sleep(for: .seconds(3.264))
                    for step in 1...14 {
                        scanStep = step
                        try await Task.sleep(for: .seconds(0.96 / 14))
                    }
                    for step in 15...22 {
                        scanStep = step
                        try await Task.sleep(for: .seconds(0.576 / 8))
                    }
                    scanStep = 0
                }
            } catch is CancellationError {
                // State changes, Reduce Motion, and removal cancel the pending sleep.
            } catch {
                scanStep = 0
            }
        }
    }
}

enum DSMNStatusIconImage {
    private struct Key: Hashable {
        var state: MenuBarIconState
        var scanStep: Int
    }

    @MainActor private static var cache: [Key: NSImage] = [:]

    @MainActor
    static func image(for state: MenuBarIconState, scanStep: Int = 0) -> NSImage {
        let step = state == .manualActive ? min(22, max(0, scanStep)) : 0
        let key = Key(state: state, scanStep: step)
        if let image = cache[key] { return image }
        // MenuBarExtra can use NSImage's intrinsic dimensions instead of SwiftUI's frame.
        // Size the artwork here so both the static mark and every scan frame stay compact.
        let image = NSImage(size: NSSize(width: 22, height: 16), flipped: true) { _ in
            guard let context = NSGraphicsContext.current?.cgContext else { return false }
            let bounds = CGRect(x: 0, y: 0, width: 22, height: 16)
            let path = DSMNIdentity.pulsePath(in: bounds)
            context.setFillColor(NSColor.black.withAlphaComponent(state == .manualActive ? 0.65 : 1).cgColor)
            context.addPath(path)
            context.fillPath()
            if step > 0 {
                context.saveGState()
                let progress = min(1, CGFloat(step) / 14)
                context.clip(to: CGRect(x: 0, y: 0, width: bounds.width * progress, height: bounds.height))
                let opacity = step <= 14 ? 1 : CGFloat(22 - step) / 8
                context.setFillColor(NSColor.black.withAlphaComponent(opacity).cgColor)
                context.addPath(path)
                context.fillPath()
                context.restoreGState()
            }
            // Retain a steady state cue between scans and when Reduce Motion is enabled.
            if state == .manualActive {
                context.setFillColor(NSColor.black.cgColor)
                context.fill(CGRect(x: 18.5, y: 2, width: 2.5, height: 2.5))
            }
            return true
        }
        image.isTemplate = true
        cache[key] = image
        return image
    }
}
