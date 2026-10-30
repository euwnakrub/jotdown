import Testing
import AppKit
@testable import Jotdown

@MainActor @Suite(.serialized) struct TableTests {
    func rt(_ md: String) -> String { MarkdownSerializer.serialize(MarkdownParser.parse(md)) }

    @Test func roundTripsAligned() {
        let md = "| a   | b   |\n| --- | --- |\n| 1   | 2   |\n"
        #expect(rt(md) == md)
        let al = "| left | center | right |\n| :--- | :----: | ----: |\n| a    |   b    |     c |\n"
        #expect(rt(al) == al)
    }

    @Test func storageHasNoPipesAndCellKinds() {
        let a = MarkdownParser.parse("| a | b |\n|:-:|--:|\n| 1 | 2 |\n")
        #expect(!a.string.contains("|"))
        #expect(a.string == "a\nb\n1\n2\n")        // เซลล์ละย่อหน้า + ย่อหน้าว่างท้ายเอกสาร
        #expect(a.blockKind(at: 0) == .tableCell(0, 0, 2))
        #expect(a.blockKind(at: 2) == .tableCell(0, 1, 3))
        #expect(a.blockKind(at: 4) == .tableCell(1, 0, 2))
        let ps = a.attribute(.paragraphStyle, at: 0, effectiveRange: nil) as! NSParagraphStyle
        #expect(ps.textBlocks.first is NSTextTableBlock)
        #expect(ps.alignment == .center)
        // เซลล์ทุกเซลล์ใช้ตารางเดียวกัน
        let t0 = (ps.textBlocks[0] as! NSTextTableBlock).table
        let t3 = ((a.attribute(.paragraphStyle, at: 6, effectiveRange: nil) as! NSParagraphStyle).textBlocks[0] as! NSTextTableBlock).table
        #expect(t0 === t3)
        #expect(t0.numberOfColumns == 2)
    }

    @Test func inlineAndEscapesInCells() {
        let md = "| **หนา** | *เอียง* | `โค้ด` | [ลิงก์](https://x.y) |\n| ---     | ---     | ---    | ---                  |\n| a \\| b  | x<br>y  | ![i](p.png) | ก็ที่  |\n"
        let out = rt(md)
        #expect(out.contains("a \\| b"))
        #expect(out.contains("x<br>y"))
        #expect(out.contains("**หนา**") && out.contains("[ลิงก์](https://x.y)") && out.contains("![i](p.png)"))
        #expect(rt(out) == out)
        let a = MarkdownParser.parse(md)
        #expect(a.string.contains("a | b"))
        #expect(a.string.contains("x\u{2028}y"))
    }

    @Test func thaiColumnsAlignByGraphemeWidth() {
        #expect(TableModel.displayWidth("ที่") == 1)
        #expect(TableModel.displayWidth("ก็") == 1)
        #expect(TableModel.displayWidth("abc") == 3)
        #expect(TableModel.displayWidth("你好") == 4)
        let out = rt("| ชื่อ | ที่อยู่ |\n|---|---|\n| สมชาย | กรุงเทพ |\n")
        let lines = out.split(separator: "\n").map(String.init)
        #expect(Set(lines.map(TableModel.displayWidth)).count == 1, Comment(rawValue: "ทุกบรรทัดต้องกว้างเท่ากัน: \(lines)"))
    }

    @Test func unevenRowsArePadded() {
        let out = rt("| a | b | c |\n|---|---|---|\n| 1 |\n| 1 | 2 | 3 | 4 |\n")
        #expect(out.contains("| 1   |     |     |"))
        #expect(MarkdownSerializer.serialize(MarkdownParser.parse(out)) == out)
        #expect(!out.contains("4"), "เซลล์เกินจำนวนคอลัมน์ของหัวตารางตามกฎ GFM")
    }

    @Test func tableLastGetsTrailingParagraph() {
        let a = MarkdownParser.parse("| a |\n|---|\n| 1 |\n")
        #expect(a.string.hasSuffix("\n"))
        #expect(rt("| a |\n|---|\n| 1 |\n\nหลัง\n") == "| a   |\n| --- |\n| 1   |\n\nหลัง\n")
    }

    // MARK: - editor
    func typeTable(explicitUndo: Bool = false) -> (JotdownDocument, EditorViewController) {
        let (doc, vc) = makeEditor(explicitUndo: explicitUndo)
        vc.textView.type("| a | b |\n")
        return (doc, vc)
    }

    @Test func typedHeaderRowCreatesTable() {
        let (doc, vc) = typeTable()
        #expect(doc.currentMarkdown == "| a   | b   |\n| --- | --- |\n|     |     |\n")
        #expect(doc.textStorage.blockKind(at: 0) == .tableCell(0, 0, 0))
        // เคอร์เซอร์อยู่เซลล์แรกของแถวแรกในตัวตาราง (แถวที่ 1)
        #expect(vc.textView.cellInfo(at: vc.textView.selectedRange().location)?.row == 1)
    }

    @Test func tabNavigationAddsRows() {
        let (doc, vc) = typeTable()
        let tv = vc.textView!
        tv.type("x\ty\t")                       // x -> (1,0), Tab -> (1,1) y, Tab ที่เซลล์สุดท้าย = เพิ่มแถว
        tv.type("z")
        #expect(doc.currentMarkdown == "| a   | b   |\n| --- | --- |\n| x   | y   |\n| z   |     |\n")
        tv.insertBacktab(nil); tv.type("w")      // ⇧Tab กลับเซลล์ก่อน (เลือกเนื้อหา) แล้วพิมพ์ทับ
        #expect(doc.currentMarkdown.contains("| x   | w   |"), Comment(rawValue: doc.currentMarkdown))
    }

    @Test func enterMovesDownAndAddsRow() {
        let (doc, vc) = typeTable()
        let tv = vc.textView!
        tv.type("1\n2\n3")
        #expect(doc.currentMarkdown == "| a   | b   |\n| --- | --- |\n| 1   |     |\n| 2   |     |\n| 3   |     |\n")
    }

    @Test func shiftEnterMakesBreakInCell() {
        let (doc, vc) = typeTable()
        let tv = vc.textView!
        tv.type("x"); tv.insertLineBreak(nil); tv.type("y")
        #expect(doc.currentMarkdown.contains("| x<br>y |"), Comment(rawValue: doc.currentMarkdown))
    }

    @Test func backspaceAndDeleteKeepStructure() {
        let (doc, vc) = typeTable()
        let tv = vc.textView!
        let before = doc.currentMarkdown
        tv.type("\u{8}\u{8}")                    // เซลล์ว่าง
        #expect(doc.currentMarkdown == before)
        tv.deleteForward(nil)
        #expect(doc.currentMarkdown == before)
        // เลือกทั้งเอกสารแล้วลบ = ล้างเนื้อหาเซลล์ ไม่ทำลายโครงสร้าง
        tv.type("hi\t")
        // เลือกบางเซลล์ (ไม่ครบทุกเซลล์) แล้วลบ = ล้างเนื้อหา โครงคงอยู่
        tv.select(0, 1)
        tv.deleteBackward(nil)
        #expect(doc.currentMarkdown.hasPrefix("|"))
        #expect(doc.currentMarkdown.contains("| --- | --- |"))
        // เลือกทั้งเอกสาร (ครอบทั้งตาราง) แล้วลบ = ลบทั้งตาราง
        tv.select(0, doc.textStorage.length)
        tv.deleteBackward(nil)
        #expect(doc.currentMarkdown == "")
    }

    @Test func arrowsMoveBetweenRows() {
        let (doc, vc) = typeTable()
        let tv = vc.textView!
        tv.type("1\n2")
        tv.moveUp(nil); tv.type("X")
        #expect(doc.currentMarkdown.contains("| X   |"))
        tv.moveDown(nil); tv.type("Y")
        #expect(doc.currentMarkdown.contains("| Y   |"))
    }

    @Test func tableCommands() {
        let (doc, vc) = typeTable()
        let tv = vc.textView!
        tv.type("1\t2")
        let base = "| a   | b   |\n| --- | --- |\n| 1   | 2   |\n"
        #expect(doc.currentMarkdown == base)
        tv.select(tv.selectedRange().location)
        tv.jotTableRowBelow(nil)
        #expect(doc.currentMarkdown == base + "|     |     |\n")
        tv.type("n")
        tv.jotTableRowAbove(nil)
        #expect(doc.currentMarkdown == base + "|     |     |\n|     | n   |\n")
        tv.jotTableDeleteRow(nil)
        #expect(doc.currentMarkdown == base + "|     | n   |\n")
        tv.jotTableColumnRight(nil)
        #expect(doc.currentMarkdown.hasPrefix("| a   | b   |     |\n"))
        tv.jotTableColumnLeft(nil)
        #expect(doc.currentMarkdown.hasPrefix("| a   | b   |     |     |\n"))
        tv.jotTableDeleteColumn(nil)
        tv.jotTableDeleteColumn(nil)
        #expect(doc.currentMarkdown.hasPrefix("| a   | b   |\n"), Comment(rawValue: doc.currentMarkdown))
        tv.jotTableAlignRight(nil)
        #expect(doc.currentMarkdown.contains("| --- | --: |") || doc.currentMarkdown.contains("| --: | --- |"), Comment(rawValue: doc.currentMarkdown))
        tv.jotTableAlignCenter(nil)
        #expect(doc.currentMarkdown.contains(":-:"))
        tv.jotTableAlignLeft(nil)
        #expect(doc.currentMarkdown.contains(":--"))
        tv.jotTableDelete(nil)
        #expect(!doc.currentMarkdown.contains("|"))
    }

    @Test func menuValidationOnlyInsideTable() {
        let (_, vc) = makeEditor("ก\n")
        let tv = vc.textView!
        let del = NSMenuItem(title: "d", action: #selector(EditorTextView.jotTableDelete(_:)), keyEquivalent: "")
        let ins = NSMenuItem(title: "i", action: #selector(EditorTextView.jotInsertTable(_:)), keyEquivalent: "")
        #expect(!tv.validateMenuItem(del)); #expect(tv.validateMenuItem(ins))
        tv.insertDefaultTable()
        #expect(tv.validateMenuItem(del)); #expect(!tv.validateMenuItem(ins))
        let menu = MainMenu.build()
        let table = menu.items.first { $0.title == "Format" }!.submenu!.items.first { $0.title == "Table" }!.submenu!
        let titles = table.items.map(\.title).filter { !$0.isEmpty }
        for t in ["Insert Table", "Insert Row Above", "Insert Row Below", "Insert Column Left", "Insert Column Right", "Delete Row", "Delete Column", "Delete Table", "Align Column Left", "Align Column Center", "Align Column Right"] { #expect(titles.contains(t), Comment(rawValue: t)) }
        let it = table.items.first { $0.title == "Insert Table" }!
        #expect(it.keyEquivalent == "t" && it.keyEquivalentModifierMask == [.command, .control])
    }

    @Test func insertTableCommandAndUndo() {
        let (doc, vc) = makeEditor("ก\n")
        let tv = vc.textView!
        tv.select(1)
        tv.insertDefaultTable()
        #expect(doc.currentMarkdown == "ก\n\n|     |     |     |\n| --- | --- | --- |\n|     |     |     |\n|     |     |     |\n")
        doc.undoManager?.undo()
        #expect(doc.currentMarkdown == "ก\n")
        doc.undoManager?.redo()
        #expect(doc.currentMarkdown.contains("| --- | --- | --- |"))
    }

    @Test func tableOpUndoIsSingleStep() {
        let (doc, vc) = typeTable(explicitUndo: true)
        let before = doc.currentMarkdown
        vc.textView.event { vc.textView.jotTableRowBelow(nil) }
        #expect(doc.currentMarkdown != before)
        doc.undoManager?.undo()
        #expect(doc.currentMarkdown == before)
    }

    @Test func copyTableGivesMarkdownAndPasteRebuilds() {
        let (doc, vc) = makeEditor("| a | b |\n|---|---|\n| 1 | 2 |\n\nจบ\n")
        let tv = vc.textView!
        tv.select(0, 6)                              // a, b, 1 (สามเซลล์แรก)
        tv.copy(nil)
        let s = NSPasteboard.general.string(forType: .string) ?? ""
        #expect(s.contains("| a") && s.contains("| 1"), Comment(rawValue: s))
        let (doc2, vc2) = makeEditor()
        let pb = NSPasteboard.withUniqueName(); pb.clearContents()
        pb.setString("| ก | ข |\n|---|:-:|\n| 1 | 2 |\n", forType: .string)
        vc2.textView.pasteFrom(pb)
        #expect(doc2.currentMarkdown == "| ก   |  ข  |\n| --- | :-: |\n| 1   |  2  |\n")
        _ = doc
    }

    @Test func pasteHTMLTable() {
        let blocks = HTMLImporter.blocks(from: "<table><thead><tr><th>ชื่อ</th><th>อายุ</th></tr></thead><tbody><tr><td><b>สมชาย</b></td><td>30</td></tr><tr><td>A<br>B</td><td></td></tr></tbody></table>")
        let md = MarkdownSerializer.serialize(blocks)
        let lines = md.split(separator: "\n").map(String.init)
        #expect(lines.count == 4)
        #expect(lines[0].hasPrefix("| ชื่อ") && lines[0].contains("อายุ"))
        #expect(lines[2].contains("**สมชาย**") && lines[2].contains("30"))
        #expect(lines[3].contains("A<br>B"))
        #expect(rt(md) == md)
    }

    @Test func largeTableTypingIsFast() {
        var md = "| ก | ข | ค |\n|---|---|---|\n"
        for i in 0..<200 { md += "| แถว \(i) | **หนา** \(i) | `x` |\n" }
        let (doc, vc) = makeEditor(md)
        let tv = vc.textView!
        tv.select(doc.textStorage.length / 2)
        let t = Date()
        for _ in 0..<20 { tv.type("ก") }
        let per = Date().timeIntervalSince(t) / 20
        #expect(per < 0.1, Comment(rawValue: "พิมพ์ในตาราง 200 แถวใช้ \(per)s ต่อตัวอักษร"))
        #expect(doc.currentMarkdown.contains("ก"))
    }

    // MARK: - ลบทั้งตาราง
    static let docMD = "ก\n\n| a | b |\n|---|---|\n| 1 | 2 |\n\nข\n"
    static let tableMD = "| a   | b   |\n| --- | --- |\n| 1   | 2   |\n"

    func tableDoc() -> (JotdownDocument, EditorViewController) {
        let (doc, vc) = makeEditor(Self.docMD, explicitUndo: true)
        return (doc, vc)
    }

    @Test func selectTableThenBackspaceDeletesTable() {
        let (doc, vc) = tableDoc()
        let tv = vc.textView!
        tv.select(tv.nsString.range(of: "a").location)
        #expect(tv.validateMenuItem(NSMenuItem(title: "", action: #selector(EditorTextView.jotSelectTable(_:)), keyEquivalent: "")))
        tv.jotSelectTable(nil)
        #expect(tv.selectedRange() == tv.tableRange(containing: tv.selectedRange().location))
        tv.event { tv.deleteBackward(nil) }
        #expect(doc.currentMarkdown == "ก\n\nข\n")
        doc.undoManager?.undo()
        #expect(doc.currentMarkdown == Self.docMD.replacingOccurrences(of: "| a | b |\n|---|---|\n| 1 | 2 |\n", with: Self.tableMD))
    }

    @Test func deleteKeyAndCutRemoveWholeTable() {
        let (doc, vc) = tableDoc()
        let tv = vc.textView!
        tv.select(tv.nsString.range(of: "a").location)
        tv.jotSelectTable(nil)
        tv.event { tv.deleteForward(nil) }
        #expect(!doc.currentMarkdown.contains("|"))
        doc.undoManager?.undo()
        #expect(doc.currentMarkdown.contains("| a   | b   |"))
        tv.select(tv.nsString.range(of: "a").location)
        tv.jotSelectTable(nil)
        tv.event { tv.cut(nil) }
        #expect(NSPasteboard.general.string(forType: .string)?.contains("| a") == true)
        #expect(NSPasteboard.general.string(forType: .string)?.contains("| --- | --- |") == true)
        #expect(doc.currentMarkdown == "ก\n\nข\n")
        doc.undoManager?.undo()
        #expect(doc.currentMarkdown.contains(Self.tableMD))
    }

    @Test func dragAcrossTableDeletesIt() {
        let (doc, vc) = tableDoc()
        let tv = vc.textView!
        let s = tv.nsString
        // จากกลางย่อหน้า "ก" ถึงต้นย่อหน้า "ข"
        let from = s.range(of: "ก").location
        let to = s.range(of: "ข").location
        tv.select(from, to - from)
        tv.event { tv.deleteBackward(nil) }
        #expect(doc.currentMarkdown == "ข\n")
        doc.undoManager?.undo()
        #expect(doc.currentMarkdown.contains(Self.tableMD) && doc.currentMarkdown.hasPrefix("ก"))
    }

    @Test func selectAllBackspaceClearsEverything() {
        let (doc, vc) = tableDoc()
        let tv = vc.textView!
        tv.selectAll(nil)
        tv.event { tv.deleteBackward(nil) }
        #expect(doc.currentMarkdown == "")
        #expect(doc.textStorage.string == "" || !doc.textStorage.string.contains("a"))
        doc.undoManager?.undo()
        #expect(doc.currentMarkdown.contains(Self.tableMD) && doc.currentMarkdown.contains("ก") && doc.currentMarkdown.contains("ข"))
    }

    @Test func partialCellsKeepStructure() {
        let (doc, vc) = tableDoc()
        let tv = vc.textView!
        let a = tv.nsString.range(of: "a").location
        let one = tv.nsString.range(of: "1").location
        tv.select(a, one - a + 1)          // a, b, 1 (ไม่ครบทุกเซลล์)
        tv.event { tv.deleteBackward(nil) }
        #expect(doc.currentMarkdown.contains("| --- | --- |"))
        #expect(doc.currentMarkdown.contains("| 2 ") || doc.currentMarkdown.contains("2   |"))
        #expect(!doc.currentMarkdown.contains("| a"))
        doc.undoManager?.undo()
        #expect(doc.currentMarkdown.contains(Self.tableMD))
    }

    @Test func typingOverWholeTableReplacesIt() {
        let (doc, vc) = tableDoc()
        let tv = vc.textView!
        tv.select(tv.nsString.range(of: "a").location)
        tv.jotSelectTable(nil)
        tv.type("x")
        #expect(!doc.currentMarkdown.contains("|"))
        #expect(doc.currentMarkdown.contains("x"))
    }

    @Test func selectTableMenuItemExists() {
        let menu = MainMenu.build()
        let table = menu.items.first { $0.title == "Format" }!.submenu!.items.first { $0.title == "Table" }!.submenu!
        #expect(table.items.contains { $0.title == "Select Table" })
        let (_, vc) = makeEditor(Self.docMD)
        #expect(vc.textView.tableContextMenu().items.contains { $0.title == "Select Table" })
    }

    func snapSelected(_ ap: NSAppearance.Name) throws {
        _ = NSApplication.shared
        let doc = JotdownDocument(); doc.load(markdown: Self.docMD)
        let vc = EditorViewController(document: doc); _ = vc.view
        let shot = try snapshot("editor-table-selected", size: CGSize(width: 900, height: 500), appearance: ap, after: {
            vc.textView.select(vc.textView.nsString.range(of: "a").location)
            vc.textView.jotSelectTable(nil)
        }, viewController: vc)
        #expect(FileManager.default.fileExists(atPath: shot.png.path))
    }
    @Test func selectedTableAqua() throws { try snapSelected(.aqua) }
    @Test func selectedTableDark() throws { try snapSelected(.darkAqua) }

    // MARK: - snapshot
    /// ตรวจพิกเซลที่ขอบขวาของตาราง: ต้องมีสีเส้นขอบจริงตลอดความสูงของตาราง (ไม่ใช่ดูด้วยตา)
    func rightBorderCoverage(_ shot: Shot, _ tv: EditorTextView) -> (covered: Int, total: Int, edge: Int) {
        let rep = shot.image
        let scale = CGFloat(rep.pixelsWide) / tv.bounds.width
        let lm = tv.layoutManager!, tc = tv.textContainer!
        // ช่วงแนวตั้งของตาราง: จากเซลล์แรกถึงเซลล์สุดท้าย
        var minY = CGFloat.greatestFiniteMagnitude, maxY: CGFloat = 0, maxX: CGFloat = 0
        tv.storage.enumerateAttribute(.paragraphStyle, in: NSRange(location: 0, length: tv.storage.length), options: []) { v, r, _ in
            guard let ps = v as? NSParagraphStyle, let b = ps.textBlocks.first as? NSTextTableBlock else { return }
            let rect = lm.boundsRect(for: b, glyphRange: lm.glyphRange(forCharacterRange: r, actualCharacterRange: nil))
            minY = min(minY, rect.minY); maxY = max(maxY, rect.maxY); maxX = max(maxX, rect.maxX)
        }
        let edgeX = tv.textContainerOrigin.x + maxX      // ขอบขวาจริงของตาราง (คอลัมน์สุดท้าย)
        let bg = rep.colorAt(x: 2, y: 2) ?? .white
        func differs(_ c: NSColor?) -> Bool {
            guard let c = c?.usingColorSpace(.sRGB), let b = bg.usingColorSpace(.sRGB) else { return false }
            return abs(c.redComponent - b.redComponent) + abs(c.greenComponent - b.greenComponent) + abs(c.blueComponent - b.blueComponent) > 0.03
        }
        let x0 = Int((edgeX - 2) * scale), x1 = Int((edgeX + 1) * scale)
        var covered = 0, total = 0
        let yEnd = min(Int((maxY + tv.textContainerOrigin.y - 4) * scale), rep.pixelsHigh - 2)     // เฉพาะส่วนที่อยู่ในภาพ
        for y in Int((minY + tv.textContainerOrigin.y + 4) * scale)..<yEnd {
            total += 1
            if (x0...x1).contains(where: { differs(rep.colorAt(x: $0, y: y)) }) { covered += 1 }
        }
        return (covered, total, Int(edgeX * scale))
    }

    func snapTable(_ size: CGSize, _ ap: NSAppearance.Name) throws {
        _ = NSApplication.shared
        Fonts.registerAll()
        let md = "# ตาราง\n\nย่อหน้าก่อนตาราง\n\n| ชื่อ | ที่อยู่ที่ยาวมากเพื่อทดสอบการตัดบรรทัดในเซลล์ของตาราง | ราคา |\n| :--- | :---: | ---: |\n| สมชาย | กรุงเทพมหานคร และปริมณฑลทั้งหมด **ตัวหนา** `code` [ลิงก์](https://x.y) | 1,200 |\n| Alice | Chiang Mai | 35.5 |\n| บรรทัด<br>สอง | | 7 |\n\nย่อหน้าหลังตาราง\n"
        let doc = JotdownDocument(); doc.load(markdown: md)
        let vc = EditorViewController(document: doc); _ = vc.view
        let shot = try snapshot("editor-table", size: size, appearance: ap, viewController: vc)
        #expect(FileManager.default.fileExists(atPath: shot.png.path))
        #expect(vc.textView.frame.width <= size.width + 0.5)
        let lm = vc.textView.layoutManager!, tc = vc.textView.textContainer!
        let used = lm.usedRect(for: tc)
        #expect(used.width <= Theme.columnMaxWidth + 1)
        let cov = rightBorderCoverage(shot, vc.textView)
        #expect(cov.total > 20 && cov.covered >= cov.total * 95 / 100, Comment(rawValue: "เส้นขอบขวาของตารางหาย: \(cov) @\(size) \(ap.rawValue)"))
    }
    @Test func tableAqua900() throws { try snapTable(CGSize(width: 900, height: 700), .aqua) }
    @Test func tableAqua480() throws { try snapTable(CGSize(width: 480, height: 320), .aqua) }
    @Test func tableDark900() throws { try snapTable(CGSize(width: 900, height: 700), .darkAqua) }
    @Test func tableDark480() throws { try snapTable(CGSize(width: 480, height: 320), .darkAqua) }
    @Test func tableAqua700() throws { try snapTable(CGSize(width: 700, height: 600), .aqua) }
    @Test func tableDark1400() throws { try snapTable(CGSize(width: 1400, height: 700), .darkAqua) }
    @Test func tableAqua1400() throws { try snapTable(CGSize(width: 1400, height: 700), .aqua) }
}
