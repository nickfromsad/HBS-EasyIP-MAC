// Renders the HBS-style background of the .dmg install window (660×460 pt, @1x and @2x).
// macOS 26 Finder shows a tab bar that hides the bottom ~40 pt, so everything important sits in
// the top 420 pt and the footer band simply runs on below that.
//   swift scripts/make-dmg-background.swift <version> <output-dir>
// Layout must match scripts/dmg-settings.py (window size, icon centres).
import AppKit

let version = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "dev"
let outDir = URL(fileURLWithPath: CommandLine.arguments.count > 2 ? CommandLine.arguments[2] : "build/dmg")

let width: CGFloat = 660, height: CGFloat = 460
let footerTop: CGFloat = 368
let appCentre = NSPoint(x: 170, y: 200), applicationsCentre = NSPoint(x: 490, y: 200)

func color(_ hex: UInt32) -> NSColor {
    NSColor(srgbRed: CGFloat(hex >> 16 & 0xFF) / 255, green: CGFloat(hex >> 8 & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255, alpha: 1)
}

func draw(_ text: String, font: NSFont, color: NSColor, kern: CGFloat = 0, at point: NSPoint, centred: Bool = false) {
    let string = NSAttributedString(string: text, attributes: [.font: font, .foregroundColor: color, .kern: kern])
    let size = string.size()
    string.draw(at: NSPoint(x: centred ? point.x - size.width / 2 : point.x, y: point.y - size.height / 2))
}

func render(scale: CGFloat) -> NSBitmapImageRep {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(width * scale), pixelsHigh: Int(height * scale),
                               bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                               colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    let cg = NSGraphicsContext(bitmapImageRep: rep)!.cgContext
    // Top-left origin, like Finder's icon coordinates.
    cg.translateBy(x: 0, y: height * scale)
    cg.scaleBy(x: scale, y: -scale)
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(cgContext: cg, flipped: true)

    // Body
    color(0x1E1E1E).setFill()
    NSRect(x: 0, y: 0, width: width, height: height).fill()

    // Header band: //HBS | EasyIP MAC  v0.1.0
    color(0x141414).setFill()
    NSRect(x: 0, y: 0, width: width, height: 64).fill()
    let arialBold = NSFont(name: "Arial-BoldMT", size: 22) ?? .boldSystemFont(ofSize: 22)
    let arial = NSFont(name: "ArialMT", size: 14) ?? .systemFont(ofSize: 14)
    draw("//HBS", font: arialBold, color: color(0xD4D4D4), kern: 3, at: NSPoint(x: 28, y: 32))
    color(0x444444).setFill()
    NSRect(x: 124, y: 18, width: 1, height: 28).fill()
    draw("EasyIP MAC", font: arial, color: color(0x909090), at: NSPoint(x: 138, y: 32))
    draw("v\(version)", font: .systemFont(ofSize: 11), color: color(0x555555), at: NSPoint(x: 226, y: 33))
    draw("Panasonic PTZ camera finder for macOS", font: .systemFont(ofSize: 11), color: color(0x686868),
         at: NSPoint(x: width - 28 - 205, y: 33))

    // Arrow from the app to Applications.
    let arrowY = appCentre.y
    let arrow = NSBezierPath()
    arrow.move(to: NSPoint(x: appCentre.x + 92, y: arrowY))
    arrow.line(to: NSPoint(x: applicationsCentre.x - 98, y: arrowY))
    arrow.lineWidth = 3
    arrow.lineCapStyle = .round
    arrow.setLineDash([2, 9], count: 2, phase: 0)
    color(0x707070).setStroke()
    arrow.stroke()
    let head = NSBezierPath()
    head.move(to: NSPoint(x: applicationsCentre.x - 104, y: arrowY - 11))
    head.line(to: NSPoint(x: applicationsCentre.x - 92, y: arrowY))
    head.line(to: NSPoint(x: applicationsCentre.x - 104, y: arrowY + 11))
    head.lineWidth = 3
    head.lineCapStyle = .round
    head.lineJoinStyle = .round
    color(0xC8C8C8).setStroke()
    head.stroke()

    // Light tags behind Finder's icon labels: over a background picture Finder draws the
    // label text in black, also in Dark mode, so it needs a light plate to stay readable.
    for centre in [appCentre, applicationsCentre] {
        let tag = NSRect(x: centre.x - 72, y: centre.y + 71, width: 144, height: 24)
        color(0xC8C8C8).setFill()
        NSBezierPath(roundedRect: tag, xRadius: 4, yRadius: 4).fill()
    }

    // Instruction
    draw("Drag the app to Applications to install", font: .systemFont(ofSize: 14, weight: .semibold),
         color: color(0xD4D4D4), at: NSPoint(x: width / 2, y: 330), centred: true)

    // Footer band with the first-launch tip.
    color(0x181818).setFill()
    NSRect(x: 0, y: footerTop, width: width, height: height - footerTop).fill()
    color(0x2A2A2A).setFill()
    NSRect(x: 0, y: footerTop, width: width, height: 1).fill()
    draw("First launch:  System Settings  →  Privacy & Security  →  Open Anyway,  then allow Local Network",
         font: .systemFont(ofSize: 11), color: color(0x909090), at: NSPoint(x: 28, y: footerTop + 18))
    draw("hofbroadcast.nl", font: .systemFont(ofSize: 10), color: color(0x555555), at: NSPoint(x: 28, y: footerTop + 35))

    NSGraphicsContext.restoreGraphicsState()
    // Only now mark the point size (→ 144 dpi for @2x); set before drawing, AppKit would scale twice.
    rep.size = NSSize(width: width, height: height)
    return rep
}

// @1x and @2x PNGs; build-app.sh combines them with `tiffutil -cathidpicheck` into the
// multi-resolution TIFF Finder needs for a sharp background on Retina screens.
try FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)
for (scale, name) in [(1.0, "background.png"), (2.0, "background@2x.png")] {
    try render(scale: scale).representation(using: .png, properties: [:])!.write(to: outDir.appendingPathComponent(name))
}
print("wrote \(outDir.path)/background.png, background@2x.png")
