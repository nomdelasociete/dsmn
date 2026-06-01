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
                    .symbolRenderingMode(.hierarchical)
            } else {
                Image(nsImage: DSMNStatusIconImage.image(for: state))
                    .resizable()
                    .renderingMode(.template)
                    .interpolation(.high)
                    .foregroundStyle(.primary)
            }
        }
        .frame(width: size, height: size)
        .id(state.rawValue)
    }
}

private enum DSMNStatusIconImage {
    @MainActor private static var cache: [MenuBarIconState: NSImage] = [:]

    @MainActor
    static func image(for state: MenuBarIconState) -> NSImage {
        if let image = cache[state] {
            return image
        }

        let image = render(for: state)
        cache[state] = image
        return image
    }

    @MainActor
    private static func render(for state: MenuBarIconState) -> NSImage {
        let size = NSSize(width: 18, height: 18)
        let image = NSImage(size: size)

        image.lockFocus()
        defer {
            image.unlockFocus()
            image.isTemplate = true
        }

        NSColor.black.setFill()

        switch state {
        case .manualActive:
            let path = NSBezierPath(ovalIn: NSRect(origin: .zero, size: size).insetBy(dx: 0.5, dy: 0.5))
            path.append(crownPath(in: NSRect(x: 3.2, y: 4.7, width: 11.6, height: 8.5)))
            path.windingRule = .evenOdd
            path.fill()
        case .loading, .off:
            crownPath(in: NSRect(x: 1.7, y: 4.2, width: 14.6, height: 8.4)).fill()
        case .warning:
            break
        }

        return image
    }

    private static func crownPath(in rect: NSRect) -> NSBezierPath {
        let sourceSize = CGSize(width: 69.73, height: 40)
        let scale = min(rect.width / sourceSize.width, rect.height / sourceSize.height)
        let scaledSize = CGSize(width: sourceSize.width * scale, height: sourceSize.height * scale)
        let origin = CGPoint(
            x: rect.midX - scaledSize.width / 2,
            y: rect.midY - scaledSize.height / 2
        )

        func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
            CGPoint(x: origin.x + x * scale, y: origin.y + (sourceSize.height - y) * scale)
        }

        let path = NSBezierPath()

        path.move(to: p(49.83, 26.16))
        path.line(to: p(45.85, 19.21))
        path.line(to: p(45.22, 18.09))
        path.line(to: p(39.49, 8.10))
        path.line(to: p(34.88, 0.00))
        path.line(to: p(33.03, 3.27))
        path.line(to: p(28.31, 11.51))
        path.line(to: p(23.89, 19.26))
        path.line(to: p(20.15, 25.74))
        path.line(to: p(13.86, 36.69))
        path.line(to: p(12.05, 39.86))
        path.line(to: p(57.70, 39.86))
        path.line(to: p(53.58, 32.71))
        path.close()

        path.move(to: p(15.27, 16.84))
        path.line(to: p(12.97, 15.78))
        path.line(to: p(0.00, 9.76))
        path.line(to: p(1.17, 14.13))
        path.line(to: p(1.90, 16.94))
        path.line(to: p(5.89, 31.77))
        path.line(to: p(8.12, 40.01))
        path.line(to: p(9.79, 34.83))
        path.line(to: p(11.31, 30.11))
        path.line(to: p(15.51, 16.95))
        path.curve(
            to: p(15.29, 16.84),
            controlPoint1: p(15.44, 16.87),
            controlPoint2: p(15.35, 16.87)
        )
        path.close()

        path.move(to: p(60.31, 14.11))
        path.line(to: p(54.29, 16.91))
        path.curve(
            to: p(54.27, 17.11),
            controlPoint1: p(54.19, 16.96),
            controlPoint2: p(54.26, 17.06)
        )
        path.line(to: p(55.13, 19.77))
        path.line(to: p(58.29, 29.72))
        path.line(to: p(61.61, 39.97))
        path.line(to: p(63.83, 31.76))
        path.line(to: p(66.67, 21.27))
        path.line(to: p(67.75, 17.22))
        path.line(to: p(68.57, 14.15))
        path.line(to: p(69.74, 9.74))
        path.close()

        return path
    }
}
