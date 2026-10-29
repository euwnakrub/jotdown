import Testing
import AppKit
@testable import Jotdown

@MainActor @Suite(.serialized) struct ObsidianTests {
    func rt(_ md: String) -> String { MarkdownSerializer.serialize(MarkdownParser.parse(md)) }

    @Test func roundTripsExactly() {
        for md in ["![[รูป.jpg]]\n", "![[a b.png|300]]\n", "![[x.png|300x200]]\n", "![[โน้ต]]\n", "![[โน้ต#หัวข้อ]]\n",
                   "ดู [[โน้ต]] และ [[โน้ต|ข้อความ]] [[โน้ต#หัว]] [[#หัว]] จบ\n", "- [[a_b_c]] *x*\n", "> [[a]] **[[b|c]]**\n", "# [[a]] หัว\n",
                   "ข้อความ ![[p.png|100]] ต่อ [[n]]\n", "1. [[folder/note|alias]]\n", "[[a]][[b]]\n"] {
            #expect(rt(md) == md, Comment(rawValue: "round-trip ล้ม: \(md.debugDescription) -> \(rt(md).debugDescription)"))
        }
    }

    @Test func wikiInTableWithEscapedPipe() {
        let md = "| a   | b   |\n| --- | --- |\n| [[x\\|y]] | ![[p.png\\|100]] |\n"
        let out = rt(md)
        #expect(out.contains("[[x\\|y]]") && out.contains("![[p.png\\|100]]"))
        #expect(rt(out) == out)
        let a = MarkdownParser.parse(md)
        #expect(!a.string.contains("|") && !a.string.contains("[["))
        #expect(a.string.contains("y"))                      // ข้อความแสดง = alias
        let tableCellImage = (0..<a.length).first { a.attribute(.jotImage, at: $0, effectiveRange: nil) != nil }
        #expect(tableCellImage != nil)
    }

    @Test func storageShowsDisplayTextOnly() {
        let a = MarkdownParser.parse("ก [[โน้ต|ชื่อแสดง]] ข [[โน้ต#หัวข้อ]] ค [[#ในหน้านี้]]\n")
        #expect(a.string == "ก ชื่อแสดง ข โน้ต > หัวข้อ ค ในหน้านี้")
        let i = (a.string as NSString).range(of: "ชื่อแสดง").location
        #expect(a.link(at: i) == "wiki:โน้ต")
        #expect(a.attribute(.jotWiki, at: i, effectiveRange: nil) as? String == "[[โน้ต|ชื่อแสดง]]")
        let j = (a.string as NSString).range(of: "หัวข้อ").location
        #expect(a.link(at: j) == "wiki:โน้ต#หัวข้อ")
        #expect(a.link(at: (a.string as NSString).range(of: "ในหน้านี้").location) == "wiki:#ในหน้านี้")
    }

    @Test func embedsBecomeImagesAndNoteCards() throws {
        let a = MarkdownParser.parse("![[รูป.png|300x200]]\n\n![[โน้ต#หัว]]\n")
        let img = try #require(ImageRef(encoded: a.attribute(.jotImage, at: 0, effectiveRange: nil) as! String))
        #expect(img.src == "รูป.png" && img.width == 300 && img.height == 200 && img.raw == "![[รูป.png|300x200]]" && !img.noteEmbed)
        #expect(a.attribute(.attachment, at: 0, effectiveRange: nil) is ImageAttachment)
        let j = a.length - 1
        let note = try #require(ImageRef(encoded: a.attribute(.jotImage, at: j, effectiveRange: nil) as! String))
        #expect(note.noteEmbed && note.src == "โน้ต" && a.link(at: j) == "wiki:โน้ต#หัว")
    }

    @Test func notParsedInCode() {
        let md = "`[[a]]` และ `![[b.png]]`\n\n```\n[[c]]\n![[d.png]]\n```\n\n    [[indented]]\n"
        let out = rt(md)
        #expect(out.contains("`[[a]]`") && out.contains("[[c]]") && out.contains("![[d.png]]") && out.contains("[[indented]]"))
        let a = MarkdownParser.parse(md)
        #expect(a.string.contains("[[a]]") && a.string.contains("[[c]]"))
        #expect((0..<a.length).allSatisfy { a.attribute(.jotWiki, at: $0, effectiveRange: nil) == nil })
        #expect((0..<a.length).allSatisfy { a.attribute(.jotImage, at: $0, effectiveRange: nil) == nil })
    }

    @Test func frontmatterIsPreserved() {
        let md = "---\ntitle: โน้ต\ntags: [a, b]\naliases:\n  - x\n---\n\n# หัวข้อ\n\nเนื้อหา\n"
        #expect(rt(md) == md)
        let a = MarkdownParser.parse(md)
        #expect(a.blockKind(at: 0) == .raw)
        #expect(a.string.hasPrefix("---\u{2028}title"))
        #expect(a.blockKind(at: (a.string as NSString).range(of: "หัวข้อ").location) == .heading(1))
        // ไม่ใช่ YAML: เส้นคั่นปกติ
        let plain = "---\n\nไม่ใช่ yaml\n\n---\n"
        #expect(MarkdownParser.parse(plain).blockKind(at: 0) == .thematicBreak)
        #expect(ObsidianSyntax.frontmatterLineCount(["---", "", "x", "---"]) == 0)
    }

    @Test func calloutsTagsAndBracketsSurvive() {
        for md in ["> [!note] หัวเรื่อง\n> เนื้อหา **หนา**\n", "#tag และ #ไทย/ย่อย ท้าย\n", "- [ ] งาน\n- [x] เสร็จ\n", "ตัวอย่าง [1] และ [a][b] อ้างอิง\n"] {
            let out = rt(md)
            #expect(out.contains("[!note]") || !md.contains("[!note]"), Comment(rawValue: out))
            #expect(out.contains("#tag") || !md.contains("#tag"))
            #expect(rt(out) == out)
        }
        #expect(rt("> [!note] หัวเรื่อง\n> เนื้อหา\n") == "> [!note] หัวเรื่อง\n> เนื้อหา\n")
        #expect(rt("#tag\n") == "#tag\n")
        // ข้อความ [x](y) ที่พิมพ์เองยังถูก escape
        let a = NSAttributedString(string: "see [x](y) done", attributes: Theme.attributes(for: .paragraph))
        let md = MarkdownSerializer.serialize(a)
        #expect(md.contains("\\[x\\](y)") && MarkdownParser.parse(md).string == "see [x](y) done")
    }

    // MARK: - vault
    func makeVault() throws -> URL {
        let root = try tempDir().appendingPathComponent("vault")
        let fm = FileManager.default
        func touch(_ p: String, _ s: String = "x") throws {
            let u = root.appendingPathComponent(p)
            try fm.createDirectory(at: u.deletingLastPathComponent(), withIntermediateDirectories: true)
            try s.write(to: u, atomically: true, encoding: .utf8)
        }
        try touch(".obsidian/app.json", "{\"attachmentFolderPath\": \"Attachments\"}")
        try touch("Attachments/Pic.PNG")
        try touch("notes/deep/dir/pic.png")
        try touch("Daily/2024/Note.md", "# หัวข้อ\n")
        try touch("Daily/2024/ที่-บ้าน.md")
        try touch("a/same.md"); try touch("a/b/c/same.md")
        try touch("Docs/Doc.md"); try touch("Docs/local.png")
        try touch(".git/hidden.md"); try touch(".trash/old.md"); try touch("node_modules/pkg/x.md")
        return root
    }

    @Test func vaultRootAndAttachmentSetting() throws {
        let root = try makeVault(); defer { try? FileManager.default.removeItem(at: root.deletingLastPathComponent()) }
        let docDir = root.appendingPathComponent("Docs")
        let (r, has) = ObsidianVault.rootDirectory(for: docDir)
        #expect(r.path == root.standardizedFileURL.path && has)
        let v = ObsidianVault(root: r, hasObsidianFolder: true)
        #expect(v.attachmentFolder == "Attachments")
        let (r2, has2) = ObsidianVault.rootDirectory(for: try tempDir())
        #expect(!has2 && r2.lastPathComponent.hasPrefix("jot-test"))
    }

    @Test func resolveOrder() throws {
        let root = try makeVault(); defer { try? FileManager.default.removeItem(at: root.deletingLastPathComponent()) }
        let v = ObsidianVault(root: root.standardizedFileURL, hasObsidianFolder: true)
        let docs = root.appendingPathComponent("Docs").standardizedFileURL
        func path(_ r: ObsidianVault.Resolution) -> String? { if case .found(let u) = r { return u.path.replacingOccurrences(of: root.standardizedFileURL.path + "/", with: "") }; return nil }
        // 1) โฟลเดอร์ของเอกสารก่อน
        #expect(path(v.resolve("local.png", docDir: docs, isNote: false)) == "Docs/local.png")
        // 2) โฟลเดอร์ attachment ตาม app.json (ไม่สนตัวพิมพ์ของนามสกุลเมื่อหาด้วย index? ชื่อเต็ม Pic.PNG)
        #expect(path(v.resolve("Pic.PNG", docDir: docs, isNote: false)) == "Attachments/Pic.PNG")
        // โน้ตไม่ต้องมี .md
        #expect(path(v.resolve("Doc", docDir: docs, isNote: true)) == "Docs/Doc.md")
        // path: จาก vault root
        #expect(path(v.resolve("Daily/2024/Note", docDir: docs, isNote: true)) == "Daily/2024/Note.md")
        // 3) ทั้ง vault ไม่สนตัวพิมพ์
        var r = v.resolve("note", docDir: docs, isNote: true)
        waitFor { r = v.resolve("note", docDir: docs, isNote: true); return path(r) != nil }
        #expect(path(r) == "Daily/2024/Note.md")
        #expect(path(v.resolve("ที่-บ้าน", docDir: docs, isNote: true)) == "Daily/2024/ที่-บ้าน.md")
        // เจอหลายไฟล์ = path สั้นสุด
        #expect(path(v.resolve("same", docDir: docs, isNote: true)) == "a/same.md")
        #expect(path(v.resolve("PIC.png", docDir: docs, isNote: false))?.lowercased() == "attachments/pic.png")
        // ข้ามโฟลเดอร์ที่ไม่ควรค้น
        #expect(v.resolve("hidden", docDir: docs, isNote: true, rebuildIfMissing: false) == .notFound)
        #expect(v.resolve("old", docDir: docs, isNote: true, rebuildIfMissing: false) == .notFound)
        #expect(v.resolve("x", docDir: docs, isNote: true, rebuildIfMissing: false) == .notFound)
        #expect(v.resolve("no-such-note", docDir: docs, isNote: true, rebuildIfMissing: false) == .notFound)
        #expect(v.isReady && v.indexedFileCount >= 8)
    }

    @Test func indexBuildsInBackgroundAndRefreshes() throws {
        let root = try makeVault(); defer { try? FileManager.default.removeItem(at: root.deletingLastPathComponent()) }
        let v = ObsidianVault(root: root.standardizedFileURL, hasObsidianFolder: true)
        v.rebuildInterval = 0
        let docs = root.appendingPathComponent("Docs")
        // ครั้งแรกยังไม่มี index = pending (ไม่บล็อก)
        #expect(v.resolve("same", docDir: docs, isNote: true) == .pending)
        waitFor { v.isReady }
        #expect(v.isReady)
        // ไฟล์ใหม่ที่เพิ่งสร้าง: หาไม่เจอ -> รีเฟรช index ให้ครั้งถัดไป
        try "n".write(to: root.appendingPathComponent("fresh.md"), atomically: true, encoding: .utf8)
        #expect(v.resolve("fresh", docDir: docs, isNote: true) == .notFound)
        waitFor { if case .found = v.resolve("fresh", docDir: docs, isNote: true, rebuildIfMissing: false) { return true } else { return false } }
        if case .found = v.resolve("fresh", docDir: docs, isNote: true, rebuildIfMissing: false) {} else { Issue.record("index ไม่รีเฟรช") }
    }

    func vaultDoc(_ md: String) throws -> (URL, JotdownDocument, EditorViewController, FakeOpener) {
        _ = NSApplication.shared
        ObsidianVault.resetCache()
        let root = try makeVault()
        let url = root.appendingPathComponent("Docs/current.md")
        try md.write(to: url, atomically: true, encoding: .utf8)
        let doc = try JotdownDocument(contentsOf: url, ofType: JotTypes.markdown)
        let vc = EditorViewController(document: doc); _ = vc.view
        let op = FakeOpener(); vc.textView.linkOpener = op
        return (root, doc, vc, op)
    }

    @Test func openWikiLinks() throws {
        let (root, _, vc, op) = try vaultDoc("# หัวข้อ\n\nลิงก์ [[Note#หัวข้อ]] และ [[ไม่มีโน้ต]] และ [[#หัวข้อ]]\n")
        defer { try? FileManager.default.removeItem(at: root.deletingLastPathComponent()) }
        let tv = vc.textView!
        var r = tv.openLink("wiki:Note#หัวข้อ")
        waitFor { r = tv.openLink("wiki:Note#หัวข้อ"); return r == .opened }
        #expect(r == .opened)
        #expect(op.markdown.last?.lastPathComponent == "Note.md" && op.headings.last == "หัวข้อ")
        waitFor { ObsidianVault.vault(for: root.appendingPathComponent("Docs")).isReady }
        #expect(tv.openLink("wiki:ไม่มีโน้ต") == .notice("Note not found"))
        #expect(!FileManager.default.fileExists(atPath: root.appendingPathComponent("Docs/ไม่มีโน้ต.md").path))     // ไม่สร้างไฟล์ใหม่
        #expect(tv.openLink("wiki:#  หัวข้อ") == .opened)                                                          // เทียบข้อความหัวข้อ ไม่สนช่องว่างซ้ำ/ตัวพิมพ์
        #expect(tv.openLink("wiki:#ไม่มีหัวข้อ") == .failed)
    }

    @Test func unresolvedLinksAreDimmed() throws {
        let (root, doc, vc, _) = try vaultDoc("ดี [[Note]] ไม่มี [[ghost]] แล้ว [[#x]]\n")
        defer { try? FileManager.default.removeItem(at: root.deletingLastPathComponent()) }
        let tv = vc.textView!
        let vault = ObsidianVault.vault(for: root.appendingPathComponent("Docs"))
        vault.startIndexIfNeeded()
        waitFor { vault.isReady }
        tv.refreshWikiLinks()
        let s = doc.textStorage
        let ok = (s.string as NSString).range(of: "Note").location, bad = (s.string as NSString).range(of: "ghost").location
        #expect(!s.inlineStyle(at: ok).contains(.unresolved))
        #expect(s.inlineStyle(at: bad).contains(.unresolved))
        #expect(s.attribute(.foregroundColor, at: bad, effectiveRange: nil) as? NSColor === Palette.secondaryText)
        #expect(s.attribute(.foregroundColor, at: ok, effectiveRange: nil) as? NSColor === Palette.link)
        // ไม่กระทบข้อความที่เขียนลงไฟล์
        #expect(doc.currentMarkdown == "ดี [[Note]] ไม่มี [[ghost]] แล้ว [[#x]]\n")
    }

    @Test func editAndRemoveWikiLink() throws {
        let (root, doc, vc, _) = try vaultDoc("ก [[Note|ชื่อ]] ข\n")
        defer { try? FileManager.default.removeItem(at: root.deletingLastPathComponent()) }
        let tv = vc.textView!
        let r = (doc.textStorage.string as NSString).range(of: "ชื่อ")
        tv.replaceWiki(range: r, raw: "[[Doc#หัว|ใหม่]]")
        #expect(doc.currentMarkdown == "ก [[Doc#หัว|ใหม่]] ข\n")
        let r2 = (doc.textStorage.string as NSString).range(of: "ใหม่")
        tv.select(r2.location + 1)
        tv.jotRemoveLink(nil)
        #expect(doc.currentMarkdown == "ก ใหม่ ข\n")
    }

    @Test func pastedImageInVaultDocUsesEmbedSyntax() throws {
        let (root, doc, vc, _) = try vaultDoc("![[Pic.PNG]]\n\nข้อความ\n")
        defer { try? FileManager.default.removeItem(at: root.deletingLastPathComponent()) }
        let src = root.appendingPathComponent("Docs/shot one.png")
        try makePNG(src, 20, 20)
        let pb = NSPasteboard.withUniqueName(); pb.clearContents(); pb.writeObjects([src as NSURL])
        vc.textView.select(doc.textStorage.length)
        #expect(vc.textView.insertImages(from: pb, at: nil))
        #expect(doc.currentMarkdown.contains("![[shot one.png]]"), Comment(rawValue: doc.currentMarkdown))
        // เอกสารที่ไม่มี ![[ อยู่แล้ว ใช้รูปแบบมาตรฐาน
        let (root2, doc2, vc2, _) = try vaultDoc("ข้อความ\n")
        defer { try? FileManager.default.removeItem(at: root2.deletingLastPathComponent()) }
        let src2 = root2.appendingPathComponent("Docs/two.png"); try makePNG(src2, 20, 20)
        let pb2 = NSPasteboard.withUniqueName(); pb2.clearContents(); pb2.writeObjects([src2 as NSURL])
        vc2.textView.select(doc2.textStorage.length)
        #expect(vc2.textView.insertImages(from: pb2, at: nil))
        #expect(doc2.currentMarkdown.contains("![two](two.png)") && !doc2.currentMarkdown.contains("![["))
    }

    // MARK: - snapshot
    func snapObsidian(_ ap: NSAppearance.Name) throws {
        _ = NSApplication.shared
        ObsidianVault.resetCache()
        let root = try makeVault(); defer { try? FileManager.default.removeItem(at: root.deletingLastPathComponent()) }
        try makePNG(root.appendingPathComponent("Attachments/รูป.jpg"), 900, 500, color: .systemIndigo)
        try makePNG(root.appendingPathComponent("Docs/small.png"), 120, 80, color: .systemOrange)
        let md = """
        ---
        title: โน้ตของ Euw
        tags: [ทดสอบ]
        ---

        # โน้ตจาก Obsidian

        ย่อหน้ามี [[Note|โน้ตที่มีอยู่]] และ [[ghost|โน้ตที่ไม่มี]] กับ [[Note#หัวข้อ]] และ [[#โน้ตจาก Obsidian]]

        ![[Note#หัวข้อ]]

        | วันที่ | รูป |
        | --- | --- |
        | จันทร์ | ![[รูป.jpg\\|240]] |
        | อังคาร | [[Note\\|ลิงก์ในตาราง]] ![[small.png]] |

        ![[ไม่มีรูป.png]]

        > [!note] Callout
        > เนื้อหา #tag
        """
        let url = root.appendingPathComponent("Docs/current.md")
        try md.write(to: url, atomically: true, encoding: .utf8)
        let doc = try JotdownDocument(contentsOf: url, ofType: JotTypes.markdown)
        let vc = EditorViewController(document: doc); _ = vc.view
        let vault = ObsidianVault.vault(for: root.appendingPathComponent("Docs"))
        vault.startIndexIfNeeded(); waitFor { vault.isReady }
        let shot = try snapshot("editor-obsidian", size: CGSize(width: 900, height: 1100), appearance: ap, after: {
            spin(0.8, vc.view)
            vc.textView.refreshImages()
            spin(0.4, vc.view)
        }, viewController: vc)
        #expect(FileManager.default.fileExists(atPath: shot.png.path))
        #expect(doc.currentMarkdown.contains("![[รูป.jpg\\|240]]") && doc.currentMarkdown.contains("[[ghost|โน้ตที่ไม่มี]]"))
    }
    @Test func obsidianSnapshotAqua() throws { try snapObsidian(.aqua) }
    @Test func obsidianSnapshotDark() throws { try snapObsidian(.darkAqua) }
}
