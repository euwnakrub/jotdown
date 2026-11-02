import AppKit

/// ข้อมูลที่ส่งไป /api/feedback บนเว็บ (Vercel) ซึ่งส่งต่อเป็นอีเมลถึงผู้พัฒนา
struct FeedbackPayload: Codable, Equatable {
    var message: String
    var email: String
    var appVersion: String
    var osVersion: String
    var model: String
}

enum Feedback {
    static let address = "euwnakrub@gmail.com"
    static let maxLength = 10_000

    static var endpoint: URL {
        if let s = ProcessInfo.processInfo.environment["JOTDOWN_FEEDBACK_URL"], let u = URL(string: s) { return u }
        return URL(string: "https://jotdown-app.vercel.app/api/feedback")!
    }

    /// ข้อความ error (แสดงในหน้าต่าง) หรือ nil ถ้าส่งได้
    static func validate(message: String, email: String) -> String? {
        let m = message.trimmingCharacters(in: .whitespacesAndNewlines)
        if m.isEmpty { return "Please write a message first." }
        if m.count > maxLength { return "Your message is too long (at most \(maxLength) characters)." }
        let e = email.trimmingCharacters(in: .whitespaces)
        if !e.isEmpty, e.range(of: #"^[^@\s]+@[^@\s]+\.[^@\s]+$"#, options: .regularExpression) == nil {
            return "That email address doesn't look right."
        }
        return nil
    }

    static func makePayload(message: String, email: String) -> FeedbackPayload {
        let info = Bundle.main.infoDictionary
        let v = info?["CFBundleShortVersionString"] as? String ?? "dev"
        let os = ProcessInfo.processInfo.operatingSystemVersion
        return FeedbackPayload(message: message.trimmingCharacters(in: .whitespacesAndNewlines),
                               email: email.trimmingCharacters(in: .whitespaces),
                               appVersion: v,
                               osVersion: "\(os.majorVersion).\(os.minorVersion).\(os.patchVersion)",
                               model: hardwareModel())
    }

    static func hardwareModel() -> String {
        var size = 0
        sysctlbyname("hw.model", nil, &size, nil, 0)
        guard size > 0 else { return "Mac" }
        var buf = [CChar](repeating: 0, count: size)
        sysctlbyname("hw.model", &buf, &size, nil, 0)
        return String(cString: buf)
    }

    static func request(for p: FeedbackPayload) throws -> URLRequest {
        var r = URLRequest(url: endpoint, timeoutInterval: 20)
        r.httpMethod = "POST"
        r.setValue("application/json", forHTTPHeaderField: "Content-Type")
        r.setValue("mac", forHTTPHeaderField: "X-Jotdown-Client")
        r.httpBody = try JSONEncoder().encode(p)
        return r
    }

    struct SendError: LocalizedError {
        let status: Int
        var errorDescription: String? { "The feedback server returned an error (\(status))." }
    }

    static func send(_ p: FeedbackPayload, session: URLSession = .shared) async throws {
        let (_, resp) = try await session.data(for: request(for: p))
        let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(code) else { throw SendError(status: code) }
    }

    /// สำรองเมื่อส่งผ่านเว็บไม่ได้: เปิดแอปอีเมลพร้อมข้อความ
    static func mailtoURL(for p: FeedbackPayload) -> URL {
        var c = URLComponents()
        c.scheme = "mailto"
        c.path = address
        let body = "\(p.message)\n\n—\nJotdown \(p.appVersion) · macOS \(p.osVersion) · \(p.model)"
        c.queryItems = [URLQueryItem(name: "subject", value: "Jotdown feedback (\(p.appVersion))"),
                        URLQueryItem(name: "body", value: body)]
        // URLComponents ไม่ encode "+" ซึ่งแอปอีเมลบางตัวอ่านเป็นช่องว่าง
        c.percentEncodedQuery = c.percentEncodedQuery?.replacingOccurrences(of: "+", with: "%2B")
        return c.url!
    }
}

/// หน้าต่าง Help → Send Feedback…
@MainActor
final class FeedbackWindowController: NSWindowController, NSWindowDelegate {
    private static var current: FeedbackWindowController?

    let textView = NSTextView()
    let emailField = NSTextField()
    let sendButton = NSButton(title: "Send", target: nil, action: nil)
    private let cancelButton = NSButton(title: "Cancel", target: nil, action: nil)
    private let spinner = NSProgressIndicator()
    let errorLabel = NSTextField(labelWithString: "")
    var session: URLSession = .shared

    static func show() {
        if let c = current { c.window?.makeKeyAndOrderFront(nil); return }
        let c = FeedbackWindowController()
        current = c
        c.window?.center()
        c.showWindow(nil)
        c.window?.makeFirstResponder(c.textView)
    }

    init() {
        let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 480, height: 360), styleMask: [.titled, .closable], backing: .buffered, defer: false)
        w.title = "Send Feedback"
        w.isReleasedWhenClosed = false
        super.init(window: w)
        w.delegate = self
        build()
    }
    required init?(coder: NSCoder) { fatalError() }

    private func styleBox(_ v: NSView) {
        v.wantsLayer = true
        v.layer?.cornerRadius = 6
        v.layer?.borderWidth = 1.5
        v.layer?.borderColor = Palette.accent.cgColor
    }

    private func build() {
        guard let window else { return }
        let title = NSTextField(labelWithString: "Send Feedback")
        title.font = Fonts.heading(.semibold, size: 15)
        let intro = NSTextField(wrappingLabelWithString: "Tell us what you like, what's broken or what you'd like to see. Your message goes straight to the developer.")
        intro.font = Fonts.body(.regular, size: 13)
        intro.textColor = .secondaryLabelColor

        let scroll = NSScrollView()
        scroll.hasVerticalScroller = true
        scroll.drawsBackground = false
        // กรอบเหลืองแบบเดียวกับช่องอีเมล (เส้นขอบของ layer บน scroll view ถูก clip view ทับ จึงใช้ NSBox ห่อ)
        let box = NSBox()
        box.boxType = .custom
        box.borderColor = Palette.accent
        box.fillColor = Palette.codeBackground
        box.borderWidth = 1.5
        box.cornerRadius = 6
        box.contentViewMargins = NSSize(width: 2, height: 2)
        box.contentView = scroll
        textView.isRichText = false
        textView.allowsUndo = true
        textView.font = Fonts.body(.regular, size: 14)
        textView.drawsBackground = false
        textView.textContainerInset = NSSize(width: 6, height: 8)
        textView.isVerticallyResizable = true
        textView.autoresizingMask = [.width]
        textView.textContainer?.widthTracksTextView = true
        textView.isAutomaticQuoteSubstitutionEnabled = false
        scroll.documentView = textView

        let emailLabel = NSTextField(labelWithString: "Your email (optional, if you'd like a reply)")
        emailLabel.font = Fonts.body(.regular, size: 12)
        emailLabel.textColor = .secondaryLabelColor
        emailField.placeholderString = "you@example.com"
        emailField.font = Fonts.body(.regular, size: 14)
        emailField.focusRingType = .none
        emailField.isBezeled = false
        emailField.drawsBackground = true
        emailField.backgroundColor = Palette.codeBackground
        styleBox(emailField)

        let note = NSTextField(wrappingLabelWithString: "Your Jotdown version, macOS version and Mac model are included to help fix problems. Your notes are never sent.")
        note.font = Fonts.body(.regular, size: 11)
        note.textColor = .tertiaryLabelColor

        errorLabel.font = Fonts.body(.regular, size: 12)
        errorLabel.textColor = .systemRed
        errorLabel.isHidden = true

        sendButton.target = self
        sendButton.action = #selector(sendPressed)
        sendButton.keyEquivalent = "\r"
        sendButton.keyEquivalentModifierMask = [.command]
        sendButton.bezelColor = Palette.accent
        sendButton.contentTintColor = Palette.onAccent
        sendButton.toolTip = "Send (⌘↩)"
        cancelButton.target = self
        cancelButton.action = #selector(cancelPressed)
        cancelButton.keyEquivalent = "\u{1b}"
        spinner.style = .spinning
        spinner.controlSize = .small
        spinner.isDisplayedWhenStopped = false
        let spacer = NSView()
        spacer.setContentHuggingPriority(.init(1), for: .horizontal)
        let row = NSStackView(views: [spinner, spacer, cancelButton, sendButton])
        row.orientation = .horizontal
        row.spacing = 8

        let stack = NSStackView(views: [title, intro, box, emailLabel, emailField, note, errorLabel, row])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 10
        stack.setCustomSpacing(14, after: box)
        stack.setCustomSpacing(4, after: emailLabel)
        stack.setCustomSpacing(16, after: errorLabel)
        stack.edgeInsets = NSEdgeInsets(top: 18, left: 20, bottom: 16, right: 20)
        stack.translatesAutoresizingMaskIntoConstraints = false
        let content = NSView()
        content.addSubview(stack)
        for v in [box, emailField, row, intro, note] as [NSView] {
            v.translatesAutoresizingMaskIntoConstraints = false
            v.widthAnchor.constraint(equalTo: stack.widthAnchor, constant: -40).isActive = true
        }
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: content.leadingAnchor), stack.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            stack.topAnchor.constraint(equalTo: content.topAnchor), stack.bottomAnchor.constraint(equalTo: content.bottomAnchor),
            stack.widthAnchor.constraint(equalToConstant: 480),
            box.heightAnchor.constraint(equalToConstant: 150),
            emailField.heightAnchor.constraint(equalToConstant: 26),
        ])
        window.contentView = content
        content.layoutSubtreeIfNeeded()
        window.setContentSize(content.fittingSize)
        window.defaultButtonCell = sendButton.cell as? NSButtonCell
    }

    private func setBusy(_ busy: Bool) {
        sendButton.isEnabled = !busy
        textView.isEditable = !busy
        emailField.isEnabled = !busy
        busy ? spinner.startAnimation(nil) : spinner.stopAnimation(nil)
    }

    func showError(_ msg: String?) {
        errorLabel.stringValue = msg ?? ""
        errorLabel.isHidden = msg == nil
    }

    @objc func sendPressed() {
        if let msg = Feedback.validate(message: textView.string, email: emailField.stringValue) { showError(msg); return }
        showError(nil)
        let payload = Feedback.makePayload(message: textView.string, email: emailField.stringValue)
        setBusy(true)
        Task { @MainActor in
            do {
                try await Feedback.send(payload, session: session)
                setBusy(false)
                close()
                let a = NSAlert()
                a.messageText = "Thanks for your feedback!"
                a.informativeText = "Your message was sent to the developer."
                a.runModal()
            } catch {
                setBusy(false)
                let a = NSAlert()
                a.messageText = "Couldn't send your feedback"
                a.informativeText = "\(error.localizedDescription)\n\nYou can send it by email instead. Your message will be filled in for you."
                a.addButton(withTitle: "Send by Email…")
                a.addButton(withTitle: "Cancel")
                if a.runModal() == .alertFirstButtonReturn {
                    NSWorkspace.shared.open(Feedback.mailtoURL(for: payload))
                    close()
                }
            }
        }
    }

    @objc private func cancelPressed() { close() }

    func windowWillClose(_ notification: Notification) {
        if Self.current === self { Self.current = nil }
    }
}
