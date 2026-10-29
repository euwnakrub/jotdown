// สร้างไอคอนแอป Jot ด้วย AppKit: swift scripts/make-icon.swift <โฟลเดอร์.iconset> [fontsDir]
import AppKit
import CoreText

let args = CommandLine.arguments
guard args.count >= 2 else { print("usage: make-icon.swift <out.iconset> [fontsDir]"); exit(1) }
let out = URL(fileURLWithPath: args[1], isDirectory: true)
let fontsDir = args.count > 2 ? args[2] : URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("Resources/Fonts").path
try? FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
for f in (try? FileManager.default.contentsOfDirectory(atPath: fontsDir)) ?? [] where f.hasSuffix(".ttf") {
    CTFontManagerRegisterFontsForURL(URL(fileURLWithPath: fontsDir + "/" + f) as CFURL, .process, nil)
}

func render(_ px: Int) -> Data {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                               isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let s = CGFloat(px) / 1024
    // ตัวไอคอนตามสัดส่วน macOS: 824 ตรงกลางผืน 1024
    let body = NSRect(x: 100 * s, y: 100 * s, width: 824 * s, height: 824 * s)
    let path = NSBezierPath(roundedRect: body, xRadius: 184 * s, yRadius: 184 * s)
    NSGraphicsContext.saveGraphicsState()
    let shadow = NSShadow()
    shadow.shadowColor = NSColor.black.withAlphaComponent(0.28)
    shadow.shadowBlurRadius = 24 * s
    shadow.shadowOffset = NSSize(width: 0, height: -10 * s)
    shadow.set()
    NSColor(calibratedRed: 0.97, green: 0.95, blue: 0.90, alpha: 1).setFill()
    path.fill()
    NSGraphicsContext.restoreGraphicsState()
    // พื้นไล่เฉดครีมอ่อน ๆ
    NSGraphicsContext.saveGraphicsState()
    path.addClip()
    // พื้นไล่เฉดครีมอ่อน ๆ
    NSGradient(colors: [NSColor(calibratedRed: 1.0, green: 0.99, blue: 0.96, alpha: 1), NSColor(calibratedRed: 0.93, green: 0.90, blue: 0.83, alpha: 1)])!
        .draw(in: body, angle: -90)
    // ขอบในบาง ๆ
    NSColor.white.withAlphaComponent(0.55).setStroke()
    let inner = NSBezierPath(roundedRect: body.insetBy(dx: 1.5 * s, dy: 1.5 * s), xRadius: 183 * s, yRadius: 183 * s)
    inner.lineWidth = 3 * s; inner.stroke()
    NSGraphicsContext.restoreGraphicsState()

    // ตัว J
    let ink = NSColor(calibratedRed: 0.14, green: 0.13, blue: 0.12, alpha: 1)
    let font = NSFont(name: "IBMPlexSansThai-SemiBold", size: 560 * s) ?? NSFont.systemFont(ofSize: 560 * s, weight: .semibold)
    let str = NSAttributedString(string: "J", attributes: [.font: font, .foregroundColor: ink])
    let size = str.size()
    str.draw(at: NSPoint(x: body.midX - size.width / 2 - 6 * s, y: body.midY - size.height / 2 + 30 * s))
    // เส้นบรรทัดสีส้มอ่อนใต้ตัว J (เหมือนเคอร์เซอร์ที่ขีดเส้นใต้บรรทัด) (เหมือนเคอร์เซอร์ที่ขีดเส้นใต้บรรทัด)
    NSColor(calibratedRed: 0.89, green: 0.45, blue: 0.20, alpha: 1).setFill()
    NSBezierPath(roundedRect: NSRect(x: body.midX - 150 * s, y: body.minY + 150 * s, width: 300 * s, height: 26 * s), xRadius: 13 * s, yRadius: 13 * s).fill()
    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

for (name, px) in [("icon_16x16", 16), ("icon_16x16@2x", 32), ("icon_32x32", 32), ("icon_32x32@2x", 64), ("icon_128x128", 128), ("icon_128x128@2x", 256),
                   ("icon_256x256", 256), ("icon_256x256@2x", 512), ("icon_512x512", 512), ("icon_512x512@2x", 1024)] {
    try render(px).write(to: out.appendingPathComponent(name + ".png"))
}
print("สร้างไอคอนที่ \(out.path)")
