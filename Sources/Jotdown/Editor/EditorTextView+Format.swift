import AppKit

extension EditorTextView {
    // MARK: - inline
    func inlineStyleState(_ flag: InlineStyle) -> Bool {
        let sel = selectedRange()
        if sel.length == 0 {
            return InlineStyle(rawValue: (typingAttributes[.jotInline] as? Int) ?? 0).contains(flag)
        }
        var all = true, any = false
        let n = nsString
        storage.enumerateAttributes(in: sel, options: []) { attrs, r, stop in
            guard self.storage.blockKind(at: r.location).allowsInline else { return }
            let style = InlineStyle(rawValue: (attrs[.jotInline] as? Int) ?? 0)
            // ไม่นับตัวคั่นย่อหน้า
            var rr = r
            while rr.length > 0, n.character(at: NSMaxRange(rr) - 1) == 0x0A { rr.length -= 1 }
            if rr.length == 0 { return }
            any = true
            if !style.contains(flag) { all = false; stop.pointee = true }
        }
        return any && all
    }

    /// สลับ inline style: ทั้งช่วงมี style แล้ว = เอาออก ไม่งั้นใส่; ไม่เลือกอะไร = เปลี่ยน typingAttributes
    func toggleInline(_ flag: InlineStyle) {
        let sel = selectedRange()
        let kind = blockKindAtCaret
        if sel.length == 0 {
            guard kind.allowsInline else { return }
            var st = InlineStyle(rawValue: (typingAttributes[.jotInline] as? Int) ?? 0)
            if st.contains(flag) { st.remove(flag) } else { st.insert(flag) }
            plainTypingAt = nil
            typingAttributes = typingAttrs(kind: kind, inline: st)
            return
        }
        let remove = inlineStyleState(flag)
        let pr = nsString.paragraphRange(for: sel)
        let local = NSRange(location: sel.location - pr.location, length: sel.length)
        transformParagraphs(in: sel) { sub in
            var runs: [(NSRange, Int)] = []
            sub.enumerateAttribute(.jotInline, in: local, options: []) { v, r, _ in
                guard sub.blockKind(at: r.location).allowsInline else { return }
                runs.append((r, (v as? Int) ?? 0))
            }
            let s = sub.string as NSString
            for (r, v) in runs {
                // ข้ามตัว "\n"
                var rr = r
                while rr.length > 0, s.character(at: NSMaxRange(rr) - 1) == 0x0A { rr.length -= 1 }
                if rr.length == 0 { continue }
                let nv = remove ? (v & ~flag.rawValue) : (v | flag.rawValue)
                if nv == 0 { sub.removeAttribute(.jotInline, range: rr) } else { sub.addAttribute(.jotInline, value: nv, range: rr) }
            }
        }
    }

    // MARK: - ลิงก์
    /// ช่วงของลิงก์ที่เคอร์เซอร์/การเลือกอยู่ (ถ้ามี)
    func linkRangeAtSelection() -> (NSRange, String)? {
        let sel = selectedRange()
        let idx = sel.length > 0 ? sel.location : (sel.location > 0 && storage.link(at: sel.location - 1) != nil ? sel.location - 1 : sel.location)
        guard idx < storage.length, let url = storage.link(at: idx) else { return nil }
        var eff = NSRange(location: 0, length: 0)
        _ = storage.attribute(.jotLink, at: idx, longestEffectiveRange: &eff, in: NSRange(location: 0, length: storage.length))
        return (eff, url)
    }

    /// ตั้ง/ลบลิงก์ของช่วง (url = nil ลบ)
    func applyLink(_ url: String?, in range: NSRange) {
        guard range.length > 0 else { return }
        let pr = nsString.paragraphRange(for: range)
        let local = NSRange(location: range.location - pr.location, length: range.length)
        let sel = selectedRange()
        transformParagraphs(in: range) { sub in
            guard sub.blockKind(at: local.location).allowsInline || true else { return }
            let s = sub.string as NSString
            var rr = local
            while rr.length > 0, s.character(at: NSMaxRange(rr) - 1) == 0x0A { rr.length -= 1 }
            if let url, !url.isEmpty { sub.addAttribute(.jotLink, value: url, range: rr) } else { sub.removeAttribute(.jotLink, range: rr) }
        }
        setSelectedRange(sel)
    }

    func makeLinkSheet(initial: String, hasExisting: Bool) -> PromptSheet {
        PromptSheet(title: "Link", message: "Enter a URL", initial: initial, placeholder: "https://", removeTitle: hasExisting ? "Remove Link" : nil)
    }

    @objc func jotEditLink(_ sender: Any?) {
        guard blockKindAtCaret.allowsInline, let window else { return }
        var sel = selectedRange()
        let existing = linkRangeAtSelection()
        if sel.length == 0, let e = existing { sel = e.0 }
        if let e = existing, e.1.hasPrefix("wiki:") { editWikiLink(range: e.0); return }
        let sheet = makeLinkSheet(initial: existing?.1 ?? "", hasExisting: existing != nil)
        promptSheet = sheet
        let target = sel
        sheet.present(on: window) { [weak self] result in
            guard let self else { return }
            self.promptSheet = nil
            switch result {
            case .ok(let url):
                if target.length == 0 { self.insertLinkedText(url) } else { self.applyLink(url, in: target) }
            case .remove: self.applyLink(nil, in: target)
            case .cancel: break
            }
        }
    }

    /// แก้ลิงก์ Obsidian: เป้าหมาย/ข้อความแสดงในรูปแบบ `โน้ต#หัวข้อ|ข้อความแสดง`
    func editWikiLink(range: NSRange) {
        guard let window, let raw = storage.attribute(.jotWiki, at: range.location, effectiveRange: nil) as? String else { return }
        let inner = String(raw.dropFirst(2).dropLast(2)).replacingOccurrences(of: "\\|", with: "|")
        let sheet = PromptSheet(title: "Wiki Link", message: "note#heading|display text", initial: inner, placeholder: "note", removeTitle: "Remove Link")
        promptSheet = sheet
        sheet.present(on: window) { [weak self] r in
            guard let self else { return }
            self.promptSheet = nil
            switch r {
            case .ok(let text): if !text.isEmpty { self.replaceWiki(range: range, raw: "[[" + text + "]]") }
            case .remove: self.replaceWiki(range: range, raw: nil)
            case .cancel: break
            }
        }
    }

    /// แทนลิงก์ Obsidian ด้วยข้อความดิบใหม่ (nil = ลบลิงก์ เหลือข้อความที่แสดง)
    func replaceWiki(range: NSRange, raw: String?) {
        let kind = kind(at: range.location)
        let current = nsString.substring(with: range)
        var attrs: NSAttributedString
        if let raw, let w = ObsidianSyntax.parse(raw: raw) {
            attrs = NSAttributedString(string: w.display, attributes: MarkdownParser.attributes(for: kind, segment: InlineSegment(text: w.display, style: [], link: w.linkValue, wiki: raw)))
        } else {
            attrs = NSAttributedString(string: current, attributes: Theme.attributes(for: kind))
        }
        replaceRange(range, with: attrs, selection: NSRange(location: range.location + attrs.length, length: 0))
    }

    func insertLinkedText(_ url: String) {
        guard !url.isEmpty else { return }
        let sel = selectedRange()
        let kind = blockKindAtCaret
        let a = NSAttributedString(string: url, attributes: Theme.attributes(for: kind, inline: [], link: url))
        replaceRange(sel, with: a, selection: NSRange(location: sel.location + (url as NSString).length, length: 0))
    }

    // MARK: - บล็อก
    func isSelection(of kind: (BlockKind) -> Bool) -> Bool {
        let sel = selectedRange()
        if storage.length == 0 || paragraphRange(containing: sel.location).length == 0 { return kind(blockKindAtCaret) }
        let pr = nsString.paragraphRange(for: NSRange(location: sel.location, length: min(sel.length, storage.length - sel.location)))
        var all = true
        var p = pr.location
        while p < NSMaxRange(pr) {
            let r = nsString.paragraphRange(for: NSRange(location: p, length: 0))
            if !kind(storage.blockKind(at: r.location)) { all = false; break }
            p = NSMaxRange(r)
        }
        return all
    }

    func setHeading(_ level: Int) {
        let already = isSelection { $0 == .heading(level) }
        applyKind { _ in already || level == 0 ? .paragraph : .heading(level) }
    }

    func toggleList(_ make: @escaping (Int) -> BlockKind, matches: @escaping (BlockKind) -> Bool) {
        let already = isSelection(of: matches)
        applyKind { k in already ? .paragraph : make(k.listLevel ?? 0) }
    }

    func toggleQuote() {
        let already = isSelection { $0 == .quote }
        applyKind { _ in already ? .paragraph : .quote }
    }

    func toggleCodeBlock() {
        let already = isSelection { $0.isCode }
        applyKind { _ in already ? .paragraph : .codeBlock("") }
    }

    // MARK: - actions (เมนู รูปแบบ)
    @objc func jotToggleBold(_ s: Any?) { toggleInline(.bold) }
    @objc func jotToggleItalic(_ s: Any?) { toggleInline(.italic) }
    @objc func jotToggleStrike(_ s: Any?) { toggleInline(.strike) }
    @objc func jotToggleCode(_ s: Any?) { toggleInline(.code) }
    @objc func jotSetParagraph(_ s: Any?) { setHeading(0) }
    @objc func jotSetHeading(_ s: Any?) { setHeading((s as? NSMenuItem)?.tag ?? 1) }
    @objc func jotToggleBullet(_ s: Any?) { toggleList({ .bullet($0) }, matches: { if case .bullet = $0 { return true } else { return false } }) }
    @objc func jotToggleOrdered(_ s: Any?) { toggleList({ .ordered($0) }, matches: { if case .ordered = $0 { return true } else { return false } }) }
    @objc func jotToggleTask(_ s: Any?) { toggleList({ .task($0, false) }, matches: { if case .task = $0 { return true } else { return false } }) }
    @objc func jotIndent(_ s: Any?) { changeListLevel(by: 1) }
    @objc func jotOutdent(_ s: Any?) { changeListLevel(by: -1) }
    @objc func jotToggleQuote(_ s: Any?) { toggleQuote() }
    @objc func jotToggleCodeBlock(_ s: Any?) { toggleCodeBlock() }

    override func validateMenuItem(_ item: NSMenuItem) -> Bool {
        guard let a = item.action else { return super.validateMenuItem(item) }
        func on(_ b: Bool) { item.state = b ? .on : .off }
        let allowsInline = blockKindAtCaret.allowsInline
        switch a {
        case #selector(jotToggleBold(_:)): on(inlineStyleState(.bold)); return allowsInline
        case #selector(jotToggleItalic(_:)): on(inlineStyleState(.italic)); return allowsInline
        case #selector(jotToggleStrike(_:)): on(inlineStyleState(.strike)); return allowsInline
        case #selector(jotToggleCode(_:)): on(inlineStyleState(.code)); return allowsInline
        case #selector(jotEditLink(_:)): on(linkRangeAtSelection() != nil); return allowsInline
        case #selector(jotSetParagraph(_:)): on(isSelection { $0 == .paragraph }); return true
        case #selector(jotSetHeading(_:)): on(isSelection { $0 == .heading(item.tag) }); return true
        case #selector(jotToggleBullet(_:)): on(isSelection { if case .bullet = $0 { return true } else { return false } }); return true
        case #selector(jotToggleOrdered(_:)): on(isSelection { if case .ordered = $0 { return true } else { return false } }); return true
        case #selector(jotToggleTask(_:)): on(isSelection { if case .task = $0 { return true } else { return false } }); return true
        case #selector(jotIndent(_:)), #selector(jotOutdent(_:)): return blockKindAtCaret.isList
        case #selector(jotToggleQuote(_:)): on(isSelection { $0 == .quote }); return true
        case #selector(jotToggleCodeBlock(_:)): on(isSelection { $0.isCode }); return true
        case #selector(jotSetCodeLanguage(_:)): return true
        case #selector(jotOpenLink(_:)), #selector(jotCopyLinkAddress(_:)), #selector(jotRemoveLink(_:)): return linkHitAtSelection() != nil
        case #selector(jotInsertVideo(_:)): return !blockKindAtCaret.isCodeLike && !blockKindAtCaret.isTableCell
        case #selector(jotInsertDivider(_:)): return !blockKindAtCaret.isCodeLike && !blockKindAtCaret.isTableCell
        case #selector(jotPlayVideo(_:)), #selector(jotOpenVideoInYouTube(_:)), #selector(jotCopyVideoLink(_:)): return selectedVideo() != nil
        case #selector(jotInsertImage(_:)): return !blockKindAtCaret.isCodeLike
        case #selector(jotToggleCheckOrExit(_:)):
            let k = blockKindAtCaret
            if case .task(_, let c) = k { on(c) } else { on(false) }
            return k.isCodeLike || { if case .task = k { return true } else { return false } }()
        default:
            if let v = validateTableItem(item) { return v }
            return super.validateMenuItem(item)
        }
    }
}
