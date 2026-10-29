import AppKit

final class EditorViewController: NSViewController, NSTextViewDelegate {
    let document: JotdownDocument
    private(set) var scrollView = NSScrollView()
    private(set) var textView: EditorTextView!
    var toolbarController: FormatToolbar?
    var linkBar: LinkBarController?
    private var savedSelection = NSRange(location: 0, length: 0)
    private var savedScrollY: CGFloat = 0

    init(document: JotdownDocument) {
        self.document = document
        super.init(nibName: nil, bundle: nil)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) not supported") }

    override func loadView() {
        Fonts.registerAll()
        textView = EditorTextView.make(storage: document.textStorage)
        textView.delegate = self
        textView.imageBaseProvider = { [weak self] in self?.document.imageBaseDirectory }
        textView.linkBaseProvider = { [weak self] in self?.document.fileURL?.deletingLastPathComponent() }
        scrollView.documentView = textView
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.borderType = .noBorder
        scrollView.drawsBackground = true
        scrollView.backgroundColor = Palette.paper
        scrollView.frame = NSRect(origin: .zero, size: Theme.defaultWindowSize)
        view = scrollView
        linkBar = LinkBarController(editor: self)

        let nc = NotificationCenter.default
        nc.addObserver(self, selector: #selector(imagesLoaded), name: .jotImageLoaded, object: nil)
        nc.addObserver(self, selector: #selector(willReload), name: .jotDocumentWillReload, object: document)
        nc.addObserver(self, selector: #selector(didReload), name: .jotDocumentDidReload, object: document)
    }

    deinit { NotificationCenter.default.removeObserver(self) }

    override func viewDidAppear() {
        super.viewDidAppear()
        view.window?.makeFirstResponder(textView)
        textView.syncTypingAttributes()
        textView.refreshWikiLinks()
        toolbarController?.update()
        DispatchQueue.main.async { [weak self] in self?.toolbarController?.update() }
    }

    // ใช้ undo manager ของเอกสาร ให้สถานะ "แก้ไขแล้ว" ตรงกับการพิมพ์
    func undoManager(for view: NSTextView) -> UndoManager? { document.undoManager }

    func textViewDidChangeSelection(_ notification: Notification) {
        textView.syncTypingAttributes()
        toolbarController?.update()
        linkBar?.caretChanged()
    }

    func textDidChange(_ notification: Notification) { linkBar?.textChanged() }

    @objc private func imagesLoaded() { textView.refreshImages() }

    // MARK: - โหลดใหม่จากไฟล์ที่ถูกแก้ภายนอก: คงตำแหน่งเคอร์เซอร์/scroll
    @objc private func willReload() {
        guard isViewLoaded else { return }
        savedSelection = textView.selectedRange()
        savedScrollY = scrollView.contentView.bounds.origin.y
    }

    @objc private func didReload() {
        guard isViewLoaded else { return }
        let len = document.textStorage.length
        let loc = min(savedSelection.location, len)
        textView.setSelectedRange(NSRange(location: loc, length: min(savedSelection.length, len - loc)))
        textView.syncTypingAttributes()
        textView.layoutManager?.ensureLayout(for: textView.textContainer!)
        scrollView.contentView.scroll(to: NSPoint(x: 0, y: max(0, savedScrollY)))
        scrollView.reflectScrolledClipView(scrollView.contentView)
    }
}
