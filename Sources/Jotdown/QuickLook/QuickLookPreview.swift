import AppKit
import QuickLookUI

/// Quick Look (กด spacebar ที่ไฟล์ .md ใน Finder): แสดงไฟล์ด้วยตัวแสดงผลเดียวกับแอปแบบอ่านอย่างเดียว
/// ไบนารีเดียวกับแอป: build-app.sh คัดลอกไปไว้ใน Contents/PlugIns/JotdownQuickLook.appex แล้ว main.swift
/// เห็นว่ารันใน .appex จึงเรียก NSExtensionMain แทนการเปิดแอป
/// ชื่อ Objective-C ต้องตรงกับ NSExtensionPrincipalClass ใน Info.plist ของ .appex
@objc(JotdownQuickLookPreview)
final class QuickLookPreview: NSViewController, QLPreviewingController {
    private let scrollView = NSScrollView()
    private var textView: EditorTextView?
    private var fileURL: URL?

    override var nibName: NSNib.Name? { nil }

    override func loadView() {
        Fonts.registerAll()
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.borderType = .noBorder
        scrollView.drawsBackground = true
        scrollView.backgroundColor = Palette.paper
        scrollView.frame = NSRect(origin: .zero, size: Theme.defaultWindowSize)
        view = scrollView
        NotificationCenter.default.addObserver(self, selector: #selector(imagesLoaded), name: .jotImageLoaded, object: nil)
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
        MainActor.assumeIsolated { textView?.stopAllPlayers() }
    }

    func preparePreviewOfFile(at url: URL, completionHandler handler: @escaping (Error?) -> Void) {
        do {
            let markdown = try MarkdownFile.decode(Data(contentsOf: url))
            show(markdown: markdown, fileURL: url)
            handler(nil)
        } catch {
            handler(error)
        }
    }

    /// แยกจากการอ่านไฟล์ เพื่อให้เทสต์เรียกได้โดยตรง
    func show(markdown: String, fileURL url: URL?) {
        _ = view
        fileURL = url
        let storage = NSTextStorage(attributedString: MarkdownParser.parse(markdown))
        let tv = EditorTextView.make(storage: storage)
        tv.isEditable = false
        tv.isSelectable = true
        let base = url?.deletingLastPathComponent()
        tv.imageBaseProvider = { base }
        tv.linkBaseProvider = { base }
        tv.frame = NSRect(origin: .zero, size: scrollView.contentSize)
        scrollView.documentView = tv
        textView = tv
        tv.refreshWikiLinks()
        tv.scheduleTableLayoutCheck()
    }

    @objc private func imagesLoaded() { textView?.refreshImages() }

    var renderedText: String { textView?.string ?? "" }
}

/// จุดเริ่มของ app extension ใน Foundation (ไม่มีใน Swift header)
@_silgen_name("NSExtensionMain")
private func _NSExtensionMain(_ argc: Int32, _ argv: UnsafeMutablePointer<UnsafeMutablePointer<CChar>?>) -> Int32

enum QuickLookExtension {
    /// true เมื่อไบนารีนี้รันอยู่ใน .appex (Quick Look เรียกใช้)
    static var isRunningAsExtension: Bool { Bundle.main.bundleURL.pathExtension == "appex" }

    static func main() -> Never {
        exit(_NSExtensionMain(CommandLine.argc, CommandLine.unsafeArgv))
    }
}
