import AppKit

final class EditorTextView: NSTextView {
    /// ย่อหน้าว่างท้ายเอกสาร (ยังไม่มีตัวอักษรให้เก็บ attribute) จำชนิดบล็อกที่ตั้งใจไว้ตรงนี้
    /// ชนิดของย่อหน้าว่างท้ายเอกสาร (ยังไม่มีตัวอักษรให้เก็บ attribute) — เปลี่ยนแล้วต้องวาดใหม่เพื่อให้ bullet/เลขขึ้นหรือหาย
    var linesShifted = false
    var pendingEmptyBlock: (location: Int, kind: BlockKind)? { didSet { setNeedsDisplay(visibleRect) } }
    /// non-contiguous layout ทำให้ NSTextTable วางเซลล์ผิดคอลัมน์ จึงปิด (ดู README) — เปิดได้เฉพาะเพื่อทดลองในเทสต์
    nonisolated(unsafe) static var useNonContiguousLayout = false
    var tableCheckWork: DispatchWorkItem?
    /// ผู้เล่นวิดีโอที่กำลังเล่น (key = attachment ของการ์ด) — สร้างเฉพาะตอนกดเล่น
    var videoPlayers: [ObjectIdentifier: VideoPlayerView] = [:]
    var internalEdit = false
    /// ตำแหน่งต้นกล่องโค้ดที่กำลังเลือกภาษา (จากป้ายภาษาหรือเมนูคลิกขวา)
    var languageTarget = 0
    /// ข้อความที่กำลังจะแทนที่ช่วงที่ shouldChangeText ตรวจอยู่ (ใช้ตอนลบตารางทั้งตารางแล้วพิมพ์ทับ)
    var pendingReplacement: String?
    /// โฟลเดอร์ที่ path รูปสัมพัทธ์อ้างอิง (ผู้ใช้: EditorViewController ผูกกับเอกสาร)
    var imageBaseProvider: (() -> URL?)?
    var imageBaseDirectory: URL? { imageBaseProvider?() }
    var promptSheet: PromptSheet?
    /// โฟลเดอร์ของเอกสารที่บันทึกแล้ว (nil = ยังไม่มีชื่อ) ใช้ resolve ลิงก์แบบ path สัมพัทธ์
    var linkBaseProvider: (() -> URL?)?
    var linkOpener: LinkOpening = SystemLinkOpener()
    var onLinkHover: ((LinkHit?) -> Void)?
    var onLinkNotice: ((String) -> Void)?
    /// เคอร์เซอร์อยู่ตำแหน่งนี้หลังแปลง inline shortcut: พิมพ์ต่อเป็นตัวธรรมดา
    var plainTypingAt: Int?

    /// สร้าง TextKit 1 stack เอง (รองรับ attachment / NSTextTable ในขั้นหลัง)
    static func make(storage: NSTextStorage) -> EditorTextView {
        let layoutManager = EditorLayoutManager()
        layoutManager.allowsNonContiguousLayout = Self.useNonContiguousLayout
        let container = NSTextContainer(size: NSSize(width: 0, height: CGFloat.greatestFiniteMagnitude))
        container.widthTracksTextView = true
        container.lineFragmentPadding = 0
        layoutManager.addTextContainer(container)
        storage.addLayoutManager(layoutManager)
        let tv = EditorTextView(frame: NSRect(origin: .zero, size: Theme.defaultWindowSize), textContainer: container)
        tv.configure()
        return tv
    }

    private func configure() {
        isRichText = true                 // ต้องการ attribute ต่อช่วง แต่ห้ามรับ rich text จากภายนอก (ดู paste)
        importsGraphics = false
        allowsImageEditing = false
        usesFontPanel = false
        usesRuler = false
        allowsUndo = true
        isEditable = true
        isSelectable = true
        isAutomaticQuoteSubstitutionEnabled = false
        isAutomaticDashSubstitutionEnabled = false
        isAutomaticTextReplacementEnabled = true   // Text Replacements ของ macOS (System Settings > Keyboard) — ข้ามโค้ด ดู handleTextCheckingResults
        isAutomaticSpellingCorrectionEnabled = false
        isAutomaticLinkDetectionEnabled = false
        isAutomaticDataDetectionEnabled = false
        isAutomaticTextCompletionEnabled = false
        isContinuousSpellCheckingEnabled = false
        isGrammarCheckingEnabled = false
        smartInsertDeleteEnabled = false
        usesFindBar = true
        isIncrementalSearchingEnabled = true
        if #available(macOS 15.0, *) { writingToolsBehavior = .none }
        drawsBackground = true
        backgroundColor = Palette.paper
        insertionPointColor = Palette.caret
        selectedTextAttributes = [.backgroundColor: Palette.selection]
        isVerticallyResizable = true
        isHorizontallyResizable = false
        autoresizingMask = [.width]
        minSize = NSSize(width: 0, height: 0)
        maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        typingAttributes = Theme.attributes(for: .paragraph)
        textContainerInset = NSSize(width: Theme.columnMinMargin, height: Theme.verticalInset)
    }

    var storage: NSTextStorage { textStorage! }
    var nsString: NSString { storage.string as NSString }

    // MARK: - คอลัมน์กว้างสูงสุด 720 อยู่กลาง
    static func horizontalInset(forWidth w: CGFloat) -> CGFloat {
        let column = min(Theme.columnMaxWidth, max(0, w - 2 * Theme.columnMinMargin))
        return max(Theme.columnMinMargin, ((w - column) / 2).rounded(.down))
    }

    private func updateInsets() {
        let inset = NSSize(width: Self.horizontalInset(forWidth: bounds.width), height: Theme.verticalInset)
        if inset != textContainerInset { textContainerInset = inset }
    }

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        updateInsets()
        updatePlayerFrames()
    }

    // MARK: - ย่อหน้า / บล็อกที่เคอร์เซอร์
    /// ย่อหน้าที่มีตำแหน่ง `loc` (ท้ายเอกสารหลัง "\n" = ย่อหน้าว่างความยาว 0)
    func paragraphRange(containing loc: Int) -> NSRange {
        let n = nsString
        if n.length == 0 { return NSRange(location: 0, length: 0) }
        if loc >= n.length {
            if n.character(at: n.length - 1) == 0x0A { return NSRange(location: n.length, length: 0) }
            return n.paragraphRange(for: NSRange(location: n.length - 1, length: 0))
        }
        return n.paragraphRange(for: NSRange(location: loc, length: 0))
    }

    func contentRange(of pr: NSRange) -> NSRange {
        var c = pr
        if c.length > 0, nsString.character(at: NSMaxRange(c) - 1) == 0x0A { c.length -= 1 }
        return c
    }

    func kind(at loc: Int) -> BlockKind {
        let pr = paragraphRange(containing: loc)
        if pr.length == 0 {
            if let p = pendingEmptyBlock, p.location == loc { return p.kind }
            return .paragraph
        }
        return storage.blockKind(at: pr.location)
    }

    var blockKindAtCaret: BlockKind { kind(at: selectedRange().location) }

    func syncTypingAttributes() {
        let loc = selectedRange().location
        if let p = plainTypingAt, p != loc { plainTypingAt = nil }
        if let p = pendingEmptyBlock, p.location != loc { pendingEmptyBlock = nil }
        let kind = blockKindAtCaret
        var inline: InlineStyle = []
        if kind.allowsInline, storage.length > 0 {
            let pr = paragraphRange(containing: loc)
            var ref = -1
            if loc > pr.location { ref = loc - 1 } else if pr.length > 1 { ref = loc }
            if ref >= 0, ref < storage.length, nsString.character(at: ref) != 0x0A {
                inline = storage.inlineStyle(at: ref).subtracting([.raw, .hardBreak])
            }
            if plainTypingAt == loc { inline = [] }
        }
        typingAttributes = typingAttrs(kind: kind, inline: inline)
    }

    /// attribute ของข้อความที่จะพิมพ์ในย่อหน้าที่เคอร์เซอร์อยู่ (ระยะหลังย่อหน้าตามบล็อกถัดไป)
    func typingAttrs(kind: BlockKind, inline: InlineStyle = []) -> [NSAttributedString.Key: Any] {
        let pr = paragraphRange(containing: selectedRange().location)
        var table: NSTextTable?
        if kind.isTableCell, pr.length > 0, let ps = storage.attribute(.paragraphStyle, at: pr.location, effectiveRange: nil) as? NSParagraphStyle { table = (ps.textBlocks.first as? NSTextTableBlock)?.table }
        let next: BlockKind? = NSMaxRange(pr) < storage.length ? storage.blockKind(at: NSMaxRange(pr)) : nil
        return Theme.attributes(for: kind, inline: inline, spacing: Theme.gap(after: kind, next: next), table: table)
    }

    /// ปรับระยะย่อหน้าของย่อหน้าข้างเคียงหลังแก้ไข (ระยะหลังย่อหน้าขึ้นกับบล็อกถัดไป)
    override func didChangeText() {
        super.didChangeText()
        // บางครั้งระบบวาดใหม่แค่บรรทัดที่แก้ ทำให้บรรทัดถัดไปค้างภาพเก่า (เช่นรายการหายหลังกด Enter ในลิสต์ย่อย)
        if linesShifted { linesShifted = false; setNeedsDisplay(visibleRect) }
        updatePlayerFrames()
        guard storage.length > 0 else { return }
        scheduleTableLayoutCheck()
        let sel = selectedRange()
        let loc = min(sel.location, storage.length)
        var r = nsString.paragraphRange(for: NSRange(location: loc, length: min(sel.length, storage.length - loc)))
        if r.location > 0 { r = NSUnionRange(r, nsString.paragraphRange(for: NSRange(location: r.location - 1, length: 0))) }
        storage.beginEditing()
        storage.restyleParagraphs(in: r)
        storage.endEditing()
    }

    // MARK: - แก้ไขแบบมีผล undo
    /// แทนที่ช่วงด้วย attributed string (ผ่าน shouldChangeText/didChangeText เพื่อ undo + แจ้งเอกสาร)
    @discardableResult
    func replaceRange(_ r: NSRange, with a: NSAttributedString, selection: NSRange? = nil) -> Bool {
        internalEdit = true; defer { internalEdit = false }
        breakUndoCoalescing()      // ไม่รวมกับการพิมพ์ก่อนหน้าเป็นก้อน undo เดียว
        guard shouldChangeText(in: r, replacementString: a.string) else { return false }
        storage.replaceCharacters(in: r, with: a)
        didChangeText()
        if let selection {
            let len = storage.length
            let loc = min(selection.location, len)
            setSelectedRange(NSRange(location: loc, length: min(selection.length, len - loc)))
        }
        return true
    }

    /// แก้ย่อหน้าทั้งหมดที่ช่วง `sel` แตะ (ผ่านฟังก์ชัน `f` บนสำเนา) แล้วแทนที่ครั้งเดียว
    @discardableResult
    func transformParagraphs(in sel: NSRange, keepSelection: Bool = true, _ f: (NSMutableAttributedString) -> Void) -> Bool {
        guard storage.length > 0 else { return false }
        let loc = min(sel.location, storage.length)
        let pr = nsString.paragraphRange(for: NSRange(location: loc, length: min(sel.length, storage.length - loc)))
        let sub = NSMutableAttributedString(attributedString: storage.attributedSubstring(from: pr))
        f(sub)
        sub.restyleParagraphs(in: NSRange(location: 0, length: sub.length))
        let keep = selectedRange()
        return replaceRange(pr, with: sub, selection: keepSelection ? keep : nil)
    }

    /// เปลี่ยนชนิดบล็อกของย่อหน้าที่เลือก (หรือย่อหน้าว่างท้ายเอกสาร)
    func applyKind(_ transform: (BlockKind) -> BlockKind) {
        let sel = selectedRange()
        let pr = paragraphRange(containing: sel.location)
        if pr.length == 0 {
            let k = transform(blockKindAtCaret)
            pendingEmptyBlock = (sel.location, k)
            syncTypingAttributes()
            return
        }
        transformParagraphs(in: sel) { sub in
            var ranges: [NSRange] = []
            let n = sub.string as NSString
            var p = 0
            while p < n.length {
                let r = n.paragraphRange(for: NSRange(location: p, length: 0))
                ranges.append(r); p = NSMaxRange(r)
            }
            var items: [(NSRange, BlockKind, BlockKind)] = []
            for r in ranges {
                let old = sub.blockKind(at: r.location)
                items.append((r, old, transform(old)))
            }
            for (r, old, new) in items.reversed() {
                var rr = r
                let hasNL = (sub.string as NSString).character(at: NSMaxRange(r) - 1) == 0x0A
                let content = NSRange(location: r.location, length: r.length - (hasNL ? 1 : 0))
                if old == .thematicBreak && new != .thematicBreak, content.length > 0 {
                    sub.replaceCharacters(in: content, with: "")
                    rr.length -= content.length
                } else if new == .thematicBreak && old != .thematicBreak {
                    sub.replaceCharacters(in: content, with: NSAttributedString(string: thematicBreakText, attributes: Theme.attributes(for: .thematicBreak)))
                    rr.length += 1 - content.length
                }
                if rr.length > 0 { sub.addAttribute(.jotBlock, value: new.code, range: rr) }
            }
        }
        syncTypingAttributes()
    }

    // MARK: - ป้องกันพิมพ์ทับเส้นคั่น
    override func shouldChangeText(in affectedCharRange: NSRange, replacementString: String?) -> Bool {
        let undoing = (undoManager?.isUndoing ?? false) || (undoManager?.isRedoing ?? false)
        pendingReplacement = replacementString
        // เพิ่ม/ลบตัวขึ้นบรรทัด = บรรทัดด้านล่างเลื่อนทั้งหมด (ดู didChangeText)
        if replacementString?.contains("\n") == true || (affectedCharRange.length > 0 && NSMaxRange(affectedCharRange) <= storage.length
            && nsString.substring(with: affectedCharRange).contains("\n")) { linesShifted = true }
        if !internalEdit, !undoing, !guardTableEdit(affectedCharRange) { return false }
        if !internalEdit, !undoing, let s = replacementString, !s.isEmpty, s != "\n", storage.length > 0 {
            let pr = paragraphRange(containing: affectedCharRange.location)
            if pr.length > 0, storage.blockKind(at: pr.location) == .thematicBreak { return false }
        }
        return super.shouldChangeText(in: affectedCharRange, replacementString: replacementString)
    }

    // MARK: - เมาส์
    private func containerPoint(for event: NSEvent) -> NSPoint {
        let p = convert(event.locationInWindow, from: nil)
        let o = textContainerOrigin
        return NSPoint(x: p.x - o.x, y: p.y - o.y)
    }

    override func mouseDown(with event: NSEvent) {
        if let hit = videoHit(atViewPoint: convert(event.locationInWindow, from: nil)) {
            window?.makeFirstResponder(self)
            setSelectedRange(NSRange(location: hit.index, length: 1))
            let p = convert(event.locationInWindow, from: nil)
            if VideoCell.playButtonRect(in: VideoCell.videoArea(in: hit.rect)).insetBy(dx: -4, dy: -4).contains(p) { playVideo(at: hit.index) }
            return
        }
        if let hit = imageHit(event) {
            window?.makeFirstResponder(self)
            setSelectedRange(NSRange(location: hit.index, length: 1))
            if event.clickCount >= 2 { openImage(at: hit.index) }
            return
        }
        if let lm = layoutManager as? EditorLayoutManager, let tc = textContainer, storage.length > 0 {
            let cp = containerPoint(for: event)
            var frac: CGFloat = 0
            let idx = lm.characterIndex(for: cp, in: tc, fractionOfDistanceBetweenInsertionPoints: &frac)
            if idx < storage.length {
                if storage.blockKind(at: idx).isCode, let label = lm.languageLabelRect(forParagraphAt: idx), label.insetBy(dx: -6, dy: -4).contains(cp) {
                    window?.makeFirstResponder(self)
                    showLanguageMenu(forBlockAt: idx)
                    return
                }
                if case .task = storage.blockKind(at: idx),
                   let box = lm.markerRect(forParagraphAt: idx), box.insetBy(dx: -5, dy: -5).contains(cp) {
                    toggleTaskChecked(at: idx)
                    return
                }
                if event.modifierFlags.contains(.command), let link = storage.link(at: idx),
                   lm.boundingRect(forGlyphRange: lm.glyphRange(forCharacterRange: NSRange(location: idx, length: 1), actualCharacterRange: nil), in: tc).insetBy(dx: -2, dy: -2).contains(cp),
                   let url = URL(string: link) {
                    NSWorkspace.shared.open(url)
                    return
                }
            }
        }
        super.mouseDown(with: event)
    }
}
