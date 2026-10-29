import AppKit

extension EditorTextView {
    // MARK: - hit test
    func imageHit(_ event: NSEvent) -> (index: Int, ref: ImageRef)? {
        guard storage.length > 0, let lm = layoutManager, let tc = textContainer else { return nil }
        let p = convert(event.locationInWindow, from: nil)
        let o = textContainerOrigin
        let cp = NSPoint(x: p.x - o.x, y: p.y - o.y)
        var frac: CGFloat = 0
        let idx = lm.characterIndex(for: cp, in: tc, fractionOfDistanceBetweenInsertionPoints: &frac)
        guard idx < storage.length, let enc = storage.attribute(.jotImage, at: idx, effectiveRange: nil) as? String, let ref = ImageRef(encoded: enc) else { return nil }
        let rect = lm.boundingRect(forGlyphRange: lm.glyphRange(forCharacterRange: NSRange(location: idx, length: 1), actualCharacterRange: nil), in: tc)
        return rect.insetBy(dx: -2, dy: -2).contains(cp) ? (idx, ref) : nil
    }

    func imageRef(at idx: Int) -> ImageRef? {
        guard idx >= 0, idx < storage.length, let enc = storage.attribute(.jotImage, at: idx, effectiveRange: nil) as? String else { return nil }
        return ImageRef(encoded: enc)
    }

    func resolvedURL(_ ref: ImageRef) -> URL? {
        if ref.raw != nil {   // Obsidian: หาแบบ vault (โฟลเดอร์เอกสาร → attachment → ทั้ง vault)
            guard !ref.noteEmbed, let dir = linkBaseProvider?() ?? imageBaseDirectory else { return nil }
            if case .found(let u) = ObsidianVault.vault(for: dir).resolve(ref.src, docDir: dir, isNote: false) { return u }
            return nil
        }
        return ImageAssets.resolve(ref.src, base: imageBaseDirectory)
    }

    func image(for ref: ImageRef) -> NSImage? {
        guard let url = resolvedURL(ref) else { return nil }
        if url.isFileURL { return NSImage(contentsOf: url) }
        if case .loaded(let cg, let px) = ImageLoader.shared.state(for: url) { return NSImage(cgImage: cg, size: px) }
        return nil
    }

    /// โหลดรูปเสร็จ: ให้ layout/วาดใหม่เฉพาะตัวอักษรรูป
    func refreshImages() {
        guard storage.length > 0, let lm = layoutManager else { return }
        storage.enumerateAttribute(.jotImage, in: NSRange(location: 0, length: storage.length), options: []) { v, r, _ in
            guard v != nil else { return }
            lm.invalidateGlyphs(forCharacterRange: r, changeInLength: 0, actualCharacterRange: nil)
            lm.invalidateLayout(forCharacterRange: r, actualCharacterRange: nil)
            lm.invalidateDisplay(forCharacterRange: r)
            lm.ensureLayout(forCharacterRange: r)
        }
        refreshWikiLinks()
        needsDisplay = true
    }

    // MARK: - การกระทำกับรูป
    func openImage(at idx: Int) {
        guard let ref = imageRef(at: idx) else { return }
        if ref.noteEmbed { performLinkOpen(storage.link(at: idx) ?? "wiki:" + ref.src); return }
        guard let url = resolvedURL(ref) else { return }
        if url.isFileURL {
            let preview = URL(fileURLWithPath: "/System/Applications/Preview.app")
            if FileManager.default.fileExists(atPath: preview.path) {
                NSWorkspace.shared.open([url], withApplicationAt: preview, configuration: NSWorkspace.OpenConfiguration())
            } else { NSWorkspace.shared.open(url) }
        } else { NSWorkspace.shared.open(url) }
    }

    override func menu(for event: NSEvent) -> NSMenu? {
        guard let hit = imageHit(event) else {
            let p = convert(event.locationInWindow, from: nil)
            if let link = linkHit(atViewPoint: p) {
                setSelectedRange(NSRange(location: link.range.location + min(1, link.range.length), length: 0))
                let m = NSMenu()
                linkContextItems().forEach { m.addItem($0) }
                if let base = super.menu(for: event), !base.items.isEmpty {
                    m.addItem(.separator())
                    for i in base.items { base.removeItem(i); m.addItem(i) }
                }
                return m
            }
            let idx = characterIndexForInsertion(at: p)
            if cellInfo(at: min(idx, max(storage.length - 1, 0))) != nil {
                setSelectedRange(NSRange(location: idx, length: 0))
                return tableContextMenu()
            }
            return super.menu(for: event)
        }
        setSelectedRange(NSRange(location: hit.index, length: 1))
        let m = NSMenu()
        func add(_ title: String, _ sel: Selector) {
            let i = NSMenuItem(title: title, action: sel, keyEquivalent: "")
            i.target = self; i.tag = hit.index
            m.addItem(i)
        }
        if let url = resolvedURL(hit.ref), url.isFileURL { add("Show in Finder", #selector(jotRevealImage(_:))) }
        add("Copy Image", #selector(jotCopyImage(_:)))
        add("Edit Description…", #selector(jotEditImageAlt(_:)))
        return m
    }

    @objc func jotRevealImage(_ s: NSMenuItem) {
        if let ref = imageRef(at: s.tag), let url = resolvedURL(ref) { NSWorkspace.shared.activateFileViewerSelecting([url]) }
    }
    @objc func jotCopyImage(_ s: NSMenuItem) {
        setSelectedRange(NSRange(location: s.tag, length: 1))
        copy(nil)
    }
    @objc func jotEditImageAlt(_ s: NSMenuItem) { editImageAlt(at: s.tag) }

    func editImageAlt(at idx: Int) {
        guard let ref = imageRef(at: idx), let window else { return }
        let sheet = PromptSheet(title: "Image Description", message: "Alternative text shown when the image cannot be loaded", initial: ref.alt)
        promptSheet = sheet
        sheet.present(on: window) { [weak self] r in
            guard let self else { return }
            self.promptSheet = nil
            if case .ok(let text) = r { self.setImageAlt(text, at: idx) }
        }
    }

    func setImageAlt(_ alt: String, at idx: Int) {
        guard var ref = imageRef(at: idx) else { return }
        ref.alt = alt
        let kind = kind(at: idx)
        let seg = InlineSegment(text: imageCharacter, style: [], link: storage.link(at: idx), image: ref)
        replaceRange(NSRange(location: idx, length: 1), with: NSAttributedString(string: imageCharacter, attributes: MarkdownParser.attributes(for: kind, segment: seg, spacing: nil)),
                     selection: NSRange(location: idx, length: 1))
    }

    // MARK: - แทรกรูป
    /// แทรกรูปที่ตำแหน่งเคอร์เซอร์: รูปเดียว = ในบรรทัด, หลายรูป = ย่อหน้าละรูป
    func insertImages(_ refs: [ImageRef]) {
        guard !refs.isEmpty, !blockKindAtCaret.isCodeLike else { return }
        let blocks = refs.map { ParsedBlock(kind: .paragraph, segments: [InlineSegment(text: imageCharacter, style: [], link: nil, image: $0)]) }
        insertBlocks(blocks)
    }

    /// รูปจาก pasteboard: ไฟล์รูป, URL รูปบนเว็บ, ข้อมูลรูป (screenshot) — คืน true ถ้าจัดการแล้ว
    @discardableResult
    func insertImages(from pb: NSPasteboard, at dropIndex: Int?) -> Bool {
        guard let base = imageBaseDirectory else { return false }
        var refs: [ImageRef] = []
        let fileURLs = (pb.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL]) ?? []
        if !fileURLs.isEmpty {
            guard fileURLs.allSatisfy(ImageAssets.isImageFile) else { return false }
            for u in fileURLs {
                if let src = try? ImageAssets.importFile(u, baseDir: base) {
                    refs.append(ImageRef(src: src, alt: u.deletingPathExtension().lastPathComponent))
                }
            }
        } else if let web = (pb.readObjects(forClasses: [NSURL.self], options: nil) as? [URL])?.first(where: { !$0.isFileURL && ImageAssets.isImageFile($0) }),
                  pb.string(forType: .html) == nil || pb.string(forType: .string) == web.absoluteString {
            refs.append(ImageRef(src: web.absoluteString, alt: web.deletingPathExtension().lastPathComponent))
        } else if pb.string(forType: .string) == nil, pb.string(forType: .html) == nil,
                  let data = pb.data(forType: .png) ?? pb.data(forType: .tiff), let img = NSImage(data: data), let png = ImageAssets.pngData(from: img),
                  let src = try? ImageAssets.importImageData(png, baseDir: base) {
            refs.append(ImageRef(src: src, alt: "image"))
        }
        guard !refs.isEmpty else { return false }
        refs = obsidianize(refs)
        if let i = dropIndex { setSelectedRange(NSRange(location: min(i, storage.length), length: 0)); syncTypingAttributes() }
        insertImages(refs)
        return true
    }

    // MARK: - เมนู Insert Image…
    @objc func jotInsertImage(_ s: Any?) {
        guard let base = imageBaseDirectory, !blockKindAtCaret.isCodeLike else { return }
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image]
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.message = "Choose images to insert"
        let handle: (NSApplication.ModalResponse) -> Void = { [weak self] r in
            guard r == .OK, let self else { return }
            self.insertImageFiles(panel.urls, base: base)
        }
        if let w = window { panel.beginSheetModal(for: w, completionHandler: handle) } else { handle(panel.runModal()) }
    }

    func insertImageFiles(_ urls: [URL], base: URL) {
        let refs = urls.compactMap { u -> ImageRef? in
            guard let src = try? ImageAssets.importFile(u, baseDir: base) else { return nil }
            return ImageRef(src: src, alt: u.deletingPathExtension().lastPathComponent)
        }
        insertImages(refs)
    }

    /// เอกสารอยู่ใน Obsidian vault และมี `![[` อยู่แล้ว: รูปใหม่ใส่เป็น `![[ชื่อไฟล์]]` (ไม่งั้นใช้ markdown มาตรฐาน)
    func obsidianize(_ refs: [ImageRef]) -> [ImageRef] {
        guard let dir = linkBaseProvider?(), ObsidianVault.rootDirectory(for: dir).1 else { return refs }
        var hasEmbed = false
        storage.enumerateAttribute(.jotImage, in: NSRange(location: 0, length: storage.length), options: []) { v, _, stop in
            if let e = v as? String, let r = ImageRef(encoded: e), r.raw?.hasPrefix("![[") == true { hasEmbed = true; stop.pointee = true }
        }
        guard hasEmbed else { return refs }
        return refs.map { r in
            if ImageAssets.isRemote(r.src) { return r }
            let name = (r.src.removingPercentEncoding ?? r.src as String) as NSString
            return ImageRef(src: name.lastPathComponent, alt: "", raw: "![[\(name.lastPathComponent)]]")
        }
    }

    // MARK: - ลากวาง
    override var acceptableDragTypes: [NSPasteboard.PasteboardType] { super.acceptableDragTypes + [.fileURL, .URL, .png, .tiff] }

    private func hasDroppableImage(_ pb: NSPasteboard) -> Bool {
        if let urls = pb.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL], !urls.isEmpty {
            return urls.allSatisfy(ImageAssets.isImageFile)
        }
        if let urls = pb.readObjects(forClasses: [NSURL.self], options: nil) as? [URL], urls.contains(where: { !$0.isFileURL && ImageAssets.isImageFile($0) }) { return true }
        return pb.string(forType: .string) == nil && (pb.data(forType: .png) != nil || pb.data(forType: .tiff) != nil)
    }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        hasDroppableImage(sender.draggingPasteboard) ? .copy : super.draggingEntered(sender)
    }
    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
        hasDroppableImage(sender.draggingPasteboard) ? .copy : super.draggingUpdated(sender)
    }
    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        let pb = sender.draggingPasteboard
        if hasDroppableImage(pb) {
            let idx = characterIndexForInsertion(at: convert(sender.draggingLocation, from: nil))
            return insertImages(from: pb, at: idx)
        }
        return super.performDragOperation(sender)
    }
}
