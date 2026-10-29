import Testing
import AppKit
@testable import Jotdown

@MainActor @Suite(.serialized) struct EditorSnapshotTests {
    func snap(_ size: CGSize, _ appearance: NSAppearance.Name, fixtureName: String = "thai-canonical", name: String = "editor-thai") throws {
        _ = NSApplication.shared
        Fonts.registerAll()
        let doc = JotdownDocument()
        doc.load(markdown: try fixture(fixtureName))
        let vc = EditorViewController(document: doc)
        _ = vc.view
        let shot = try snapshot(name, size: size, appearance: appearance, viewController: vc)
        #expect(FileManager.default.fileExists(atPath: shot.png.path))
        let tv = vc.textView!
        // ไม่ล้น: กล่องข้อความอยู่ในกรอบ และเนื้อความกว้างไม่เกิน 720
        #expect(tv.frame.width <= size.width + 0.5)
        let used = tv.layoutManager!.usedRect(for: tv.textContainer!)
        #expect(used.width <= Theme.columnMaxWidth + 0.5)
        #expect(tv.textContainerInset.width * 2 + used.width <= size.width + 0.5)
        // ไม่เป็นภาพว่าง
        let all = shot.image.bitmapData.map { Array(UnsafeBufferPointer(start: $0, count: shot.image.bytesPerRow * shot.image.pixelsHigh)) } ?? []
        #expect(Set(all).count > 3)
    }

    @Test func allAqua900() throws { try snap(CGSize(width: 900, height: 700), .aqua, fixtureName: "full-canonical", name: "editor-all") }
    @Test func allAqua480() throws { try snap(CGSize(width: 480, height: 360), .aqua, fixtureName: "full-canonical", name: "editor-all") }
    @Test func allDark900() throws { try snap(CGSize(width: 900, height: 700), .darkAqua, fixtureName: "full-canonical", name: "editor-all") }
    @Test func allDark480() throws { try snap(CGSize(width: 480, height: 360), .darkAqua, fixtureName: "full-canonical", name: "editor-all") }
    /// ภาพสูงเพื่อดูทั้งเอกสาร (ใช้ตรวจด้วยตา)
    @Test func allTall() throws { try snap(CGSize(width: 900, height: 1500), .aqua, fixtureName: "full-canonical", name: "editor-all-tall") }
    @Test func allTallDark() throws { try snap(CGSize(width: 900, height: 1500), .darkAqua, fixtureName: "full-canonical", name: "editor-all-tall") }
    @Test func aqua900() throws { try snap(CGSize(width: 900, height: 700), .aqua) }
    @Test func aqua480() throws { try snap(CGSize(width: 480, height: 360), .aqua) }
    @Test func dark900() throws { try snap(CGSize(width: 900, height: 700), .darkAqua) }
    @Test func dark480() throws { try snap(CGSize(width: 480, height: 360), .darkAqua) }
}
