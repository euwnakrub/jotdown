import AppKit
import Markdown

extension EditorTextView {
    // MARK: - คัดลอก
    func markdown(forSelection sel: NSRange) -> String {
        let sub = storage.attributedSubstring(from: sel)
        if !sub.string.contains("\n") {
            let kind = sub.length > 0 ? sub.blockKind(at: 0) : .paragraph
            let segs = MarkdownSerializer.segments(of: sub, in: NSRange(location: 0, length: sub.length), kind: kind)
            if kind.isCodeLike { return sub.string.replacingOccurrences(of: softBreakString, with: "\n") }
            return InlineWriter.write(segs)
        }
        var out = MarkdownSerializer.serialize(sub)
        if out.hasSuffix("\n") { out.removeLast() }
        return out
    }

    override func copy(_ sender: Any?) {
        let sel = selectedRange()
        guard sel.length > 0 else { return }
        let pb = NSPasteboard.general
        pb.clearContents()
        let md = markdown(forSelection: sel)
        pb.setString(md, forType: .string)
        pb.setString(md, forType: Self.jotMarkdownType)
        if sel.length == 1, let enc = storage.attribute(.jotImage, at: sel.location, effectiveRange: nil) as? String, let ref = ImageRef(encoded: enc), let img = image(for: ref) {
            if let tiff = img.tiffRepresentation { pb.setData(tiff, forType: .tiff) }
            return
        }
        let rich = NSMutableAttributedString(attributedString: storage.attributedSubstring(from: sel))
        rich.removeAttribute(.foregroundColor, range: NSRange(location: 0, length: rich.length))
        rich.removeAttribute(.backgroundColor, range: NSRange(location: 0, length: rich.length))
        if let data = try? rich.data(from: NSRange(location: 0, length: rich.length), documentAttributes: [.documentType: NSAttributedString.DocumentType.rtf]) {
            pb.setData(data, forType: .rtf)
        }
        // HTML: Notion / Google Docs / Mail อ่าน HTML ก่อน RTF — ได้หัวข้อ ลิสต์ ตาราง ครบ (RTF ไม่มีโครงสร้างพวกนี้)
        pb.setString(Self.html(fromMarkdown: md), forType: .html)
    }

    /// ชนิดบน clipboard ที่บอกว่าคัดลอกจาก Jotdown — วางกลับในแอปให้ใช้ Markdown แทน HTML
    static let jotMarkdownType = NSPasteboard.PasteboardType("com.euw.jotdown.markdown")

    static func html(fromMarkdown md: String) -> String {
        "<meta charset=\"utf-8\">" + HTMLFormatter.format(md)
    }

    /// คัดลอกเป็นโค้ด Markdown ล้วน (ไม่มี RTF) ให้แอปอื่นวางเป็นข้อความ Markdown — ไม่ได้เลือกอะไร = ทั้งเอกสาร
    @objc func jotCopyAsMarkdown(_ sender: Any?) {
        let sel = selectedRange()
        var md: String
        if sel.length > 0 {
            md = markdown(forSelection: sel)
        } else {
            md = MarkdownSerializer.serialize(storage)
            if md.hasSuffix("\n") { md.removeLast() }
        }
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(md, forType: .string)
    }

    override func cut(_ sender: Any?) {
        guard selectedRange().length > 0 else { return }
        copy(sender)
        delete(sender)
    }

    // MARK: - วาง
    override var readablePasteboardTypes: [NSPasteboard.PasteboardType] { [Self.jotMarkdownType, .string, .html] }
    override func paste(_ sender: Any?) { pasteFrom(NSPasteboard.general) }
    override func pasteAsRichText(_ sender: Any?) { pasteFrom(NSPasteboard.general) }
    override func pasteAsPlainText(_ sender: Any?) { pasteFrom(NSPasteboard.general, forcePlain: true) }

    static func looksLikeMarkdown(_ s: String) -> Bool {
        let patterns = [#"(?m)^#{1,6} \S"#, #"(?m)^\s*[-*+] \S"#, #"(?m)^\s*\d+\. \S"#, #"(?m)^> \S"#, "```", #"\*\*[^*\n]+\*\*"#,
                        #"\[[^\]\n]+\]\([^)\n]+\)"#, #"(?m)^---+$"#, #"`[^`\n]+`"#, #"(?m)^\s*[-*+] \[[ xX]\] "#, #"~~[^~\n]+~~"#, #"(?m)^\|.+\|[ \t]*\n\|?[ \t]*:?-+:?[ \t]*\|"#]
        return patterns.contains { s.range(of: $0, options: .regularExpression) != nil }
    }

    static func isURL(_ s: String) -> Bool {
        guard !s.contains(where: { $0 == " " || $0 == "\n" }), let u = URL(string: s), let scheme = u.scheme?.lowercased() else { return false }
        return ["http", "https", "mailto"].contains(scheme) && (u.host != nil || scheme == "mailto")
    }

    func pasteFrom(_ pb: NSPasteboard, forcePlain: Bool = false) {
        if !forcePlain, insertImages(from: pb, at: nil) { return }
        let fromJot = pb.string(forType: Self.jotMarkdownType)
        let string = fromJot ?? pb.string(forType: .string)
        let html = fromJot == nil ? pb.string(forType: .html) : nil
        let sel = selectedRange()
        let kind = blockKindAtCaret

        if kind.isTableCell {
            if let s = string { insertText(MarkdownParser.normalize(s).trimmingCharacters(in: .newlines).replacingOccurrences(of: "\n", with: softBreakString), replacementRange: sel) }
            return
        }
        if kind.isCodeLike {
            if let s = string { insertText(s.replacingOccurrences(of: "\r\n", with: "\n"), replacementRange: sel) }
            return
        }
        if sel.length == 0, kind == .paragraph, !forcePlain, let s = string?.trimmingCharacters(in: .whitespacesAndNewlines), !s.contains(where: { $0 == " " || $0 == "\n" }),
           let v = Self.makeVideo(from: s), contentRange(of: paragraphRange(containing: sel.location)).length == 0 {
            insertVideo(v)
            finishNewParagraph(.paragraph)
            return
        }
        if sel.length > 0, let s = string?.trimmingCharacters(in: .whitespacesAndNewlines), Self.isURL(s) {
            applyLink(s, in: sel)
            return
        }
        var blocks: [ParsedBlock]?
        if forcePlain {
            if let s = string { blocks = Self.plainBlocks(s) }
        } else if let s = string, Self.looksLikeMarkdown(s) || html == nil {
            blocks = Self.looksLikeMarkdown(s) ? MarkdownParser.blocks(from: s) : Self.plainBlocks(s)
        } else if let h = html {
            let b = HTMLImporter.blocks(from: h)
            blocks = b.isEmpty ? string.map(Self.plainBlocks) : b
        }
        guard let blocks, !blocks.isEmpty else { return }
        insertBlocks(blocks)
    }

    /// ข้อความธรรมดา: บรรทัดว่างคั่นย่อหน้า, ขึ้นบรรทัดเดี่ยว = soft break
    static func plainBlocks(_ s: String) -> [ParsedBlock] {
        let t = MarkdownParser.normalize(s)
        return t.components(separatedBy: "\n\n").map { $0.trimmingCharacters(in: .newlines) }.filter { !$0.isEmpty }
            .map { ParsedBlock(kind: .paragraph, text: $0.replacingOccurrences(of: "\n", with: softBreakString)) }
    }

    func insertBlocks(_ blocks: [ParsedBlock]) {
        let sel = selectedRange()
        // ย่อหน้าเดียวธรรมดา: แทรกในบรรทัด
        if blocks.count == 1, blocks[0].kind == .paragraph {
            let kind = blockKindAtCaret
            let out = NSMutableAttributedString()
            for s in blocks[0].segments { out.append(NSAttributedString(string: s.text, attributes: MarkdownParser.attributes(for: kind, segment: s))) }
            replaceRange(sel, with: out, selection: NSRange(location: sel.location + out.length, length: 0))
            syncTypingAttributes()
            return
        }
        if sel.length > 0 { replaceRange(sel, with: NSAttributedString(), selection: NSRange(location: sel.location, length: 0)) }
        let loc = selectedRange().location
        let pr = paragraphRange(containing: loc)
        let content = contentRange(of: pr)
        let hasNL = pr.length > content.length
        let oldKind = kind(at: loc)

        // สร้างทุกบล็อกพร้อมกัน (เซลล์ตารางต้องใช้ตารางเดียวกัน) แล้วแยกเป็นรายย่อหน้า
        let all = MarkdownParser.attributedString(from: blocks)
        var blockPieces: [NSAttributedString] = []
        var from = 0
        for _ in blocks.indices {
            let nl = (all.string as NSString).range(of: "\n", range: NSRange(location: from, length: all.length - from)).location
            let end = nl == NSNotFound ? all.length : nl
            blockPieces.append(all.attributedSubstring(from: NSRange(location: from, length: end - from)))
            from = end + 1
        }
        var pieces: [(NSAttributedString, BlockKind)] = []
        if loc > content.location {
            pieces.append((storage.attributedSubstring(from: NSRange(location: content.location, length: loc - content.location)), oldKind))
        }
        for (i, b) in blocks.enumerated() { pieces.append((blockPieces[i], b.kind)) }
        let blocksEnd = pieces.count
        if NSMaxRange(content) > loc {
            pieces.append((storage.attributedSubstring(from: NSRange(location: loc, length: NSMaxRange(content) - loc)), oldKind))
        }
        let out = NSMutableAttributedString()
        var caretAt = 0
        for (i, p) in pieces.enumerated() {
            if i > 0 { out.append(NSAttributedString(string: "\n", attributes: Theme.attributes(for: pieces[i - 1].1))) }
            out.append(p.0)
            if i == blocksEnd - 1 { caretAt = out.length }
        }
        if hasNL { out.append(NSAttributedString(string: "\n", attributes: Theme.attributes(for: pieces.last!.1))) }
        let target = NSRange(location: content.location, length: pr.length)
        replaceRange(target, with: out, selection: NSRange(location: content.location + caretAt, length: 0))
        syncTypingAttributes()
    }
}
