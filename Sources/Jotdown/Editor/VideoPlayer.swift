import AppKit
import WebKit

/// ผู้เล่นในหน้า: สร้างเฉพาะตอนกดเล่น วางทับส่วนภาพ 16:9 ของการ์ด (subview ของ text view จึงเลื่อนตามเนื้อหา)
final class VideoPlayerView: NSView, WKScriptMessageHandler, WKNavigationDelegate {
    /// เทสต์ปิดการโหลดเว็บ (swift test โหลดเว็บไม่ได้)
    nonisolated(unsafe) static var loadsContent = true

    let ref: VideoRef
    let yt: YouTubeRef
    var webView: WKWebView?
    private let closeButton = NSButton()
    private let errorLabel = NSTextField(labelWithString: "")
    private let openButton = NSButton()
    var onClose: (() -> Void)?
    private(set) var errorMessage: String?

    init(ref: VideoRef, yt: YouTubeRef) {
        self.ref = ref; self.yt = yt
        super.init(frame: .zero)
        wantsLayer = true
        layer?.cornerRadius = 10
        layer?.masksToBounds = true
        layer?.backgroundColor = NSColor.black.cgColor

        let cfg = WKWebViewConfiguration()
        cfg.mediaTypesRequiringUserActionForPlayback = []
        let proxy = WeakScriptHandler(self)
        cfg.userContentController.add(proxy, name: YouTubePlayerHTML.messageHandler)
        let web = WKWebView(frame: .zero, configuration: cfg)
        web.navigationDelegate = self
        web.translatesAutoresizingMaskIntoConstraints = false
        addSubview(web)
        webView = web

        closeButton.image = NSImage(systemSymbolName: "xmark.circle.fill", accessibilityDescription: "Close player")?.withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: 20, weight: .regular))
        closeButton.isBordered = false
        closeButton.contentTintColor = .white
        closeButton.toolTip = "Close Player"
        closeButton.target = self; closeButton.action = #selector(close)
        closeButton.translatesAutoresizingMaskIntoConstraints = false
        addSubview(closeButton)

        errorLabel.textColor = .white
        errorLabel.font = Fonts.body(.medium, size: 14)
        errorLabel.alignment = .center
        errorLabel.isHidden = true
        errorLabel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(errorLabel)
        openButton.title = "Open in YouTube"
        openButton.bezelStyle = .rounded
        openButton.target = self; openButton.action = #selector(openInYouTube)
        openButton.isHidden = true
        openButton.translatesAutoresizingMaskIntoConstraints = false
        addSubview(openButton)

        NSLayoutConstraint.activate([
            web.leadingAnchor.constraint(equalTo: leadingAnchor), web.trailingAnchor.constraint(equalTo: trailingAnchor),
            web.topAnchor.constraint(equalTo: topAnchor), web.bottomAnchor.constraint(equalTo: bottomAnchor),
            closeButton.topAnchor.constraint(equalTo: topAnchor, constant: 6), closeButton.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -6),
            errorLabel.centerXAnchor.constraint(equalTo: centerXAnchor), errorLabel.centerYAnchor.constraint(equalTo: centerYAnchor, constant: -16),
            openButton.centerXAnchor.constraint(equalTo: centerXAnchor), openButton.topAnchor.constraint(equalTo: errorLabel.bottomAnchor, constant: 10),
        ])
        if Self.loadsContent { web.loadHTMLString(YouTubePlayerHTML.html(for: yt), baseURL: YouTubePlayerHTML.baseURL) }
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) not supported") }

    func showError(_ message: String) {
        errorMessage = message
        webView?.isHidden = true
        errorLabel.stringValue = message
        errorLabel.isHidden = false
        openButton.isHidden = false
    }

    @objc private func close() { stop(); onClose?() }
    @objc private func openInYouTube() { NSWorkspace.shared.open(yt.watchURL) }

    /// หยุดเสียง/วิดีโอและปล่อย WKWebView
    func stop() {
        webView?.configuration.userContentController.removeScriptMessageHandler(forName: YouTubePlayerHTML.messageHandler)
        webView?.stopLoading()
        webView?.loadHTMLString("", baseURL: nil)
        webView?.removeFromSuperview()
        webView = nil
    }

    func userContentController(_ c: WKUserContentController, didReceive message: WKScriptMessage) {
        if let d = message.body as? [String: Any], let code = d["error"] as? Int, let m = YouTubePlayerHTML.message(forError: code) { showError(m) }
    }
    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) { showError("This video can't be played here") }
    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) { showError("This video can't be played here") }
}

/// กัน retain cycle ของ WKScriptMessageHandler
private final class WeakScriptHandler: NSObject, WKScriptMessageHandler {
    weak var target: WKScriptMessageHandler?
    init(_ t: WKScriptMessageHandler) { target = t }
    func userContentController(_ c: WKUserContentController, didReceive message: WKScriptMessage) { target?.userContentController(c, didReceive: message) }
}
