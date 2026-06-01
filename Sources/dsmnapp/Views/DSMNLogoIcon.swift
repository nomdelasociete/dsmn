import DSMNCore
import SwiftUI

struct DSMNMenuBarIcon: View {
    var state: MenuBarIconState
    var size: CGFloat = 16

    var body: some View {
        Group {
            switch state {
            case .warning:
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: size * 0.82, weight: .semibold))
                    .symbolRenderingMode(.hierarchical)
                    .frame(width: size, height: size)
            case .manualActive:
                DSMNCrownBadgeShape()
                    .fill(.primary, style: FillStyle(eoFill: true))
                    .frame(width: size, height: size)
            case .loading:
                DSMNCrownShape()
                    .fill(.primary.opacity(0.45))
                    .frame(width: size, height: size)
            case .off:
                DSMNCrownShape()
                    .fill(.primary)
                    .frame(width: size, height: size)
            }
        }
        .id(state.rawValue)
    }
}

private struct DSMNCrownBadgeShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let circleRect = rect.insetBy(dx: rect.width * 0.03, dy: rect.height * 0.03)
        path.addEllipse(in: circleRect)

        let crownRect = rect.insetBy(dx: rect.width * 0.14, dy: rect.height * 0.20)
        path.addPath(DSMNCrownShape().path(in: crownRect))
        return path
    }
}

private struct DSMNCrownShape: Shape {
    private static let sourceSize = CGSize(width: 69.73, height: 40)

    func path(in rect: CGRect) -> Path {
        let scale = min(rect.width / Self.sourceSize.width, rect.height / Self.sourceSize.height)
        let scaledSize = CGSize(width: Self.sourceSize.width * scale, height: Self.sourceSize.height * scale)
        let offset = CGPoint(
            x: rect.midX - scaledSize.width / 2,
            y: rect.midY - scaledSize.height / 2
        )

        let transform = CGAffineTransform(translationX: offset.x, y: offset.y)
            .scaledBy(x: scale, y: scale)

        return Self.sourcePath.applying(transform)
    }

    private static var sourcePath: Path {
        var path = Path()

        path.move(to: CGPoint(x: 49.83, y: 26.16))
        path.addLine(to: CGPoint(x: 45.85, y: 19.21))
        path.addLine(to: CGPoint(x: 45.22, y: 18.09))
        path.addLine(to: CGPoint(x: 39.49, y: 8.10))
        path.addLine(to: CGPoint(x: 34.88, y: 0.00))
        path.addLine(to: CGPoint(x: 33.03, y: 3.27))
        path.addLine(to: CGPoint(x: 28.31, y: 11.51))
        path.addLine(to: CGPoint(x: 23.89, y: 19.26))
        path.addLine(to: CGPoint(x: 20.15, y: 25.74))
        path.addLine(to: CGPoint(x: 13.86, y: 36.69))
        path.addLine(to: CGPoint(x: 12.05, y: 39.86))
        path.addLine(to: CGPoint(x: 57.70, y: 39.86))
        path.addLine(to: CGPoint(x: 53.58, y: 32.71))
        path.closeSubpath()

        path.move(to: CGPoint(x: 15.27, y: 16.84))
        path.addLine(to: CGPoint(x: 12.97, y: 15.78))
        path.addLine(to: CGPoint(x: 0.00, y: 9.76))
        path.addLine(to: CGPoint(x: 1.17, y: 14.13))
        path.addLine(to: CGPoint(x: 1.90, y: 16.94))
        path.addLine(to: CGPoint(x: 5.89, y: 31.77))
        path.addLine(to: CGPoint(x: 8.12, y: 40.01))
        path.addLine(to: CGPoint(x: 9.79, y: 34.83))
        path.addLine(to: CGPoint(x: 11.31, y: 30.11))
        path.addLine(to: CGPoint(x: 15.51, y: 16.95))
        path.addCurve(
            to: CGPoint(x: 15.29, y: 16.84),
            control1: CGPoint(x: 15.44, y: 16.87),
            control2: CGPoint(x: 15.35, y: 16.87)
        )
        path.closeSubpath()

        path.move(to: CGPoint(x: 60.31, y: 14.11))
        path.addLine(to: CGPoint(x: 54.29, y: 16.91))
        path.addCurve(
            to: CGPoint(x: 54.27, y: 17.11),
            control1: CGPoint(x: 54.19, y: 16.96),
            control2: CGPoint(x: 54.26, y: 17.06)
        )
        path.addLine(to: CGPoint(x: 55.13, y: 19.77))
        path.addLine(to: CGPoint(x: 58.29, y: 29.72))
        path.addLine(to: CGPoint(x: 61.61, y: 39.97))
        path.addLine(to: CGPoint(x: 63.83, y: 31.76))
        path.addLine(to: CGPoint(x: 66.67, y: 21.27))
        path.addLine(to: CGPoint(x: 67.75, y: 17.22))
        path.addLine(to: CGPoint(x: 68.57, y: 14.15))
        path.addLine(to: CGPoint(x: 69.74, y: 9.74))
        path.closeSubpath()

        return path
    }
}
