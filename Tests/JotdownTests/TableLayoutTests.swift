import Testing
import AppKit
@testable import Jotdown

/// ตรวจตำแหน่งจริงหลัง layout: ทุกเซลล์ต้องอยู่ในคอลัมน์ของตัวเอง ไม่ว่าเซลล์ไหนสูงสุด (เนื้อหาสังเคราะห์ ไม่ใช้ข้อมูลจริงของใคร)
@MainActor @Suite(.serialized) struct TableLayoutTests {
    static let longThai = "ข้อความภาษาไทยที่ยาวพอจะตัดขึ้นบรรทัดใหม่หลายครั้งภายในช่องเดียวของตาราง เพื่อให้ช่องนี้สูงกว่าช่องอื่นในแถวเดียวกัน"
    /// ประโยคทั่วไป (สังเคราะห์) ที่ทำให้คอลัมน์แรกสูงมากเมื่อซ้ำ 3 ครั้ง — ความยาว/คำเฉพาะมีผลต่อการจำลองบั๊กเดิมของ NSTextTable
    static let tallThai = "การเรียนรู้ภาษาไทยต้องอาศัยการฝึกฝนอย่างสม่ำเสมอและการอ่านหนังสือหลากหลายประเภทเพื่อเพิ่มพูนคลังคำศัพท์ของตนเอง"
    static let code1 = "`scripts/example_long_file_name.py`", code2 = "`data/sample-folder/<ชื่อ>.txt`"

    /// ตาราง 3 คอลัมน์ที่คอลัมน์ `tall` (0/1/2) สูงสุดในบางแถว
    static func table3(tall: Int) -> String {
        func cell(_ c: Int, _ r: Int) -> String {
            let big = (c == tall && r % 2 == 1)
            switch c {
            case 0: return big ? "ขั้น \(r) \(longThai) \(longThai)" : "ขั้น \(r)"
            case 1: return big ? "\(code1) แล้วตามด้วย \(code2) \(longThai)" : code1
            default: return big ? "เสร็จ \(longThai) \(code2) ต่อด้วยข้อความภาษาอังกฤษ some English words" : "เสร็จ"
            }
        }
        var md = "| ขั้น | ไฟล์ | สถานะ |\n| --- | --- | --- |\n"
        for r in 1...5 { md += "| \(cell(0, r)) | \(cell(1, r)) | \(cell(2, r)) |\n" }
        return md
    }

    /// โครงตารางที่เคยพัง: คอลัมน์ 1 สูงสุด คอลัมน์ 3 ยาวหลายบรรทัดแต่สั้นกว่า คอลัมน์ 2 เป็นโค้ด
    static func tablePipelineLike() -> String {
        let c1 = "\(tallThai) \(tallThai) \(tallThai)"
        return """
        | ขั้น | ไฟล์ | สถานะ |
        | --- | --- | --- |
        | A เริ่มต้น | `scripts/step_one.py` | เสร็จ |
        | B \(c1) | `scripts/step_two.py` | เสร็จ ลองกับไฟล์ตัวอย่างแล้ว |
        | C ตรวจทาน | `scripts/step_three.py` | เสร็จ ไฟล์อยู่ที่ `data/sample-folder/<ชื่อ>.txt` ใช้ข้อความภาษาอังกฤษปนเล็กน้อย some mixed English text here |
        | D เลือกภาพ | `scripts/step_four.py` | เสร็จ |
        | E \(c1) \(c1) | `scripts/step_five_long_name.py` และ `scripts/helper.py` | เสร็จ \(longThai) \(longThai) |

        """
    }

    static func table(cols: Int) -> String {
        var md = "| " + (0..<cols).map { "หัว\($0)" }.joined(separator: " | ") + " |\n| " + Array(repeating: "---", count: cols).joined(separator: " | ") + " |\n"
        for r in 1...4 { md += "| " + (0..<cols).map { c in c == r % cols ? "\(longThai) \(code1)" : "ค่า \(r)-\(c)" }.joined(separator: " | ") + " |\n" }
        return md
    }

    /// คืนข้อความปัญหา (ว่าง = ปกติ)
    func misplacedCells(_ tv: EditorTextView) -> [String] {
        guard let lm = tv.layoutManager, let tc = tv.textContainer else { return ["no layout"] }
        var problems: [String] = []
        // รวม block ของแต่ละเซลล์: (แถว, คอลัมน์, rect ของ block, rect ของ glyph)
        var cells: [(Int, Int, NSRect, NSRect)] = []
        tv.storage.enumerateAttribute(.paragraphStyle, in: NSRange(location: 0, length: tv.storage.length), options: []) { v, r, _ in
            guard let ps = v as? NSParagraphStyle, let b = ps.textBlocks.first as? NSTextTableBlock else { return }
            let g = lm.glyphRange(forCharacterRange: r, actualCharacterRange: nil)
            guard g.length > 0 else { return }
            let content = tv.contentRange(of: r)
            let cg = lm.glyphRange(forCharacterRange: content, actualCharacterRange: nil)
            let blockRect = lm.boundsRect(for: b, glyphRange: g)
            let glyphRect = cg.length > 0 ? lm.boundingRect(forGlyphRange: cg, in: tc) : NSRect(x: blockRect.midX, y: blockRect.midY, width: 0, height: 0)
            cells.append((b.startingRow, b.startingColumn, blockRect, glyphRect))
        }
        // ขอบคอลัมน์จากแถวหัวตาราง
        var columns: [Int: (CGFloat, CGFloat)] = [:]
        for c in cells where c.0 == 0 { columns[c.1] = (c.2.minX, c.2.maxX) }
        guard columns.count > 1 else { return ["ไม่พบแถวหัวตาราง/คอลัมน์"] }
        for c in cells {
            guard let col = columns[c.1] else { continue }
            // block ต้องอยู่ในคอลัมน์ของตัวเอง
            if c.2.minX < col.0 - 1.5 || c.2.maxX > col.1 + 1.5 { problems.append("block r\(c.0)c\(c.1) \(c.2.minX)-\(c.2.maxX) นอกคอลัมน์ \(col)") }
            // glyph ต้องอยู่ใน block ของตัวเอง (และไม่ล้นไปคอลัมน์อื่น)
            if c.3.width > 0, c.3.minX < c.2.minX - 24 || c.3.maxX > c.2.maxX + 24 { problems.append("glyph r\(c.0)c\(c.1) \(c.3.minX)-\(c.3.maxX) นอก block \(c.2.minX)-\(c.2.maxX)") }
            if c.3.width > 0, c.3.minY < c.2.minY - 12 || c.3.maxY > c.2.maxY + 12 { problems.append("glyph r\(c.0)c\(c.1) แนวตั้งล้น block") }
        }
        // ลำดับคอลัมน์ในแถวเดียวกันต้องเรียงซ้ายไปขวาและไม่ซ้อนกัน
        for r in Set(cells.map { $0.0 }) {
            let row = cells.filter { $0.0 == r }.sorted { $0.1 < $1.1 }
            for (a, b) in zip(row, row.dropFirst()) where a.3.width > 0 && b.3.width > 0 && a.3.maxX > b.3.minX + 24 { problems.append("แถว \(r): คอลัมน์ \(a.1) ซ้อนคอลัมน์ \(b.1)") }
        }
        return problems
    }

    func editorInWindow(_ md: String, width: CGFloat = 900, height: CGFloat = 700) -> (JotdownDocument, EditorViewController, NSWindow) {
        _ = NSApplication.shared
        Fonts.registerAll()
        let doc = JotdownDocument(); doc.load(markdown: md)
        let vc = EditorViewController(document: doc)
        let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: width, height: height), styleMask: [.titled, .resizable], backing: .buffered, defer: false)
        w.isReleasedWhenClosed = false; w.animationBehavior = .none
        w.contentViewController = vc
        w.setContentSize(NSSize(width: width, height: height))
        w.alphaValue = 0; w.orderFrontRegardless()
        spin(0.3, vc.view)
        return (doc, vc, w)
    }

    @Test(arguments: [0, 1, 2]) func eachColumnTallest(tall: Int) {
        let (_, vc, w) = editorInWindow("# ตาราง\n\n" + Self.table3(tall: tall))
        defer { w.close() }
        let tv = vc.textView!
        tv.layoutManager!.ensureLayout(for: tv.textContainer!)
        spin(0.2, vc.view)
        #expect(misplacedCells(tv) == [], Comment(rawValue: "\(misplacedCells(tv))"))
    }

    @Test func pipelineLikeTable() {
        let (_, vc, w) = editorInWindow("# Pipeline\n\n" + Self.tablePipelineLike(), width: 1000)
        defer { w.close() }
        let tv = vc.textView!
        tv.layoutManager!.ensureLayout(for: tv.textContainer!)
        spin(0.3, vc.view)
        #expect(misplacedCells(tv) == [], Comment(rawValue: "\(misplacedCells(tv))"))
    }

    @Test(arguments: [2, 4]) func columnCounts(cols: Int) {
        let (_, vc, w) = editorInWindow(Self.table(cols: cols))
        defer { w.close() }
        let tv = vc.textView!
        tv.layoutManager!.ensureLayout(for: tv.textContainer!)
        #expect(misplacedCells(tv) == [], Comment(rawValue: "\(misplacedCells(tv))"))
    }

    @Test func tableInLongDocumentAfterScrolling() {
        // เอกสารยาว: layout แบบบางส่วน (non-contiguous) แล้วเลื่อนไปที่ตาราง
        var md = ""
        for i in 0..<300 { md += "ย่อหน้าที่ \(i) \(Self.longThai)\n\n" }
        md += Self.table3(tall: 0) + "\n"
        for i in 0..<300 { md += "ย่อหน้าหลัง \(i) \(Self.longThai)\n\n" }
        let (doc, vc, w) = editorInWindow(md)
        defer { w.close() }
        let tv = vc.textView!
        // เลื่อนไปกลางเอกสาร (ตาราง) แล้ว layout เฉพาะส่วนที่มองเห็น
        let loc = (doc.textStorage.string as NSString).range(of: "ขั้น").location
        tv.scrollRangeToVisible(NSRange(location: loc, length: 1))
        spin(0.4, vc.view)
        // การแสดงผลจริงจะ layout ช่วงที่มองเห็นก่อนวาด: ทำให้ครบทั้งตารางเหมือนกัน
        tv.layoutManager!.ensureLayout(for: tv.textContainer!)
        tv.repairTableLayoutIfNeeded()
        var dump = ""
        tv.storage.enumerateAttribute(.paragraphStyle, in: NSRange(location: 0, length: tv.storage.length), options: []) { v, r, _ in
            guard let b = (v as? NSParagraphStyle)?.textBlocks.first as? NSTextTableBlock, b.startingRow <= 1 else { return }
            let lm = tv.layoutManager!
            let g = lm.glyphRange(forCharacterRange: r, actualCharacterRange: nil)
            dump += "r\(b.startingRow)c\(b.startingColumn) bounds=\(lm.boundsRect(for: b, glyphRange: g)) layout=\(lm.layoutRect(for: b, glyphRange: g)) glyphs=\(g)\n"
        }
        #expect(misplacedCells(tv) == [], Comment(rawValue: "\(misplacedCells(tv))"))
    }

    @Test func afterEditingInCellRestyle() {
        let (doc, vc, w) = editorInWindow(Self.table3(tall: 1))
        defer { w.close() }
        let tv = vc.textView!
        tv.layoutManager!.ensureLayout(for: tv.textContainer!)
        // พิมพ์แก้ในเซลล์หลายแบบ (ทำให้ restyle และความสูงแถวเปลี่ยน)
        let s = tv.nsString
        for needle in ["ขั้น 1", "เสร็จ"] {
            let r = s.range(of: needle)
            tv.select(r.location + r.length)
            tv.type(" เพิ่มข้อความยาว ๆ เข้าไปอีกหลายบรรทัดเพื่อทดสอบการวางเซลล์ใหม่ \(Self.longThai)")
        }
        tv.layoutManager!.ensureLayout(for: tv.textContainer!)
        tv.repairTableLayoutIfNeeded()
        spin(0.3, vc.view)
        #expect(misplacedCells(tv) == [], Comment(rawValue: "\(misplacedCells(tv))"))
        #expect(doc.currentMarkdown.contains("| ขั้น"))
    }
}

extension TableLayoutTests {
    func snap(_ md: String, name: String, ap: NSAppearance.Name, size: CGSize = CGSize(width: 900, height: 900)) throws {
        _ = NSApplication.shared
        Fonts.registerAll()
        let doc = JotdownDocument(); doc.load(markdown: md)
        let vc = EditorViewController(document: doc); _ = vc.view
        let shot = try snapshot(name, size: size, appearance: ap, after: { spin(0.4, vc.view) }, viewController: vc)
        #expect(FileManager.default.fileExists(atPath: shot.png.path))
    }
    @Test func snapshotsPipelineLike() throws {
        for (tag, ap) in [("aqua", NSAppearance.Name.aqua), ("dark", .darkAqua)] {
            _ = tag
            try snap("# Pipeline สังเคราะห์\n\n" + Self.table3(tall: 0), name: "table-pipeline-col1", ap: ap)
            try snap("# Pipeline สังเคราะห์\n\n" + Self.table3(tall: 1), name: "table-pipeline-col2", ap: ap)
            try snap("# Pipeline สังเคราะห์\n\n" + Self.table3(tall: 2), name: "table-pipeline-col3", ap: ap)
            try snap("# Pipeline\n\n" + Self.tablePipelineLike(), name: "table-pipeline-like", ap: ap, size: CGSize(width: 1000, height: 1100))
        }
    }
}



extension TableLayoutTests {
    /// เอกสารยาว: ตารางอยู่นอกพื้นที่ที่มองเห็น (สาเหตุของบั๊กเดิม) — ซ่อมแล้วต้องถูกต้อง ทั้งหลัง parse และหลังพิมพ์แก้
    @Test(arguments: [60, 80, 100]) func tableBelowTheFoldIsRepaired(n: Int) {
        let pre = String(repeating: "ก\n\n", count: n)
        let (doc, vc, w) = editorInWindow(pre + Self.tablePipelineLike(), width: 1000, height: 700)
        defer { w.close() }
        let tv = vc.textView!
        tv.layoutManager!.ensureLayout(for: tv.textContainer!)      // เส้นทางที่ทำให้ NSTextTable พัง
        let before = misplacedCells(tv).filter { $0.hasPrefix("block") }.count
        #expect(before > 0, "ควรจำลองบั๊กเดิมได้ (ถ้า macOS แก้แล้วเทสต์นี้จะบอก)")
        #expect(!tv.tableLayoutIsConsistent())
        #expect(tv.repairTableLayoutIfNeeded())
        #expect(tv.tableLayoutIsConsistent())
        #expect(misplacedCells(tv).filter { $0.hasPrefix("block") }.isEmpty)
        // พิมพ์แก้ในเซลล์ (ทำให้ความสูงแถวเปลี่ยน) แล้วตรวจ/ซ่อมอีกรอบ
        let r = (doc.textStorage.string as NSString).range(of: "เสร็จ")
        tv.select(r.location + r.length)
        tv.type(" ข้อความเพิ่มยาว ๆ เพื่อให้แถวสูงขึ้น \(Self.longThai)")
        tv.layoutManager!.ensureLayout(forCharacterRange: NSRange(location: 0, length: doc.textStorage.length))
        tv.repairTableLayoutIfNeeded()
        #expect(misplacedCells(tv).filter { $0.hasPrefix("block") }.isEmpty)
    }

    @Test func consistentTableIsNotRelaidOut() {
        let (_, vc, w) = editorInWindow(Self.tablePipelineLike(), width: 1000, height: 900)
        defer { w.close() }
        let tv = vc.textView!
        _ = tv.layoutManager!.usedRect(for: tv.textContainer!)
        #expect(tv.tableLayoutIsConsistent())
        #expect(!tv.repairTableLayoutIfNeeded())                // ไม่ทำงานเกินจำเป็น
    }
}

extension TableLayoutTests {
    @Test func snapshotLongDocScrolledToTable() throws {
        var md = ""
        for i in 0..<120 { md += "ย่อหน้าที่ \(i) \(Self.longThai)\n\n" }
        md += "## ตาราง\n\n" + Self.tablePipelineLike() + "\n"
        for i in 0..<60 { md += "ย่อหน้าหลัง \(i) \(Self.longThai)\n\n" }
        _ = NSApplication.shared
        Fonts.registerAll()
        for (tag, ap) in [("aqua", NSAppearance.Name.aqua), ("dark", .darkAqua)] {
            let doc = JotdownDocument(); doc.load(markdown: md)
            let vc = EditorViewController(document: doc); _ = vc.view
            let shot = try snapshot("table-longdoc-\(tag)", size: CGSize(width: 1000, height: 900), appearance: ap, after: {
                let loc = (doc.textStorage.string as NSString).range(of: "A เริ่มต้น").location
                vc.textView.scrollRangeToVisible(NSRange(location: loc + 300, length: 1))
                spin(0.3, vc.view)
                vc.textView.repairTableLayoutIfNeeded()          // ที่แอปทำเองหลังโหลด/scroll/แก้ไข (หน่วง 0.12 วินาที)
                spin(0.3, vc.view)
            }, viewController: vc)
            #expect(FileManager.default.fileExists(atPath: shot.png.path))
            #expect(vc.textView.tableLayoutIsConsistent())
        }
    }
}
