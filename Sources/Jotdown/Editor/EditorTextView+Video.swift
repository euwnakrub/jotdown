import AppKit

extension EditorTextView {
    // MARK: - หาการ์ดวิดีโอ
    func videoRef(at idx: Int) -> VideoRef? {
        guard idx >= 0, idx < storage.length, let enc = storage.attribute(.jotVideo, at: idx, effectiveRange: nil) as? String else { return nil }
        return VideoRef(encoded: enc)
    }

    /// การ์ดที่ถูกเลือกอยู่ (เลือกตัวอักษรการ์ดตัวเดียว) หรือที่เคอร์เซอร์ชิด
    func selectedVideo() -> (index: Int, ref: VideoRef)? {
        let sel = selectedRange()
        if sel.length == 1, let v = videoRef(at: sel.location) { return (sel.location, v) }
        return nil
    }

    /// กรอบการ์ดในพิกัด view
    func cardRect(at idx: Int) -> NSRect? {
        guard let lm = layoutManager, let tc = textContainer, idx < storage.length else { return nil }
        let g = lm.glyphRange(forCharacterRange: NSRange(location: idx, length: 1), actualCharacterRange: nil)
        guard g.length > 0 else { return nil }
        return lm.boundingRect(forGlyphRange: g, in: tc).offsetBy(dx: textContainerOrigin.x, dy: textContainerOrigin.y)
    }

    func videoHit(atViewPoint p: NSPoint) -> (index: Int, ref: VideoRef, rect: NSRect)? {
        guard storage.length > 0, let lm = layoutManager, let tc = textContainer else { return nil }
        let o = textContainerOrigin
        var frac: CGFloat = 0
        let idx = lm.characterIndex(for: NSPoint(x: p.x - o.x, y: p.y - o.y), in: tc, fractionOfDistanceBetweenInsertionPoints: &frac)
        guard let v = videoRef(at: idx), let r = cardRect(at: idx), r.contains(p) else { return nil }
        return (idx, v, r)
    }

    // MARK: - เล่นในหน้า
    func playVideo(at idx: Int) {
        guard let v = videoRef(at: idx), let yt = v.ref, let att = storage.attribute(.attachment, at: idx, effectiveRange: nil) as? NSTextAttachment else { return }
        let key = ObjectIdentifier(att)
        if videoPlayers[key] != nil { return }
        let view = VideoPlayerView(ref: v, yt: yt)
        view.onClose = { [weak self] in self?.closePlayer(key) }
        videoPlayers[key] = view
        addSubview(view)
        updatePlayerFrames()
    }

    func closePlayer(_ key: ObjectIdentifier) {
        guard let v = videoPlayers.removeValue(forKey: key) else { return }
        v.stop(); v.removeFromSuperview()
    }

    func stopAllPlayers() { for k in Array(videoPlayers.keys) { closePlayer(k) } }

    /// ให้ผู้เล่นตามการ์ดเสมอ (หลังแก้ข้อความ/ปรับขนาด/ซูม); การ์ดที่หายไป = ปิดผู้เล่น
    func updatePlayerFrames() {
        guard !videoPlayers.isEmpty else { return }
        var found: [ObjectIdentifier: Int] = [:]
        storage.enumerateAttribute(.attachment, in: NSRange(location: 0, length: storage.length), options: []) { v, r, _ in
            if let a = v as? VideoAttachment { found[ObjectIdentifier(a)] = r.location }
        }
        for (key, view) in videoPlayers {
            guard let idx = found[key], let rect = cardRect(at: idx) else { closePlayer(key); continue }
            view.frame = VideoCell.videoArea(in: rect)
        }
    }

    // MARK: - actions (เมนูคลิกขวา/เมนู Format)
    @objc func jotPlayVideo(_ s: Any?) { if let v = selectedVideo() { playVideo(at: v.index) } }
    @objc func jotOpenVideoInYouTube(_ s: Any?) { if let v = selectedVideo(), let yt = v.ref.ref { NSWorkspace.shared.open(yt.watchURL) } }
    @objc func jotCopyVideoLink(_ s: Any?) {
        guard let v = selectedVideo() else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(v.ref.url, forType: .string)
    }

    func videoContextMenu(index: Int) -> NSMenu {
        setSelectedRange(NSRange(location: index, length: 1))
        let m = NSMenu()
        for (t, sel) in [("Play", #selector(jotPlayVideo(_:))), ("Open in YouTube", #selector(jotOpenVideoInYouTube(_:))), ("Copy Link", #selector(jotCopyVideoLink(_:)))] {
            let i = NSMenuItem(title: t, action: sel, keyEquivalent: ""); i.target = self; m.addItem(i)
        }
        MenuIcons.decorate(m)
        return m
    }

    // MARK: - ใส่วิดีโอ
    /// สร้าง VideoRef จากข้อความที่ผู้ใช้ใส่ (URL เปล่า ถ้าไม่มี scheme เติม https://) — nil ถ้าไม่ใช่ YouTube
    static func makeVideo(from text: String) -> VideoRef? {
        var t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if t.hasPrefix("<"), t.hasSuffix(">") { t = String(t.dropFirst().dropLast()) }
        guard YouTubeLink.parse(t) != nil else { return nil }
        if !t.lowercased().hasPrefix("http") { t = "https://" + t }
        return VideoRef(raw: t, url: t)
    }

    func videoAttributedString(_ v: VideoRef) -> NSAttributedString {
        let seg = InlineSegment(text: imageCharacter, style: [], link: v.url, video: v)
        return NSAttributedString(string: imageCharacter, attributes: MarkdownParser.attributes(for: .paragraph, segment: seg))
    }

    /// ใส่การ์ดเป็นย่อหน้าของตัวเอง: ย่อหน้าว่าง = แทนที่, ไม่ว่าง = ต่อท้ายย่อหน้าเป็นย่อหน้าใหม่
    @discardableResult
    func insertVideo(_ v: VideoRef) -> Bool {
        guard !blockKindAtCaret.isCodeLike, !blockKindAtCaret.isTableCell else { return false }
        let pr = paragraphRange(containing: selectedRange().location)
        let content = contentRange(of: pr)
        let card = videoAttributedString(v)
        if content.length == 0 {
            replaceRange(NSRange(location: content.location, length: 0), with: card, selection: NSRange(location: content.location + 1, length: 0))
        } else {
            let out = NSMutableAttributedString(string: "\n", attributes: Theme.attributes(for: storage.blockKind(at: content.location)))
            out.append(card)
            let at = NSMaxRange(content)
            replaceRange(NSRange(location: at, length: 0), with: out, selection: NSRange(location: at + 2, length: 0))
        }
        syncTypingAttributes()
        return true
    }

    @objc func jotInsertVideo(_ s: Any?) {
        guard !blockKindAtCaret.isCodeLike, !blockKindAtCaret.isTableCell, let window else { return }
        let sheet = PromptSheet(title: "YouTube Video", message: "Paste a YouTube link", initial: "", placeholder: "https://www.youtube.com/watch?v=…")
        sheet.validator = { Self.makeVideo(from: $0) == nil ? "Not a YouTube link" : nil }
        promptSheet = sheet
        sheet.present(on: window) { [weak self] r in
            guard let self else { return }
            self.promptSheet = nil
            if case .ok(let text) = r, let v = Self.makeVideo(from: text) { self.insertVideo(v) }
        }
    }

    // MARK: - Insert Divider
    @objc func jotInsertDivider(_ s: Any?) { insertDivider() }

    /// เส้นคั่น: ย่อหน้าว่าง = แปลงเป็นเส้นคั่น, ไม่ว่าง = แทรกเป็นบล็อกใหม่ใต้บล็อกปัจจุบัน
    /// เคอร์เซอร์ไปอยู่ย่อหน้าว่างถัดจากเส้นคั่นเสมอ แก้ครั้งเดียว (undo ครั้งเดียว)
    @discardableResult
    func insertDivider() -> Bool {
        let kind = blockKindAtCaret
        guard !kind.isCodeLike, !kind.isTableCell else { return false }
        let pr = paragraphRange(containing: selectedRange().location)
        let content = contentRange(of: pr)
        let hrAttrs = Theme.attributes(for: .thematicBreak)
        let hasNL = pr.length > content.length
        let target: Int
        if content.length == 0 {
            let out = NSMutableAttributedString(string: thematicBreakText + "\n", attributes: hrAttrs)
            if hasNL { out.append(NSAttributedString(string: "\n", attributes: Theme.attributes(for: .paragraph))) }
            replaceRange(pr, with: out, selection: NSRange(location: pr.location + 2, length: 0))
            target = pr.location + 2
        } else if hasNL {
            let out = NSMutableAttributedString(string: thematicBreakText + "\n", attributes: hrAttrs)
            out.append(NSAttributedString(string: "\n", attributes: Theme.attributes(for: .paragraph)))
            let at = NSMaxRange(pr)
            replaceRange(NSRange(location: at, length: 0), with: out, selection: NSRange(location: at + 2, length: 0))
            target = at + 2
        } else {
            let out = NSMutableAttributedString(string: "\n", attributes: Theme.attributes(for: kind))
            out.append(NSAttributedString(string: thematicBreakText + "\n", attributes: hrAttrs))
            let at = NSMaxRange(content)
            replaceRange(NSRange(location: at, length: 0), with: out, selection: NSRange(location: at + 3, length: 0))
            target = at + 3
        }
        if paragraphRange(containing: target).length == 0 { pendingEmptyBlock = (target, .paragraph) }
        syncTypingAttributes()
        return true
    }
}
