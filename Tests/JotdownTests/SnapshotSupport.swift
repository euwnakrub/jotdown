import AppKit
import SwiftUI
import Testing

// แม่แบบ snapshot offscreen (ยกมาจาก TA Studio) วางใน Tests/<App>Tests/
// ใช้: let shot = try snapshot("export-tab", size: CGSize(width: 900, height: 700)) { ExportTab(model: m) }
//      #expect(shot.fitting.width <= 900)   // ไม่ล้นความกว้างหน้าต่าง
// PNG ไปที่ $APP_SNAPSHOT_DIR (ค่าเริ่มต้น build/snapshots/ ของโปรเจกต์) แล้ว lead เปิดดูด้วยตาทุกครั้ง

/// หน้าต่างที่ macOS ไม่บีบให้เล็กลงตามความสูงจอ (ไม่งั้น 1600x1000 ถูกตัดบนจอเล็ก)
final class UnconstrainedWindow: NSWindow {
    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect { frameRect }
}

/// Tests/JotdownTests/SnapshotSupport.swift -> root ของโปรเจกต์
let projectRoot = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()

enum SnapshotDir {
    static let url: URL = {
        let d = ProcessInfo.processInfo.environment["APP_SNAPSHOT_DIR"].map { URL(fileURLWithPath: $0) }
            ?? projectRoot.appendingPathComponent("build/snapshots", isDirectory: true)
        try? FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
        return d
    }()
}

struct Shot { var fitting: CGSize; var png: URL; var image: NSBitmapImageRep }

/// snapshot ของ NSViewController (AppKit) — ธีม .aqua หรือ .darkAqua
@MainActor
func snapshot(_ name: String, size: CGSize, appearance: NSAppearance.Name = .aqua, after: (() -> Void)? = nil,
              viewController controller: NSViewController) throws -> Shot {
    _ = NSApplication.shared
    let window = UnconstrainedWindow(contentRect: NSRect(origin: .zero, size: size), styleMask: [.borderless], backing: .buffered, defer: false)
    window.isReleasedWhenClosed = false
    window.animationBehavior = .none
    window.appearance = NSAppearance(named: appearance)
    window.contentViewController = controller
    window.alphaValue = 0
    window.orderFrontRegardless()
    window.setContentSize(size)
    if let v = NSScreen.main?.visibleFrame { window.setFrameTopLeftPoint(NSPoint(x: v.minX, y: v.maxY)) }
    let host = controller.view
    host.frame = NSRect(origin: .zero, size: size)
    spin(0.4, host)
    after?()
    spin(0.4, host)
    let rep = try #require(host.bitmapImageRepForCachingDisplay(in: host.bounds))
    host.cacheDisplay(in: host.bounds, to: rep)
    let tag = appearance == .darkAqua ? "dark" : "aqua"
    let png = SnapshotDir.url.appendingPathComponent("\(name)-\(tag)-\(Int(size.width))x\(Int(size.height)).png")
    try #require(rep.representation(using: .png, properties: [:])).write(to: png)
    window.contentViewController = nil
    window.close()
    return Shot(fitting: size, png: png, image: rep)
}

@MainActor
func snapshot<V: View>(_ name: String, size: CGSize, after: (() -> Void)? = nil, @ViewBuilder _ content: () -> V) throws -> Shot {
    _ = NSApplication.shared
    let controller = NSHostingController(rootView: content())
    controller.sizingOptions = []
    let host = controller.view
    let window = UnconstrainedWindow(contentRect: NSRect(origin: .zero, size: size), styleMask: [.borderless], backing: .buffered, defer: false)
    window.isReleasedWhenClosed = false
    // สำคัญ: ไม่ปิดแอนิเมชัน = worker thread ค้างสะสมจนเทสต์ที่เหลือหยุดรอทั้งชุด
    window.animationBehavior = .none
    // บังคับธีมสว่าง ไม่งั้นเครื่องที่อยู่ dark mode ได้ตัวขาวบนพื้นขาว
    window.appearance = NSAppearance(named: .aqua)
    window.contentViewController = controller
    window.alphaValue = 0              // มองไม่เห็นแต่ AppKit ถือว่าแสดงอยู่ (List/sidebar วาดได้)
    window.orderFrontRegardless()
    window.setContentSize(size)
    // ชิดมุมซ้ายบน ไม่ทับแถบเมนู (ไม่งั้นมี safe area 20pt ทำ layout เพี้ยน)
    if let v = NSScreen.main?.visibleFrame { window.setFrameTopLeftPoint(NSPoint(x: v.minX, y: v.maxY)) }
    host.frame = NSRect(origin: .zero, size: size)
    spin(0.5, host)
    after?()
    spin(0.5, host)
    // ความกว้างต่ำสุดที่เนื้อหายอมหด: มากกว่าหน้าต่าง = ล้น
    let fitting = controller.sizeThatFits(in: CGSize(width: 1, height: size.height))
    let rep = try #require(host.bitmapImageRepForCachingDisplay(in: host.bounds))
    host.cacheDisplay(in: host.bounds, to: rep)
    let png = SnapshotDir.url.appendingPathComponent("\(name)-\(Int(size.width))x\(Int(size.height)).png")
    try #require(rep.representation(using: .png, properties: [:])).write(to: png)
    window.contentViewController = nil
    window.close()
    return Shot(fitting: fitting, png: png, image: rep)
}

@MainActor
func spin(_ t: TimeInterval, _ host: NSView) {
    let end = Date().addingTimeInterval(t)
    while Date() < end {
        RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.02))
        host.layoutSubtreeIfNeeded()
    }
}


/// snapshot ของ view ที่ไม่มีหน้าต่างพื้นหลัง (เช่น contentView ของ sheet): วาดสีพื้นหน้าต่างตามธีมก่อน
/// (เดิมพื้นโปร่งใสกลายเป็นขาวในไฟล์ PNG ทำให้ตัวอักษรสีอ่อนของโหมดมืดมองไม่เห็น — พังเฉพาะ snapshot ไม่ใช่แอปจริง)
@MainActor
func snapshotWithWindowBackground(_ v: NSView, appearance: NSAppearance.Name, to url: URL) throws {
    let ap = NSAppearance(named: appearance)!
    v.appearance = ap
    v.layoutSubtreeIfNeeded()
    let fg = try #require(v.bitmapImageRepForCachingDisplay(in: v.bounds))
    v.cacheDisplay(in: v.bounds, to: fg)
    let w = fg.pixelsWide, h = fg.pixelsHigh
    let cs = CGColorSpace(name: CGColorSpace.sRGB)!
    let ctx = try #require(CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0, space: cs, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
    // สีพื้นหน้าต่างตามธีม (ค่าตรง ๆ เพราะ NSColor.windowBackgroundColor นอกหน้าต่างจริงแปลงเป็นสีผิดได้)
    let g: CGFloat = appearance == .darkAqua ? 0.17 : 0.93
    ctx.setFillColor(CGColor(srgbRed: g, green: g, blue: g + (appearance == .darkAqua ? 0.01 : 0), alpha: 1))
    ctx.fill(CGRect(x: 0, y: 0, width: w, height: h))
    if let cg = fg.cgImage { ctx.draw(cg, in: CGRect(x: 0, y: 0, width: w, height: h)) }
    let out = NSBitmapImageRep(cgImage: try #require(ctx.makeImage()))
    try #require(out.representation(using: .png, properties: [:])).write(to: url)
}
