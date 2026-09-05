import CoreGraphics

/// The website's 28 × 20 heartbeat, expanded from its square-capped 2 px SVG stroke.
/// Shared by the menu bar, window wordmark, and icon generation script.
enum DSMNIdentity {
    static func pulsePath(in rect: CGRect) -> CGPath {
        let points: [CGPoint] = [
            .init(x: 1, y: 11), .init(x: 7, y: 11), .init(x: 7, y: 7),
            .init(x: 9, y: 7), .init(x: 9, y: 3), .init(x: 11, y: 3),
            .init(x: 11, y: 7), .init(x: 13, y: 7), .init(x: 13, y: 13),
            .init(x: 15, y: 13), .init(x: 15, y: 17), .init(x: 17, y: 17),
            .init(x: 17, y: 11), .init(x: 27, y: 11)
        ]
        let line = CGMutablePath()
        line.addLines(between: points)
        let outline = line.copy(strokingWithWidth: 2, lineCap: .square, lineJoin: .miter, miterLimit: 10)
        let scale = min(rect.width / 28, rect.height / 20)
        var transform = CGAffineTransform(translationX: rect.midX - 14 * scale, y: rect.midY - 10 * scale)
            .scaledBy(x: scale, y: scale)
        return outline.copy(using: &transform)!
    }
}
