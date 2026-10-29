import AppKit
import UniformTypeIdentifiers

extension Notification.Name {
    static let jotdownZoomChanged = Notification.Name("JotdownZoomChanged")
    static let jotDocumentWillReload = Notification.Name("JotdownDocumentWillReload")
    static let jotDocumentDidReload = Notification.Name("JotdownDocumentDidReload")
}

enum JotTypes {
    static let markdown = "net.daringfireball.markdown"
}

enum MarkdownFile {
    /// UTF-8 (มี/ไม่มี BOM) -> ข้อความ LF
    static func decode(_ data: Data) throws -> String {
        guard let s = String(data: data, encoding: .utf8) else {
            throw NSError(domain: NSCocoaErrorDomain, code: NSFileReadInapplicableStringEncodingError,
                          userInfo: [NSLocalizedDescriptionKey: "This file is not UTF-8 and cannot be opened."])
        }
        return MarkdownParser.normalize(s)
    }
    static func encode(_ s: String) -> Data { Data(s.utf8) }
}

@objc(JotdownDocument)
final class JotdownDocument: NSDocument, NSTextStorageDelegate {
    let textStorage = NSTextStorage()
    /// markdown ของเนื้อหาตอนโหลด/บันทึกล่าสุด — ใช้เทียบเพื่อไม่เขียนไฟล์ถ้าเนื้อหาไม่ต่าง
    private(set) var syncedMarkdown: String = ""
    private(set) var isReloading = false
    private var pendingWritten: String?

    lazy var saveDebouncer = Debouncer(delay: 1.0) { [weak self] in self?.saveNow() }

    override init() {
        super.init()
        textStorage.delegate = self
        NotificationCenter.default.addObserver(self, selector: #selector(storageDidEdit(_:)),
                                               name: NSTextStorage.didProcessEditingNotification, object: textStorage)
    }

    deinit { NotificationCenter.default.removeObserver(self) }

    // MARK: - ชนิดเอกสาร (ไม่พึ่ง Info.plist เพื่อให้ swift run / เทสต์ทำงานได้)
    override class var autosavesInPlace: Bool { true }
    override class var readableTypes: [String] { [JotTypes.markdown, "public.plain-text"] }
    override class var writableTypes: [String] { [JotTypes.markdown] }
    override class func isNativeType(_ type: String) -> Bool { type == JotTypes.markdown || type == "public.plain-text" }
    override func fileNameExtension(forType typeName: String, saveOperation: NSDocument.SaveOperationType) -> String? { "md" }

    // MARK: - รูปภาพ
    /// โฟลเดอร์ชั่วคราวของเอกสารที่ยังไม่มีชื่อ (Application Support) — path รูปสัมพัทธ์ resolve จากที่นี่ จนกว่าจะบันทึกครั้งแรก
    private(set) lazy var untitledRoot: URL = {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return support.appendingPathComponent("Jotdown/Untitled/\(UUID().uuidString)", isDirectory: true)
    }()

    /// โฟลเดอร์ที่ path รูปสัมพัทธ์อ้างอิง: โฟลเดอร์ของไฟล์ .md หรือโฟลเดอร์ชั่วคราว
    var imageBaseDirectory: URL { fileURL?.deletingLastPathComponent() ?? untitledRoot }

    /// ย้ายรูปที่เก็บชั่วคราว (เอกสารไม่มีชื่อ) ไป `assets/` ข้างไฟล์ที่เพิ่งบันทึก และแก้ path ในเอกสาร
    func migrateUntitledAssets(to dir: URL) throws {
        let root = untitledRoot
        var moved: [String: String] = [:]     // src เดิม -> src ใหม่
        var edits: [(NSRange, ImageRef)] = []
        let fm = FileManager.default
        storage_enumerate: do {
            guard textStorage.length > 0 else { break storage_enumerate }
            textStorage.enumerateAttribute(.jotImage, in: NSRange(location: 0, length: textStorage.length), options: []) { v, r, _ in
                guard let enc = v as? String, let ref = ImageRef(encoded: enc), !ImageAssets.isRemote(ref.src),
                      let url = ImageAssets.resolve(ref.src, base: root), ImageAssets.relativePath(from: root, to: url) != nil else { return }
                edits.append((r, ref))
            }
        }
        guard !edits.isEmpty else { return }
        for (_, ref) in edits where moved[ref.src] == nil {
            guard let from = ImageAssets.resolve(ref.src, base: root), fm.fileExists(atPath: from.path) else { continue }
            let assets = dir.appendingPathComponent("assets", isDirectory: true)
            try fm.createDirectory(at: assets, withIntermediateDirectories: true)
            let name = ImageAssets.uniqueName(from.lastPathComponent, in: assets)
            try fm.moveItem(at: from, to: assets.appendingPathComponent(name))
            moved[ref.src] = ImageAssets.encodePath("assets/" + name)
        }
        isReloading = true
        textStorage.beginEditing()
        for (r, ref) in edits {
            guard let newSrc = moved[ref.src] else { continue }
            var n = ref; n.src = newSrc
            textStorage.addAttribute(.jotImage, value: n.encoded, range: r)
            textStorage.addAttribute(.attachment, value: ImageAttachment(ref: n), range: r)
        }
        textStorage.endEditing()
        isReloading = false
        try? fm.removeItem(at: root)
        NotificationCenter.default.post(name: .jotImageLoaded, object: nil)
    }

    override func save(to url: URL, ofType typeName: String, for saveOperation: NSDocument.SaveOperationType,
                       completionHandler: @escaping (Error?) -> Void) {
        if fileURL == nil, saveOperation != .autosaveElsewhereOperation {
            try? migrateUntitledAssets(to: url.deletingLastPathComponent())
        }
        super.save(to: url, ofType: typeName, for: saveOperation, completionHandler: completionHandler)
    }

    /// จัดรูปแบบทั้งเอกสารใหม่ตามธีม/ซูมปัจจุบัน (ไม่เปลี่ยนข้อความ ไม่ทริกเกอร์บันทึก)
    func reapplyStyles() {
        guard textStorage.length > 0 else { NotificationCenter.default.post(name: .jotdownZoomChanged, object: self); return }
        isReloading = true
        textStorage.beginEditing()
        textStorage.restyleParagraphs(in: NSRange(location: 0, length: textStorage.length))
        textStorage.endEditing()
        isReloading = false
        NotificationCenter.default.post(name: .jotdownZoomChanged, object: self)
    }

    // MARK: - เนื้อหา
    var currentMarkdown: String { MarkdownSerializer.serialize(textStorage) }

    /// แทนที่เนื้อหาทั้งหมดโดยไม่ทริกเกอร์บันทึก
    func load(markdown: String) {
        NotificationCenter.default.post(name: .jotDocumentWillReload, object: self)
        isReloading = true
        textStorage.setAttributedString(MarkdownParser.parse(markdown))
        isReloading = false
        syncedMarkdown = currentMarkdown
        saveDebouncer.cancel()
        undoManager?.removeAllActions()
        NotificationCenter.default.post(name: .jotDocumentDidReload, object: self)
    }

    override func read(from data: Data, ofType typeName: String) throws {
        let md = try MarkdownFile.decode(data)
        // เนื้อหาเท่าเดิม (เช่นไฟล์ที่เราเพิ่งเขียนเอง) ไม่ต้องโหลดใหม่
        if currentMarkdown == MarkdownSerializer.serialize(MarkdownParser.blocks(from: md)) {
            syncedMarkdown = currentMarkdown
            return
        }
        load(markdown: md)
    }

    override func data(ofType typeName: String) throws -> Data {
        let md = currentMarkdown
        pendingWritten = md
        return MarkdownFile.encode(md)
    }

    override func write(to url: URL, ofType typeName: String, for saveOperation: NSDocument.SaveOperationType,
                        originalContentsURL absoluteOriginalContentsURL: URL?) throws {
        try super.write(to: url, ofType: typeName, for: saveOperation, originalContentsURL: absoluteOriginalContentsURL)
        if saveOperation != .autosaveElsewhereOperation, let w = pendingWritten { syncedMarkdown = w }
    }

    // MARK: - ปรับ attribute ของย่อหน้าที่แก้ (ชนิดบล็อกตามตัวอักษรแรก, inline style คงไว้)
    func textStorage(_ textStorage: NSTextStorage, willProcessEditing editedMask: NSTextStorageEditActions,
                     range editedRange: NSRange, changeInLength delta: Int) {
        guard !isReloading, editedMask.contains(.editedCharacters), textStorage.length > 0 else { return }
        textStorage.restyleParagraphs(in: editedRange)
    }

    @objc private func storageDidEdit(_ n: Notification) {
        guard !isReloading else { return }
        saveDebouncer.trigger()
    }

    // MARK: - บันทึก
    /// บันทึกทันทีถ้าเนื้อหาต่างจากที่อยู่ในไฟล์ (ไฟล์มีชื่อ = in-place autosave, ไม่มีชื่อ = ฉบับร่าง)
    func saveNow(completion: ((Bool) -> Void)? = nil) {
        saveDebouncer.cancel()
        // โฟลเดอร์ของไฟล์ถูกลบ/ย้ายไปแล้ว: ไม่พยายามเขียน (กันไดอะล็อก error ค้าง)
        if let u = fileURL, !FileManager.default.fileExists(atPath: u.deletingLastPathComponent().path) { completion?(false); return }
        let md = currentMarkdown
        if md == syncedMarkdown {
            if isDocumentEdited { updateChangeCount(.changeCleared) }
            completion?(true)
            return
        }
        if !isDocumentEdited { updateChangeCount(.changeDone) }
        autosave(withImplicitCancellability: false) { error in completion?(error == nil) }
    }

    override func canClose(withDelegate delegate: Any, shouldClose shouldCloseSelector: Selector?, contextInfo: UnsafeMutableRawPointer?) {
        guard fileURL != nil else {
            saveDebouncer.cancel()
            super.canClose(withDelegate: delegate, shouldClose: shouldCloseSelector, contextInfo: contextInfo)
            return
        }
        saveNow { [self] _ in
            self.superCanClose(delegate, shouldCloseSelector, contextInfo)
        }
    }

    private func superCanClose(_ delegate: Any, _ sel: Selector?, _ ctx: UnsafeMutableRawPointer?) {
        super.canClose(withDelegate: delegate, shouldClose: sel, contextInfo: ctx)
    }

    /// เทสต์อัตโนมัติ (JOTDOWN_TESTING=1): ไม่แสดงไดอะล็อก error แบบ modal (จะค้างทั้งชุดเทสต์) แค่พิมพ์ลง stderr
    override func presentError(_ error: Error) -> Bool {
        if ProcessInfo.processInfo.environment["JOTDOWN_TESTING"] != nil {
            FileHandle.standardError.write(Data("JotdownDocument error (suppressed in tests): \(error)\n".utf8))
            return false
        }
        return super.presentError(error)
    }

    // MARK: - หน้าต่าง
    override func makeWindowControllers() {
        let vc = EditorViewController(document: self)
        let window = NSWindow(contentRect: NSRect(origin: .zero, size: Theme.defaultWindowSize),
                              styleMask: [.titled, .closable, .miniaturizable, .resizable],
                              backing: .buffered, defer: false)
        window.contentViewController = vc
        window.setContentSize(Theme.defaultWindowSize)
        window.contentMinSize = Theme.minWindowSize
        let tb = FormatToolbar(editor: vc)
        vc.toolbarController = tb
        window.toolbar = tb.toolbar
        window.toolbarStyle = .unifiedCompact
        window.isReleasedWhenClosed = false
        let wc = NSWindowController(window: window)
        wc.shouldCascadeWindows = true
        addWindowController(wc)
    }
}
