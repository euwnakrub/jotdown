import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
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
