import AppKit

let folder = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)

func writeIcon(_ size: Int, name: String) throws {
    let image = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size,
                                bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    let context = NSGraphicsContext(bitmapImageRep: image)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = context
    let cg = context.cgContext
    cg.scaleBy(x: CGFloat(size) / 512, y: CGFloat(size) / 512)
    let bounds = NSRect(x: 41, y: 41, width: 430, height: 430)
    let face = NSBezierPath(roundedRect: bounds, xRadius: 108, yRadius: 108)
    NSColor(calibratedRed: 0.07, green: 0.15, blue: 0.28, alpha: 0.20).setFill()
    NSBezierPath(roundedRect: bounds.offsetBy(dx: 0, dy: -10), xRadius: 108, yRadius: 108).fill()
    let colors = [NSColor(calibratedRed: 0.09, green: 0.19, blue: 0.37, alpha: 1),
                  NSColor(calibratedRed: 0.25, green: 0.42, blue: 0.72, alpha: 1),
                  NSColor(calibratedRed: 0.44, green: 0.72, blue: 0.84, alpha: 1)]
    NSGradient(colors: colors)!.draw(in: face, angle: 65)
    NSColor.white.withAlphaComponent(0.43).setStroke()
    face.lineWidth = 3
    face.stroke()
    for (x, y, side, stroke) in [(269.0, 256.0, 173.0, false), (221.0, 257.0, 142.0, true)] {
        cg.saveGState()
        cg.translateBy(x: x, y: y)
        cg.rotate(by: .pi / 4)
        let path = NSBezierPath(roundedRect: CGRect(x: -side/2, y: -side/2, width: side, height: side),
                                xRadius: 22, yRadius: 22)
        if stroke {
            NSColor.white.withAlphaComponent(0.76).setStroke()
            path.lineWidth = 5
            path.stroke()
        } else {
            NSGradient(colors: [.white, .systemCyan.withAlphaComponent(0.79), .systemIndigo.withAlphaComponent(0.43)])!
                .draw(in: path, angle: 120)
        }
        cg.restoreGState()
    }
    context.flushGraphics()
    NSGraphicsContext.restoreGraphicsState()
    try image.representation(using: .png, properties: [:])!.write(to: folder.appendingPathComponent(name))
}

for size in [16, 32, 128, 256, 512] {
    try writeIcon(size, name: "icon_\(size)x\(size).png")
    try writeIcon(size * 2, name: "icon_\(size)x\(size)@2x.png")
}
