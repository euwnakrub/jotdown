import AppKit
import Markdown

enum MarkdownParser {
    /// ทำให้ข้อความเป็นรูปแบบเดียว: ตัด BOM, CRLF/CR -> LF
    static func normalize(_ s: String) -> String {
        var t = s
        if t.unicodeScalars.first == "\u{FEFF}" { t = String(t.unicodeScalars.dropFirst()) }
        // "\r\n" เป็น Character เดียวใน Swift จึงใช้ replacingOccurrences (ระดับ NSString) เสมอ
        return t.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n")
    }

    // MARK: - markdown -> บล็อก
    static func blocks(from markdown: String) -> [ParsedBlock] {
        var md = normalize(markdown)
        let lines = md.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        // frontmatter (YAML) ต้นไฟล์: เก็บเป็นบล็อก raw ตามต้นฉบับ (ไม่ให้ cmark ตีเป็นเส้นคั่น/หัวข้อ)
        let fm = ObsidianSyntax.frontmatterLineCount(lines)
        if fm > 0 {
            let head = ParsedBlock(kind: .raw, text: lines[0..<fm].joined(separator: softBreakString))
            let rest = lines[fm...].joined(separator: "\n")
            let tail = rest.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? [] : blocks(from: rest)
            return [head] + tail
        }
        // [[wiki]] / ![[embed]] ของ Obsidian -> placeholder ก่อนส่ง cmark (เก็บข้อความดิบไว้ใน raws)
        let pre = ObsidianSyntax.preprocess(md)
        md = pre.text
        Thread.current.threadDictionary["jot.wikiRaws"] = pre.raws
        defer { Thread.current.threadDictionary.removeObject(forKey: "jot.wikiRaws") }
        let doc = Document(parsing: md, options: [.disableSmartOpts])
        var result: [ParsedBlock] = []
        var covered = 0   // จำนวนบรรทัด (1-based) ที่จัดการแล้ว

        func isBlank(_ s: String) -> Bool { s.allSatisfy { $0 == " " || $0 == "\t" } }
        func slice(_ a: Int, _ b: Int) -> [String] { a <= b && a >= 1 && b <= lines.count ? Array(lines[(a - 1)...(b - 1)]) : [] }
        func rawBlock(_ ls: [String]) -> ParsedBlock { ParsedBlock(kind: .raw, text: ls.joined(separator: softBreakString)) }

        /// บรรทัดที่ไม่มีบล็อกใดครอบคลุม (เช่น link reference definition ที่ cmark ไม่ส่งออกมา) เก็บดิบ
        func flushGap(upTo end: Int) {
            guard end > covered else { return }
            var run: [String] = []
            for l in lines[covered..<min(end, lines.count)] {
                if isBlank(l) { if !run.isEmpty { result.append(rawBlock(run)); run = [] } } else { run.append(l) }
            }
            if !run.isEmpty { result.append(rawBlock(run)) }
        }

        for child in doc.children {
            guard let r = child.range else { continue }
            let start = r.lowerBound.line
            var end = r.upperBound.line
            if r.upperBound.column == 1 && end > start { end -= 1 }
            if end <= covered { continue }
            flushGap(upTo: start - 1)
            let raw = slice(max(start, covered + 1), end)
            result.append(contentsOf: convert(child, raw: raw) ?? [rawBlock(raw)])
            covered = end
        }
        flushGap(upTo: lines.count)
        // ตารางท้ายเอกสาร: เติมย่อหน้าว่างต่อท้ายเพื่อให้พิมพ์ต่อ/ออกจากตารางได้
        if let last = result.last, last.kind.isTableCell { result.append(ParsedBlock(kind: .paragraph, segments: [])) }
        return result
    }

    /// nil = ไม่รองรับ (ผู้เรียกเก็บดิบ)
    private static func convert(_ node: Markup, raw: [String]) -> [ParsedBlock]? {
        switch node {
        case let h as Heading:
            return [ParsedBlock(kind: .heading(h.level), segments: segments(of: h))]
        case let p as Paragraph:
            return [ParsedBlock(kind: .paragraph, segments: segments(of: p))]
        case let t as Markdown.Table:
            var rows: [[[InlineSegment]]] = [t.head.children.map { segments(of: $0, inCell: true) }]
            for r in t.body.children { rows.append(r.children.map { segments(of: $0, inCell: true) }) }
            guard rows[0].count > 0 else { return nil }
            let aligns = t.columnAlignments.map { a -> Int in a == .left ? 1 : (a == .center ? 2 : (a == .right ? 3 : 0)) }
            return TableModel(align: aligns, rows: rows).blocks()
        case is ThematicBreak:
            return [ParsedBlock(kind: .thematicBreak, text: thematicBreakText)]
        case let c as CodeBlock:
            guard let first = raw.first?.drop(while: { $0 == " " }), first.hasPrefix("```") || first.hasPrefix("~~~") else { return nil }
            let fenceChar = first.first!
            let info = first.drop(while: { $0 == fenceChar }).trimmingCharacters(in: .whitespaces)
            if info.contains("`") { return nil }
            var code = c.code
            if code.hasSuffix("\n") { code.removeLast() }
            return [ParsedBlock(kind: .codeBlock(info), text: code.replacingOccurrences(of: "\n", with: softBreakString))]
        case let q as BlockQuote:
            var out: [ParsedBlock] = []
            for ch in q.children {
                guard let p = ch as? Paragraph else { return nil }
                out.append(ParsedBlock(kind: .quote, segments: segments(of: p)))
            }
            return out.isEmpty ? nil : out
        case is UnorderedList, is OrderedList:
            var out: [ParsedBlock] = []
            return listBlocks(node, level: 0, into: &out) ? out : nil
        default:
            return nil
        }
    }

    private static func listBlocks(_ list: Markup, level: Int, into out: inout [ParsedBlock]) -> Bool {
        let ordered = list is OrderedList
        guard ordered || list is UnorderedList else { return false }
        for item in list.children {
            guard let li = item as? ListItem else { return false }
            var kids = Array(li.children)
            var segs: [InlineSegment] = []
            if let p = kids.first as? Paragraph { segs = segments(of: p); kids.removeFirst() }
            let kind: BlockKind
            switch li.checkbox {
            case .checked?: kind = .task(level, true)
            case .unchecked?: kind = .task(level, false)
            case nil: kind = ordered ? .ordered(level) : .bullet(level)
            }
            out.append(ParsedBlock(kind: kind, segments: segs))
            for k in kids {
                guard k is UnorderedList || k is OrderedList, listBlocks(k, level: level + 1, into: &out) else { return false }
            }
        }
        return true
    }

    // MARK: - inline
    static func segments(of container: Markup, inCell: Bool = false) -> [InlineSegment] {
        var out: [InlineSegment] = []
        collect(container, style: [], link: nil, inCell: inCell, into: &out)
        return merged(out)
    }

    /// ข้อความธรรมดา: URL เปล่า (http/https) กลายเป็นลิงก์อัตโนมัติ (เขียนกลับเป็น URL เปล่า)
    private static let bareURL = try! NSRegularExpression(pattern: #"https?://[^\s<>]+"#)
    private static func appendText(_ text: String, style: InlineStyle, link: String?, into out: inout [InlineSegment]) {
        if text.contains(ObsidianSyntax.open), let raws = Thread.current.threadDictionary["jot.wikiRaws"] as? [String] {
            var rest = Substring(text)
            while let o = rest.range(of: ObsidianSyntax.open), let c = rest[o.upperBound...].range(of: ObsidianSyntax.close),
                  let idx = Int(rest[o.upperBound..<c.lowerBound]), idx < raws.count, let w = ObsidianSyntax.parse(raw: raws[idx]) {
                if o.lowerBound > rest.startIndex { appendText(String(rest[..<o.lowerBound]), style: style, link: link, into: &out) }
                if w.isImage {
                    out.append(.init(text: imageCharacter, style: [], link: link, image: ImageRef(src: w.target, alt: "", raw: w.raw, width: w.width, height: w.height)))
                } else if w.isNoteEmbed {
                    out.append(.init(text: imageCharacter, style: [], link: w.linkValue, image: ImageRef(src: w.target, alt: w.display, raw: w.raw, noteEmbed: true)))
                } else {
                    out.append(.init(text: w.display, style: style, link: w.linkValue, wiki: w.raw))
                }
                rest = rest[c.upperBound...]
            }
            if !rest.isEmpty { appendText(String(rest), style: style, link: link, into: &out) }
            return
        }
        guard link == nil, text.contains("://") else { out.append(.init(text: text, style: style, link: link)); return }
        let ns = text as NSString
        var last = 0
        for m in bareURL.matches(in: text, range: NSRange(location: 0, length: ns.length)) {
            var r = m.range
            while r.length > 8, let c = Optional(ns.character(at: NSMaxRange(r) - 1)), ".,;:!?)*_~\"'".unicodeScalars.contains(where: { $0.value == UInt32(c) }) { r.length -= 1 }
            guard r.length > 8 else { continue }
            if r.location > last { out.append(.init(text: ns.substring(with: NSRange(location: last, length: r.location - last)), style: style, link: nil)) }
            let u = ns.substring(with: r)
            out.append(.init(text: u, style: style, link: u))
            last = NSMaxRange(r)
        }
        if last < ns.length { out.append(.init(text: ns.substring(from: last), style: style, link: nil)) }
    }

    /// ใช้ทดสอบ: segment ของย่อหน้าแรกใน markdown
    static func inlineSegments(from md: String) -> [InlineSegment] {
        guard let p = Document(parsing: md, options: [.disableSmartOpts]).children.first(where: { $0 is Paragraph }) else { return [] }
        return segments(of: p)
    }

    private static func collect(_ node: Markup, style: InlineStyle, link: String?, inCell: Bool = false, into out: inout [InlineSegment]) {
        for c in node.children {
            switch c {
            case let t as Text: appendText(t.string, style: style, link: link, into: &out)
            case is SoftBreak: out.append(.init(text: softBreakString, style: style.subtracting([.code]), link: link))
            case is LineBreak: out.append(.init(text: softBreakString, style: [.hardBreak], link: nil))
            case let h as InlineHTML where inCell && ["<br>", "<br/>", "<br />"].contains(h.rawHTML.lowercased()):
                out.append(.init(text: softBreakString, style: style.subtracting([.code]), link: link))
            case let s as Strong: collect(s, style: style.union(.bold), link: link, inCell: inCell, into: &out)
            case let e as Emphasis: collect(e, style: style.union(.italic), link: link, inCell: inCell, into: &out)
            case let s as Strikethrough: collect(s, style: style.union(.strike), link: link, inCell: inCell, into: &out)
            case let code as InlineCode: out.append(.init(text: code.code, style: style.union(.code), link: link))
            case let l as Link:
                if let title = l.title, !title.isEmpty {
                    out.append(.init(text: l.format().replacingOccurrences(of: "\n", with: softBreakString), style: [.raw], link: nil))
                } else {
                    collect(l, style: style, link: l.destination ?? "", inCell: inCell, into: &out)
                }
            case let img as Image:
                out.append(.init(text: imageCharacter, style: [], link: link,
                                 image: ImageRef(src: img.source ?? "", alt: img.plainText, title: (img.title ?? "").isEmpty ? nil : img.title)))
            default:
                out.append(.init(text: c.format().replacingOccurrences(of: "\n", with: softBreakString), style: [.raw], link: nil))
            }
        }
    }

    private static func merged(_ segs: [InlineSegment]) -> [InlineSegment] {
        var out: [InlineSegment] = []
        for s in segs where !s.text.isEmpty {
            if var last = out.last, last.image == nil, s.image == nil, last.wiki == nil, s.wiki == nil, last.style == s.style, last.link == s.link, !s.style.contains(.hardBreak) {
                last.text += s.text; out[out.count - 1] = last
            } else { out.append(s) }
        }
        return out
    }

    /// attribute ของ segment หนึ่ง (รวม attachment ของรูป)
    static func attributes(for kind: BlockKind, segment s: InlineSegment, spacing: CGFloat? = nil, table: NSTextTable? = nil) -> [NSAttributedString.Key: Any] {
        var a = Theme.attributes(for: kind, inline: s.style, link: s.link, spacing: spacing, table: table)
        if let img = s.image {
            a[.jotImage] = img.encoded
            a[.attachment] = ImageAttachment(ref: img)
        }
        if let w = s.wiki { a[.jotWiki] = w }
        return a
    }

    // MARK: - บล็อก -> NSAttributedString
    /// markdown -> NSAttributedString (ไม่มีเครื่องหมาย markdown ของสิ่งที่รองรับ)
    static func parse(_ markdown: String) -> NSAttributedString {
        attributedString(from: blocks(from: markdown))
    }

    static func attributedString(from blocks: [ParsedBlock], terminated: Bool = false) -> NSAttributedString {
        var text = ""
        var runs: [(Range<Int>, [NSAttributedString.Key: Any])] = []   // ช่วง UTF-16
        var offset = 0
        func append(_ s: String, _ attrs: [NSAttributedString.Key: Any]) {
            let len = s.utf16.count
            if len == 0 { return }
            text += s
            runs.append((offset..<(offset + len), attrs))
            offset += len
        }
        // ตาราง: เซลล์ทุกเซลล์ของตารางเดียวกันใช้ JotTable ตัวเดียว
        var tables: [JotTable?] = Array(repeating: nil, count: blocks.count)
        var current: JotTable?
        for (i, b) in blocks.enumerated() {
            guard case .tableCell(let r, let c, _) = b.kind else { current = nil; continue }
            if r == 0 && c == 0 {
                var cols = 0, rows = 0, j = i
                while j < blocks.count, case .tableCell(let rr, let cc, _) = blocks[j].kind, !(j > i && rr == 0 && cc == 0) {
                    if rr == 0 { cols += 1 }
                    rows = max(rows, rr + 1); j += 1
                }
                let t = JotTable(); t.numberOfColumns = max(cols, 1); t.rowCount = rows
                current = t
            }
            tables[i] = current
        }
        for (i, b) in blocks.enumerated() {
            let next: BlockKind? = i + 1 < blocks.count ? blocks[i + 1].kind : nil
            let gap = Theme.gap(after: b.kind, next: next)
            if i > 0 {
                append("\n", Theme.attributes(for: blocks[i - 1].kind, spacing: Theme.gap(after: blocks[i - 1].kind, next: b.kind), table: tables[i - 1]))
            }
            for s in b.segments { append(s.text, attributes(for: b.kind, segment: s, spacing: gap, table: tables[i])) }
        }
        if terminated, let last = blocks.last { append("\n", Theme.attributes(for: last.kind, spacing: Theme.gap(after: last.kind, next: nil), table: tables[blocks.count - 1])) }
        let out = NSMutableAttributedString(string: text)
        for (r, a) in runs { out.setAttributes(a, range: NSRange(location: r.lowerBound, length: r.count)) }
        return out
    }
}
