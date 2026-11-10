// Draws the app icon and writes dist/AppIcon.icns. Run via scripts/bundle.sh.
import AppKit

let out = URL(fileURLWithPath: CommandLine.arguments[1])
let iconset = out.deletingLastPathComponent().appendingPathComponent("AppIcon.iconset")
try? FileManager.default.removeItem(at: iconset)
try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)

func draw(_ px: Int) -> Data {
    let s = CGFloat(px)
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px, bitsPerSample: 8,
                               samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                               colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)

    // macOS icon grid: 824/1024 tile, centred, corner radius ≈ 22.5% of the tile.
    let tile = NSRect(x: s * 100 / 1024, y: s * 100 / 1024, width: s * 824 / 1024, height: s * 824 / 1024)
    let shape = NSBezierPath(roundedRect: tile, xRadius: tile.width * 0.225, yRadius: tile.width * 0.225)
    NSGraphicsContext.current?.saveGraphicsState()
    let shadow = NSShadow()
    shadow.shadowColor = NSColor.black.withAlphaComponent(0.35)
    shadow.shadowOffset = NSSize(width: 0, height: -s * 0.012)
    shadow.shadowBlurRadius = s * 0.03
    shadow.set()
    NSColor(calibratedRed: 0.13, green: 0.13, blue: 0.15, alpha: 1).setFill()
    shape.fill()
    NSGraphicsContext.current?.restoreGraphicsState()
    NSGradient(starting: NSColor(calibratedWhite: 0.24, alpha: 1), ending: NSColor(calibratedWhite: 0.11, alpha: 1))!
        .draw(in: shape, angle: -90)
    NSColor(calibratedWhite: 1, alpha: 0.08).setStroke()
    shape.lineWidth = max(1, s * 0.004)
    shape.stroke()

    // Mouse body: a tall capsule with a split between the two buttons.
    let w = tile.width * 0.40, h = tile.width * 0.62
    let body = NSRect(x: tile.midX - w / 2, y: tile.midY - h / 2, width: w, height: h)
    let mouse = NSBezierPath(roundedRect: body, xRadius: w / 2, yRadius: w / 2)
    NSGradient(starting: NSColor(calibratedWhite: 0.98, alpha: 1), ending: NSColor(calibratedWhite: 0.80, alpha: 1))!
        .draw(in: mouse, angle: -90)

    let line = NSBezierPath()
    line.move(to: NSPoint(x: body.midX, y: body.maxY))
    line.line(to: NSPoint(x: body.midX, y: body.maxY - h * 0.36))
    line.move(to: NSPoint(x: body.minX + w * 0.04, y: body.maxY - h * 0.36))
    line.line(to: NSPoint(x: body.maxX - w * 0.04, y: body.maxY - h * 0.36))
    line.lineWidth = max(1, s * 0.010)
    NSColor(calibratedWhite: 0.55, alpha: 1).setStroke()
    line.stroke()

    // Scroll wheel, then the DPI LED glowing green under it (stage 2, the default).
    let wheel = NSRect(x: body.midX - w * 0.07, y: body.maxY - h * 0.27, width: w * 0.14, height: h * 0.15)
    NSColor(calibratedWhite: 0.22, alpha: 1).setFill()
    NSBezierPath(roundedRect: wheel, xRadius: wheel.width / 2, yRadius: wheel.width / 2).fill()

    let ledSize = w * 0.10
    let led = NSRect(x: body.midX - ledSize / 2, y: body.maxY - h * 0.47, width: ledSize, height: ledSize)
    NSGraphicsContext.current?.saveGraphicsState()
    let glow = NSShadow()
    glow.shadowColor = NSColor(calibratedRed: 0.19, green: 0.82, blue: 0.35, alpha: 0.9)
    glow.shadowBlurRadius = s * 0.025
    glow.set()
    NSColor(calibratedRed: 0.19, green: 0.82, blue: 0.35, alpha: 1).setFill()
    NSBezierPath(ovalIn: led).fill()
    NSGraphicsContext.current?.restoreGraphicsState()

    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

for base in [16, 32, 128, 256, 512] {
    try draw(base).write(to: iconset.appendingPathComponent("icon_\(base)x\(base).png"))
    try draw(base * 2).write(to: iconset.appendingPathComponent("icon_\(base)x\(base)@2x.png"))
}
