import AppKit
import DSMNCore
import SwiftUI

struct DSMNMenuBarIcon: View {
    var state: MenuBarIconState
    var size: CGFloat = 16

    var body: some View {
        Group {
            if state == .warning {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: size * 0.82, weight: .semibold))
            } else {
                Image(nsImage: DSMNStatusIconImage.image(for: state))
                    .resizable()
                    .renderingMode(.template)
                    .interpolation(.none)
            }
        }
        .frame(width: size * 1.4, height: size)
        .id(state.rawValue)
        .accessibilityHidden(true)
    }
}

enum DSMNStatusIconImage {
    @MainActor private static var cache: [MenuBarIconState: NSImage] = [:]

    @MainActor
    static func image(for state: MenuBarIconState) -> NSImage {
        if let image = cache[state] { return image }
        let image = NSImage(size: NSSize(width: 28, height: 20), flipped: true) { _ in
            guard let context = NSGraphicsContext.current?.cgContext else { return false }
            context.setFillColor(NSColor.black.cgColor)
            context.addPath(DSMNIdentity.pulsePath(in: CGRect(x: 0, y: 0, width: 28, height: 20)))
            context.fillPath()
            // A steady activity pixel keeps the state distinct without continuous animation.
            if state == .manualActive {
                context.fill(CGRect(x: 23, y: 2, width: 4, height: 4))
            }
            return true
        }
        image.isTemplate = true
        cache[state] = image
        return image
    }
}
