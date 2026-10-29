import Testing
import AppKit
@testable import Jotdown

/// ไฮไลต์ตอนเลือกข้อความในเซลล์ตาราง (หัวตารางและเซลล์ปกติ) ต้องไม่ล้นเส้นขอบเซลล์
/// สาเหตุเดิม: EditorLayoutManager ฟิลล์ `boundsRect(for: block)` ทั้งช่องทุกครั้งที่เลือกข้อความในช่อง และ rect นั้นรวม margin
/// (หัวตารางมี margin บน 6pt, แถวสุดท้ายมี margin ล่าง 10pt) จึงล้นออกนอกเส้นขอบ
@MainActor @Suite(.serialized) struct TableSelectionTests {
    static let md = "Intro paragraph\n\n| Heading one | Heading two | Third |\n| --- | --- | --- |\n| alpha beta | gamma | delta |\n\nOutro\n"

    func snap(_ name: String, _ ap: NSAppearance.Name, select: @escaping (EditorTextView) -> Void) throws -> (Shot, EditorTextView) {
        _ = NSApplication.shared
        Fonts.registerAll()
        let doc = JotdownDocument(); doc.load(markdown: Self.md)
        let vc = EditorViewController(document: doc); _ = vc.view
        let tv = vc.textView!
        let s = try snapshot(name, size: CGSize(width: 900, height: 500), appearance: ap, after: {
            tv.window?.makeFirstResponder(tv)
            select(tv)
        }, viewController: vc)
        return (s, tv)
    }

    /// ขอบเขต (พิกัด view) ภายในเส้นขอบของทุกเซลล์ที่ฟิลล์ได้ + กรอบนอกสุดของตาราง
    func cellRects(_ tv: EditorTextView) -> (inner: [NSRect], outer: NSRect) {
        let lm = tv.layoutManager as! EditorLayoutManager
        let o = tv.textContainerOrigin
        var inner: [NSRect] = [], outer = NSRect.null
        tv.storage.enumerateAttribute(.paragraphStyle, in: NSRange(location: 0, length: tv.storage.length), options: []) { v, r, _ in
            guard let b = (v as? NSParagraphStyle)?.textBlocks.first as? NSTextTableBlock else { return }
            let raw = lm.boundsRect(for: b, glyphRange: lm.glyphRange(forCharacterRange: r, actualCharacterRange: nil))
            inner.append(EditorLayoutManager.cellFillRect(raw, block: b).offsetBy(dx: o.x, dy: o.y))
            outer = outer.union(raw.offsetBy(dx: o.x, dy: o.y))
        }
        return (inner, outer)
    }

    /// จำนวนพิกเซลที่ต่างจากภาพฐาน (ไม่มี selection) ภายใน/นอกกรอบที่กำหนด — กรอบอยู่ในพิกัด view (จุด)
    /// เทียบกับภาพฐานแทนการจับสีไฮไลต์: หน้าต่าง offscreen ไม่ใช่ key window ระบบจึงวาด selection เป็นสีเทา (ในแอปจริงเป็นสีเหลือง)
    func changedPixels(_ shot: Shot, base: Shot, inside rects: [NSRect]) -> (inside: Int, outside: Int) {
        let rep = shot.image, ref = base.image
        let scale = CGFloat(rep.pixelsWide) / 900
        var inside = 0, outside = 0
        for y in 0..<rep.pixelsHigh {
            for x in 0..<rep.pixelsWide {
                guard let c = rep.colorAt(x: x, y: y)?.usingColorSpace(.sRGB), let d = ref.colorAt(x: x, y: y)?.usingColorSpace(.sRGB) else { continue }
                if abs(c.redComponent - d.redComponent) + abs(c.greenComponent - d.greenComponent) + abs(c.blueComponent - d.blueComponent) < 0.02 { continue }
                let p = NSPoint(x: (CGFloat(x) + 0.5) / scale, y: (CGFloat(y) + 0.5) / scale)
                if rects.contains(where: { $0.insetBy(dx: -0.75, dy: -0.75).contains(p) }) { inside += 1 } else { outside += 1 }
            }
        }
        return (inside, outside)
    }

    func check(_ ap: NSAppearance.Name, name: String, select: @escaping (EditorTextView) -> Void, expectFullCell: Bool) throws {
        let (s, tv) = try snap(name, ap, select: select)
        let (base, _) = try snap("table-selection-baseline", ap, select: { $0.setSelectedRange(NSRange(location: 0, length: 0)) })
        let rects = cellRects(tv)
        let n = changedPixels(s, base: base, inside: rects.inner)
        #expect(n.inside > 100, Comment(rawValue: "ไม่เห็นไฮไลต์เลย \(n)"))
        #expect(n.outside == 0, Comment(rawValue: "ไฮไลต์ล้นนอกขอบเซลล์ \(n) \(name)"))
        if expectFullCell {
            // ฟิลล์ทั้งช่อง: พื้นที่ฟิลล์ใหญ่กว่าตัวหนังสือมาก
            let h = rects.inner.first!
            #expect(Double(n.inside) > Double(h.width * h.height) * 4 * 0.5)
        } else {
            // ข้อความปกติ: ไม่ฟิลล์ทั้งช่อง (น้อยกว่าพื้นที่ช่องแรกมาก)
            let h = rects.inner.first!
            #expect(Double(n.inside) < Double(h.width * h.height) * 4 * 0.6)
        }
    }

    static func selectWord(_ w: String) -> (EditorTextView) -> Void {
        { tv in tv.setSelectedRange(tv.nsString.range(of: w)) }
    }
    static func selectTable(_ tv: EditorTextView) { tv.select(tv.nsString.range(of: "Heading").location); tv.jotSelectTable(nil) }

    @Test func headerWordAqua() throws { try check(.aqua, name: "table-header-selection", select: Self.selectWord("Heading"), expectFullCell: false) }
    @Test func headerWordDark() throws { try check(.darkAqua, name: "table-header-selection", select: Self.selectWord("Heading"), expectFullCell: false) }
    @Test func bodyWordAqua() throws { try check(.aqua, name: "table-body-selection", select: Self.selectWord("beta"), expectFullCell: false) }
    @Test func bodyWordDark() throws { try check(.darkAqua, name: "table-body-selection", select: Self.selectWord("beta"), expectFullCell: false) }
    @Test func wholeTableAqua() throws { try check(.aqua, name: "table-all-selection", select: Self.selectTable, expectFullCell: true) }
    @Test func wholeTableDark() throws { try check(.darkAqua, name: "table-all-selection", select: Self.selectTable, expectFullCell: true) }

    @Test func coverageRule() {
        let ns = "abc\nxyz\n" as NSString
        let pr = NSRange(location: 4, length: 4)       // "xyz\n"
        #expect(!EditorLayoutManager.selectionCoversCell(NSRange(location: 4, length: 3), paragraph: pr, in: ns))   // เนื้อหาช่องเดียวพอดี
        #expect(!EditorLayoutManager.selectionCoversCell(NSRange(location: 5, length: 1), paragraph: pr, in: ns))
        #expect(EditorLayoutManager.selectionCoversCell(NSRange(location: 0, length: 8), paragraph: pr, in: ns))
        #expect(EditorLayoutManager.selectionCoversCell(NSRange(location: 2, length: 6), paragraph: pr, in: ns))
    }
}
