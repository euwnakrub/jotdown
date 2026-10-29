import Foundation

struct InlineSegment: Equatable {
    var text: String            // อาจมี U+2028 (ขึ้นบรรทัดในย่อหน้า)
    var style: InlineStyle = []
    var link: String? = nil
    var image: ImageRef? = nil
    var wiki: String? = nil          // ข้อความดิบ `[[…]]` ของ Obsidian (text = ข้อความที่แสดง)
}

/// เขียนข้อความ inline เป็น markdown: escape อักขระพิเศษ, ย้ายช่องว่างออกนอกเครื่องหมาย, ซ้อน style ได้
enum InlineWriter {
    static func isWhitespace(_ c: Character) -> Bool { c == " " || c == "\t" || c == softBreakCharacter }
    private static func isWord(_ c: Character) -> Bool { c.isLetter || c.isNumber || c.unicodeScalars.contains { $0.properties.generalCategory == .nonspacingMark || $0.properties.generalCategory == .spacingMark } }
    private static func isASCIIPunct(_ c: Character) -> Bool { c.isASCII && c.isPunctuation || "$+<=>^`|~".contains(c) }

    // MARK: - escape
    /// คืน string ที่ escape แล้วของแต่ละตัวอักษร (ตัวที่ไม่ต้อง escape = ตัวเอง)
    static func escapedCharacters(_ chars: [Character], escapable: [Bool], isHeading: Bool, pipe: Bool = false) -> [String] {
        let n = chars.count
        var out = chars.map { String($0) }
        var extra = Set<Int>()   // ตำแหน่งที่ต้องใส่ \ นำหน้า
        var bracketEscaped = Set<Int>()
        func at(_ i: Int) -> Character? { i >= 0 && i < n ? chars[i] : nil }
        func lineStart(_ i: Int) -> Bool { i == 0 || chars[i - 1] == softBreakCharacter }
        func endsLine(_ i: Int) -> Bool { i >= n || chars[i] == softBreakCharacter }
        func lineAll(_ i: Int, _ c: Character) -> Bool {
            var j = i
            while j < n, chars[j] != softBreakCharacter { if chars[j] != c { return false }; j += 1 }
            return true
        }
        for i in 0..<n where escapable[i] {
            let c = chars[i]
            switch c {
            case "\\":
                if let nx = at(i + 1), !endsLine(i + 1) { if isASCIIPunct(nx) { extra.insert(i) } } else { extra.insert(i) }
            case "*", "`", "~": extra.insert(i)
            case "[":
                // escape เฉพาะที่อาจกลายเป็นลิงก์/ภาพ/checkbox: [..](..)  [..][..]  ต้นบรรทัด [ ] [x]  (ไม่ escape [!note] ของ callout, [[wiki]])
                var depth = 0, k = i, closeAt = -1
                while k < n { if chars[k] == "[" { depth += 1 } else if chars[k] == "]" { depth -= 1; if depth == 0 { closeAt = k; break } }; k += 1 }
                let afterClose = closeAt >= 0 ? at(closeAt + 1) : nil
                let task = lineStart(i) && closeAt == i + 2 && [" ", "x", "X"].contains(chars[i + 1])
                if closeAt < 0 || afterClose == "(" || afterClose == "[" || afterClose == ":" || task { extra.insert(i); bracketEscaped.insert(i); if closeAt >= 0 { bracketEscaped.insert(closeAt) } }
            case "]": if bracketEscaped.contains(i) || at(i + 1) == "(" || at(i + 1) == "[" { extra.insert(i) }
            case "|": if pipe { extra.insert(i) }
            case "_":
                if !(at(i - 1).map(isWord) == true && at(i + 1).map(isWord) == true) { extra.insert(i) }
            case "<":
                if let nx = at(i + 1), nx.isLetter || "/!?".contains(nx) { extra.insert(i) }
            case "&":
                if let nx = at(i + 1), nx.isLetter || nx == "#" { extra.insert(i) }
            case "#":
                if lineStart(i) {
                    var j = i; while at(j) == "#" { j += 1 }
                    if j - i <= 6, endsLine(j) || at(j) == " " || at(j) == "\t" { extra.insert(i) }
                }
            case ">":
                if lineStart(i) { extra.insert(i) }
            case "-", "+":
                if lineStart(i) && (endsLine(i + 1) || at(i + 1) == " " || at(i + 1) == "\t" || (c == "-" && lineAll(i, "-"))) { extra.insert(i) }
            case "=":
                if lineStart(i) && lineAll(i, "=") { extra.insert(i) }
            case ".", ")":
                // "1. " / "1) " ต้นบรรทัด
                var j = i - 1
                while j >= 0, chars[j].isASCII, chars[j].isNumber { j -= 1 }
                if j + 1 < i, i - j - 1 <= 9, lineStart(j + 1), endsLine(i + 1) || at(i + 1) == " " || at(i + 1) == "\t" { extra.insert(i) }
            default: break
            }
        }
        if isHeading, let last = chars.last, last == "#", escapable[n - 1] { extra.insert(n - 1) }
        for i in extra { out[i] = "\\" + out[i] }
        return out
    }

    // MARK: - code span / link destination
    static func codeSpan(_ text: String) -> String {
        let t = text.replacingOccurrences(of: softBreakString, with: " ")
        var longest = 0, cur = 0
        for c in t { if c == "`" { cur += 1; longest = max(longest, cur) } else { cur = 0 } }
        let fence = String(repeating: "`", count: longest + 1)
        let pad = t.hasPrefix("`") || t.hasSuffix("`") || (t.hasPrefix(" ") && t.hasSuffix(" ") && t.contains { $0 != " " })
        return fence + (pad ? " " + t + " " : t) + fence
    }

    static func linkDestination(_ url: String) -> String {
        let cleaned = url.replacingOccurrences(of: "\n", with: "%0A").replacingOccurrences(of: "<", with: "%3C").replacingOccurrences(of: ">", with: "%3E")
        if cleaned.contains(where: { $0 == " " || $0 == "(" || $0 == ")" }) || cleaned.isEmpty { return "<" + cleaned + ">" }
        return cleaned
    }

    static func imageMarkdown(_ img: ImageRef) -> String {
        var alt = ""
        for c in img.alt.replacingOccurrences(of: softBreakString, with: " ") { if c == "\\" || c == "[" || c == "]" { alt.append("\\") }; alt.append(c) }
        let dest = (img.src.isEmpty || img.src.contains(where: { $0 == " " || $0 == "(" || $0 == ")" })) ? "<" + img.src.replacingOccurrences(of: ">", with: "%3E").replacingOccurrences(of: "<", with: "%3C") + ">" : img.src
        var title = ""
        if let t = img.title, !t.isEmpty { title = " \"" + t.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"") + "\"" }
        return "![" + alt + "](" + dest + title + ")"
    }

    // MARK: - เขียนทั้งย่อหน้า
    private struct Token { var text: String; var style: InlineStyle; var verbatim: Bool; var link: String?; var plain: String? = nil }

    static func write(_ segments: [InlineSegment], isHeading: Bool = false, pipeEscape: Bool = false) -> String {
        // 1) escape ตามบริบททั้งย่อหน้า
        var chars: [Character] = [], escapable: [Bool] = [], segOf: [Int] = []
        for (si, s) in segments.enumerated() {
            let esc = !s.style.contains(.code) && !s.style.contains(.raw) && !s.style.contains(.hardBreak) && s.image == nil && s.wiki == nil
            for c in s.text { chars.append(c); escapable.append(esc); segOf.append(si) }
        }
        let escaped = escapedCharacters(chars, escapable: escapable, isHeading: isHeading, pipe: pipeEscape)
        var tokens: [Token] = []
        var idx = 0
        for (si, s) in segments.enumerated() {
            var text = ""
            while idx < chars.count, segOf[idx] == si { text += escaped[idx]; idx += 1 }
            if text.isEmpty { continue }
            if let raw = s.wiki {
                tokens.append(Token(text: raw, style: s.style.intersection([.bold, .italic, .strike]), verbatim: true, link: s.link))
            } else if let img = s.image {
                tokens.append(Token(text: img.raw ?? imageMarkdown(img), style: [], verbatim: true, link: s.link))
            } else if s.style.contains(.raw) {
                tokens.append(Token(text: text.replacingOccurrences(of: softBreakString, with: "\n"), style: [], verbatim: true, link: nil))
            } else if s.style.contains(.hardBreak) {
                tokens.append(Token(text: "\\\n", style: [], verbatim: true, link: nil))
            } else if s.style.contains(.code) {
                tokens.append(Token(text: pipeEscape ? codeSpan(s.text).replacingOccurrences(of: "|", with: "\\|") : codeSpan(s.text), style: s.style.intersection([.bold, .italic, .strike]), verbatim: true, link: s.link))
            } else {
                tokens.append(Token(text: text.replacingOccurrences(of: softBreakString, with: "\n"), style: s.style.intersection([.bold, .italic, .strike]), verbatim: false, link: s.link, plain: s.text))
            }
        }
        // 2) แยกกลุ่มตามลิงก์
        var out = ""
        var i = 0
        while i < tokens.count {
            let link = tokens[i].link
            var j = i
            while j < tokens.count, tokens[j].link == link { j += 1 }
            let group = Array(tokens[i..<j])
            let inner = styled(group)
            if let link, isBareURL(link, group) {
                out += link          // URL เปล่า (autolink) เขียนเป็น URL เปล่าเหมือนเดิม
            } else if let link, !link.hasPrefix("wiki:") { out += "[" + inner + "](" + linkDestination(link) + ")" } else { out += inner }
            i = j
        }
        return out
    }

    /// ข้อความลิงก์ = URL เอง ไม่มี style และลงท้ายไม่ใช่เครื่องหมายที่ autolink ตัดทิ้ง -> เขียนเป็น URL เปล่าได้
    private static func isBareURL(_ link: String, _ group: [Token]) -> Bool {
        let lower = link.lowercased()
        guard lower.hasPrefix("http://") || lower.hasPrefix("https://"), group.allSatisfy({ !$0.verbatim && $0.style.isEmpty && $0.plain != nil }) else { return false }
        guard group.compactMap(\.plain).joined() == link, let last = link.last, !".,;:!?)*_~\"'".contains(last) else { return false }
        return !link.contains(where: { $0 == " " || $0 == "<" || $0 == ">" || $0 == softBreakCharacter })
    }

    private static let order: [(InlineStyle, String)] = [(.strike, "~~"), (.bold, "**"), (.italic, "*")]

    private static func isWS(_ c: Character) -> Bool { c == " " || c == "\t" || c == "\n" }
    private static func isWSToken(_ t: Token) -> Bool { !t.verbatim && !t.text.isEmpty && t.text.allSatisfy(isWS) }

    /// ซ้อนเครื่องหมายแบบ interval: เลือก style ที่ต่อเนื่องยาวที่สุดเป็นชั้นนอก แล้วไล่เข้าไปข้างใน
    private static func styled(_ tokens: [Token]) -> String { render(tokens, 0, tokens.count, order) }

    private static func render(_ toks: [Token], _ lo: Int, _ hi: Int, _ flags: [(InlineStyle, String)]) -> String {
        var out = ""
        var p = lo
        while p < hi {
            let t = toks[p]
            var best: (idx: Int, end: Int)?
            if !isWSToken(t) {
                for (fi, f) in flags.enumerated() where t.style.contains(f.0) {
                    var e = p + 1
                    while e < hi, toks[e].style.contains(f.0) || isWSToken(toks[e]) { e += 1 }
                    while e > p + 1, isWSToken(toks[e - 1]) { e -= 1 }
                    if best == nil || e > best!.end { best = (fi, e) }
                }
            }
            if let b = best {
                var rest = flags
                let f = rest.remove(at: b.idx)
                let inner = render(toks, p, b.end, rest)
                var core = Substring(inner)
                var lead = "", trail = ""
                while let c = core.first, isWS(c) { lead.append(c); core = core.dropFirst() }
                while let c = core.last, isWS(c) { trail.insert(c, at: trail.startIndex); core = core.dropLast() }
                out += lead + (core.isEmpty ? "" : f.1 + core + f.1) + trail
                p = b.end
            } else {
                out += t.text
                p += 1
            }
        }
        return out
    }
}
