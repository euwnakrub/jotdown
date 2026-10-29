import AppKit

/// ตัวเปิดปลายทางของลิงก์ (เทสต์ฉีดตัวปลอมเพื่อไม่เปิดเบราว์เซอร์จริง)
protocol LinkOpening {
    func open(external url: URL)
    func open(file url: URL)
    func open(markdown url: URL, heading: String?)
}

struct SystemLinkOpener: LinkOpening {
    func open(external url: URL) { NSWorkspace.shared.open(url) }
    func open(file url: URL) { NSWorkspace.shared.open(url) }
    func open(markdown url: URL, heading: String?) {
        NSDocumentController.shared.openDocument(withContentsOf: url, display: true) { doc, _, error in
            if error != nil { NSWorkspace.shared.open(url); return }
            if let h = heading, let d = doc as? JotdownDocument,
               let vc = d.windowControllers.first?.contentViewController as? EditorViewController {
                _ = vc.textView.scrollToHeading(text: h)
            }
        }
    }
}

enum LinkOpenResult: Equatable {
    case opened
    case notice(String)      // ข้อความสั้น ๆ ให้แสดงในแถบลิงก์
    case failed              // ไม่มีอะไรให้เปิด (เสียงเตือน)
}

extension EditorTextView {
    // MARK: - หาลิงก์
    /// ลิงก์ ณ ตำแหน่งตัวอักษร
    func linkHit(atCharacter idx: Int) -> LinkHit? {
        guard idx >= 0, idx < storage.length, let url = storage.link(at: idx) else { return nil }
        var eff = NSRange(location: 0, length: 0)
        _ = storage.attribute(.jotLink, at: idx, longestEffectiveRange: &eff, in: NSRange(location: 0, length: storage.length))
        return LinkHit(range: eff, url: url)
    }

    /// ลิงก์ใต้จุดเมาส์ (พิกัด view) — ต้องอยู่ในกรอบข้อความจริง
    func linkHit(atViewPoint p: NSPoint) -> LinkHit? {
        guard storage.length > 0, let lm = layoutManager, let tc = textContainer else { return nil }
        let o = textContainerOrigin
        let cp = NSPoint(x: p.x - o.x, y: p.y - o.y)
        var frac: CGFloat = 0
        let idx = lm.characterIndex(for: cp, in: tc, fractionOfDistanceBetweenInsertionPoints: &frac)
        guard idx < storage.length, storage.link(at: idx) != nil else { return nil }
        let rect = lm.boundingRect(forGlyphRange: lm.glyphRange(forCharacterRange: NSRange(location: idx, length: 1), actualCharacterRange: nil), in: tc)
        return rect.insetBy(dx: -1, dy: -1).contains(cp) ? linkHit(atCharacter: idx) : nil
    }

    /// ลิงก์ที่เคอร์เซอร์อยู่ (เคอร์เซอร์ไม่มีช่วงเลือก) หรือที่การเลือกอยู่
    func linkHitAtSelection() -> LinkHit? {
        guard let (r, url) = linkRangeAtSelection() else { return nil }
        return LinkHit(range: r, url: url)
    }

    /// ตำแหน่งแถวแรกของลิงก์ในพิกัด view
    func linkRect(_ hit: LinkHit) -> NSRect? {
        guard let lm = layoutManager, let tc = textContainer else { return nil }
        var first: NSRect?
        lm.enumerateEnclosingRects(forGlyphRange: lm.glyphRange(forCharacterRange: hit.range, actualCharacterRange: nil),
                                   withinSelectedGlyphRange: NSRange(location: NSNotFound, length: 0), in: tc) { r, stop in
            first = r; stop.pointee = true
        }
        return first?.offsetBy(dx: textContainerOrigin.x, dy: textContainerOrigin.y)
    }

    // MARK: - เปิดลิงก์
    @discardableResult
    func openLink(_ raw: String) -> LinkOpenResult {
        if raw.hasPrefix("wiki:") { return openWiki(String(raw.dropFirst(5))) }
        switch LinkResolver.resolve(raw, base: linkBaseProvider?()) {
        case .web(let u): linkOpener.open(external: u); return .opened
        case .file(let u): linkOpener.open(file: u); return .opened
        case .markdown(let u): linkOpener.open(markdown: u, heading: nil); return .opened
        case .anchor(let a): return scrollToHeading(anchor: a) ? .opened : .failed
        case .missingFile: return .notice("File not found")
        case .needsSave: return .notice("Save the document to open relative links")
        case .invalid: return .failed
        }
    }

    /// เลื่อนไปหัวข้อที่ slug ตรง (แบบ GitHub, รองรับภาษาไทย)
    func scrollToHeading(anchor: String) -> Bool {
        var titles: [String] = [], starts: [Int] = []
        var p = 0
        let n = nsString
        while p < n.length {
            let pr = n.paragraphRange(for: NSRange(location: p, length: 0))
            if storage.blockKind(at: pr.location).isHeading {
                titles.append(n.substring(with: contentRange(of: pr)).replacingOccurrences(of: softBreakString, with: " "))
                starts.append(pr.location)
            }
            p = NSMaxRange(pr)
        }
        let slugs = LinkResolver.slugs(forHeadings: titles)
        let want = (anchor.removingPercentEncoding ?? anchor).lowercased()
        guard let i = slugs.firstIndex(of: want) ?? slugs.firstIndex(of: LinkResolver.slug(want)) else { return false }
        setSelectedRange(NSRange(location: starts[i], length: 0))
        scrollRangeToVisible(NSRange(location: starts[i], length: 0))
        return true
    }

    /// ลิงก์ Obsidian `note#heading` / `#heading`
    func openWiki(_ value: String) -> LinkOpenResult {
        var target = value, heading: String?
        if let h = value.firstIndex(of: "#") { target = String(value[..<h]); heading = String(value[value.index(after: h)...]) }
        if target.isEmpty {
            guard let heading else { return .failed }
            return scrollToHeading(text: heading) ? .opened : .failed
        }
        guard let docDir = linkBaseProvider?() else { return .notice("Save the document to open links") }
        switch ObsidianVault.vault(for: docDir).resolve(target, docDir: docDir, isNote: true) {
        case .found(let u):
            if ObsidianSyntax.isImageName(u.lastPathComponent) || !["md", "markdown"].contains(u.pathExtension.lowercased()) { linkOpener.open(file: u) }
            else { linkOpener.open(markdown: u, heading: heading) }
            return .opened
        case .pending: return .notice("Indexing vault…")
        case .notFound: return .notice("Note not found")
        }
    }

    /// หัวข้อตามข้อความตรง ๆ (Obsidian: ไม่สนตัวพิมพ์/ช่องว่างซ้ำ ไม่ใช่ slug)
    func scrollToHeading(text: String) -> Bool {
        func norm(_ s: String) -> String { s.lowercased().split(whereSeparator: { $0.isWhitespace }).joined(separator: " ") }
        let want = norm(text)
        var p = 0
        let n = nsString
        while p < n.length {
            let pr = n.paragraphRange(for: NSRange(location: p, length: 0))
            if storage.blockKind(at: pr.location).isHeading, norm(n.substring(with: contentRange(of: pr)).replacingOccurrences(of: softBreakString, with: " ")) == want {
                setSelectedRange(NSRange(location: pr.location, length: 0))
                scrollRangeToVisible(NSRange(location: pr.location, length: 0))
                return true
            }
            p = NSMaxRange(pr)
        }
        return false
    }

    /// ลิงก์ Obsidian ที่หาโน้ตไม่เจอ = สีจาง (เหมือน unresolved link) — เรียกหลังโหลด/index เสร็จ
    func refreshWikiLinks() {
        guard storage.length > 0, let docDir = linkBaseProvider?() else { return }
        let vault = ObsidianVault.vault(for: docDir)
        var changes: [(NSRange, Bool)] = []
        storage.enumerateAttribute(.jotWiki, in: NSRange(location: 0, length: storage.length), options: []) { v, r, _ in
            guard let raw = v as? String, let w = ObsidianSyntax.parse(raw: raw), !w.embed else { return }
            var missing = false
            if !w.target.isEmpty {
                switch vault.resolve(w.target, docDir: docDir, isNote: true, rebuildIfMissing: false) {
                case .notFound: missing = true
                case .pending: return
                case .found: missing = false
                }
            }
            let now = storage.inlineStyle(at: r.location).contains(.unresolved)
            if now != missing { changes.append((r, missing)) }
        }
        guard !changes.isEmpty else { return }
        storage.beginEditing()
        for (r, missing) in changes {
            var st = storage.inlineStyle(at: r.location)
            if missing { st.insert(.unresolved) } else { st.remove(.unresolved) }
            storage.addAttribute(.jotInline, value: st.rawValue, range: r)
            storage.restyleParagraphs(in: r)
        }
        storage.endEditing()
    }

    /// เปิดลิงก์ที่เคอร์เซอร์อยู่ + เสียง/แจ้งเตือนเมื่อเปิดไม่ได้
    @objc func jotOpenLink(_ sender: Any?) {
        guard let hit = linkHitAtSelection() else { return }
        performLinkOpen(hit.url)
    }

    func performLinkOpen(_ url: String) {
        switch openLink(url) {
        case .opened: break
        case .failed: NSSound.beep()
        case .notice(let m): onLinkNotice?(m)
        }
    }

    @objc func jotCopyLinkAddress(_ sender: Any?) {
        guard let hit = linkHitAtSelection() else { return }
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(hit.url, forType: .string)
    }

    @objc func jotRemoveLink(_ sender: Any?) {
        guard let hit = linkHitAtSelection() else { return }
        if hit.url.hasPrefix("wiki:") { replaceWiki(range: hit.range, raw: nil); return }
        applyLink(nil, in: hit.range)
    }

    // MARK: - เมนูคลิกขวาบนลิงก์
    func linkContextItems() -> [NSMenuItem] {
        var items: [NSMenuItem] = []
        for (t, sel) in [("Open Link", #selector(jotOpenLink(_:))), ("Copy Link Address", #selector(jotCopyLinkAddress(_:))),
                         ("Edit Link…", #selector(jotEditLink(_:))), ("Remove Link", #selector(jotRemoveLink(_:)))] {
            let i = NSMenuItem(title: t, action: sel, keyEquivalent: ""); i.target = self; items.append(i)
        }
        return items
    }

    // MARK: - cursor รูปมือเมื่อกด ⌘
    override func flagsChanged(with event: NSEvent) {
        super.flagsChanged(with: event)
        window?.invalidateCursorRects(for: self)
    }

    override func resetCursorRects() {
        super.resetCursorRects()
        guard NSEvent.modifierFlags.contains(.command), storage.length > 0, let lm = layoutManager, let tc = textContainer else { return }
        let o = textContainerOrigin
        let vis = visibleRect.offsetBy(dx: -o.x, dy: -o.y)
        let glyphs = lm.glyphRange(forBoundingRect: vis, in: tc)
        let chars = lm.characterRange(forGlyphRange: glyphs, actualGlyphRange: nil)
        storage.enumerateAttribute(.jotLink, in: chars, options: []) { v, r, _ in
            guard v != nil else { return }
            lm.enumerateEnclosingRects(forGlyphRange: lm.glyphRange(forCharacterRange: r, actualCharacterRange: nil),
                                       withinSelectedGlyphRange: NSRange(location: NSNotFound, length: 0), in: tc) { rect, _ in
                self.addCursorRect(rect.offsetBy(dx: o.x, dy: o.y), cursor: .pointingHand)
            }
        }
    }

    // MARK: - เมาส์ชี้ลิงก์ (เรียกแถบลิงก์)
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        for a in trackingAreas where a.owner === self && a.userInfo?["jotLink"] != nil { removeTrackingArea(a) }
        addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseMoved, .mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect], owner: self, userInfo: ["jotLink": true]))
    }

    override func mouseMoved(with event: NSEvent) {
        super.mouseMoved(with: event)
        onLinkHover?(linkHit(atViewPoint: convert(event.locationInWindow, from: nil)))
    }

    override func mouseExited(with event: NSEvent) {
        super.mouseExited(with: event)
        onLinkHover?(nil)
    }

    // MARK: - URL เปล่า + เว้นวรรค = ลิงก์อัตโนมัติ
    /// เรียกก่อนแทรกช่องว่าง: ถ้าคำก่อนเคอร์เซอร์เป็น http(s)://… ที่ยังไม่เป็นลิงก์ ให้ทำเป็นลิงก์
    func autolinkWordBeforeCaret() {
        let caret = selectedRange().location
        guard selectedRange().length == 0, caret > 0, blockKindAtCaret.allowsInline else { return }
        let n = nsString
        var start = caret
        while start > 0 {
            let c = n.character(at: start - 1)
            if c == 0x20 || c == 0x09 || c == 0x0A || c == 0x2028 { break }
            start -= 1
        }
        var end = caret
        while end > start, let ch = Optional(n.character(at: end - 1)), ".,;:!?)".unicodeScalars.contains(where: { $0.value == UInt32(ch) }) { end -= 1 }
        let range = NSRange(location: start, length: end - start)
        guard range.length > 8 else { return }
        let word = n.substring(with: range)
        guard word.range(of: #"^https?://[^\s]+$"#, options: .regularExpression) != nil, storage.link(at: range.location) == nil else { return }
        let keep = selectedRange()
        applyLink(word, in: range)
        setSelectedRange(keep)
    }
}
