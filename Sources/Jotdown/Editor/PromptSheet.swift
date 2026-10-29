import AppKit

/// sheet เล็ก ๆ ช่องข้อความเดียว: [ลบ] ……… [ยกเลิก] [ตกลง] (↩ = ตกลง, Esc = ยกเลิก)
final class PromptSheet: NSObject {
    enum Result: Equatable { case ok(String), remove, cancel }

    let window: NSWindow
    let field = NSTextField()
    private var completion: ((Result) -> Void)?
    /// ตรวจข้อความก่อนปิด: คืนข้อความ error (แสดงใต้ช่อง ไม่ปิด sheet) หรือ nil ถ้าใช้ได้
    var validator: ((String) -> String?)?
    private let errorLabel = NSTextField(labelWithString: "")
    private weak var parent: NSWindow?

    init(title: String, message: String, initial: String, placeholder: String = "", removeTitle: String? = nil) {
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 400, height: 140), styleMask: [.titled], backing: .buffered, defer: false)
        super.init()
        window.isReleasedWhenClosed = false
        window.animationBehavior = .none

        let titleLabel = NSTextField(labelWithString: title)
        titleLabel.font = Fonts.heading(.semibold, size: 15)
        let messageLabel = NSTextField(wrappingLabelWithString: message)
        messageLabel.font = Fonts.body(.regular, size: 13)
        messageLabel.textColor = .secondaryLabelColor
        field.stringValue = initial
        field.placeholderString = placeholder
        field.font = Fonts.body(.regular, size: 14)
        // ช่องข้อความ: กรอบเหลืองของแอปแทน focus ring สีน้ำเงินของระบบ
        field.focusRingType = .none
        field.isBezeled = false
        field.drawsBackground = true
        field.backgroundColor = Palette.codeBackground
        field.wantsLayer = true
        field.layer?.cornerRadius = 6
        field.layer?.borderWidth = 1.5
        field.layer?.borderColor = Palette.accent.cgColor
        field.translatesAutoresizingMaskIntoConstraints = false
        field.widthAnchor.constraint(greaterThanOrEqualToConstant: 360).isActive = true

        let ok = NSButton(title: "OK", target: self, action: #selector(okPressed))
        ok.keyEquivalent = "\r"
        ok.bezelColor = Palette.accent
        ok.contentTintColor = Palette.onAccent
        let cancel = NSButton(title: "Cancel", target: self, action: #selector(cancelPressed))
        cancel.keyEquivalent = "\u{1b}"
        let spacer = NSView()
        spacer.setContentHuggingPriority(.init(1), for: .horizontal)
        spacer.setContentCompressionResistancePriority(.init(1), for: .horizontal)
        var buttons: [NSView] = []
        if let removeTitle {
            let rm = NSButton(title: removeTitle, target: self, action: #selector(removePressed))
            buttons.append(rm)
        }
        buttons += [spacer, cancel, ok]
        let row = NSStackView(views: buttons)
        row.orientation = .horizontal
        row.spacing = 8

        let stack = NSStackView(views: [titleLabel, messageLabel, field, row])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 10
        stack.setCustomSpacing(16, after: field)
        stack.edgeInsets = NSEdgeInsets(top: 18, left: 20, bottom: 16, right: 20)
        stack.translatesAutoresizingMaskIntoConstraints = false
        row.translatesAutoresizingMaskIntoConstraints = false
        let content = NSView()
        content.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: content.leadingAnchor), stack.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            stack.topAnchor.constraint(equalTo: content.topAnchor), stack.bottomAnchor.constraint(equalTo: content.bottomAnchor),
            row.widthAnchor.constraint(equalTo: stack.widthAnchor, constant: -40),
            field.widthAnchor.constraint(equalTo: stack.widthAnchor, constant: -40),
        ])
        window.contentView = content
        content.layoutSubtreeIfNeeded()
        window.setContentSize(content.fittingSize)
        window.initialFirstResponder = field
        window.defaultButtonCell = ok.cell as? NSButtonCell
    }

    func present(on parent: NSWindow, completion: @escaping (Result) -> Void) {
        self.parent = parent
        self.completion = completion
        parent.beginSheet(window) { _ in }
        window.makeFirstResponder(field)
    }

    private func finish(_ r: Result) {
        parent?.endSheet(window)
        window.orderOut(nil)
        let c = completion; completion = nil
        c?(r)
    }
    @objc private func okPressed() {
        let text = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        if let msg = validator?(text) { showError(msg); return }
        finish(.ok(text))
    }

    func showError(_ message: String) {
        errorLabel.stringValue = message
        errorLabel.textColor = .systemRed
        errorLabel.font = Fonts.body(.regular, size: 12)
        errorLabel.isHidden = false
        if errorLabel.superview == nil, let stack = window.contentView?.subviews.first as? NSStackView {
            stack.insertArrangedSubview(errorLabel, at: 3)
            stack.setCustomSpacing(4, after: field)
            window.setContentSize(window.contentView!.fittingSize)
        }
    }
    var errorText: String? { errorLabel.isHidden ? nil : errorLabel.stringValue }
    func submitForTesting() { okPressed() }
    @objc private func cancelPressed() { finish(.cancel) }
    @objc private func removePressed() { finish(.remove) }
}
