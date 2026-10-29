import AppKit

/// ค่าคงที่ของหน้าตา + ตัวสร้าง attribute ของบล็อก/inline ทุกชนิด
enum Theme {
    static let bodySize: CGFloat = 16
    static let bodyLineHeightMultiple: CGFloat = 1.6     // ความสูงบรรทัดขั้นต่ำ = ขนาดฟอนต์ x 1.6 (เผื่อสระบน-ล่างภาษาไทย)
    static let headingLineHeightMultiple: CGFloat = 1.35
    static let italicObliqueness: CGFloat = 0.15
    static let listIndent: CGFloat = 24
    static let quoteIndent: CGFloat = 18
    static let codePadding: CGFloat = 14

    static let columnMaxWidth: CGFloat = 720
    static let columnMinMargin: CGFloat = 24
    static let verticalInset: CGFloat = 40

    static let defaultWindowSize = NSSize(width: 900, height: 700)
    static let minWindowSize = NSSize(width: 480, height: 360)

    /// (ขนาด, ระยะบน, ระยะล่าง, น้ำหนัก) ของหัวข้อแต่ละระดับ
    static func headingSpec(_ level: Int) -> (size: CGFloat, before: CGFloat, after: CGFloat, weight: Fonts.Weight) {
        switch level {
        case 1: return (28, 28, 8, .semibold)
        case 2: return (22, 24, 6, .semibold)
        case 3: return (18, 20, 4, .semibold)
        default: return (bodySize, 16, 4, .bold)
        }
    }

    static var monoSize: CGFloat { bodySize - 1 }

    // MARK: - ฟอนต์
    private static var fontCache: [String: NSFont] = [:]
    private static let lock = NSLock()

    static func font(for kind: BlockKind, inline: InlineStyle = []) -> NSFont {
        lock.lock(); defer { lock.unlock() }
        let bold = inline.contains(.bold)
        var header = false
        if case .tableCell(let r, _, _) = kind { header = r == 0 }
        let key = "\(kind.code.prefix(2))|\(kind.isHeading ? kind.code : "")|\(bold || header)|\(inline.contains(.code))"
        if let f = fontCache[key] { return f }
        let f: NSFont
        switch kind {
        case .codeBlock, .raw:
            f = NSFont.monospacedSystemFont(ofSize: monoSize, weight: bold ? .bold : .regular)
        case .heading(let l):
            let s = headingSpec(l)
            if inline.contains(.code) { f = NSFont.monospacedSystemFont(ofSize: s.size - 1, weight: .semibold) }
            else { f = Fonts.heading(bold ? .bold : s.weight, size: s.size) }
        default:
            if inline.contains(.code) { f = NSFont.monospacedSystemFont(ofSize: monoSize, weight: bold || header ? .bold : .regular) }
            else { f = Fonts.body(bold || header ? .bold : .regular) }
        }
        fontCache[key] = f
        return f
    }

    // MARK: - paragraph style
    private static var styleCache: [String: NSParagraphStyle] = [:]

    /// ระยะหลังย่อหน้าตามบล็อกถัดไป (nil = ใช้ค่าปกติของชนิดนั้น)
    static func gap(after kind: BlockKind, next: BlockKind?) -> CGFloat? {
        func ordered(_ k: BlockKind) -> Bool { if case .ordered = k { return true } else { return false } }
        if kind.isList {
            guard let n = next, n.isList else { return 6 }
            if n.listLevel == 0, ordered(n) != ordered(kind) { return 10 }   // ลิสต์ใหม่ชนิดอื่น
            return 4
        }
        if kind == .quote { return next == .quote ? 4 : 6 }
        return nil
    }

    static func paragraphStyle(for kind: BlockKind, spacing: CGFloat? = nil) -> NSParagraphStyle {
        lock.lock(); defer { lock.unlock() }
        var key: String
        if let l = kind.listLevel { key = "list\(l)" } else if kind.isCode { key = "code" } else { key = kind.code }
        if let sp = spacing { key += "|\(sp)" }
        if let s = styleCache[key] { return s }
        let p = NSMutableParagraphStyle()
        let body = (bodySize * bodyLineHeightMultiple).rounded()
        switch kind {
        case .heading(let l):
            let s = headingSpec(l)
            p.minimumLineHeight = (s.size * headingLineHeightMultiple).rounded()
            p.paragraphSpacingBefore = s.before
            p.paragraphSpacing = s.after
        case .bullet, .ordered, .task:
            let l = CGFloat(kind.listLevel ?? 0)
            p.minimumLineHeight = body
            p.firstLineHeadIndent = listIndent * (l + 1)
            p.headIndent = listIndent * (l + 1)
            p.paragraphSpacing = 4
        case .quote:
            p.minimumLineHeight = body
            p.firstLineHeadIndent = quoteIndent
            p.headIndent = quoteIndent
            p.paragraphSpacingBefore = 2
            p.paragraphSpacing = 6
        case .codeBlock, .raw:
            p.minimumLineHeight = (monoSize * 1.5).rounded()
            p.firstLineHeadIndent = codePadding
            p.headIndent = codePadding
            p.tailIndent = -codePadding
            p.paragraphSpacingBefore = 12
            p.paragraphSpacing = 12
        case .thematicBreak:
            p.minimumLineHeight = body
            p.paragraphSpacingBefore = 8
            p.paragraphSpacing = 8
        case .tableCell:
            p.minimumLineHeight = body
            p.paragraphSpacing = 0
        case .paragraph:
            p.minimumLineHeight = body
            p.paragraphSpacingBefore = 4
            p.paragraphSpacing = 6
        }
        if let sp = spacing { p.paragraphSpacing = sp }
        styleCache[key] = p
        return p
    }

    /// paragraph style ของเซลล์ตาราง (NSTextTableBlock) แคชไว้ที่ตัวตารางเพื่อให้เทียบเท่ากันได้
    static func tableStyle(_ kind: BlockKind, _ table: NSTextTable?) -> NSParagraphStyle? {
        guard case .tableCell(let r, let c, let a) = kind, let t = table as? JotTable else { return nil }
        let key = "\(r).\(c).\(a).\(t.rowCount)"
        if let s = t.styleCache[key] { return s }
        let b = NSTextTableBlock(table: t, startingRow: r, rowSpan: 1, startingColumn: c, columnSpan: 1)
        // เส้นขอบ: ใช้ collapsesBorders=false (แบบ collapse ทำให้เส้นขวานอกสุดหายเมื่อตารางกว้างเท่า container)
        // จึงวาดเส้นเองต่อเซลล์ให้บางเท่ากันทุกเส้น: ซ้าย/บนเฉพาะเซลล์ริม, ขวา/ล่างทุกเซลล์
        for edge in [NSRectEdge.minX, .minY, .maxX, .maxY] {
            let outerLeading = (edge == .minX && c == 0) || (edge == .minY && r == 0)
            let w: CGFloat = (edge == .maxX || edge == .maxY || outerLeading) ? 0.5 : 0
            b.setWidth(w, type: .absoluteValueType, for: .border, edge: edge)
        }
        b.setBorderColor(Palette.tableBorder)
        b.setWidth(7, type: .absoluteValueType, for: .padding)
        b.verticalAlignment = .topAlignment
        if r == 0 { b.backgroundColor = Palette.tableHeader }
        if r == 0 { b.setWidth(8, type: .absoluteValueType, for: .margin, edge: .minY) }
        if r == t.rowCount - 1 { b.setWidth(12, type: .absoluteValueType, for: .margin, edge: .maxY) }
        let p = NSMutableParagraphStyle()
        p.minimumLineHeight = (bodySize * bodyLineHeightMultiple).rounded()
        p.paragraphSpacing = 0
        p.alignment = a == 2 ? .center : (a == 3 ? .right : .left)
        p.textBlocks = [b]
        t.styleCache[key] = p
        return p
    }

    // MARK: - attribute ทั้งชุด
    /// attribute ทั้งชุดของบล็อก + inline style + ลิงก์ (ใช้ทั้งตอน parse, restyle และ typingAttributes)
    static func attributes(for kind: BlockKind, inline: InlineStyle = [], link: String? = nil, spacing: CGFloat? = nil, table: NSTextTable? = nil) -> [NSAttributedString.Key: Any] {
        let inl = kind.allowsInline ? inline : []
        let lnk = kind.allowsInline ? link : nil
        var a: [NSAttributedString.Key: Any] = [
            .font: font(for: kind, inline: inl),
            .paragraphStyle: tableStyle(kind, table) ?? paragraphStyle(for: kind, spacing: spacing),
            .foregroundColor: Palette.text,
            .jotBlock: kind.code,
        ]
        if inl.rawValue != 0 { a[.jotInline] = inl.rawValue }
        if inl.contains(.italic) { a[.obliqueness] = italicObliqueness }
        var strike = inl.contains(.strike)
        if case .task(_, true) = kind { strike = true; a[.foregroundColor] = Palette.secondaryText }
        if strike { a[.strikethroughStyle] = NSUnderlineStyle.single.rawValue }
        if inl.contains(.raw) { a[.foregroundColor] = Palette.secondaryText }
        if kind == .raw { a[.foregroundColor] = Palette.secondaryText }
        if let lnk {
            a[.jotLink] = lnk
            a[.foregroundColor] = inl.contains(.unresolved) ? Palette.secondaryText : Palette.link
            a[.underlineStyle] = NSUnderlineStyle.single.rawValue
            a[.underlineColor] = Palette.linkUnderline
        }
        return a
    }
}

extension NSMutableAttributedString {
    /// คำนวณ attribute ที่แสดงผลใหม่ให้ทุกย่อหน้าที่ช่วง `range` แตะ: ชนิดบล็อกตามตัวอักษรแรกของย่อหน้า
    /// inline style (`.jotInline`/`.jotLink`) คงไว้ ส่วนฟอนต์/สี/ย่อหน้าคำนวณจาก Theme
    func restyleParagraphs(in range: NSRange) {
        guard length > 0 else { return }
        let ns = string as NSString
        let loc = min(range.location, ns.length)
        let target = ns.paragraphRange(for: NSRange(location: loc, length: min(range.length, ns.length - loc)))
        var p = target.location
        while p < NSMaxRange(target) {
            let pr = ns.paragraphRange(for: NSRange(location: p, length: 0))
            restyleOne(pr)
            p = NSMaxRange(pr)
        }
    }

    private func restyleOne(_ pr: NSRange) {
        let kind = blockKind(at: pr.location)
        var contentEnd = NSMaxRange(pr)
        let ns = string as NSString
        let hasNewline = contentEnd > pr.location && ns.character(at: contentEnd - 1) == 0x0A
        if hasNewline { contentEnd -= 1 }
        // เปลี่ยนเฉพาะช่วงที่ attribute ต่างจริง (การแก้ attribute ใน willProcessEditing ทำให้ editedRange โต แล้วเคอร์เซอร์เลื่อน)
        let next: BlockKind? = NSMaxRange(pr) < length ? blockKind(at: NSMaxRange(pr)) : nil
        let spacing = Theme.gap(after: kind, next: next)
        var table: NSTextTable?
        if kind.isTableCell, let ps = attribute(.paragraphStyle, at: pr.location, effectiveRange: nil) as? NSParagraphStyle { table = (ps.textBlocks.first as? NSTextTableBlock)?.table }
        var updates: [(NSRange, [NSAttributedString.Key: Any])] = []
        if contentEnd > pr.location {
            enumerateAttributes(in: NSRange(location: pr.location, length: contentEnd - pr.location), options: []) { attrs, r, _ in
                var want = Theme.attributes(for: kind, inline: InlineStyle(rawValue: (attrs[.jotInline] as? Int) ?? 0), link: attrs[.jotLink] as? String, spacing: spacing, table: table)
                if let a = attrs[.attachment] { want[.attachment] = a }
                if let j = attrs[.jotImage] { want[.jotImage] = j }
                if let w = attrs[.jotWiki] { want[.jotWiki] = w }
                if !(attrs as NSDictionary).isEqual(to: want) { updates.append((r, want)) }
            }
        }
        if hasNewline {
            let r = NSRange(location: contentEnd, length: 1)
            let want = Theme.attributes(for: kind, spacing: spacing, table: table)
            if !(attributes(at: contentEnd, effectiveRange: nil) as NSDictionary).isEqual(to: want) { updates.append((r, want)) }
        }
        for (r, a) in updates { setAttributes(a, range: r) }
    }

    /// ตั้งชนิดบล็อกให้ย่อหน้าทั้งหมดในช่วง แล้ว restyle (inline style คงไว้ถ้าชนิดใหม่รองรับ)
    func setBlockKind(_ kind: BlockKind, in range: NSRange) {
        guard length > 0 else { return }
        let ns = string as NSString
        let loc = min(range.location, ns.length)
        let target = ns.paragraphRange(for: NSRange(location: loc, length: min(range.length, ns.length - loc)))
        addAttribute(.jotBlock, value: kind.code, range: target)
        restyleParagraphs(in: target)
    }
}


/// ตารางของเรา: เก็บจำนวนแถว + แคช paragraph style ของเซลล์
final class JotTable: NSTextTable {
    var rowCount = 1
    var styleCache: [String: NSParagraphStyle] = [:]
    override init() {
        super.init()
        layoutAlgorithm = .automaticLayoutAlgorithm
        collapsesBorders = false
        setContentWidth(100, type: .percentageValueType)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) not supported") }
}

/// สีทั้งหมดของแอปอยู่ที่นี่ (dynamic NSColor สว่าง/มืด) — ธีมเหลืองอำพันอบอุ่นสื่อถึงความคิดสร้างสรรค์
enum Palette {
    struct Pair { var light: UInt32; var dark: UInt32 }

    // ค่าฐาน (hex) แยกไว้ให้เทสต์คำนวณ contrast ได้
    static let paperHex = Pair(light: 0xFFFDF5, dark: 0x1F1C17)
    static let textHex = Pair(light: 0x2B2620, dark: 0xF1ECE0)
    static let linkHex = Pair(light: 0x7A4F00, dark: 0xF5C542)         // ข้อความลิงก์ (เหลืองเข้ม/ทองเข้มบนพื้นสว่าง, เหลืองสว่างบนพื้นมืด)
    static let linkUnderlineHex = Pair(light: 0xF2B21B, dark: 0xF2B21B)
    static let accentHex = Pair(light: 0xF2B21B, dark: 0xF5C542)       // เหลืองอำพัน
    static let caretHex = Pair(light: 0xD99A00, dark: 0xF5C542)
    static let selectionHex = Pair(light: 0xF8DC85, dark: 0x6B5316)    // พื้นข้อความที่เลือก (ข้อความยังอ่านชัด)
    static let codeBackgroundHex = Pair(light: 0xF3EDDA, dark: 0x2D2921)
    static let tableHeaderHex = Pair(light: 0xF5EEDA, dark: 0x2A261E)
    static let borderHex = Pair(light: 0xDDD3B8, dark: 0x3C372C)
    static let secondaryTextHex = Pair(light: 0x7A7160, dark: 0xA79F8D)

    static func color(_ p: Pair) -> NSColor {
        func ns(_ v: UInt32) -> NSColor {
            NSColor(srgbRed: CGFloat((v >> 16) & 0xFF) / 255, green: CGFloat((v >> 8) & 0xFF) / 255, blue: CGFloat(v & 0xFF) / 255, alpha: 1)
        }
        return NSColor(name: nil) { ap in
            ap.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? ns(p.dark) : ns(p.light)
        }
    }

    static let paper = color(paperHex)
    static let text = color(textHex)
    static let link = color(linkHex)
    static let linkUnderline = color(linkUnderlineHex)
    static let accent = color(accentHex)
    static let caret = color(caretHex)
    static let selection = color(selectionHex)
    static let codeBackground = color(codeBackgroundHex)
    static let tableHeader = color(tableHeaderHex)
    static let tableBorder = color(borderHex)
    static let rule = color(borderHex)
    static let secondaryText = color(secondaryTextHex)
    /// ตัวหนังสือบนปุ่ม/กล่องที่พื้นเหลือง
    static let onAccent = NSColor(srgbRed: 0.17, green: 0.15, blue: 0.12, alpha: 1)

    /// contrast ratio ตาม WCAG ของสี hex สองสี
    static func contrast(_ a: UInt32, _ b: UInt32) -> Double {
        func lum(_ v: UInt32) -> Double {
            func ch(_ x: UInt32) -> Double { let c = Double(x) / 255; return c <= 0.03928 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4) }
            return 0.2126 * ch((v >> 16) & 0xFF) + 0.7152 * ch((v >> 8) & 0xFF) + 0.0722 * ch(v & 0xFF)
        }
        let l1 = lum(a), l2 = lum(b)
        return (max(l1, l2) + 0.05) / (min(l1, l2) + 0.05)
    }
}
