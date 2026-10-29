import Testing
import AppKit
@testable import Jotdown

@MainActor
func tempDir() throws -> URL {
    let d = FileManager.default.temporaryDirectory.appendingPathComponent("jot-test-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
    return d
}

func mtime(_ u: URL) throws -> Date { try FileManager.default.attributesOfItem(atPath: u.path)[.modificationDate] as! Date }

@MainActor
func waitFor(_ timeout: TimeInterval = 5, _ cond: () -> Bool) {
    let end = Date().addingTimeInterval(timeout)
    while !cond() && Date() < end { RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.02)) }
}

@MainActor @Suite(.serialized) struct DocumentTests {
    @Test func readNormalizesCRLFBOM() throws {
        let doc = JotdownDocument()
        try doc.read(from: Data("\u{FEFF}# หัวข้อ\r\n\r\nเนื้อหา\r\n".utf8), ofType: JotTypes.markdown)
        #expect(doc.currentMarkdown == "# หัวข้อ\n\nเนื้อหา\n")
        let out = try doc.data(ofType: JotTypes.markdown)
        #expect(out.starts(with: Array("# ".utf8)))
        #expect(!out.contains(0x0D))
    }

    @Test func invalidUTF8Throws() {
        let doc = JotdownDocument()
        #expect(throws: Error.self) { try doc.read(from: Data([0xFF, 0xFE, 0x41]), ofType: JotTypes.markdown) }
    }

    @Test func unchangedContentDoesNotRewriteFile() throws {
        _ = NSApplication.shared
        let dir = try tempDir(); defer { try? FileManager.default.removeItem(at: dir) }
        let url = dir.appendingPathComponent("a.md")
        try "# หัวข้อ\n\nเนื้อหา\n".write(to: url, atomically: true, encoding: .utf8)
        let old = Date(timeIntervalSince1970: 1_600_000_000)
        try FileManager.default.setAttributes([.modificationDate: old], ofItemAtPath: url.path)

        let doc = try JotdownDocument(contentsOf: url, ofType: JotTypes.markdown)
        #expect(doc.currentMarkdown == "# หัวข้อ\n\nเนื้อหา\n")
        var done = false
        doc.saveNow { _ in done = true }
        waitFor { done }
        #expect(done)
        #expect(try mtime(url) == old)
    }

    @Test func nonCanonicalFileUntouchedUntilEdited() throws {
        _ = NSApplication.shared
        let dir = try tempDir(); defer { try? FileManager.default.removeItem(at: dir) }
        let url = dir.appendingPathComponent("b.md")
        let original = "## ชื่อ ##\r\n\r\n* รายการ\r\n"
        try original.write(to: url, atomically: true, encoding: .utf8)
        let doc = try JotdownDocument(contentsOf: url, ofType: JotTypes.markdown)
        var done = false
        doc.saveNow { _ in done = true }
        waitFor { done }
        #expect(try String(contentsOf: url, encoding: .utf8) == original)
    }

    @Test func editThenSaveRoundTrips() throws {
        _ = NSApplication.shared
        let dir = try tempDir(); defer { try? FileManager.default.removeItem(at: dir) }
        let url = dir.appendingPathComponent("c.md")
        try "# หัวข้อ\n".write(to: url, atomically: true, encoding: .utf8)
        let doc = try JotdownDocument(contentsOf: url, ofType: JotTypes.markdown)
        doc.textStorage.append(NSAttributedString(string: "\nเพิ่มเติม", attributes: Theme.attributes(for: .paragraph)))
        #expect(doc.saveDebouncer.isPending)
        var ok = false, done = false
        doc.saveNow { ok = $0; done = true }
        waitFor { done }
        #expect(ok)
        #expect(try String(contentsOf: url, encoding: .utf8) == "# หัวข้อ\n\nเพิ่มเติม\n")
        // อ่านกลับเป็นเอกสารใหม่
        let doc2 = try JotdownDocument(contentsOf: url, ofType: JotTypes.markdown)
        #expect(doc2.currentMarkdown == "# หัวข้อ\n\nเพิ่มเติม\n")
    }

    @Test func reloadDoesNotTriggerSave() throws {
        let doc = JotdownDocument()
        doc.load(markdown: "# ก\n\nข\n")
        #expect(!doc.saveDebouncer.isPending)
        try doc.read(from: Data("# ค\n".utf8), ofType: JotTypes.markdown)
        #expect(!doc.saveDebouncer.isPending)
        #expect(doc.currentMarkdown == "# ค\n")
    }

    @Test func typingAfterHeadingNormalizesBlock() throws {
        let doc = JotdownDocument()
        doc.load(markdown: "# หัวข้อ\n\nเนื้อ\n")
        // ลบตัวคั่นระหว่างหัวข้อกับเนื้อ => รวมเป็นหัวข้อเดียว ฟอนต์ต้องเป็นฟอนต์หัวข้อทั้งย่อหน้า
        let s = doc.textStorage
        s.replaceCharacters(in: NSRange(location: 6, length: 1), with: "")
        #expect(s.string == "หัวข้อเนื้อ")
        #expect(s.blockKind(at: s.length - 1) == .heading(1))
        let f = s.attribute(.font, at: s.length - 1, effectiveRange: nil) as? NSFont
        #expect(f?.fontName == Theme.font(for: .heading(1)).fontName)
    }
}
