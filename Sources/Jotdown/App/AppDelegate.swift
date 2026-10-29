import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuItemValidation {
    private var resignObserver: NSObjectProtocol?

    var jotDocuments: [JotdownDocument] { NSDocumentController.shared.documents.compactMap { $0 as? JotdownDocument } }

    func applicationWillFinishLaunching(_ notification: Notification) {
        Fonts.registerAll()
        // dev: JOTDOWN_APPEARANCE=dark|light บังคับธีม (ใช้ตรวจ dark mode)
        switch ProcessInfo.processInfo.environment["JOTDOWN_APPEARANCE"] {
        case "dark": NSApp.appearance = NSAppearance(named: .darkAqua)
        case "light": NSApp.appearance = NSAppearance(named: .aqua)
        default: break
        }
        NSApp.mainMenu = MainMenu.build()
        NSWindow.allowsAutomaticWindowTabbing = true
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        resignObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didResignActiveNotification, object: nil, queue: .main) { [weak self] _ in
            self?.jotDocuments.forEach { $0.saveNow() }
        }
    }

    /// เมนู ไฟล์ > แท็บใหม่ (⌘T): สร้างเอกสารใหม่แล้วเพิ่มเป็นแท็บของหน้าต่างปัจจุบัน
    @objc func newWindowForTab(_ sender: Any?) {
        let current = NSApp.keyWindow
        guard let doc = try? NSDocumentController.shared.openUntitledDocumentAndDisplay(false) as? JotdownDocument else { return }
        doc.makeWindowControllers()
        guard let w = doc.windowControllers.first?.window else { return }
        if let current { current.addTabbedWindow(w, ordered: .above) }
        w.makeKeyAndOrderFront(nil)
    }

    // MARK: - ซูม (View > Zoom In ⌘+ / Zoom Out ⌘− / Actual Size ⌘0)
    @objc func jotZoomIn(_ sender: Any?) { Self.changeZoom(Theme.zoom + Theme.zoomStep) }
    @objc func jotZoomOut(_ sender: Any?) { Self.changeZoom(Theme.zoom - Theme.zoomStep) }
    @objc func jotZoomReset(_ sender: Any?) { Self.changeZoom(1) }

    /// ตั้งซูมแล้วจัดรูปแบบเอกสารที่เปิดอยู่ทุกฉบับใหม่ (ไม่เปลี่ยนเนื้อหาไฟล์)
    static func changeZoom(_ z: CGFloat) {
        guard Theme.setZoom(z) else { return }
        for case let doc as JotdownDocument in NSDocumentController.shared.documents { doc.reapplyStyles() }
    }

    func validateMenuItem(_ item: NSMenuItem) -> Bool {
        switch item.action {
        case #selector(jotZoomIn(_:)): return Theme.zoom < Theme.zoomRange.upperBound - 0.001
        case #selector(jotZoomOut(_:)): return Theme.zoom > Theme.zoomRange.lowerBound + 0.001
        case #selector(jotZoomReset(_:)): return abs(Theme.zoom - 1) > 0.001
        default: return true
        }
    }

    func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool { true }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        let docs = jotDocuments
        var remaining = docs.count
        if remaining == 0 { return .terminateNow }
        for d in docs {
            d.saveNow { _ in
                remaining -= 1
                if remaining == 0 { NSApp.reply(toApplicationShouldTerminate: true) }
            }
        }
        return remaining == 0 ? .terminateNow : .terminateLater
    }
}
