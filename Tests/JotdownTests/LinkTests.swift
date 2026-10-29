import Testing
import AppKit
@testable import Jotdown

final class FakeOpener: LinkOpening {
    var external: [URL] = [], files: [URL] = [], markdown: [URL] = [], headings: [String?] = []
    func open(external url: URL) { external.append(url) }
    func open(file url: URL) { files.append(url) }
    func open(markdown url: URL, heading: String?) { markdown.append(url); headings.append(heading) }
}

@MainActor @Suite(.serialized) struct LinkTests {
    let base = URL(fileURLWithPath: "/tmp/doc")

    @Test func resolveDestinations() {
        let exists: (URL) -> Bool = { $0.path.hasSuffix("other.md") || $0.path.hasSuffix("a.pdf") || $0.path.hasSuffix("/sub/n.markdown") }
        func r(_ s: String, _ b: URL? = URL(fileURLWithPath: "/tmp/doc")) -> LinkDestination { LinkResolver.resolve(s, base: b, fileExists: exists) }
        #expect(r("https://x.y/z") == .web(URL(string: "https://x.y/z")!))
        #expect(r("mailto:a@b.co") == .web(URL(string: "mailto:a@b.co")!))
        #expect(r("example.com/x") == .web(URL(string: "https://example.com/x")!))
        #expect(r("www.example.com") == .web(URL(string: "https://www.example.com")!))
        #expect(r("example.com") == .web(URL(string: "https://example.com")!))
        #expect(r("notes/other.md") == .markdown(URL(fileURLWithPath: "/tmp/doc/notes/other.md")))
        #expect(r("./other.md") == .markdown(URL(fileURLWithPath: "/tmp/doc/other.md")))
        #expect(r("sub/n.markdown") == .markdown(URL(fileURLWithPath: "/tmp/doc/sub/n.markdown")))
        #expect(r("a.pdf") == .file(URL(fileURLWithPath: "/tmp/doc/a.pdf")))
        #expect(r("file:///tmp/doc/a.pdf") == .file(URL(fileURLWithPath: "/tmp/doc/a.pdf")))
        #expect(r("missing.md") == .missingFile("/tmp/doc/missing.md"))
        #expect(r("notes/other.md#sec") == .markdown(URL(fileURLWithPath: "/tmp/doc/notes/other.md")))
        #expect(r("other.md", nil) == .needsSave)
        #expect(r("#หัวข้อ") == .anchor("หัวข้อ"))
        #expect(r("   ") == .invalid)
        #expect(r("a.md") == .missingFile("/tmp/doc/a.md"))       // a.md ไม่ใช่โดเมน
    }

    @Test func slugsThaiAndEnglish() {
        #expect(LinkResolver.slug("Hello, World! 2") == "hello-world-2")
        #expect(LinkResolver.slug("หัวข้อ ที่หนึ่ง") == "หัวข้อ-ที่หนึ่ง")
        #expect(LinkResolver.slug("C++ & Swift") == "c--swift")
        #expect(LinkResolver.slugs(forHeadings: ["A", "A", "B", "A"]) == ["a", "a-1", "b", "a-2"])
    }

    @Test func displayTruncatesMiddle() {
        #expect(LinkResolver.display("https://example.com/a") == "example.com/a")
        let long = "https://example.com/" + String(repeating: "x", count: 100) + "/end"
        let d = LinkResolver.display(long, max: 30)
        #expect(d.count == 30 && d.contains("…") && d.hasPrefix("example.com") && d.hasSuffix("/end"))
        #expect(LinkResolver.symbol(for: "https://a.b") == "globe")
        #expect(LinkResolver.symbol(for: "notes/a.md") == "doc")
    }

    @Test func barStateTiming() {
        var s = LinkBarState()
        let a = LinkHit(range: NSRange(location: 0, length: 3), url: "https://a.b")
        s.mouseOver(a, at: 0)
        #expect(s.visible(at: 0.2) == nil)                     // ยังไม่ครบ 0.4 วิ
        #expect(s.visible(at: 0.41) == a)
        s.mouseOver(nil, at: 1.0)
        #expect(s.visible(at: 1.2) == a)                       // ออกจากลิงก์แล้วยังอยู่ 0.3 วิ ให้เลื่อนไปที่แถบ
        #expect(s.visible(at: 1.31) == nil)
        // เลื่อนเมาส์ไปที่แถบ = ไม่ซ่อน
        s.mouseOver(a, at: 2); _ = s.visible(at: 2.5)
        s.mouseOver(nil, at: 3); s.panelMouse(inside: true, at: 3.05)
        #expect(s.visible(at: 4) == a)
        s.panelMouse(inside: false, at: 4)
        #expect(s.visible(at: 4.35) == nil)
    }

    @Test func barStateCaretScrollTypingResign() {
        var s = LinkBarState()
        let a = LinkHit(range: NSRange(location: 0, length: 3), url: "https://a.b")
        s.caretMoved(a)
        #expect(s.visible(at: 0) == a)                         // เคอร์เซอร์ในลิงก์ = แสดงทันที
        s.invalidate()                                         // พิมพ์/scroll
        #expect(s.visible(at: 0.1) == nil)
        s.caretMoved(a)
        #expect(s.visible(at: 0.2) == a)
        s.caretMoved(nil)                                      // เคอร์เซอร์ออกจากลิงก์
        #expect(s.visible(at: 0.3) == nil)
        s.caretMoved(a); s.windowResigned()
        #expect(s.visible(at: 0.4) == nil)
    }

    func editor(_ md: String, base: URL? = URL(fileURLWithPath: "/tmp/doc")) -> (JotdownDocument, EditorViewController, FakeOpener) {
        let (doc, vc) = makeEditor(md)
        let op = FakeOpener()
        vc.textView.linkOpener = op
        vc.textView.linkBaseProvider = { base }
        return (doc, vc, op)
    }

    @Test func openLinkUsesOpener() throws {
        let dir = try tempDir(); defer { try? FileManager.default.removeItem(at: dir) }
        try "x".write(to: dir.appendingPathComponent("other.md"), atomically: true, encoding: .utf8)
        let (_, vc, op) = editor("ก [a](https://x.y) [b](example.com/p) [c](other.md) [d](gone.md)\n", base: dir)
        let tv = vc.textView!
        #expect(tv.openLink("https://x.y") == .opened)
        #expect(tv.openLink("example.com/p") == .opened)
        #expect(op.external == [URL(string: "https://x.y")!, URL(string: "https://example.com/p")!])
        #expect(tv.openLink("other.md") == .opened)
        #expect(op.markdown.map(\.lastPathComponent) == ["other.md"])
        #expect(tv.openLink("gone.md") == .notice("File not found"))
        #expect(tv.openLink("") == .failed)
        let (_, vc2, _) = editor("[x](rel.md)\n", base: nil)
        #expect(vc2.textView.openLink("rel.md") == .notice("Save the document to open relative links"))
    }

    @Test func anchorScrollsToHeading() {
        let (_, vc, _) = editor("# Intro\n\nข้อความ\n\n## หัวข้อ ที่สอง\n\nจบ\n\n## Intro\n")
        let tv = vc.textView!
        #expect(tv.openLink("#หัวข้อ-ที่สอง") == .opened)
        #expect(tv.selectedRange().location == tv.nsString.range(of: "หัวข้อ ที่สอง").location)
        #expect(tv.openLink("#intro-1") == .opened)
        #expect(tv.selectedRange().location == tv.nsString.range(of: "Intro", options: .backwards).location)
        #expect(tv.openLink("#ไม่มี") == .failed)
    }

    @Test func openMenuItemsEnabledOnlyInLink() {
        let (_, vc, _) = editor("plain [link](https://x.y) end\n")
        let tv = vc.textView!
        let open = NSMenuItem(title: "", action: #selector(EditorTextView.jotOpenLink(_:)), keyEquivalent: "")
        let copy = NSMenuItem(title: "", action: #selector(EditorTextView.jotCopyLinkAddress(_:)), keyEquivalent: "")
        tv.select(1); #expect(!tv.validateMenuItem(open)); #expect(!tv.validateMenuItem(copy))
        tv.select(tv.nsString.range(of: "link").location + 1); #expect(tv.validateMenuItem(open)); #expect(tv.validateMenuItem(copy))
        tv.jotCopyLinkAddress(nil)
        #expect(NSPasteboard.general.string(forType: .string) == "https://x.y")
        let menu = MainMenu.build()
        let fmt = menu.items.first { $0.title == "Format" }!.submenu!
        let item = fmt.items.first { $0.title == "Open Link" }
        #expect(item?.keyEquivalent == "\r" && item?.keyEquivalentModifierMask == [.option])
        #expect(fmt.items.contains { $0.title == "Copy Link Address" })
    }

    @Test func contextItemsOrder() {
        let (_, vc, _) = editor("[link](https://x.y)\n")
        #expect(vc.textView.linkContextItems().map(\.title) == ["Open Link", "Copy Link Address", "Edit Link…", "Remove Link"])
    }

    @Test func linkHitAndRect() {
        let (_, vc, _) = editor("ab [link](https://x.y) cd\n")
        let tv = vc.textView!
        tv.layoutManager?.ensureLayout(for: tv.textContainer!)
        let loc = tv.nsString.range(of: "link").location
        let hit = tv.linkHit(atCharacter: loc + 1)
        #expect(hit == LinkHit(range: NSRange(location: loc, length: 4), url: "https://x.y"))
        let rect = tv.linkRect(hit!)!
        #expect(tv.linkHit(atViewPoint: NSPoint(x: rect.midX, y: rect.midY)) == hit)
        #expect(tv.linkHit(atViewPoint: NSPoint(x: rect.minX - 40, y: rect.midY)) == nil)
    }

    // MARK: - URL เปล่า
    @Test func bareURLBecomesLinkOnSpaceAndRoundTrips() {
        let (doc, vc, _) = editor("")
        let tv = vc.textView!
        tv.type("ดู https://example.com/a_b ต่อ")
        let loc = tv.nsString.range(of: "https").location
        #expect(doc.textStorage.link(at: loc) == "https://example.com/a_b")
        #expect(doc.textStorage.link(at: tv.nsString.range(of: "ต่อ").location) == nil)
        #expect(doc.currentMarkdown == "ดู https://example.com/a_b ต่อ\n")
        let back = MarkdownParser.parse(doc.currentMarkdown)
        #expect(back.link(at: loc) == "https://example.com/a_b")
        // วรรคตอนท้ายไม่รวมในลิงก์
        let (d2, v2, _) = editor("")
        v2.textView.type("see https://x.y/z. ok")
        #expect(d2.textStorage.link(at: v2.textView.nsString.range(of: "https").location) == "https://x.y/z")
        #expect(d2.currentMarkdown == "see https://x.y/z. ok\n")
    }

    @Test func autolinkAndMarkdownLinkRoundTrip() {
        for md in ["https://example.com/a?b=1\n", "[x](https://x.y)\n", "[https://x.y/](https://x.y/)\n".replacingOccurrences(of: "[https://x.y/](https://x.y/)", with: "https://x.y/")] {
            #expect(MarkdownSerializer.serialize(MarkdownParser.parse(md)) == md, Comment(rawValue: md))
        }
        // <https://…> กลายเป็น URL เปล่า (ความหมายเดิม)
        #expect(MarkdownSerializer.serialize(MarkdownParser.parse("<https://x.y>\n")) == "https://x.y\n")
        // ลิงก์ข้อความธรรมดาไม่เปลี่ยน
        #expect(MarkdownSerializer.serialize(MarkdownParser.parse("[https://x.y](https://other.z)\n")) == "[https://x.y](https://other.z)\n")
    }

    // MARK: - snapshot ของแถบ
    func snapBar(_ url: String, name: String, flash: String? = nil) throws {
        _ = NSApplication.shared
        for (tag, ap) in [("aqua", NSAppearance.Name.aqua), ("dark", .darkAqua)] {
            let bar = LinkBarView(url: url)
            bar.appearance = NSAppearance(named: ap)
            if let flash { bar.flash(flash) }
            let size = NSSize(width: max(bar.fittingSize.width, 220), height: LinkBarView.height)
            bar.frame = NSRect(origin: .zero, size: size)
            bar.layoutSubtreeIfNeeded()
            // วางบนพื้นกระดาษของธีมเพื่อดูขอบมน
            let host = NSView(frame: NSRect(x: 0, y: 0, width: size.width + 40, height: size.height + 40))
            host.appearance = NSAppearance(named: ap)
            host.wantsLayer = true
            NSAppearance(named: ap)!.performAsCurrentDrawingAppearance { host.layer?.backgroundColor = Palette.paper.cgColor }
            bar.frame.origin = NSPoint(x: 20, y: 20)
            host.addSubview(bar)
            host.layoutSubtreeIfNeeded()
            let rep = try #require(host.bitmapImageRepForCachingDisplay(in: host.bounds))
            host.cacheDisplay(in: host.bounds, to: rep)
            try #require(rep.representation(using: .png, properties: [:])).write(to: SnapshotDir.url.appendingPathComponent("link-bar-\(name)-\(tag).png"))
            #expect(bar.buttons.count == 4)
            #expect(bar.buttons.map(\.toolTip) == ["Open Link (⌥↩)", "Copy Link Address", "Edit Link… (⌘K)", "Remove Link"])
        }
    }

    @Test func barSnapshots() throws {
        try snapBar("https://example.com/docs/page", name: "short")
        try snapBar("https://example.com/" + String(repeating: "very-long-path/", count: 8) + "end.html?x=1", name: "long")
        try snapBar("notes/missing.md", name: "missing", flash: "File not found")
        try snapBar("mailto:euw@example.com", name: "mailto")
    }

    @Test func barViewTruncatesAndKeepsFullURLInTooltip() {
        let url = "https://example.com/" + String(repeating: "p/", count: 60)
        let bar = LinkBarView(url: url)
        #expect(bar.displayedText.count <= 44 && bar.displayedText.contains("…"))
        #expect(bar.toolTip == nil)
        bar.flash("File not found")
        #expect(bar.displayedText == "File not found")
    }
}
