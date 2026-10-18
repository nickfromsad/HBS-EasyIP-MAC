// Renders Resources/AppIcon.icns: the HOF Broadcast Services circle from the HBS family
// (Resources/hbs-logo-256.png, the same logo as the ATEM Auto Switcher) with an "IP" badge
// in place of "CAM1". Only needed when changing the icon:
//   swift scripts/make-icon.swift && iconutil -c icns build/AppIcon.iconset -o Resources/AppIcon.icns
import AppKit

let logo = NSImage(contentsOfFile: "Resources/hbs-logo-256.png")!
let badgeRed = NSColor(red: 0.882, green: 0.369, blue: 0.353, alpha: 1)
let logoBlack = NSColor(srgbRed: 0.0157, green: 0.0221, blue: 0.0254, alpha: 1)   // the logo's circle colour

func render(size: CGFloat) -> NSBitmapImageRep {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size), pixelsHigh: Int(size), bitsPerSample: 8,
                               samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                               bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    let context = NSGraphicsContext(bitmapImageRep: rep)!
    NSGraphicsContext.current = context
    context.imageInterpolation = .high

    // macOS icon grid: an 824/1024 rounded square. Icons of any other shape get put on a
    // white plate by macOS 26, so the HOF circle sits on a dark HBS tile.
    let px = size / 1024
    let tile = NSRect(x: 100 * px, y: 100 * px, width: 824 * px, height: 824 * px)
    let tilePath = NSBezierPath(roundedRect: tile, xRadius: 185 * px, yRadius: 185 * px)
    NSGradient(starting: NSColor(srgbRed: 0.17, green: 0.17, blue: 0.17, alpha: 1),
               ending: NSColor(srgbRed: 0.08, green: 0.08, blue: 0.08, alpha: 1))!.draw(in: tilePath, angle: -90)
    NSColor(white: 1, alpha: 0.08).setStroke()
    tilePath.lineWidth = 4 * px
    tilePath.stroke()

    let circle = NSRect(x: 172 * px, y: 196 * px, width: 680 * px, height: 680 * px)
    let unit = circle.width / 256   // one pixel of the 256 px source logo

    // Circle in the logo's own black, then the logo with its original CAM1 badge masked out.
    logoBlack.setFill()
    NSBezierPath(ovalIn: circle).fill()
    // Badge in the source spans x 123…247, y 186…243 (top-down) plus its white border.
    let badgeInSource = NSRect(x: 115, y: 256 - 251, width: 141, height: 73)
    let mask = NSBezierPath(rect: circle)
    mask.append(NSBezierPath(rect: NSRect(x: circle.minX + badgeInSource.minX * unit, y: circle.minY + badgeInSource.minY * unit,
                                          width: badgeInSource.width * unit, height: badgeInSource.height * unit)))
    mask.windingRule = .evenOdd
    NSGraphicsContext.saveGraphicsState()
    mask.addClip()
    logo.draw(in: circle)
    NSGraphicsContext.restoreGraphicsState()

    // New "IP" badge, same red and white rim as the CAM1 badge, anchored bottom-right.
    let badge = NSRect(x: circle.minX + 150 * unit, y: circle.minY + 2 * unit, width: 100 * unit, height: 60 * unit)
    let rim = NSBezierPath(roundedRect: badge.insetBy(dx: -4 * unit, dy: -4 * unit), xRadius: 14 * unit, yRadius: 14 * unit)
    NSColor.white.setFill()
    rim.fill()
    badgeRed.setFill()
    NSBezierPath(roundedRect: badge, xRadius: 10 * unit, yRadius: 10 * unit).fill()
    let font = NSFont(name: "Arial Black", size: 40 * unit) ?? .systemFont(ofSize: 40 * unit, weight: .black)
    let text = NSAttributedString(string: "IP", attributes: [.font: font, .foregroundColor: NSColor.white, .kern: 1.5 * unit])
    let textSize = text.size()
    text.draw(at: NSPoint(x: badge.midX - textSize.width / 2, y: badge.midY - textSize.height / 2 + 1 * unit))

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
