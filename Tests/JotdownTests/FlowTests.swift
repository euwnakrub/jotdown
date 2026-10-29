import Testing
import AppKit
@testable import Jotdown

final class CloseProbe: NSObject {
    var result: Bool?
    @objc func document(_ doc: NSDocument, shouldClose: Bool, contextInfo: UnsafeMutableRawPointer?) { result = shouldClose }
}

@MainActor @Suite(.serialized) struct FlowTests {
    @Test func closingNamedDocumentSavesWithoutAsking() throws {
        _ = NSApplication.shared
        let dir = try tempDir(); defer { try? FileManager.default.removeItem(at: dir) }
        let url = dir.appendingPathComponent("close.md")
        try "# เดิม\n".write(to: url, atomically: true, encoding: .utf8)
        let doc = try JotdownDocument(contentsOf: url, ofType: JotTypes.markdown)
        doc.makeWindowControllers()
        let tv = (doc.windowControllers[0].contentViewController as! EditorViewController).textView!
        tv.setSelectedRange(NSRange(location: doc.textStorage.length, length: 0))
        tv.type("ใหม่")
        let probe = CloseProbe()
        doc.canClose(withDelegate: probe, shouldClose: #selector(CloseProbe.document(_:shouldClose:contextInfo:)), contextInfo: nil)
        waitFor { probe.result != nil }
        #expect(probe.result == true)
        #expect(try String(contentsOf: url, encoding: .utf8) == "# เดิมใหม่\n")
        doc.close()
    }

    @Test func externalChangeReloadsAndKeepsCursor() throws {
        _ = NSApplication.shared
        let dir = try tempDir(); defer { try? FileManager.default.removeItem(at: dir) }
        let url = dir.appendingPathComponent("ext.md")
        try "# หัวข้อ\n\nบรรทัดเดิม\n".write(to: url, atomically: true, encoding: .utf8)
        let doc = try JotdownDocument(contentsOf: url, ofType: JotTypes.markdown)
        let vc = EditorViewController(document: doc); _ = vc.view
        vc.textView.setSelectedRange(NSRange(location: 10, length: 0))
        try "# หัวข้อ\n\nบรรทัดใหม่จากโปรแกรมอื่น\n".write(to: url, atomically: true, encoding: .utf8)
        try doc.revert(toContentsOf: url, ofType: JotTypes.markdown)
        #expect(doc.currentMarkdown == "# หัวข้อ\n\nบรรทัดใหม่จากโปรแกรมอื่น\n")
        #expect(vc.textView.selectedRange().location == 10)
        #expect(!doc.saveDebouncer.isPending)
        // ไม่เขียนทับไฟล์ที่เพิ่งโหลด
        let before = try mtime(url)
        var done = false
        doc.saveNow { _ in done = true }
        waitFor { done }
        #expect(try mtime(url) == before)
    }

    @Test func newTabActionIsHandled() {
        let d = AppDelegate()
        #expect(d.responds(to: NSSelectorFromString("newWindowForTab:")))
    }

    @Test func nonLossOnLongMixedDocument() throws {
        let md = try fixture("full-canonical") + "\n* a\n* b\n\n1) x\n2) y\n\nSetext\n---\n\n> q1\n> q2\n\n+ [ ] t\n\n    indented\n\n<div>x</div>\n\nการ **ทดสอบ** _ภาษาไทย_ ยาว ๆ\n"
        func words(_ s: String) -> [String] { s.split { !($0.isLetter || $0.isNumber) }.map(String.init).sorted() }
        let out = MarkdownSerializer.serialize(MarkdownParser.parse(md))
        #expect(words(out) == words(md))
        #expect(MarkdownSerializer.serialize(MarkdownParser.parse(out)) == out)
    }
}
