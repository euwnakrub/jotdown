import Foundation

/// แปลง HTML จาก clipboard เป็นบล็อกของเรา (หนา/เอียง/ขีดฆ่า/โค้ด/ลิงก์/หัวข้อ/ลิสต์/quote/โค้ดบล็อก/เส้นคั่น) ส่วนอื่นทิ้ง style
/// ตัวแยก tag แบบหลวม ๆ (ไม่ใช้ WebKit): เร็วและทดสอบได้
enum HTMLImporter {
    private struct Open { var name: String; var style: InlineStyle; var link: String?; var listOrdered: Bool?; var blockKind: BlockKind?; }

    static func blocks(from html: String) -> [ParsedBlock] {
        var out: [ParsedBlock] = []
        var stack: [Open] = []
        var segs: [InlineSegment] = []
        var curKind: BlockKind = .paragraph
        var kindExplicit = false
        var inPre = false
        var preLang = ""
        var skipUntil: String?
        var inTable = false, inCell = false
        var tableRows: [[[InlineSegment]]] = []
        var curRow: [[InlineSegment]] = []
        var tableHasTH = false

        func style() -> InlineStyle { stack.reduce([]) { $0.union($1.style) } }
        func link() -> String? { stack.last(where: { $0.link != nil })?.link }
        func listDepth() -> Int { stack.filter { $0.listOrdered != nil }.count }
        func inQuote() -> Bool { stack.contains { $0.name == "blockquote" } }
        func inLI() -> Bool { stack.contains { $0.name == "li" } }

        func flush() {
            if inTable { return }
            // ตัดช่องว่างหัวท้าย
            while let f = segs.first, f.text.trimmingCharacters(in: .whitespaces).isEmpty, !f.style.contains(.hardBreak) { segs.removeFirst() }
            while let l = segs.last, l.text.trimmingCharacters(in: .whitespaces).isEmpty, !l.style.contains(.hardBreak) { segs.removeLast() }
            if !segs.isEmpty {
                segs[0].text = String(segs[0].text.drop(while: { $0 == " " }))
                segs[segs.count - 1].text = segs[segs.count - 1].text.replacingOccurrences(of: #"\s+$"#, with: "", options: .regularExpression)
                var kind = curKind
                if !kindExplicit { kind = inQuote() ? .quote : .paragraph }
                var merged: [InlineSegment] = []
                for s in segs where !s.text.isEmpty {
                    if var last = merged.last, last.image == nil, s.image == nil, last.style == s.style, last.link == s.link, !s.style.contains(.hardBreak) { last.text += s.text; merged[merged.count - 1] = last } else { merged.append(s) }
                }
                if !merged.isEmpty { out.append(ParsedBlock(kind: kind.allowsInline ? kind : kind, segments: merged)) }
            }
            segs = []; kindExplicit = false; curKind = .paragraph
        }

        func addText(_ raw: String) {
            if inTable && !inCell { return }
            if inPre { segs.append(.init(text: raw.replacingOccurrences(of: "\n", with: softBreakString), style: [], link: nil)); return }
            var t = decode(raw).replacingOccurrences(of: #"[\s]+"#, with: " ", options: .regularExpression)
            if t.isEmpty { return }
            if segs.isEmpty || segs.last?.text.hasSuffix(" ") == true { t = String(t.drop(while: { $0 == " " })) }
            if t.isEmpty { return }
            segs.append(.init(text: t, style: style(), link: link()))
        }

        let scalars = Array(html)
        var i = 0
        var text = ""
        func flushText() { if !text.isEmpty { if skipUntil == nil { addText(text) }; text = "" } }

        while i < scalars.count {
            let c = scalars[i]
            if c == "<" {
                // comment
                if html.hasPrefix("<!--", at: i, in: scalars) {
                    flushText()
                    if let end = find("-->", from: i, in: scalars) { i = end + 3 } else { break }
                    continue
                }
                guard let close = find(">", from: i, in: scalars) else { text.append(c); i += 1; continue }
                let inner = String(scalars[(i + 1)..<close])
                i = close + 1
                flushText()
                if inner.hasPrefix("!") || inner.hasPrefix("?") { continue }
                let isClose = inner.hasPrefix("/")
                let body = isClose ? String(inner.dropFirst()) : inner
                let name = String(body.prefix(while: { !$0.isWhitespace && $0 != "/" })).lowercased()
                let attrs = isClose ? "" : String(body.dropFirst(name.count))
                if let s = skipUntil { if isClose && name == s { skipUntil = nil }; continue }
                if !isClose, ["script", "style", "head", "title"].contains(name) { skipUntil = name; continue }
                handleTag(name: name, attrs: attrs, isClose: isClose)
            } else {
                text.append(c); i += 1
            }
        }
        flushText()
        flush()
        return out

        func handleTag(name: String, attrs: String, isClose: Bool) {
            switch name {
            case "table":
                if isClose {
                    if inTable {
                        inTable = false
                        let rows = tableRows.filter { !$0.isEmpty }
                        if !rows.isEmpty { out.append(contentsOf: TableModel(align: [], rows: rows).blocks()) }
                    }
                    tableRows = []
                } else { flush(); inTable = true; tableRows = []; tableHasTH = false }
                return
            case "tr":
                if isClose { if inTable { tableRows.append(curRow) }; curRow = [] } else { curRow = [] }
                return
            case "td", "th":
                if isClose {
                    if inTable, inCell {
                        var cell = segs
                        while let f = cell.first, f.text.trimmingCharacters(in: .whitespaces).isEmpty, f.image == nil { cell.removeFirst() }
                        while let l = cell.last, l.text.trimmingCharacters(in: .whitespaces).isEmpty, l.image == nil { cell.removeLast() }
                        curRow.append(cell)
                    }
                    segs = []; inCell = false
                    if let idx = stack.lastIndex(where: { $0.name == name }) { stack.removeSubrange(idx...) }
                } else if inTable {
                    segs = []; inCell = true
                    stack.append(Open(name: name, style: [], link: nil, listOrdered: nil, blockKind: nil))
                }
                return
            case "thead", "tbody", "tfoot", "colgroup", "caption": return
            default: break
            }
            let blockTags: Set<String> = ["p", "div", "section", "article", "tr", "td", "th", "table", "ul", "ol", "li", "blockquote", "pre", "h1", "h2", "h3", "h4", "h5", "h6", "figure", "figcaption", "header", "footer"]
            if isClose {
                if name == "pre" { inPre = false; if !segs.isEmpty { var t = segs.map(\.text).joined(); while t.hasSuffix(softBreakString) { t.removeLast() }; out.append(ParsedBlock(kind: .codeBlock(preLang), text: t)); segs = [] }; kindExplicit = false; preLang = "" }
                else if blockTags.contains(name) { flush() }
                if let idx = stack.lastIndex(where: { $0.name == name }) { stack.removeSubrange(idx...) }
                return
            }
            switch name {
            case "br":
                segs.append(.init(text: softBreakString, style: inPre ? [] : style().subtracting(.code), link: nil)); return
            case "hr":
                flush(); out.append(ParsedBlock(kind: .thematicBreak, text: thematicBreakText)); return
            case "img":
                if let src = attr("src", in: attrs), !src.lowercased().hasPrefix("data:") {
                    segs.append(.init(text: imageCharacter, style: [], link: link(), image: ImageRef(src: decode(src), alt: decode(attr("alt", in: attrs) ?? ""), title: nil)))
                }
                return
            case "meta", "link", "input", "wbr", "col": return
            default: break
            }
            var open = Open(name: name, style: [], link: nil, listOrdered: nil, blockKind: nil)
            let st = attr("style", in: attrs)?.lowercased() ?? ""
            switch name {
            case "b", "strong": if !st.contains("font-weight:normal") && !st.contains("font-weight: normal") && !st.contains("font-weight:400") { open.style.insert(.bold) }
            case "i", "em", "cite": open.style.insert(.italic)
            case "s", "strike", "del": open.style.insert(.strike)
            case "code", "kbd", "tt", "samp": if !inPre { open.style.insert(.code) } else if let cls = attr("class", in: attrs), let r = cls.range(of: "language-") { preLang = String(cls[r.upperBound...].prefix(while: { !$0.isWhitespace })) }
            case "a": if let h = attr("href", in: attrs), !h.lowercased().hasPrefix("javascript:") { open.link = decode(h) }
            case "ul": flush(); open.listOrdered = false
            case "ol": flush(); open.listOrdered = true
            case "li":
                flush()
                let depth = max(listDepth() - 1, 0)
                let ordered = stack.last(where: { $0.listOrdered != nil })?.listOrdered ?? false
                curKind = ordered ? .ordered(depth) : .bullet(depth); kindExplicit = true
            case "h1", "h2", "h3", "h4", "h5", "h6":
                flush(); curKind = .heading(Int(name.dropFirst()) ?? 1); kindExplicit = true
            case "pre": flush(); inPre = true
            case "blockquote": flush()
            case "p", "div", "section", "article", "td", "th", "tr", "figure", "figcaption", "header", "footer", "table":
                if !inLI() { flush() }
            default: break
            }
            if name == "span" || name == "font" || name == "b" || name == "div" || name == "p" {
                if st.contains("font-weight:700") || st.contains("font-weight: 700") || st.contains("font-weight:bold") || st.contains("font-weight: bold") || st.contains("font-weight:600") || st.contains("font-weight:800") { open.style.insert(.bold) }
                if st.contains("font-style:italic") || st.contains("font-style: italic") { open.style.insert(.italic) }
                if st.contains("line-through") { open.style.insert(.strike) }
            }
            if !["br", "hr"].contains(name) { stack.append(open) }
        }
    }

    // MARK: - ตัวช่วย
    private static func find(_ needle: String, from: Int, in chars: [Character]) -> Int? {
        let n = Array(needle)
        var i = from
        while i + n.count <= chars.count {
            if Array(chars[i..<(i + n.count)]) == n { return i }
            i += 1
        }
        return nil
    }

    private static func attr(_ name: String, in attrs: String) -> String? {
        let pattern = "\(name)\\s*=\\s*(\"([^\"]*)\"|'([^']*)'|([^\\s>]+))"
        guard let re = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive),
              let m = re.firstMatch(in: attrs, range: NSRange(location: 0, length: (attrs as NSString).length)) else { return nil }
        for g in 2...4 where m.range(at: g).location != NSNotFound { return (attrs as NSString).substring(with: m.range(at: g)) }
        return nil
    }

    static func decode(_ s: String) -> String {
        guard s.contains("&") else { return s }
        var out = s
        let named = ["&nbsp;": " ", "&lt;": "<", "&gt;": ">", "&quot;": "\"", "&apos;": "'", "&#39;": "'"]
        for (k, v) in named { out = out.replacingOccurrences(of: k, with: v) }
        if let re = try? NSRegularExpression(pattern: "&#(x?)([0-9a-fA-F]+);") {
            let ns = out as NSString
            var result = ""
            var last = 0
            for m in re.matches(in: out, range: NSRange(location: 0, length: ns.length)) {
                result += ns.substring(with: NSRange(location: last, length: m.range.location - last))
                let hex = ns.substring(with: m.range(at: 1)) == "x"
                if let v = UInt32(ns.substring(with: m.range(at: 2)), radix: hex ? 16 : 10), let u = Unicode.Scalar(v) { result.append(Character(u)) }
                last = NSMaxRange(m.range)
            }
            result += ns.substring(from: last)
            out = result
        }
        return out.replacingOccurrences(of: "&amp;", with: "&")
    }
}

private extension String {
    func hasPrefix(_ p: String, at i: Int, in chars: [Character]) -> Bool {
        let a = Array(p)
        guard i + a.count <= chars.count else { return false }
        return Array(chars[i..<(i + a.count)]) == a
    }
}
