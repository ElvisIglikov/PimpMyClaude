import AppKit

// Значок приложения PMP: фиолетовый бейдж на графите (WF119, #8609).
// Перерисовать на сборочном M1: swift make-appicon.swift AppIcon.iconset
//                            iconutil -c icns AppIcon.iconset -o AppIcon.icns
// Рисуем прямо в битмап нужного размера (lockFocus на Retina удвоил бы пиксели).
let out = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "AppIcon.iconset"
try? FileManager.default.createDirectory(atPath: out, withIntermediateDirectories: true)
let names: [Int: [String]] = [
    16: ["icon_16x16"], 32: ["icon_16x16@2x", "icon_32x32"], 64: ["icon_32x32@2x"],
    128: ["icon_128x128"], 256: ["icon_128x128@2x", "icon_256x256"],
    512: ["icon_256x256@2x", "icon_512x512"], 1024: ["icon_512x512@2x"],
]

func color(_ hex: UInt32, _ alpha: CGFloat = 1) -> NSColor {
    NSColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255, alpha: alpha)
}

func rounded(_ size: CGFloat, _ weight: NSFont.Weight) -> NSFont {
    let base = NSFont.systemFont(ofSize: size, weight: weight)
    guard let descriptor = base.fontDescriptor.withDesign(.rounded) else { return base }
    return NSFont(descriptor: descriptor, size: size) ?? base
}

for (px, files) in names {
    guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px,
                                     bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                     colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0) else { continue }
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let side = CGFloat(px), inset = side * 0.09
    let box = NSRect(x: inset, y: inset, width: side - inset * 2, height: side - inset * 2)
    let shape = NSBezierPath(roundedRect: box, xRadius: box.width * 0.225, yRadius: box.width * 0.225)
    color(0x1C1C1E).setFill()
    shape.fill()
    // Обводка — как у панели.
    color(0x3A3A3D).setStroke()
    shape.lineWidth = max(1, side * 0.008)
    shape.stroke()

    // Бейдж «PMP» — фиолетовый, без свечения и градиента.
    let badgeW = box.width * 0.70, badgeH = box.width * 0.40
    let badge = NSRect(x: box.midX - badgeW / 2, y: box.midY - badgeH / 2, width: badgeW, height: badgeH)
    let badgePath = NSBezierPath(roundedRect: badge, xRadius: badgeH * 0.28, yRadius: badgeH * 0.28)
    color(0xB56AFB).setFill()
    badgePath.fill()

    let font = rounded(badgeH * 0.56, .heavy)
    let text = NSAttributedString(string: "PMP", attributes: [.font: font, .foregroundColor: color(0x1C1C1E),
                                                              .kern: badgeH * 0.02])
    let size = text.size()
    text.draw(at: NSPoint(x: badge.midX - size.width / 2,
                          y: badge.midY - font.capHeight / 2 + font.descender))
    NSGraphicsContext.restoreGraphicsState()
    guard let png = rep.representation(using: .png, properties: [:]) else { continue }
    for file in files { try png.write(to: URL(fileURLWithPath: "\(out)/\(file).png")) }
}
