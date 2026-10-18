// Renders Resources/AppIcon.icns. Only needed when changing the icon:
//   swift scripts/make-icon.swift && iconutil -c icns build/AppIcon.iconset -o Resources/AppIcon.icns
import AppKit

func render(size: CGFloat) -> NSBitmapImageRep {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size), pixelsHigh: Int(size), bitsPerSample: 8,
                               samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                               bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let s = size / 1024

    // macOS icon grid: 824pt rounded square centred on a 1024 canvas.
    let tile = NSRect(x: 100 * s, y: 100 * s, width: 824 * s, height: 824 * s)
    let shape = NSBezierPath(roundedRect: tile, xRadius: 185 * s, yRadius: 185 * s)
    NSGradient(starting: NSColor(red: 0.13, green: 0.16, blue: 0.22, alpha: 1),
               ending: NSColor(red: 0.04, green: 0.05, blue: 0.08, alpha: 1))!.draw(in: shape, angle: -90)

    // Scanning arcs.
    let centre = NSPoint(x: 512 * s, y: 470 * s)
    NSColor(red: 1.0, green: 0.62, blue: 0.10, alpha: 1).setStroke()
    for (index, radius) in [250.0, 330.0].enumerated() {
        let arc = NSBezierPath()
        arc.appendArc(withCenter: centre, radius: radius * s, startAngle: 35, endAngle: 145)
        arc.lineWidth = 34 * s
        arc.lineCapStyle = .round
        NSColor(red: 1.0, green: 0.62, blue: 0.10, alpha: index == 0 ? 1 : 0.55).setStroke()
        arc.stroke()
    }

    // Dome camera: base plate, half-sphere dome, lens.
    NSColor.white.setFill()
    NSBezierPath(roundedRect: NSRect(x: 292 * s, y: 250 * s, width: 440 * s, height: 56 * s), xRadius: 28 * s, yRadius: 28 * s).fill()
    let dome = NSBezierPath()
    dome.appendArc(withCenter: NSPoint(x: 512 * s, y: 322 * s), radius: 190 * s, startAngle: 0, endAngle: 180)
    dome.close()
    dome.fill()
    let lens = NSPoint(x: 512 * s, y: 410 * s)
    NSColor(red: 0.06, green: 0.07, blue: 0.10, alpha: 1).setFill()
    NSBezierPath(ovalIn: NSRect(x: lens.x - 70 * s, y: lens.y - 70 * s, width: 140 * s, height: 140 * s)).fill()
    NSColor(red: 1.0, green: 0.62, blue: 0.10, alpha: 1).setFill()
    NSBezierPath(ovalIn: NSRect(x: lens.x - 30 * s, y: lens.y - 30 * s, width: 60 * s, height: 60 * s)).fill()
    NSGraphicsContext.restoreGraphicsState()
    return rep
}

let iconset = URL(fileURLWithPath: "build/AppIcon.iconset")
try? FileManager.default.removeItem(at: iconset)
try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)
for base in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let name = scale == 1 ? "icon_\(base)x\(base).png" : "icon_\(base)x\(base)@2x.png"
        let png = render(size: CGFloat(base * scale)).representation(using: .png, properties: [:])!
        try png.write(to: iconset.appendingPathComponent(name))
    }
}
print("wrote \(iconset.path)")
