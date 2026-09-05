import AppKit

@main
enum RenderAppIcon {
    static func main() throws {
        let output = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
        let sizes = [("16x16", 16), ("16x16@2x", 32), ("32x32", 32), ("32x32@2x", 64),
                     ("128x128", 128), ("128x128@2x", 256), ("256x256", 256), ("256x256@2x", 512),
                     ("512x512", 512), ("512x512@2x", 1024)]
        for (name, pixels) in sizes {
            let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels,
                                          bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                                          isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
            let context = NSGraphicsContext(bitmapImageRep: bitmap)!.cgContext
            context.translateBy(x: 0, y: CGFloat(pixels))
            context.scaleBy(x: CGFloat(pixels) / 48, y: -CGFloat(pixels) / 48)
            context.translateBy(x: 4, y: 4)
            // Website icon's stepped paper tile, with macOS icon breathing room.
            let tile = CGMutablePath()
            tile.addLines(between: [CGPoint(x: 4, y: 0), CGPoint(x: 36, y: 0), CGPoint(x: 36, y: 4),
                CGPoint(x: 40, y: 4), CGPoint(x: 40, y: 36), CGPoint(x: 36, y: 36), CGPoint(x: 36, y: 40),
                CGPoint(x: 4, y: 40), CGPoint(x: 4, y: 36), CGPoint(x: 0, y: 36), CGPoint(x: 0, y: 4), CGPoint(x: 4, y: 4)])
            tile.closeSubpath()
            context.setFillColor(CGColor(srgbRed: 241.0/255, green: 240.0/255, blue: 231.0/255, alpha: 1))
            context.addPath(tile)
            context.fillPath()
            context.setFillColor(CGColor(srgbRed: 32.0/255, green: 35.0/255, blue: 30.0/255, alpha: 1))
            context.addPath(DSMNIdentity.pulsePath(in: CGRect(x: 6, y: 10, width: 28, height: 20)))
            context.fillPath()
            try bitmap.representation(using: .png, properties: [:])!.write(to: output.appendingPathComponent("icon_\(name).png"))
        }
    }
}
