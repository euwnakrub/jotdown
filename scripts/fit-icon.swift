// ปรับไอคอนที่ออกแบบเองให้ขนาดเท่าไอคอนแอป Mac อื่น
// อ่าน PNG 1024 → ตัดพื้นที่โปร่งใสรอบนอก → ย่อให้รูปทรงกว้าง 824px (ตาม grid ของ Apple) วางกลางผืน 1024
// แล้วสร้าง iconset ครบ 10 ขนาด
//   swift scripts/fit-icon.swift <source-1024.png> <out.iconset>
import AppKit

let args = CommandLine.arguments
guard args.count == 3, let src = NSBitmapImageRep(data: (try? Data(contentsOf: URL(fileURLWithPath: args[1]))) ?? Data()) else {
    FileHandle.standardError.write("usage: fit-icon.swift <source.png> <out.iconset>\n".data(using: .utf8)!)
    exit(1)
}
let outDir = URL(fileURLWithPath: args[2])

// กรอบของส่วนที่ไม่โปร่งใส (alpha > 0.5)
var minX = src.pixelsWide, minY = src.pixelsHigh, maxX = 0, maxY = 0
for y in 0..<src.pixelsHigh {
    for x in 0..<src.pixelsWide where (src.colorAt(x: x, y: y)?.alphaComponent ?? 0) > 0.5 {
        minX = min(minX, x); maxX = max(maxX, x); minY = min(minY, y); maxY = max(maxY, y)
    }
}
guard maxX > minX, maxY > minY else { print("icon is fully transparent"); exit(1) }
let cropW = CGFloat(maxX - minX + 1), cropH = CGFloat(maxY - minY + 1)

// พิกัด bitmap นับจากบน, NSImage วาดนับจากล่าง
let srcImage = NSImage(size: NSSize(width: src.pixelsWide, height: src.pixelsHigh))
srcImage.addRepresentation(src)
let cropRect = NSRect(x: CGFloat(minX), y: CGFloat(src.pixelsHigh - 1 - maxY), width: cropW, height: cropH)

func render(_ px: Int) -> Data {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px, bitsPerSample: 8,
                               samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                               colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    rep.size = NSSize(width: px, height: px)
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    NSGraphicsContext.current?.imageInterpolation = .high
    let canvas = CGFloat(px)
    let scale = canvas * (824.0 / 1024.0) / max(cropW, cropH)
    let w = cropW * scale, h = cropH * scale
    srcImage.draw(in: NSRect(x: (canvas - w) / 2, y: (canvas - h) / 2, width: w, height: h),
                  from: cropRect, operation: .copy, fraction: 1)
    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

try? FileManager.default.removeItem(at: outDir)
try FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)
for base in [16, 32, 128, 256, 512] {
    try render(base).write(to: outDir.appendingPathComponent("icon_\(base)x\(base).png"))
    try render(base * 2).write(to: outDir.appendingPathComponent("icon_\(base)x\(base)@2x.png"))
}
