import AppKit

/// markdown ที่แยกเป็นบล็อกแล้ว (ฟังก์ชันล้วน ทดสอบได้โดยไม่ต้องแตะ AppKit)
struct ParsedBlock: Equatable {
    var kind: BlockKind
    var segments: [InlineSegment]

    init(kind: BlockKind, segments: [InlineSegment]) { self.kind = kind; self.segments = segments }
    init(kind: BlockKind, text: String, style: InlineStyle = []) {
        self.kind = kind
        self.segments = text.isEmpty ? [] : [InlineSegment(text: text, style: style, link: nil)]
    }
    var text: String { segments.map(\.text).joined() }
}

enum MarkdownSerializer {
    /// text storage -> markdown. บล็อกคั่นด้วยบรรทัดว่าง 1 บรรทัด ลงท้าย "\n" 1 ตัว; เอกสารว่าง = ""
    static func serialize(_ s: NSAttributedString) -> String { serialize(paragraphs(of: s)) }

    static func serialize(_ blocks: [ParsedBlock]) -> String {
        var chunks: [String] = []
        var i = 0
        while i < blocks.count {
            let b = blocks[i]
            if b.kind.isList {
                var j = i
                while j < blocks.count, blocks[j].kind.isList { j += 1 }
                chunks.append(listText(Array(blocks[i..<j])))
                i = j; continue
            }
            if b.kind.isTableCell {
                var j = i + 1
                while j < blocks.count, case .tableCell(let r, let c, _) = blocks[j].kind, !(r == 0 && c == 0) { j += 1 }
                if let m = TableModel.from(Array(blocks[i..<j])) { chunks.append(m.markdown()) }
                i = j; continue
            }
            if b.kind == .quote {
                var j = i
                while j < blocks.count, blocks[j].kind == .quote { j += 1 }
                if let t = quoteText(Array(blocks[i..<j])) { chunks.append(t) }
                i = j; continue
            }
            if let t = single(b) { chunks.append(t) }
            i += 1
        }
        return chunks.isEmpty ? "" : chunks.joined(separator: "\n\n") + "\n"
    }

    private static func inline(_ b: ParsedBlock) -> String { InlineWriter.write(b.segments, isHeading: b.kind.isHeading) }

    private static func single(_ b: ParsedBlock) -> String? {
        switch b.kind {
        case .heading(let l):
            let t = inline(b).replacingOccurrences(of: "\n", with: " ")
            return String(repeating: "#", count: l) + (t.isEmpty ? "" : " " + t)
        case .thematicBreak: return "---"
        case .raw:
            let t = b.text.replacingOccurrences(of: softBreakString, with: "\n")
            return t.isEmpty ? nil : t
        case .codeBlock(let lang):
            let body = b.text.replacingOccurrences(of: softBreakString, with: "\n")
            var longest = 0, cur = 0
            for c in body { if c == "`" { cur += 1; longest = max(longest, cur) } else { cur = 0 } }
            let fence = String(repeating: "`", count: max(3, longest + 1))
            return fence + lang + "\n" + (body.isEmpty ? "" : body + "\n") + fence
        case .paragraph:
            let t = inline(b)
            return t.isEmpty ? nil : t
        default: return inline(b)
        }
    }

    private static func quoteText(_ run: [ParsedBlock]) -> String? {
        var paras = run.map { inline($0) }
        while let l = paras.last, l.isEmpty { paras.removeLast() }
        if paras.isEmpty { return nil }
        return paras.map { p in p.components(separatedBy: "\n").map { $0.isEmpty ? ">" : "> " + $0 }.joined(separator: "\n") }
            .joined(separator: "\n>\n")
    }

    private static func listText(_ run: [ParsedBlock]) -> String {
        let numbers = ListNumbering.numbers(for: run.map(\.kind))
        var widths: [Int] = []
        var lines: [String] = []
        var prevTopOrdered: Bool?
        for (idx, b) in run.enumerated() {
            let level = b.kind.listLevel ?? 0
            if level == 0 {
                var ord = false
                if case .ordered = b.kind { ord = true }
                if let p = prevTopOrdered, p != ord { lines.append("") }   // ชนิดลิสต์เปลี่ยน = ลิสต์ใหม่
                prevTopOrdered = ord
            }
            while widths.count > level { widths.removeLast() }
            while widths.count < level { widths.append(2) }
            let indent = String(repeating: " ", count: widths.reduce(0, +))
            var marker: String
            var width = 2
            switch b.kind {
            case .ordered: marker = "\(numbers[idx] ?? 1). "; width = marker.count
            case .task(_, let c): marker = c ? "- [x] " : "- [ ] "
            default: marker = "- "
            }
            widths.append(width)
            let content = inline(b).components(separatedBy: "\n")
            let cont = indent + String(repeating: " ", count: width)
            var first = indent + marker + content[0]
            if content[0].isEmpty { first = String(first.dropLast()) }
            lines.append(first)
            for c in content.dropFirst() { lines.append(c.isEmpty ? "" : cont + c) }
        }
        return lines.joined(separator: "\n")
    }

    /// แยก text storage เป็นบล็อกตามย่อหน้า ("\n"); inline style/ลิงก์เป็น segment
    static func paragraphs(of s: NSAttributedString) -> [ParsedBlock] {
        let ns = s.string as NSString
        let separators: Set<unichar> = [0x0A, 0x0D, 0x2029]
        var out: [ParsedBlock] = []
        var loc = 0
        while loc < ns.length {
            let pr = ns.paragraphRange(for: NSRange(location: loc, length: 0))
            var content = pr
            while content.length > 0, separators.contains(ns.character(at: content.location + content.length - 1)) { content.length -= 1 }
            let kind = s.blockKind(at: pr.location)
            out.append(ParsedBlock(kind: kind, segments: segments(of: s, in: content, kind: kind)))
            loc = NSMaxRange(pr)
        }
        return out
    }

    static func segments(of s: NSAttributedString, in range: NSRange, kind: BlockKind) -> [InlineSegment] {
        guard range.length > 0 else { return [] }
        if kind == .thematicBreak { return [] }
        var segs: [InlineSegment] = []
        let ns = s.string as NSString
        s.enumerateAttributes(in: range, options: []) { attrs, r, _ in
            let text = ns.substring(with: r)
            let style = kind.allowsInline ? InlineStyle(rawValue: (attrs[.jotInline] as? Int) ?? 0) : []
            let link = kind.allowsInline ? attrs[.jotLink] as? String : nil
            if let enc = attrs[.jotImage] as? String, let ref = ImageRef(encoded: enc) {
                segs.append(InlineSegment(text: text, style: [], link: link, image: ref)); return
            }
            if let enc = attrs[.jotVideo] as? String, let v = VideoRef(encoded: enc) {
                segs.append(InlineSegment(text: text, style: [], link: link, video: v)); return
            }
            if let w = attrs[.jotWiki] as? String {
                segs.append(InlineSegment(text: text, style: style, link: link, wiki: w)); return
            }
            if var last = segs.last, last.image == nil, last.wiki == nil, last.video == nil, last.style == style, last.link == link {
                last.text += text; segs[segs.count - 1] = last
            } else { segs.append(InlineSegment(text: text, style: style, link: link)) }
        }
        return segs
    }
}
