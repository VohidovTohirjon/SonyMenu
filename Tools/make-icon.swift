// Draws the app icon (original artwork: over-ear headphones on a dark squircle)
// and writes Resources/AppIcon.icns.  Run: swift Tools/make-icon.swift
import AppKit

func drawIcon(size: CGFloat) -> NSBitmapImageRep {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size), pixelsHigh: Int(size),
                               bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                               colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let s = size / 1024
    let ctx = NSGraphicsContext.current!.cgContext

    // Squircle background (macOS icon grid: 824 pt body inside 1024 canvas).
    let body = NSRect(x: 100 * s, y: 100 * s, width: 824 * s, height: 824 * s)
    let squircle = NSBezierPath(roundedRect: body, xRadius: 185 * s, yRadius: 185 * s)
    ctx.saveGState()
    let shadow = NSShadow()
    shadow.shadowColor = NSColor.black.withAlphaComponent(0.35)
    shadow.shadowBlurRadius = 24 * s
    shadow.shadowOffset = NSSize(width: 0, height: -10 * s)
    shadow.set()
    NSColor.black.setFill()
    squircle.fill()
    ctx.restoreGState()
    NSGradient(colors: [NSColor(srgbRed: 0.24, green: 0.24, blue: 0.26, alpha: 1),
                        NSColor(srgbRed: 0.07, green: 0.07, blue: 0.08, alpha: 1)])!
        .draw(in: squircle, angle: -90)

    // Soft blue glow behind the headphones (noise-cancelling hint).
    let glow = NSGradient(colors: [NSColor(srgbRed: 0.04, green: 0.52, blue: 1.0, alpha: 0.55),
                                   NSColor(srgbRed: 0.04, green: 0.52, blue: 1.0, alpha: 0.0)])!
    ctx.saveGState()
    squircle.addClip()
    glow.draw(fromCenter: NSPoint(x: 512 * s, y: 430 * s), radius: 0,
              toCenter: NSPoint(x: 512 * s, y: 430 * s), radius: 380 * s, options: [])
    ctx.restoreGState()

    let metal = NSGradient(colors: [NSColor(srgbRed: 0.98, green: 0.98, blue: 0.99, alpha: 1),
                                    NSColor(srgbRed: 0.74, green: 0.75, blue: 0.78, alpha: 1)])!

    // Headband: thick arc.
    let band = NSBezierPath()
    band.appendArc(withCenter: NSPoint(x: 512 * s, y: 470 * s), radius: 265 * s,
                   startAngle: 192, endAngle: -12, clockwise: true)
    band.lineWidth = 46 * s
    band.lineCapStyle = .round
    ctx.saveGState()
    ctx.addPath(band.cgPath)
    ctx.setLineWidth(46 * s)
    ctx.setLineCap(.round)
    ctx.replacePathWithStrokedPath()
    ctx.clip()
    metal.draw(in: NSRect(x: 200 * s, y: 420 * s, width: 624 * s, height: 340 * s), angle: -90)
    ctx.restoreGState()

    // Sliders connecting band and cups.
    for x in [262.0, 762.0] {
        let slider = NSBezierPath(roundedRect: NSRect(x: (x - 14) * s, y: 380 * s, width: 28 * s, height: 90 * s),
                                  xRadius: 14 * s, yRadius: 14 * s)
        NSColor(srgbRed: 0.62, green: 0.63, blue: 0.66, alpha: 1).setFill()
        slider.fill()
    }

    // Ear cups: tall rounded ovals, with a darker cushion on the inner side.
    for (x, inner) in [(262.0, 1.0), (762.0, -1.0)] {
        let cup = NSBezierPath(roundedRect: NSRect(x: (x - 78) * s, y: 215 * s, width: 156 * s, height: 225 * s),
                               xRadius: 78 * s, yRadius: 90 * s)
        metal.draw(in: cup, angle: -90)
        let cushion = NSBezierPath(roundedRect: NSRect(x: (x + inner * 40 - 34) * s, y: 232 * s,
                                                       width: 68 * s, height: 191 * s),
                                   xRadius: 34 * s, yRadius: 60 * s)
        NSColor(srgbRed: 0.16, green: 0.16, blue: 0.18, alpha: 1).setFill()
        cushion.fill()
    }

    NSGraphicsContext.restoreGraphicsState()
    return rep
}

let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
let iconset = root.appendingPathComponent("build/AppIcon.iconset")
try? FileManager.default.removeItem(at: iconset)
try! FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)
for base in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let px = CGFloat(base * scale)
        let name = scale == 1 ? "icon_\(base)x\(base).png" : "icon_\(base)x\(base)@2x.png"
        try! drawIcon(size: px).representation(using: .png, properties: [:])!
            .write(to: iconset.appendingPathComponent(name))
    }
}
try! drawIcon(size: 1024).representation(using: .png, properties: [:])!
    .write(to: root.appendingPathComponent("docs/icon.png"))
print(iconset.path)
