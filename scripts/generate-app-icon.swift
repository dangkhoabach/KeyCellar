// Renders the app icon set from code: on the near-black rounded square all
// of the author's apps share, a key, in one gradient, so the project needs
// no design tool to produce KeyCellarApp/Resources/Assets.xcassets/AppIcon.appiconset.
//
// Run once (or whenever the look changes):
//   swift scripts/generate-app-icon.swift
import AppKit

let root = URL(fileURLWithPath: CommandLine.arguments.first!).deletingLastPathComponent().deletingLastPathComponent()
let iconset = root.appendingPathComponent("KeyCellarApp/Resources/Assets.xcassets/AppIcon.appiconset")
try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)

func color(_ hex: UInt32) -> NSColor {
    NSColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255, blue: CGFloat(hex & 0xFF) / 255, alpha: 1)
}

/// A stroked path through `points`, with round ends and corners.
func line(_ points: [NSPoint], width: CGFloat = 44) -> NSBezierPath {
    let path = NSBezierPath()
    path.lineWidth = width
    path.lineCapStyle = .round
    path.lineJoinStyle = .round
    path.move(to: points[0])
    points.dropFirst().forEach { path.line(to: $0) }
    return path
}

/// Drawn on a 1024-point canvas; every size is scaled down from it.
func drawIcon() {
    // macOS icon grid: the squircle occupies ~80% of the canvas.
    color(0x121214).setFill()
    NSBezierPath(roundedRect: NSRect(x: 100, y: 100, width: 824, height: 824), xRadius: 185, yRadius: 185).fill()

    // An upright key: ring, shaft and two teeth, then turned 45 degrees.
    let ring = NSBezierPath(ovalIn: NSRect(x: 512 - 118, y: 700 - 118, width: 236, height: 236))
    ring.lineWidth = 52
    let strokes = [ring,
                   line([NSPoint(x: 512, y: 582), NSPoint(x: 512, y: 240)], width: 52),
                   line([NSPoint(x: 512, y: 300), NSPoint(x: 600, y: 300)], width: 52),
                   line([NSPoint(x: 512, y: 400), NSPoint(x: 580, y: 400)], width: 52)]
    let turn = NSAffineTransform()
    turn.translateX(by: 512, yBy: 512)
    turn.rotate(byDegrees: -45)
    turn.translateX(by: -512, yBy: -512)
    strokes.forEach { $0.transform(using: turn as AffineTransform) }

    // All of it white in a layer, then tinted with one gradient.
    NSGraphicsContext.saveGraphicsState()
    let context = NSGraphicsContext.current!.cgContext
    context.beginTransparencyLayer(auxiliaryInfo: nil)
    NSColor.white.setStroke()
    NSColor.white.setFill()
    strokes.forEach { $0.stroke() }
    NSGraphicsContext.current!.compositingOperation = .sourceIn
    NSGradient(colors: [color(0xFEF08A), color(0xEAB308)])!.draw(in: NSRect(x: 0, y: 0, width: 1024, height: 1024), angle: -90)
    context.endTransparencyLayer()
    NSGraphicsContext.restoreGraphicsState()
}

// Contents.json already lists these file names, so only the pictures are written.
for (points, scale) in [(16, 1), (16, 2), (32, 1), (32, 2), (128, 1), (128, 2), (256, 1), (256, 2), (512, 1), (512, 2)] {
    let pixels = points * scale
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels, bitsPerSample: 8,
                               samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    let context = NSGraphicsContext(bitmapImageRep: rep)!
    context.imageInterpolation = .high
    NSGraphicsContext.current = context
    let transform = NSAffineTransform()
    transform.scale(by: CGFloat(pixels) / 1024)
    transform.concat()
    drawIcon()
    NSGraphicsContext.restoreGraphicsState()
    let name = "icon_\(points)x\(points)\(scale == 2 ? "@2x" : "").png"
    try rep.representation(using: .png, properties: [:])!.write(to: iconset.appendingPathComponent(name))
}
print("Wrote 10 icons to \(iconset.path)")
