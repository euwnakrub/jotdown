import Foundation

/// ตาราง GFM ในรูปแบบข้อมูลล้วน (แถวแรก = หัวตาราง) แปลงไป-กลับระหว่างบล็อกเซลล์ของ text storage และ markdown
struct TableModel: Equatable {
    var align: [Int]                       // ต่อคอลัมน์: 0 ไม่กำหนด, 1 ซ้าย, 2 กลาง, 3 ขวา
    var rows: [[[InlineSegment]]]          // rows[0] = หัวตาราง

    var cols: Int { align.count }

    init(align: [Int], rows: [[[InlineSegment]]]) {
        let n = max(align.count, rows.map(\.count).max() ?? 0, 1)
        self.align = align + Array(repeating: 0, count: n - align.count)
        var r = rows.isEmpty ? [[]] : rows
        for i in r.indices { r[i] += Array(repeating: [], count: n - r[i].count) }   // เซลล์ไม่เท่ากัน: เติมเซลล์ว่าง
        self.rows = r
    }

    static func empty(rows: Int, cols: Int) -> TableModel {
        TableModel(align: Array(repeating: 0, count: cols), rows: Array(repeating: Array(repeating: [], count: cols), count: max(rows, 1)))
    }

    /// จากบล็อกเซลล์ที่ต่อเนื่องของตารางเดียว
    static func from(_ blocks: [ParsedBlock]) -> TableModel? {
        var cells: [(Int, Int, Int, [InlineSegment])] = []
        for b in blocks { if case .tableCell(let r, let c, let a) = b.kind { cells.append((r, c, a, b.segments)) } }
        guard !cells.isEmpty else { return nil }
        let cols = (cells.filter { $0.0 == 0 }.map { $0.1 }.max() ?? cells.map { $0.1 }.max() ?? 0) + 1
        let rowCount = (cells.map { $0.0 }.max() ?? 0) + 1
        var align = Array(repeating: 0, count: cols)
        var grid = Array(repeating: Array(repeating: [InlineSegment](), count: cols), count: rowCount)
        for (r, c, a, segs) in cells where c < cols {
            grid[r][c] = segs
            if r == 0 { align[c] = a }
        }
        return TableModel(align: align, rows: grid)
    }

    func blocks() -> [ParsedBlock] {
        var out: [ParsedBlock] = []
        for (r, row) in rows.enumerated() { for (c, segs) in row.enumerated() { out.append(ParsedBlock(kind: .tableCell(r, c, align[c]), segments: segs)) } }
        return out
    }

    // MARK: - แก้โครงสร้าง
    mutating func insertRow(at index: Int) {
        let i = min(max(index, 1), rows.count)
        rows.insert(Array(repeating: [], count: cols), at: i)
    }
    mutating func insertColumn(at index: Int) {
        let i = min(max(index, 0), cols)
        align.insert(0, at: i)
        for r in rows.indices { rows[r].insert([], at: i) }
    }
    mutating func deleteRow(_ r: Int) { if r >= 1, r < rows.count { rows.remove(at: r) } }
    mutating func deleteColumn(_ c: Int) {
        guard cols > 1, c < cols else { return }
        align.remove(at: c)
        for r in rows.indices { rows[r].remove(at: c) }
    }

    // MARK: - markdown
    /// ความกว้างเมื่อแสดงในฟอนต์ monospace: อักขระไทยผสมสระ/วรรณยุกต์นับรวมเป็น 1 (grapheme cluster), CJK/emoji = 2
    static func displayWidth(_ s: String) -> Int {
        var w = 0
        for ch in s {
            guard let first = ch.unicodeScalars.first else { continue }
            let v = first.value
            let wide = (0x1100...0x115F).contains(v) || (0x2E80...0xA4CF).contains(v) || (0xAC00...0xD7A3).contains(v) || (0xF900...0xFAFF).contains(v)
                || (0xFE30...0xFE6F).contains(v) || (0xFF00...0xFF60).contains(v) || (0xFFE0...0xFFE6).contains(v) || (0x1F300...0x1FAFF).contains(v)
            let markOnly = ch.unicodeScalars.allSatisfy { [.nonspacingMark, .spacingMark, .enclosingMark, .format].contains($0.properties.generalCategory) }
            w += markOnly ? 0 : (wide ? 2 : 1)
        }
        return w
    }

    static func cellText(_ segs: [InlineSegment]) -> String {
        InlineWriter.write(segs, pipeEscape: true).replacingOccurrences(of: "\\\n", with: "<br>").replacingOccurrences(of: "\n", with: "<br>")
    }

    func markdown() -> String {
        let text = rows.map { $0.map(Self.cellText) }
        var widths = Array(repeating: 3, count: cols)
        for row in text { for (c, t) in row.enumerated() { widths[c] = max(widths[c], Self.displayWidth(t)) } }
        func pad(_ t: String, _ c: Int) -> String {
            let gap = widths[c] - Self.displayWidth(t)
            switch align[c] {
            case 3: return String(repeating: " ", count: gap) + t
            case 2: let l = gap / 2; return String(repeating: " ", count: l) + t + String(repeating: " ", count: gap - l)
            default: return t + String(repeating: " ", count: gap)
            }
        }
        func line(_ cells: [String]) -> String { "| " + cells.enumerated().map { pad($1, $0) }.joined(separator: " | ") + " |" }
        var sep: [String] = []
        for c in 0..<cols {
            let w = widths[c]
            switch align[c] {
            case 1: sep.append(":" + String(repeating: "-", count: w - 1))
            case 2: sep.append(":" + String(repeating: "-", count: w - 2) + ":")
            case 3: sep.append(String(repeating: "-", count: w - 1) + ":")
            default: sep.append(String(repeating: "-", count: w))
            }
        }
        var out = [line(text[0]), "| " + sep.joined(separator: " | ") + " |"]
        for row in text.dropFirst() { out.append(line(row)) }
        return out.joined(separator: "\n")
    }
}
