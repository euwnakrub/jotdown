import Foundation

/// รูปแบบของ Obsidian: `[[โน้ต]]`, `[[โน้ต#หัวข้อ|ข้อความแสดง]]`, `![[รูป.png|300]]`, `![[โน้ต]]` (ฝัง)
/// เก็บข้อความดิบไว้ครบทุกตัวอักษรเพื่อ round-trip (ห้ามแปลงเป็น markdown มาตรฐาน)
struct WikiLink: Equatable {
    var raw: String            // ข้อความต้นฉบับทั้งก้อน เช่น "![[a.png|300]]"
    var embed: Bool
    var target: String         // ชื่อไฟล์/โน้ต (ไม่รวม #หัวข้อ)
    var heading: String?
    var alias: String?         // ข้อความแสดง (สำหรับ [[a|b]]) — ใน embed รูปคือ alt
    var width: Int?
    var height: Int?

    var isImage: Bool { embed && ObsidianSyntax.isImageName(target) }
    var isNoteEmbed: Bool { embed && !isImage }

    /// ข้อความที่แสดงแทน `[[ ]]`
    var display: String {
        if let a = alias, !a.isEmpty, !isImage { return a }
        if target.isEmpty { return heading ?? "" }
        if let h = heading { return target + " > " + h }
        return target
    }

    /// ค่าที่เก็บใน `.jotLink` (ขึ้นต้นด้วย wiki: ให้ตัวเปิดลิงก์รู้ว่าเป็นของ Obsidian)
    var linkValue: String { "wiki:" + target + (heading.map { "#" + $0 } ?? "") }
}

enum ObsidianSyntax {
    static let imageExtensions: Set<String> = ["png", "jpg", "jpeg", "gif", "webp", "svg", "heic", "bmp", "tiff", "tif", "avif"]
    static let open = "\u{E000}", close = "\u{E001}"

    static func isImageName(_ name: String) -> Bool { imageExtensions.contains((name as NSString).pathExtension.lowercased()) }

    /// แยกข้อความดิบ `[[…]]` / `![[…]]`
    static func parse(raw: String) -> WikiLink? {
        var s = raw
        var embed = false
        if s.hasPrefix("!") { embed = true; s.removeFirst() }
        guard s.hasPrefix("[["), s.hasSuffix("]]"), s.count >= 5 else { return nil }
        var inner = String(s.dropFirst(2).dropLast(2))
        var alias: String?
        // `|` ตัวแรก (รวมแบบ escape `\|` ที่ Obsidian เขียนในตาราง)
        if let r = inner.range(of: #"\\?\|"#, options: .regularExpression) {
            alias = String(inner[r.upperBound...])
            inner = String(inner[..<r.lowerBound])
        }
        var target = inner, heading: String?
        if let h = inner.firstIndex(of: "#") {
            target = String(inner[..<h]); heading = String(inner[inner.index(after: h)...])
        }
        target = target.trimmingCharacters(in: .whitespaces)
        var w: Int?, hgt: Int?
        if embed, isImageName(target), let a = alias?.trimmingCharacters(in: .whitespaces),
           let m = a.range(of: #"^(\d+)(?:x(\d+))?$"#, options: .regularExpression) {
            let parts = a[m].split(separator: "x").map { Int($0) }
            w = parts.first ?? nil; hgt = parts.count > 1 ? parts[1] : nil
            alias = nil
        }
        if target.isEmpty && heading == nil { return nil }
        return WikiLink(raw: raw, embed: embed, target: target, heading: heading, alias: alias, width: w, height: hgt)
    }

    /// แทน `[[…]]` / `![[…]]` นอกโค้ดด้วย placeholder ที่คงโครงบรรทัดเดิม (ไม่ให้ cmark แตะ `_` `*` `|` ในชื่อ)
    static func preprocess(_ md: String) -> (text: String, raws: [String]) {
        guard md.contains("[[") else { return (md, []) }
        var out = ""
        var raws: [String] = []
        var fence: Character?
        var fenceLen = 0
        for (i, lineSub) in md.split(separator: "\n", omittingEmptySubsequences: false).enumerated() {
            if i > 0 { out += "\n" }
            let line = String(lineSub)
            let trimmed = line.drop(while: { $0 == " " })
            if let f = fence {
                if trimmed.first == f, trimmed.prefix(while: { $0 == f }).count >= fenceLen, trimmed.dropFirst(fenceLen).allSatisfy({ $0 == f || $0 == " " }) { fence = nil }
                out += line; continue
            }
            if let c = trimmed.first, c == "`" || c == "~" {
                let n = trimmed.prefix(while: { $0 == c }).count
                if n >= 3 { fence = c; fenceLen = n; out += line; continue }
            }
            if line.hasPrefix("    ") || line.hasPrefix("\t") { out += line; continue }   // โค้ดแบบเยื้อง (พอประมาณ)
            out += replaceInline(line, raws: &raws)
        }
        return (out, raws)
    }

    private static func replaceInline(_ line: String, raws: inout [String]) -> String {
        guard line.contains("[[") else { return line }
        let chars = Array(line)
        var out = "", i = 0
        while i < chars.count {
            let c = chars[i]
            if c == "`" {   // ข้าม code span
                var n = 0; while i + n < chars.count, chars[i + n] == "`" { n += 1 }
                let fence = String(repeating: "`", count: n)
                var j = i + n, closed = false
                while j + n <= chars.count {
                    if String(chars[j..<(j + n)]) == fence, (j + n == chars.count || chars[j + n] != "`") { closed = true; break }
                    j += 1
                }
                if closed { out += String(chars[i..<(j + n)]); i = j + n; continue }
                out += fence; i += n; continue
            }
            var start = i
            if c == "!", i + 2 < chars.count, chars[i + 1] == "[", chars[i + 2] == "[" { start = i; }
            else if !(c == "[" && i + 1 < chars.count && chars[i + 1] == "[") { out.append(c); i += 1; continue }
            let bracketStart = chars[start] == "!" ? start + 1 : start
            // หา "]]" ปิดโดยไม่มี [ ] ซ้อนและไม่ข้ามบรรทัด
            var j = bracketStart + 2
            var ok = false
            while j + 1 < chars.count {
                if chars[j] == "]" && chars[j + 1] == "]" { ok = true; break }
                if chars[j] == "[" || chars[j] == "]" { break }
                j += 1
            }
            if ok, j > bracketStart + 2 {
                let raw = String(chars[start..<(j + 2)])
                if parse(raw: raw) != nil {
                    out += open + String(raws.count) + close
                    raws.append(raw)
                    i = j + 2
                    continue
                }
            }
            out.append(c); i += 1
        }
        return out
    }

    /// frontmatter (YAML) ต้นไฟล์: คืนจำนวนบรรทัดที่เป็น frontmatter (รวม `---` ปิด) หรือ 0
    static func frontmatterLineCount(_ lines: [String]) -> Int {
        guard let first = lines.first, first.trimmingCharacters(in: .whitespaces) == "---", lines.count >= 3 else { return 0 }
        for i in 1..<lines.count {
            let t = lines[i].trimmingCharacters(in: .whitespaces)
            if t == "---" || t == "..." {
                let body = lines[1..<i].filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
                guard let firstBody = body.first else { return 0 }
                let looksYAML = firstBody.range(of: #"^\s*[\p{L}\p{N}_\-"' ]+:"#, options: .regularExpression) != nil || firstBody.hasPrefix("- ") || firstBody.hasPrefix("#")
                return looksYAML ? i + 1 : 0
            }
        }
        return 0
    }
}
