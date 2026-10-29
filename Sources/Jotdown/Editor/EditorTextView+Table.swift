import AppKit

extension EditorTextView {
    // MARK: - ค้นหาตาราง / เซลล์
    func cellInfo(at loc: Int) -> (row: Int, col: Int)? {
        let pr = paragraphRange(containing: loc)
        guard pr.length > 0, case .tableCell(let r, let c, _) = storage.blockKind(at: pr.location) else { return nil }
        return (r, c)
    }

    /// ช่วงของตารางทั้งตาราง (ทุกเซลล์รวมตัวขึ้นบรรทัดท้าย) ที่ตำแหน่ง `loc` อยู่
    func tableRange(containing loc: Int) -> NSRange? {
        guard let cell = cellInfo(at: loc) else { return nil }
        var start = paragraphRange(containing: loc).location
        var row = cell.row, col = cell.col
        while !(row == 0 && col == 0), start > 0 {
            let prev = paragraphRange(containing: start - 1)
            guard case .tableCell(let r, let c, _) = storage.blockKind(at: prev.location) else { break }
            start = prev.location; row = r; col = c
        }
        var end = NSMaxRange(paragraphRange(containing: loc))
        while end < storage.length {
            let next = nsString.paragraphRange(for: NSRange(location: end, length: 0))
            guard case .tableCell(let r, let c, _) = storage.blockKind(at: next.location), !(r == 0 && c == 0) else { break }
            end = NSMaxRange(next)
        }
        return NSRange(location: start, length: end - start)
    }

    func readTable(_ range: NSRange) -> TableModel? {
        TableModel.from(MarkdownSerializer.paragraphs(of: storage.attributedSubstring(from: range)))
    }

    /// เลือกเนื้อหาของเซลล์ (row, col) ของตารางที่เริ่มที่ `tableStart`
    func selectCell(row: Int, col: Int, tableStart: Int, cols: Int) {
        var idx = row * cols + col
        var p = tableStart
        while idx > 0, p < storage.length { p = NSMaxRange(nsString.paragraphRange(for: NSRange(location: p, length: 0))); idx -= 1 }
        let pr = nsString.paragraphRange(for: NSRange(location: min(p, max(storage.length - 1, 0)), length: 0))
        setSelectedRange(contentRange(of: pr))
        syncTypingAttributes()
        scrollRangeToVisible(selectedRange())
    }

    // MARK: - แก้โครงสร้างด้วย TableModel (undo ครั้งเดียว)
    /// `f` แก้โมเดลและคืนเซลล์ที่จะเลือกต่อ (nil = ลบทั้งตาราง)
    func applyTable(_ f: (inout TableModel, Int, Int) -> (Int, Int)?) {
        let caret = selectedRange().location
        guard let range = tableRange(containing: caret), var m = readTable(range), let cell = cellInfo(at: caret) else { return }
        guard let target = f(&m, cell.row, cell.col) else {
            replaceRange(range, with: NSAttributedString(), selection: NSRange(location: range.location, length: 0))
            syncTypingAttributes()
            return
        }
        replaceRange(range, with: MarkdownParser.attributedString(from: m.blocks(), terminated: true), selection: NSRange(location: range.location, length: 0))
        selectCell(row: min(target.0, m.rows.count - 1), col: min(target.1, m.cols - 1), tableStart: range.location, cols: m.cols)
    }

    func insertRow(below: Bool) { applyTable { m, r, c in let at = below ? r + 1 : max(r, 1); m.insertRow(at: at); return (at, c) } }
    func insertColumn(right: Bool) { applyTable { m, r, c in let at = right ? c + 1 : c; m.insertColumn(at: at); return (r, at) } }
    func deleteRow() { applyTable { m, r, c in
        guard r >= 1 else { return (r, c) }
        m.deleteRow(r); return (min(r, m.rows.count - 1), c) } }
    func deleteColumn() { applyTable { m, r, c in
        guard m.cols > 1 else { return nil }
        m.deleteColumn(c); return (r, min(c, m.cols - 1)) } }
    func deleteTable() { applyTable { _, _, _ in nil } }
    func alignColumn(_ a: Int) { applyTable { m, r, c in m.align[c] = a; return (r, c) } }

    // MARK: - ย้ายระหว่างเซลล์
    /// ย้ายไปเซลล์ถัดไป/ก่อนหน้า (เซลล์สุดท้าย + Tab = เพิ่มแถว)
    @discardableResult
    func moveCell(by delta: Int) -> Bool {
        let caret = selectedRange().location
        guard let range = tableRange(containing: caret), let m = readTable(range), let cell = cellInfo(at: caret) else { return false }
        let idx = cell.row * m.cols + cell.col + delta
        if idx < 0 { return true }
        if idx >= m.rows.count * m.cols {
            applyTable { m, _, _ in m.insertRow(at: m.rows.count); return (m.rows.count - 1, 0) }
            return true
        }
        selectCell(row: idx / m.cols, col: idx % m.cols, tableStart: range.location, cols: m.cols)
        return true
    }

    /// Enter / ↓ / ↑: ไปเซลล์เดียวกันแถวถัดไป/ก่อนหน้า (แถวสุดท้าย + ลง = เพิ่มแถวใหม่เมื่อ `addRow`)
    func moveVertically(by delta: Int, addRow: Bool = true) {
        let caret = selectedRange().location
        guard let range = tableRange(containing: caret), let m = readTable(range), let cell = cellInfo(at: caret) else { return }
        let r = cell.row + delta
        if r < 0 { return }
        if r >= m.rows.count {
            if addRow { applyTable { m, r, c in m.insertRow(at: m.rows.count); return (m.rows.count - 1, c) } }
            return
        }
        selectCell(row: r, col: cell.col, tableStart: range.location, cols: m.cols)
    }

    private func caretLineIsEdge(up: Bool) -> Bool {
        guard let lm = layoutManager, storage.length > 0 else { return true }
        let pr = paragraphRange(containing: selectedRange().location)
        guard pr.length > 0 else { return true }
        let loc = min(selectedRange().location, NSMaxRange(pr) - 1)
        let caretGlyph = lm.glyphIndexForCharacter(at: loc)
        let g = lm.glyphRange(forCharacterRange: pr, actualCharacterRange: nil)
        let edgeGlyph = up ? g.location : max(NSMaxRange(g) - 1, g.location)
        return lm.lineFragmentRect(forGlyphAt: caretGlyph, effectiveRange: nil) == lm.lineFragmentRect(forGlyphAt: edgeGlyph, effectiveRange: nil)
    }

    override func moveDown(_ sender: Any?) {
        if blockKindAtCaret.isTableCell, caretLineIsEdge(up: false), let range = tableRange(containing: selectedRange().location),
           let m = readTable(range), let cell = cellInfo(at: selectedRange().location), cell.row + 1 < m.rows.count {
            moveVertically(by: 1, addRow: false); return
        }
        super.moveDown(sender)
    }

    override func moveUp(_ sender: Any?) {
        if blockKindAtCaret.isTableCell, caretLineIsEdge(up: true), let cell = cellInfo(at: selectedRange().location), cell.row > 0 {
            moveVertically(by: -1, addRow: false); return
        }
        super.moveUp(sender)
    }


    override func deleteForward(_ sender: Any?) {
        let sel = selectedRange()
        if sel.length == 0, blockKindAtCaret.isTableCell {
            let pr = paragraphRange(containing: sel.location)
            if sel.location >= NSMaxRange(contentRange(of: pr)) { return }
        }
        super.deleteForward(sender)
    }

    // MARK: - ป้องกันโครงตาราง
    /// การแก้ที่ข้ามเซลล์/แตะตัวขึ้นบรรทัดของเซลล์ = ล้างเฉพาะเนื้อหาในเซลล์แทน (คืน false เมื่อจัดการเองแล้ว)
    func guardTableEdit(_ range: NSRange) -> Bool {
        guard storage.length > 0, range.location <= storage.length else { return true }
        let ns = nsString
        let loc = min(range.location, storage.length)
        let pr = ns.paragraphRange(for: NSRange(location: loc, length: min(range.length, storage.length - loc)))
        // เลือกครอบตารางทั้งตาราง (ทั้งตารางพอดี หรือลากข้ามจากข้อความก่อน/หลัง) = ลบโครงตารางด้วย
        if range.length > 0 {
            var cover = range
            var found = false
            var q = pr.location
            while q < NSMaxRange(pr) {
                let one = ns.paragraphRange(for: NSRange(location: q, length: 0))
                if storage.blockKind(at: one.location).isTableCell, let tr = tableRange(containing: one.location) {
                    if range.location <= tr.location, NSMaxRange(range) >= NSMaxRange(tr) - 1 { cover = NSUnionRange(cover, tr); found = true }
                    q = max(NSMaxRange(tr), NSMaxRange(one))
                } else { q = NSMaxRange(one) }
            }
            if found {
                let rep = pendingReplacement
                replaceRange(cover, with: NSAttributedString(), selection: NSRange(location: cover.location, length: 0))
                if let rep, !rep.isEmpty { insertText(rep, replacementRange: selectedRange()) }
                syncTypingAttributes()
                return false
            }
        }
        // เฉพาะเมื่อมีเซลล์ในช่วงที่แตะ
        var cells: [NSRange] = []
        var p = pr.location
        var touchesCell = false
        while p < NSMaxRange(pr) || (p == pr.location && pr.length == 0) {
            let one = ns.paragraphRange(for: NSRange(location: min(p, storage.length - 1), length: 0))
            if storage.blockKind(at: one.location).isTableCell { touchesCell = true; cells.append(one) }
            if NSMaxRange(one) <= p { break }
            p = NSMaxRange(one)
        }
        guard touchesCell else { return true }
        if cells.count == 1 {
            let c = contentRange(of: cells[0])
            if range.location >= c.location, NSMaxRange(range) <= NSMaxRange(c), pr == cells[0] { return true }
        }
        // ล้างเนื้อหาส่วนที่ถูกเลือกในแต่ละเซลล์ (จากท้ายไปต้น)
        for one in cells.reversed() {
            let c = contentRange(of: one)
            let inter = NSIntersectionRange(c, range)
            if inter.length > 0 { replaceRange(inter, with: NSAttributedString(), selection: nil) }
        }
        return false
    }

    // MARK: - สร้างตาราง
    /// `| a | b |` พิมพ์ในย่อหน้าแล้ว Enter -> ตาราง (หัว + 1 แถวว่าง)
    func tableModelFromTypedRow(_ text: String) -> TableModel? {
        let t = text.trimmingCharacters(in: .whitespaces)
        guard t.hasPrefix("|"), t.hasSuffix("|"), t.count >= 3 else { return nil }
        var cells: [String] = [""]
        var escaped = false
        for ch in t.dropFirst().dropLast() {
            if escaped { cells[cells.count - 1].append(ch); escaped = false; continue }
            if ch == "\\" { escaped = true; continue }
            if ch == "|" { cells.append(""); continue }
            cells[cells.count - 1].append(ch)
        }
        let heads = cells.map { $0.trimmingCharacters(in: .whitespaces) }
        guard heads.contains(where: { !$0.isEmpty }) else { return nil }
        var m = TableModel.empty(rows: 2, cols: heads.count)
        m.rows[0] = heads.map { $0.isEmpty ? [] : [InlineSegment(text: $0)] }
        return m
    }

    /// วางตารางที่ย่อหน้าปัจจุบัน: `replacing` = แทนที่ย่อหน้านั้น, nil = แทรกหลังย่อหน้า (ถ้าย่อหน้าว่างจะแทนที่)
    func placeTable(_ m: TableModel, replacing: NSRange? = nil, selectCell cell: (Int, Int) = (0, 0)) {
        let built = MarkdownParser.attributedString(from: m.blocks(), terminated: true)
        let loc = selectedRange().location
        var pr = replacing ?? paragraphRange(containing: loc)
        let content = contentRange(of: pr)
        var start = pr.location
        var out: NSAttributedString = built
        if replacing != nil || content.length == 0 {
            // แทนที่ย่อหน้า (ถ้าไม่มีตัวขึ้นบรรทัดท้าย = ท้ายเอกสาร ตารางมี "\n" ของตัวเองแล้ว)
        } else {
            let hasNL = pr.length > content.length
            start = NSMaxRange(pr)
            pr = NSRange(location: start, length: 0)
            if !hasNL {
                let m2 = NSMutableAttributedString(string: "\n", attributes: Theme.attributes(for: storage.blockKind(at: content.location)))
                m2.append(built); out = m2
            }
        }
        replaceRange(pr, with: out, selection: NSRange(location: start, length: 0))
        let tableStart = start + (out === built ? 0 : 1)
        selectCell(row: cell.0, col: cell.1, tableStart: tableStart, cols: m.cols)
    }

    func insertDefaultTable() {
        guard !blockKindAtCaret.isCodeLike, !blockKindAtCaret.isTableCell else { return }
        placeTable(TableModel.empty(rows: 3, cols: 3))
    }

    // MARK: - ซ่อมการวางเซลล์ผิดคอลัมน์ของ NSTextTable
    /// ตรวจว่าทุกเซลล์ที่ layout แล้วอยู่ในคอลัมน์ของตัวเอง (x ตรงกับเซลล์หัวตารางของคอลัมน์เดียวกัน)
    /// สาเหตุที่พบ: เมื่อตารางอยู่นอกพื้นที่ที่มองเห็นและถูก layout ด้วย ensureLayout(forCharacterRange/glyphRange) (เช่นจาก scrollRangeToVisible)
    /// NSTextTable วางเซลล์ของแถวที่เซลล์ต้นแถวสูงผิดคอลัมน์ ขณะที่ layout แบบ rect/usedRect ถูกต้อง
    func tableLayoutIsConsistent() -> Bool {
        guard let lm = layoutManager, storage.length > 0 else { return true }
        let laidOut = lm.firstUnlaidCharacterIndex()
        var columnX: [ObjectIdentifier: [Int: CGFloat]] = [:]
        var consistent = true
        storage.enumerateAttribute(.paragraphStyle, in: NSRange(location: 0, length: min(laidOut, storage.length)), options: []) { v, r, stop in
            guard let b = (v as? NSParagraphStyle)?.textBlocks.first as? NSTextTableBlock, NSMaxRange(r) <= laidOut else { return }
            let g = lm.glyphRange(forCharacterRange: r, actualCharacterRange: nil)
            guard g.length > 0 else { return }
            let x = lm.boundsRect(for: b, glyphRange: g).minX
            let id = ObjectIdentifier(b.table)
            if b.startingRow == 0 { columnX[id, default: [:]][b.startingColumn] = x; return }
            if let ref = columnX[id]?[b.startingColumn], abs(ref - x) > 1.5 { consistent = false; stop.pointee = true }
        }
        return consistent
    }

    /// ถ้าเซลล์ถูกวางผิด: ล้าง layout ทั้งเอกสารแล้ว layout ใหม่ด้วยเส้นทาง rect (`usedRect`) ซึ่งถูกต้อง
    @discardableResult
    func repairTableLayoutIfNeeded() -> Bool {
        guard storage.length > 0, let lm = layoutManager, let tc = textContainer, !tableLayoutIsConsistent() else { return false }
        lm.invalidateLayout(forCharacterRange: NSRange(location: 0, length: storage.length), actualCharacterRange: nil)
        _ = lm.usedRect(for: tc)
        needsDisplay = true
        return true
    }

    /// ตรวจ/ซ่อมแบบหน่วงเวลา (รวมการแก้ไขถี่ ๆ)
    func scheduleTableLayoutCheck() {
        tableCheckWork?.cancel()
        let w = DispatchWorkItem { [weak self] in self?.repairTableLayoutIfNeeded() }
        tableCheckWork = w
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12, execute: w)
    }

    // MARK: - เมนู Table
    @objc func jotSelectTable(_ s: Any?) { selectTable() }
    func selectTable() {
        guard let r = tableRange(containing: selectedRange().location) else { return }
        setSelectedRange(r)
    }
    @objc func jotInsertTable(_ s: Any?) { insertDefaultTable() }
    @objc func jotTableRowAbove(_ s: Any?) { insertRow(below: false) }
    @objc func jotTableRowBelow(_ s: Any?) { insertRow(below: true) }
    @objc func jotTableColumnLeft(_ s: Any?) { insertColumn(right: false) }
    @objc func jotTableColumnRight(_ s: Any?) { insertColumn(right: true) }
    @objc func jotTableDeleteRow(_ s: Any?) { deleteRow() }
    @objc func jotTableDeleteColumn(_ s: Any?) { deleteColumn() }
    @objc func jotTableDelete(_ s: Any?) { deleteTable() }
    @objc func jotTableAlignLeft(_ s: Any?) { alignColumn(1) }
    @objc func jotTableAlignCenter(_ s: Any?) { alignColumn(2) }
    @objc func jotTableAlignRight(_ s: Any?) { alignColumn(3) }

    func validateTableItem(_ item: NSMenuItem) -> Bool? {
        guard let a = item.action else { return nil }
        let cell = cellInfo(at: selectedRange().location)
        switch a {
        case #selector(jotSelectTable(_:)): return cell != nil
        case #selector(jotInsertTable(_:)): return !blockKindAtCaret.isCodeLike && cell == nil
        case #selector(jotTableRowAbove(_:)), #selector(jotTableDeleteRow(_:)): return (cell?.row ?? 0) >= 1
        case #selector(jotTableRowBelow(_:)), #selector(jotTableColumnLeft(_:)), #selector(jotTableColumnRight(_:)),
             #selector(jotTableDeleteColumn(_:)), #selector(jotTableDelete(_:)),
             #selector(jotTableAlignLeft(_:)), #selector(jotTableAlignCenter(_:)), #selector(jotTableAlignRight(_:)):
            return cell != nil
        default: return nil
        }
    }

    /// เมนูคลิกขวาในตาราง
    func tableContextMenu() -> NSMenu {
        let m = NSMenu()
        for (t, sel) in [("Select Table", #selector(jotSelectTable(_:))), ("Insert Row Above", #selector(jotTableRowAbove(_:))), ("Insert Row Below", #selector(jotTableRowBelow(_:))),
                         ("Insert Column Left", #selector(jotTableColumnLeft(_:))), ("Insert Column Right", #selector(jotTableColumnRight(_:))),
                         ("Delete Row", #selector(jotTableDeleteRow(_:))), ("Delete Column", #selector(jotTableDeleteColumn(_:))), ("Delete Table", #selector(jotTableDelete(_:))),
                         ("Align Column Left", #selector(jotTableAlignLeft(_:))), ("Align Column Center", #selector(jotTableAlignCenter(_:))), ("Align Column Right", #selector(jotTableAlignRight(_:)))] {
            if t == "Insert Row Above" || t == "Delete Row" || t == "Align Column Left" { m.addItem(.separator()) }
            let i = NSMenuItem(title: t, action: sel, keyEquivalent: ""); i.target = self; m.addItem(i)
        }
        return m
    }
}
