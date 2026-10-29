import AppKit

/// ชนิดบล็อก (ระดับย่อหน้า) เก็บเป็น attribute `.jotBlock` ของทุกตัวอักษรในย่อหน้า (ค่า = `code` เป็น NSString)
/// หนึ่งย่อหน้าใน text storage = หนึ่งบล็อก (กล่องโค้ด/ข้อความดิบใช้ U+2028 คั่นบรรทัดในย่อหน้าเดียว)
enum BlockKind: Equatable, Hashable {
    case paragraph
    case heading(Int)            // 1...6
    case bullet(Int)             // ระดับซ้อน 0...
    case ordered(Int)
    case task(Int, Bool)         // ระดับ, ติ๊กแล้ว
    case quote
    case codeBlock(String)       // ภาษา (info string)
    case thematicBreak
    case tableCell(Int, Int, Int)   // แถว (0 = หัวตาราง), คอลัมน์, การจัดชิด (0 ไม่กำหนด, 1 ซ้าย, 2 กลาง, 3 ขวา)
    case raw                     // markdown ที่ยังไม่รองรับ (ตาราง รูปภาพ HTML ฯลฯ) เก็บดิบ ไม่เสียเนื้อหา

    var code: String {
        switch self {
        case .paragraph: return "p"
        case .heading(let l): return "h\(min(max(l, 1), 6))"
        case .bullet(let l): return "ul\(l)"
        case .ordered(let l): return "ol\(l)"
        case .task(let l, let c): return "tk\(l)\(c ? "x" : "o")"
        case .quote: return "q"
        case .codeBlock(let lang): return "code:" + lang
        case .thematicBreak: return "hr"
        case .raw: return "raw"
        case .tableCell(let r, let c, let a): return "tc\(r).\(c).\(a)"
        }
    }

    init(code: String) {
        if code.hasPrefix("tc") {
            let p = code.dropFirst(2).split(separator: ".").compactMap { Int($0) }
            if p.count == 3 { self = .tableCell(p[0], p[1], p[2]); return }
        }
        if code.hasPrefix("code:") { self = .codeBlock(String(code.dropFirst(5))); return }
        if code.hasPrefix("ul"), let l = Int(code.dropFirst(2)) { self = .bullet(l); return }
        if code.hasPrefix("ol"), let l = Int(code.dropFirst(2)) { self = .ordered(l); return }
        if code.hasPrefix("tk"), let last = code.last, let l = Int(code.dropFirst(2).dropLast()) { self = .task(l, last == "x"); return }
        if code.hasPrefix("h"), let l = Int(code.dropFirst()), (1...6).contains(l) { self = .heading(l); return }
        switch code {
        case "q": self = .quote
        case "hr": self = .thematicBreak
        case "raw": self = .raw
        default: self = .paragraph
        }
    }

    var isTableCell: Bool { if case .tableCell = self { return true } else { return false } }
    var isHeading: Bool { if case .heading = self { return true } else { return false } }
    var isList: Bool { listLevel != nil }
    var listLevel: Int? {
        switch self {
        case .bullet(let l), .ordered(let l), .task(let l, _): return l
        default: return nil
        }
    }
    var isCodeLike: Bool { switch self { case .codeBlock, .raw: return true; default: return false } }
    var isCode: Bool { if case .codeBlock = self { return true } else { return false } }
    /// รองรับ inline style (ตัวหนา เอียง ลิงก์ ฯลฯ) หรือไม่
    var allowsInline: Bool {
        switch self { case .codeBlock, .raw, .thematicBreak: return false; default: return true }
    }
    func withListLevel(_ l: Int) -> BlockKind {
        switch self {
        case .bullet: return .bullet(l)
        case .ordered: return .ordered(l)
        case .task(_, let c): return .task(l, c)
        default: return self
        }
    }
}

/// inline style ที่เก็บใน attribute `.jotInline` (NSNumber)
struct InlineStyle: OptionSet, Hashable {
    let rawValue: Int
    static let bold = InlineStyle(rawValue: 1)
    static let italic = InlineStyle(rawValue: 2)
    static let strike = InlineStyle(rawValue: 4)
    static let code = InlineStyle(rawValue: 8)
    /// ข้อความ markdown ดิบ (เช่นรูปภาพในย่อหน้า) เขียนออกตรง ๆ ไม่ escape
    static let raw = InlineStyle(rawValue: 16)
    /// ตัวคั่นบรรทัดแบบ hard break (`\` ท้ายบรรทัด)
    static let hardBreak = InlineStyle(rawValue: 32)
    /// ลิงก์ Obsidian ที่หาโน้ตไม่เจอ (แสดงสีจาง; ไม่ใช้ตอน serialize)
    static let unresolved = InlineStyle(rawValue: 64)
    /// เฉพาะที่ผู้ใช้สลับด้วยคีย์ลัดได้
    static let toggleable: InlineStyle = [.bold, .italic, .strike, .code]
}

extension NSAttributedString.Key {
    static let jotBlock = NSAttributedString.Key("com.euw.jot.block")
    static let jotInline = NSAttributedString.Key("com.euw.jot.inline")
    static let jotLink = NSAttributedString.Key("com.euw.jot.link")
    /// รูปภาพ (ค่า = `ImageRef.encoded`) ตัวอักษร U+FFFC 1 ตัวที่มี `.attachment` ของเรา
    static let jotImage = NSAttributedString.Key("com.euw.jot.image")
    /// ลิงก์ Obsidian (ค่า = ข้อความดิบ `[[…]]` ทั้งก้อน เขียนกลับตามเดิม)
    static let jotWiki = NSAttributedString.Key("com.euw.jot.wiki")
}

extension NSAttributedString {
    func blockKind(at index: Int) -> BlockKind {
        guard length > 0 else { return .paragraph }
        let i = min(max(index, 0), length - 1)
        if let code = attribute(.jotBlock, at: i, effectiveRange: nil) as? String { return BlockKind(code: code) }
        return .paragraph
    }

    func inlineStyle(at index: Int) -> InlineStyle {
        guard index >= 0, index < length else { return [] }
        return InlineStyle(rawValue: (attribute(.jotInline, at: index, effectiveRange: nil) as? Int) ?? 0)
    }
    func link(at index: Int) -> String? {
        guard index >= 0, index < length else { return nil }
        return attribute(.jotLink, at: index, effectiveRange: nil) as? String
    }
}

/// ตัวคั่นบรรทัดอ่อนภายในย่อหน้า (soft break) ใน text storage — "\n" ใช้แทนการขึ้นย่อหน้าใหม่
let softBreakCharacter: Character = "\u{2028}"
let softBreakString = "\u{2028}"
/// ตัวอักษรเดียวที่เป็นเนื้อหาของเส้นคั่น (zero-width space)
let thematicBreakText = "\u{200B}"

/// ตัวเลขของรายการลิสต์ตัวเลขแต่ละรายการ (nil = ไม่ใช่ลิสต์ตัวเลข) ใช้ร่วมกันระหว่างตัววาดและ serializer
enum ListNumbering {
    static func numbers(for kinds: [BlockKind]) -> [Int?] {
        var counters: [Int] = []
        var out: [Int?] = []
        for k in kinds {
            guard let l = k.listLevel else { counters = []; out.append(nil); continue }
            while counters.count > l + 1 { counters.removeLast() }
            while counters.count < l + 1 { counters.append(0) }
            if case .ordered = k { counters[l] += 1; out.append(counters[l]) } else { counters[l] = 0; out.append(nil) }
        }
        return out
    }
}

/// รูปภาพใน markdown: `![alt](src "title")` หรือ `![[รูป.png|300]]` / `![[โน้ต]]` ของ Obsidian (`raw` != nil)
struct ImageRef: Equatable {
    var src: String
    var alt: String
    var title: String?
    var raw: String? = nil        // ข้อความดิบของ Obsidian (เขียนกลับตามเดิม)
    var width: Int? = nil
    var height: Int? = nil
    var noteEmbed = false         // ![[โน้ต]] ไม่ใช่รูป: แสดงเป็นการ์ดลิงก์

    var encoded: String {
        [src, alt, title ?? "\u{2}", raw ?? "\u{2}", width.map(String.init) ?? "", height.map(String.init) ?? "", noteEmbed ? "1" : ""].joined(separator: "\u{1}")
    }
    init(src: String, alt: String, title: String? = nil, raw: String? = nil, width: Int? = nil, height: Int? = nil, noteEmbed: Bool = false) {
        self.src = src; self.alt = alt; self.title = title; self.raw = raw; self.width = width; self.height = height; self.noteEmbed = noteEmbed
    }
    init?(encoded: String) {
        let p = encoded.components(separatedBy: "\u{1}")
        guard p.count == 3 || p.count == 7 else { return nil }
        self.init(src: p[0], alt: p[1], title: p[2] == "\u{2}" ? nil : p[2])
        if p.count == 7 {
            raw = p[3] == "\u{2}" ? nil : p[3]
            width = Int(p[4]); height = Int(p[5]); noteEmbed = p[6] == "1"
        }
    }
}

/// ตัวอักษรแทนรูปใน text storage
let imageCharacter = "\u{FFFC}"
