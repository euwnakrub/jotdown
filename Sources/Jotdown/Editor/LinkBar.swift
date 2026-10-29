import AppKit

/// แถบลิงก์ลอย (แบบ Notion): ไอคอน + URL ย่อ + Open / Copy / Edit / Remove
final class LinkBarView: NSView {
    struct Actions {
        var open: () -> Void = {}
        var copy: () -> Void = {}
        var edit: () -> Void = {}
        var remove: () -> Void = {}
    }

    let url: String
    var actions: Actions
    private let icon = NSImageView()
    private let urlButton = NSButton()
    private(set) var buttons: [NSButton] = []
    var onMouse: ((Bool) -> Void)?
    private var flashTimer: Timer?

    static let height: CGFloat = 32

    init(url: String, actions: Actions = Actions()) {
        self.url = url
        self.actions = actions
        super.init(frame: .zero)
        wantsLayer = true
        layer?.cornerRadius = 10
        layer?.cornerCurve = .continuous
        layer?.borderWidth = 0.5

        icon.image = NSImage(systemSymbolName: LinkResolver.symbol(for: url), accessibilityDescription: nil)?
            .withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: 13, weight: .regular))
        icon.contentTintColor = Palette.secondaryText
        icon.setContentHuggingPriority(.required, for: .horizontal)

        urlButton.isBordered = false
        urlButton.alignment = .left
        urlButton.lineBreakMode = .byTruncatingMiddle
        urlButton.target = self
        urlButton.action = #selector(openClicked)
        urlButton.toolTip = url
        urlButton.focusRingType = .none
        setURLText(LinkResolver.display(url), color: Palette.link)
        urlButton.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        let specs: [(String, String, Selector)] = [
            ("arrow.up.right.square", "Open Link (⌥↩)", #selector(openClicked)),
            ("doc.on.doc", "Copy Link Address", #selector(copyClicked)),
            ("pencil", "Edit Link… (⌘K)", #selector(editClicked)),
            ("trash", "Remove Link", #selector(removeClicked)),
        ]
        buttons = specs.map { sym, tip, sel in
            let b = NSButton()
            b.image = NSImage(systemSymbolName: sym, accessibilityDescription: tip)?.withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: 13, weight: .regular))
            b.isBordered = false
            b.imagePosition = .imageOnly
            b.toolTip = tip
            b.target = self; b.action = sel
            b.contentTintColor = Palette.text
            b.focusRingType = .none
            b.translatesAutoresizingMaskIntoConstraints = false
            b.widthAnchor.constraint(equalToConstant: 26).isActive = true
            b.heightAnchor.constraint(equalToConstant: 24).isActive = true
            b.setAccessibilityLabel(tip)
            return b
        }
        let stack = NSStackView(views: [icon, urlButton] + buttons)
        stack.orientation = .horizontal
        stack.spacing = 6
        stack.setCustomSpacing(10, after: urlButton)
        stack.edgeInsets = NSEdgeInsets(top: 4, left: 10, bottom: 4, right: 6)
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor), stack.trailingAnchor.constraint(equalTo: trailingAnchor),
            stack.topAnchor.constraint(equalTo: topAnchor), stack.bottomAnchor.constraint(equalTo: bottomAnchor),
            urlButton.widthAnchor.constraint(lessThanOrEqualToConstant: 260),
            heightAnchor.constraint(equalToConstant: Self.height),
        ])
        updateColors()
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) not supported") }

    private func setURLText(_ s: String, color: NSColor) {
        urlButton.attributedTitle = NSAttributedString(string: s, attributes: [.font: Fonts.body(.regular, size: 13), .foregroundColor: color])
    }

    /// ข้อความเตือนสั้น ๆ แทน URL ชั่วคราว (เช่น "File not found")
    func flash(_ message: String) {
        setURLText(message, color: Palette.secondaryText)
        flashTimer?.invalidate()
        flashTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: false) { [weak self] _ in
            guard let self else { return }
            self.setURLText(LinkResolver.display(self.url), color: Palette.link)
        }
    }

    var displayedText: String { urlButton.attributedTitle.string }

    override func viewDidChangeEffectiveAppearance() { super.viewDidChangeEffectiveAppearance(); updateColors() }
    private func updateColors() {
        effectiveAppearance.performAsCurrentDrawingAppearance {
            layer?.backgroundColor = Palette.paper.cgColor
            layer?.borderColor = Palette.tableBorder.cgColor
        }
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self, userInfo: nil))
    }
    override func mouseEntered(with event: NSEvent) { onMouse?(true) }
    override func mouseExited(with event: NSEvent) { onMouse?(false) }

    @objc private func openClicked() { actions.open() }
    @objc private func copyClicked() { actions.copy() }
    @objc private func editClicked() { actions.edit() }
    @objc private func removeClicked() { actions.remove() }
}

final class LinkBarPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

/// ควบคุมการแสดง/ซ่อนแถบ: เมาส์ชี้ลิงก์ ~0.4 วิ หรือเคอร์เซอร์อยู่ในลิงก์ (ไม่ขโมยโฟกัส)
final class LinkBarController: NSObject {
    private weak var editor: EditorViewController?
    private(set) var state = LinkBarState()
    private var panel: LinkBarPanel?
    private var bar: LinkBarView?
    private var shownHit: LinkHit?
    private var timer: Timer?
    private let epoch = Date()
    private var now: TimeInterval { Date().timeIntervalSince(epoch) }

    init(editor: EditorViewController) {
        self.editor = editor
        super.init()
        let tv = editor.textView!
        tv.onLinkHover = { [weak self] hit in self?.state.mouseOver(hit, at: self?.now ?? 0); self?.evaluate() }
        tv.onLinkNotice = { [weak self] m in self?.bar?.flash(m) }
        let nc = NotificationCenter.default
        nc.addObserver(self, selector: #selector(scrolled), name: NSView.boundsDidChangeNotification, object: editor.scrollView.contentView)
        editor.scrollView.contentView.postsBoundsChangedNotifications = true
        nc.addObserver(self, selector: #selector(resigned), name: NSWindow.didResignKeyNotification, object: nil)
        timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in self?.evaluate() }
        RunLoop.main.add(timer!, forMode: .common)
    }

    deinit { timer?.invalidate(); NotificationCenter.default.removeObserver(self); hide() }

    // เหตุการณ์จาก editor
    func caretChanged() { state.caretMoved(editor?.textView.linkHitAtSelection()); evaluate() }
    func textChanged() { state.invalidate(); evaluate() }
    @objc private func scrolled() { state.invalidate(); evaluate() }
    @objc private func resigned(_ n: Notification) {
        if let w = n.object as? NSWindow, w === editor?.view.window { state.windowResigned(); evaluate() }
    }

    func evaluate() {
        let hit = state.visible(at: now)
        if hit == shownHit, hit == nil || panel?.isVisible == true { return }
        if let hit { show(hit) } else { hide() }
    }

    private func show(_ hit: LinkHit) {
        guard let editor, let tv = editor.textView, let window = tv.window, window.isKeyWindow, let rect = tv.linkRect(hit) else { hide(); return }
        hide()
        shownHit = hit
        let actions = LinkBarView.Actions(
            open: { [weak self] in
                guard let self, let tv = self.editor?.textView else { return }
                switch tv.openLink(hit.url) { case .opened: break; case .failed: NSSound.beep(); case .notice(let m): self.bar?.flash(m) }
            },
            copy: { NSPasteboard.general.clearContents(); NSPasteboard.general.setString(hit.url, forType: .string) },
            edit: { [weak self] in
                guard let self, let tv = self.editor?.textView else { return }
                self.hide(); self.state.invalidate()
                tv.window?.makeFirstResponder(tv)
                tv.setSelectedRange(NSRange(location: hit.range.location + min(1, hit.range.length), length: 0))
                tv.jotEditLink(nil)
            },
            remove: { [weak self] in
                guard let self, let tv = self.editor?.textView else { return }
                tv.applyLink(nil, in: hit.range)
                self.state.invalidate(); self.hide()
            })
        let bar = LinkBarView(url: hit.url, actions: actions)
        bar.appearance = window.effectiveAppearance
        bar.onMouse = { [weak self] inside in self?.state.panelMouse(inside: inside, at: self?.now ?? 0) }
        let size = NSSize(width: max(bar.fittingSize.width, 220), height: LinkBarView.height)
        bar.frame = NSRect(origin: .zero, size: size)
        bar.layoutSubtreeIfNeeded()

        // ใต้ลิงก์ ถ้าไม่พอแสดงเหนือลิงก์ (ไม่บังข้อความที่พิมพ์)
        let vis = tv.visibleRect
        var x = min(max(rect.minX, vis.minX + 4), max(vis.maxX - size.width - 4, vis.minX + 4))
        let below = NSRect(x: x, y: rect.maxY + 4, width: size.width, height: size.height)
        let above = NSRect(x: x, y: rect.minY - 4 - size.height, width: size.width, height: size.height)
        let placed = below.maxY <= vis.maxY ? below : (above.minY >= vis.minY ? above : below)
        x = placed.minX
        let screenRect = window.convertToScreen(tv.convert(placed, to: nil))

        let p = LinkBarPanel(contentRect: screenRect, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        p.isReleasedWhenClosed = false
        p.hasShadow = true
        p.backgroundColor = .clear
        p.isOpaque = false
        p.animationBehavior = .none
        p.becomesKeyOnlyIfNeeded = true
        p.hidesOnDeactivate = true
        p.contentView = bar
        p.setFrame(screenRect, display: false)
        window.addChildWindow(p, ordered: .above)
        p.orderFront(nil)
        panel = p; self.bar = bar
    }

    func hide() {
        if let p = panel { p.parent?.removeChildWindow(p); p.orderOut(nil) }
        panel = nil; bar = nil; shownHit = nil
    }

    var isShowing: Bool { panel?.isVisible == true }
}
