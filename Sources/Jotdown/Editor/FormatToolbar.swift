import AppKit

/// แถบปุ่มจัดรูปแบบบนหัวหน้าต่าง: ปุ่มทุกปุ่มส่ง action เดียวกับเมนู Format ไปยัง text view
/// และอ่านสถานะ (ติ๊ก/disabled) จาก `validateMenuItem` ของ text view (logic เดียวกับเมนู)
final class FormatToolbar: NSObject, NSToolbarDelegate {
    struct Tool {
        var id: String
        var tip: String           // tooltip (อังกฤษ + คีย์ลัด)
        var label: String
        var action: Selector
        var tag = 0
        /// ไอคอนมาจากตารางกลาง `MenuIcons` (ตัวเดียวกับเมนู)
        var symbol: String { MenuIcons.name(for: action, tag: tag) ?? "questionmark" }
    }

    static let textStyleID = NSToolbarItem.Identifier("jotdown.textStyle")
    static let groups: [(id: String, label: String, tools: [Tool])] = [
        ("jotdown.inline", "Inline", [
            Tool(id: "bold", tip: "Bold (⌘B)", label: "Bold", action: #selector(EditorTextView.jotToggleBold(_:))),
            Tool(id: "italic", tip: "Italic (⌘I)", label: "Italic", action: #selector(EditorTextView.jotToggleItalic(_:))),
        ]),
        ("jotdown.inline2", "Inline", [
            Tool(id: "strike", tip: "Strikethrough (⇧⌘X)", label: "Strikethrough", action: #selector(EditorTextView.jotToggleStrike(_:))),
            Tool(id: "code", tip: "Inline Code (⌘E)", label: "Inline Code", action: #selector(EditorTextView.jotToggleCode(_:))),
            Tool(id: "link", tip: "Link… (⌘K)", label: "Link", action: #selector(EditorTextView.jotEditLink(_:))),
        ]),
        ("jotdown.lists", "Lists", [
            Tool(id: "bullet", tip: "Bulleted List (⇧⌘8)", label: "Bulleted List", action: #selector(EditorTextView.jotToggleBullet(_:))),
            Tool(id: "ordered", tip: "Numbered List (⇧⌘7)", label: "Numbered List", action: #selector(EditorTextView.jotToggleOrdered(_:))),
            Tool(id: "task", tip: "Checklist (⇧⌘9)", label: "Checklist", action: #selector(EditorTextView.jotToggleTask(_:))),
        ]),
        ("jotdown.blocks", "Blocks", [
            Tool(id: "quote", tip: "Quote (⇧⌘.)", label: "Quote", action: #selector(EditorTextView.jotToggleQuote(_:))),
            Tool(id: "codeblock", tip: "Code Block (⌥⌘C)", label: "Code Block", action: #selector(EditorTextView.jotToggleCodeBlock(_:))),
            Tool(id: "table", tip: "Insert Table (⌃⌘T)", label: "Table", action: #selector(EditorTextView.jotInsertTable(_:))),
            Tool(id: "video", tip: "Insert YouTube Video… (⌃⌘Y)", label: "YouTube Video", action: #selector(EditorTextView.jotInsertVideo(_:))),
            Tool(id: "image", tip: "Insert Image… (⇧⌘I)", label: "Image", action: #selector(EditorTextView.jotInsertImage(_:))),
        ]),
    ]
    static let styleNames = ["Body", "Heading 1", "Heading 2", "Heading 3", "Heading 4", "Heading 5", "Heading 6"]

    let toolbar: NSToolbar
    weak var editor: EditorViewController?
    private var groupViews: [String: ToolGroupView] = [:]
    private var styleItem: NSMenuToolbarItem?

    init(editor: EditorViewController) {
        self.editor = editor
        toolbar = NSToolbar(identifier: "JotdownFormatToolbar")
        super.init()
        toolbar.delegate = self
        toolbar.displayMode = .iconOnly
        toolbar.allowsUserCustomization = true
        toolbar.autosavesConfiguration = true
    }

    // MARK: - NSToolbarDelegate
    func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        [Self.textStyleID, .space] + Self.groups.flatMap { [NSToolbarItem.Identifier($0.id), .space] }.dropLast()
    }
    func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        toolbarDefaultItemIdentifiers(toolbar) + [.flexibleSpace]
    }

    func toolbar(_ toolbar: NSToolbar, itemForItemIdentifier itemIdentifier: NSToolbarItem.Identifier, willBeInsertedIntoToolbar flag: Bool) -> NSToolbarItem? {
        if itemIdentifier == Self.textStyleID {
            let item = NSMenuToolbarItem(itemIdentifier: itemIdentifier)
            let menu = NSMenu()
            for (i, name) in Self.styleNames.enumerated() {
                let m = NSMenuItem(title: name, action: i == 0 ? #selector(EditorTextView.jotSetParagraph(_:)) : #selector(EditorTextView.jotSetHeading(_:)), keyEquivalent: "")
                m.tag = i
                m.target = self
                m.action = #selector(styleChosen(_:))
                m.image = NSImage(systemSymbolName: i == 0 ? MenuIcons.name(for: #selector(EditorTextView.jotSetParagraph(_:)))! : MenuIcons.headingSymbol(i), accessibilityDescription: name)
                menu.addItem(m)
            }
            item.menu = menu
            item.title = "Body"
            item.label = "Body"
            item.visibilityPriority = .high
            item.paletteLabel = "Text Style"
            item.toolTip = "Text Style"
            item.showsIndicator = true
            let rep = NSMenuItem(title: "Text Style", action: nil, keyEquivalent: "")
            rep.submenu = menu.copy() as? NSMenu
            item.menuFormRepresentation = rep
            styleItem = item
            return item
        }
        guard let g = Self.groups.first(where: { $0.id == itemIdentifier.rawValue }) else { return nil }
        let item = NSToolbarItem(itemIdentifier: itemIdentifier)
        let view = ToolGroupView(tools: g.tools, target: self, action: #selector(toolClicked(_:)))
        item.view = view
        item.label = g.label
        item.paletteLabel = g.label
        item.visibilityPriority = g.id.hasPrefix("jotdown.inline") ? .high : (g.id == "jotdown.lists" ? .standard : .low)
        // overflow (») : เมนูที่มีรายการของกลุ่ม
        let overflow = NSMenuItem(title: g.label, action: nil, keyEquivalent: "")
        let sub = NSMenu(title: g.label)
        for t in g.tools {
            let m = NSMenuItem(title: t.label, action: #selector(menuToolChosen(_:)), keyEquivalent: "")
            m.target = self
            m.representedObject = t.id
            m.image = NSImage(systemSymbolName: t.symbol, accessibilityDescription: t.label)
            sub.addItem(m)
        }
        overflow.submenu = sub
        item.menuFormRepresentation = overflow
        groupViews[g.id] = view
        return item
    }

    @objc func toolClicked(_ sender: ToolButton) {
        guard let t = Self.groups.flatMap(\.tools).first(where: { $0.id == sender.toolID }) else { return }
        send(t.action)
    }

    // MARK: - actions
    private var textView: EditorTextView? { editor?.textView }

    private func send(_ action: Selector, tag: Int = 0) {
        guard let tv = textView, let window = tv.window else { return }
        window.makeFirstResponder(tv)         // ไม่ขโมยโฟกัส
        let item = NSMenuItem(title: "", action: action, keyEquivalent: "")
        item.tag = tag
        if !tv.tryToPerform(action, with: item) { NSApp.sendAction(action, to: nil, from: item) }
        window.makeFirstResponder(tv)
        update()
    }

    @objc func menuToolChosen(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? String, let t = Self.groups.flatMap(\.tools).first(where: { $0.id == id }) else { return }
        send(t.action)
    }

    @objc func styleChosen(_ sender: NSMenuItem) {
        if sender.tag == 0 { send(#selector(EditorTextView.jotSetParagraph(_:))) }
        else {
            // jotSetHeading สลับกลับเป็นย่อหน้าถ้าเป็นหัวข้อนั้นอยู่แล้ว: เลือกหัวข้อเดิมซ้ำ = คงเดิม
            if case .heading(sender.tag)? = textView.map({ $0.blockKindAtCaret }) { return }
            send(#selector(EditorTextView.jotSetHeading(_:)), tag: sender.tag)
        }
    }

    // MARK: - สถานะตามเคอร์เซอร์

    /// อ่านสถานะจาก `validateMenuItem` ของ text view (logic เดียวกับเมนู Format) — เบา: ดูเฉพาะที่เคอร์เซอร์/การเลือก
    func update() {
        guard let tv = textView else { return }
        for g in Self.groups {
            guard let view = groupViews[g.id] else { continue }
            for (i, t) in g.tools.enumerated() {
                let probe = NSMenuItem(title: "", action: t.action, keyEquivalent: "")
                let enabled = tv.validateMenuItem(probe)
                view.buttons[i].isEnabled = enabled
                view.buttons[i].active = enabled && probe.state == .on
            }
        }
        let name = Self.shortStyleName(for: tv.blockKindAtCaret)
        styleItem?.title = name
        styleItem?.label = name
        styleItem?.toolTip = "Text Style: " + Self.styleName(for: tv.blockKindAtCaret)
    }

    static func shortStyleName(for kind: BlockKind) -> String {
        if case .heading(let l) = kind { return "H\(l)" }
        return "Body"
    }

    static func styleName(for kind: BlockKind) -> String {
        if case .heading(let l) = kind { return "Heading \(l)" }
        return "Body"
    }
}


/// ปุ่มในแถบ: สถานะใช้งาน = พื้นเหลือง accent อยู่ในแคปซูลของกลุ่ม (inset 3pt จากขอบแคปซูล มุมมนเป็นแคปซูล) ไอคอนสีเข้ม; hover = พื้นจาง
/// ความสูงปุ่ม = ความสูงแคปซูลที่ระบบวาดให้ (วัดแล้ว: แคปซูลเท่ากรอบ view ของกลุ่ม)
final class ToolButton: NSButton {
    static let capsuleInsetY: CGFloat = 3
    static let capsuleInsetX: CGFloat = 1.5
    var toolID = ""
    var active = false { didSet { if active != oldValue { refresh() } } }
    private var hovering = false { didSet { refresh() } }
    private let symbol: String
    private let label: String

    init(tool: FormatToolbar.Tool, target: AnyObject, action: Selector) {
        symbol = tool.symbol; label = tool.label
        super.init(frame: NSRect(x: 0, y: 0, width: 34, height: 24))
        toolID = tool.id
        self.target = target
        self.action = action
        isBordered = false
        imagePosition = .imageOnly
        toolTip = tool.tip
        setButtonType(.momentaryChange)
        translatesAutoresizingMaskIntoConstraints = false
        widthAnchor.constraint(equalToConstant: 34).isActive = true
        heightAnchor.constraint(equalToConstant: 24).isActive = true
        setAccessibilityLabel(label)
        refresh()
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) not supported") }

    override var isEnabled: Bool { didSet { if isEnabled != oldValue { refresh() } } }
    override func viewDidChangeEffectiveAppearance() { super.viewDidChangeEffectiveAppearance(); refresh() }

    /// พื้นที่ระบายสีเมื่อใช้งาน/ชี้
    var highlightRect: NSRect { bounds.insetBy(dx: Self.capsuleInsetX, dy: Self.capsuleInsetY) }
    var highlightFill: NSColor? {
        active ? Palette.accent : (hovering && isEnabled ? NSColor.labelColor.withAlphaComponent(0.10) : nil)
    }

    func refresh() {
        let base = NSImage(systemSymbolName: symbol, accessibilityDescription: label)
        let size = NSImage.SymbolConfiguration(pointSize: 14, weight: .regular)
        if active {
            image = base?.withSymbolConfiguration(size.applying(NSImage.SymbolConfiguration(paletteColors: [Palette.onAccent])))
            contentTintColor = nil
        } else {
            image = base?.withSymbolConfiguration(size)
            contentTintColor = isEnabled ? NSColor.labelColor : NSColor.tertiaryLabelColor
        }
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        if let fill = highlightFill {
            let r = highlightRect
            fill.setFill()
            NSBezierPath(roundedRect: r, xRadius: r.height / 2, yRadius: r.height / 2).fill()
        }
        super.draw(dirtyRect)
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeInKeyWindow], owner: self, userInfo: nil))
    }
    override func mouseEntered(with event: NSEvent) { hovering = true }
    override func mouseExited(with event: NSEvent) { hovering = false }
    override var acceptsFirstResponder: Bool { false }       // ไม่ขโมยโฟกัสจาก text view
    override var focusRingType: NSFocusRingType { get { .none } set {} }
}

/// กลุ่มปุ่มติดกันในแคปซูลเดียวของ toolbar
final class ToolGroupView: NSStackView {
    let buttons: [ToolButton]
    init(tools: [FormatToolbar.Tool], target: AnyObject, action: Selector) {
        buttons = tools.map { ToolButton(tool: $0, target: target, action: action) }
        super.init(frame: .zero)
        orientation = .horizontal
        spacing = 2
        edgeInsets = NSEdgeInsets(top: 0, left: 3, bottom: 0, right: 3)
        alignment = .centerY
        buttons.forEach(addArrangedSubview)
        translatesAutoresizingMaskIntoConstraints = false
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) not supported") }

    /// ความสูงของแคปซูลที่ระบบวาดให้กลุ่ม (วัดจาก view ที่หุ้มเราอยู่ ไม่เดา)
    var capsuleHeight: CGFloat { superview?.bounds.height ?? bounds.height }

    override func layout() {
        super.layout()
        if ProcessInfo.processInfo.environment["JOTDOWN_DEBUG_TB"] != nil {
            var v: NSView? = self; var out = ""
            while let x = v { out += "\(type(of: x)) frame=\(x.frame) bounds=\(x.bounds)\n"; v = x.superview; if out.count > 4000 { break } }
            try? out.write(toFile: "/tmp/jd/tbframes.txt", atomically: true, encoding: .utf8)
        }
        buttons.forEach { $0.needsDisplay = true }
    }
}
