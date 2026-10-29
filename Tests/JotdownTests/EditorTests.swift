import Testing
import AppKit
@testable import Jotdown

@MainActor
func makeEditor(_ md: String = "", explicitUndo: Bool = false) -> (JotdownDocument, EditorViewController) {
    _ = NSApplication.shared
    let doc = JotdownDocument()
    // explicitUndo: แยกกลุ่ม undo ต่อการกดคีย์เองแบบ run loop จริง (ไม่มี run loop ในเทสต์)
    if explicitUndo { doc.undoManager?.groupsByEvent = false }
    if !md.isEmpty { doc.load(markdown: md) }
    let vc = EditorViewController(document: doc)
    _ = vc.view
    vc.textView.setSelectedRange(NSRange(location: doc.textStorage.length, length: 0))
    vc.textView.syncTypingAttributes()
    return (doc, vc)
}

extension EditorTextView {
    /// จำลองการพิมพ์ทีละตัวอักษร ("\n" = Enter, "\t" = Tab, "\u{8}" = Backspace)
    func type(_ s: String) {
        // จำลองเหตุการณ์คีย์บอร์ด: การกดแต่ละคีย์ = กลุ่ม undo หนึ่งกลุ่ม (เหมือน run loop จริง)
        let um = undoManager
        let explicit = um?.groupsByEvent == false
        for ch in s {
            if explicit { um?.beginUndoGrouping() }
            defer { if explicit { um?.endUndoGrouping() } }
            switch ch {
            case "\n": insertNewline(nil)
            case "\t": insertTab(nil)
            case "\u{8}": deleteBackward(nil)
            default: insertText(String(ch), replacementRange: selectedRange())
            }
        }
    }
    func event(_ body: () -> Void) {
        let um = undoManager
        um?.beginUndoGrouping(); body(); um?.endUndoGrouping()
    }
    func select(_ loc: Int, _ len: Int = 0) { setSelectedRange(NSRange(location: loc, length: len)); syncTypingAttributes() }
}

@MainActor @Suite(.serialized) struct EditorTests {
    @Test func enterAtEndOfHeadingStartsBodyParagraph() {
        let (doc, vc) = makeEditor("# หัวข้อ\n")
        vc.textView.type("\nเนื้อ")
        #expect(doc.currentMarkdown == "# หัวข้อ\n\nเนื้อ\n")
        #expect(doc.textStorage.blockKind(at: doc.textStorage.length - 1) == .paragraph)
    }

    @Test func enterAtEndOfHeadingBeforeAnotherParagraph() {
        let (doc, vc) = makeEditor("# หัวข้อ\n\nเนื้อ\n")
        vc.textView.select(6)
        vc.textView.type("\nใหม่")
        #expect(doc.currentMarkdown == "# หัวข้อ\n\nใหม่\n\nเนื้อ\n")
    }

    @Test func typingAttributesFollowBlock() {
        let (_, vc) = makeEditor("# หัวข้อ\n\nเนื้อ\n")
        let tv = vc.textView!
        tv.select(3)
        #expect((tv.typingAttributes[.font] as? NSFont)?.fontName == Theme.font(for: .heading(1)).fontName)
        tv.select(7)
        #expect((tv.typingAttributes[.font] as? NSFont)?.fontName == Theme.font(for: .paragraph).fontName)
    }

    // MARK: - พิมพ์ลัดบล็อก
    @Test(arguments: [
        ("# x", "# x\n"), ("## x", "## x\n"), ("###### x", "###### x\n"), ("- x", "- x\n"), ("* x", "- x\n"), ("+ x", "- x\n"),
        ("1. x", "1. x\n"), ("[] x", "- [ ] x\n"), ("[ ] x", "- [ ] x\n"), ("[x] x", "- [x] x\n"), ("- [ ] x", "- [ ] x\n"),
        ("- [x] x", "- [x] x\n"), ("> x", "> x\n"),
    ]) func blockShortcuts(typed: String, md: String) {
        let (doc, vc) = makeEditor()
        vc.textView.type(typed)
        #expect(doc.currentMarkdown == md, "พิมพ์ \(typed.debugDescription)")
        #expect(!doc.textStorage.string.contains("#") && !doc.textStorage.string.contains("["))
    }

    @Test func shortcutOnlyAtStartOfPlainParagraph() {
        let (doc, vc) = makeEditor()
        vc.textView.type("abc # x")
        #expect(doc.textStorage.blockKind(at: 0) == .paragraph)
        #expect(doc.textStorage.string == "abc # x")
    }

    @Test func shortcutUndoRestoresTypedText() {
        let (doc, vc) = makeEditor(explicitUndo: true)
        vc.textView.type("# ")
        #expect(doc.textStorage.blockKind(at: 0) == .paragraph || doc.textStorage.length == 0)
        #expect(doc.textStorage.string == "")
        vc.textView.type("x")
        #expect(doc.textStorage.blockKind(at: 0) == .heading(1))
        doc.undoManager?.undo()          // ย้อน "x"
        doc.undoManager?.undo()          // ย้อนการแปลงเป็นหัวข้อ => "# "
        #expect(doc.textStorage.string == "# ")
        #expect(doc.textStorage.blockKind(at: 0) == .paragraph)
    }

    @Test func shortcutUndoSingleStep() {
        let (doc, vc) = makeEditor("ก\n", explicitUndo: true)
        vc.textView.select(doc.textStorage.length)
        vc.textView.type("\n# ")
        doc.undoManager?.undo()
        #expect(doc.textStorage.string.hasSuffix("# "), "ได้: \(doc.textStorage.string.debugDescription)")
        #expect(doc.textStorage.blockKind(at: doc.textStorage.length - 1) == .paragraph)
    }

    @Test func fencedCodeBlock() {
        let (doc, vc) = makeEditor()
        vc.textView.type("```swift\nlet x\ny")
        #expect(doc.currentMarkdown == "```swift\nlet x\ny\n```\n")
        #expect(doc.textStorage.blockKind(at: 0) == .codeBlock("swift"))
        vc.textView.type("\n\nafter")
        #expect(doc.currentMarkdown == "```swift\nlet x\ny\n```\n\nafter\n")
    }

    @Test func codeBlockHasNoShortcutsOrInline() {
        let (doc, vc) = makeEditor()
        vc.textView.type("```\n# **x** - ")
        #expect(doc.textStorage.string == "# **x** - ")
        #expect(doc.currentMarkdown == "```\n# **x** - \n```\n")
    }

    @Test func codeBlockExitWithCommandEnter() {
        let (doc, vc) = makeEditor()
        vc.textView.type("```\nx")
        vc.textView.jotToggleCheckOrExit(nil)
        vc.textView.type("y")
        #expect(doc.currentMarkdown == "```\nx\n```\n\ny\n")
    }

    @Test func thematicBreak() {
        let (doc, vc) = makeEditor()
        vc.textView.type("---\nx")
        #expect(doc.currentMarkdown == "---\n\nx\n")
        #expect(doc.textStorage.blockKind(at: 0) == .thematicBreak)
        // พิมพ์ทับเส้นคั่นไม่ได้
        vc.textView.select(1)
        vc.textView.type("zzz")
        #expect(doc.currentMarkdown == "---\n\nx\n")
        // Backspace จากย่อหน้าถัดไปลบเส้นคั่น
        vc.textView.select(2)
        vc.textView.type("\u{8}")
        #expect(doc.currentMarkdown == "x\n")
    }

    // MARK: - พิมพ์ลัด inline
    @Test(arguments: [("**ab**", "**ab**\n", InlineStyle.bold), ("*ab*", "*ab*\n", .italic), ("_ab_", "*ab*\n", .italic),
                      ("`ab`", "`ab`\n", .code), ("~~ab~~", "~~ab~~\n", .strike)])
    func inlineShortcuts(typed: String, md: String, flag: InlineStyle) {
        let (doc, vc) = makeEditor()
        vc.textView.type(typed)
        #expect(doc.textStorage.string == "ab")
        #expect(doc.textStorage.inlineStyle(at: 0).contains(flag))
        #expect(doc.currentMarkdown == md)
        vc.textView.type(" c")
        #expect(doc.textStorage.string == "ab c")
        #expect(!doc.textStorage.inlineStyle(at: 3).contains(flag), "พิมพ์ต่อต้องเป็นตัวธรรมดา")
    }

    @Test func inlineShortcutMidSentenceAndUndo() {
        let (doc, vc) = makeEditor(explicitUndo: true)
        vc.textView.type("คำ **หนา**")
        #expect(doc.currentMarkdown == "คำ **หนา**\n")
        doc.undoManager?.undo()
        #expect(doc.textStorage.string == "คำ **หนา**")
        #expect(doc.currentMarkdown == "คำ \\*\\*หนา\\*\\*\n")
    }

    @Test func noInlineShortcutForSpacedStars() {
        let (doc, vc) = makeEditor()
        vc.textView.type("2 * 3 * 4")
        #expect(doc.textStorage.string == "2 * 3 * 4")
    }

    // MARK: - Enter / Backspace / Tab ในลิสต์
    @Test func enterInListsAndExit() {
        let (doc, vc) = makeEditor()
        vc.textView.type("- a\nb\n\np")
        #expect(doc.currentMarkdown == "- a\n- b\n\np\n")
    }

    @Test func orderedNumbering() {
        let (doc, vc) = makeEditor()
        vc.textView.type("1. a\nb\nc")
        #expect(doc.currentMarkdown == "1. a\n2. b\n3. c\n")
    }

    @Test func nestedWithTabAndBacktab() {
        let (doc, vc) = makeEditor()
        vc.textView.type("- a\n\tb\nc\n\nd")           // Enter ในรายการว่างระดับ 1 = ลดระดับ
        #expect(doc.currentMarkdown == "- a\n  - b\n  - c\n- d\n")
        vc.textView.insertBacktab(nil)                  // d อยู่ระดับ 0 อยู่แล้ว
        #expect(doc.currentMarkdown == "- a\n  - b\n  - c\n- d\n")
        vc.textView.select(doc.textStorage.length - 1)
        vc.textView.insertTab(nil)
        #expect(doc.currentMarkdown == "- a\n  - b\n  - c\n  - d\n")
    }

    @Test func firstItemCannotIndent() {
        let (doc, vc) = makeEditor()
        vc.textView.type("- a")
        vc.textView.insertTab(nil)
        #expect(doc.currentMarkdown == "- a\n")
    }

    @Test func orderedNestedNumbers() {
        let (doc, vc) = makeEditor()
        vc.textView.type("1. a\n\tb\nc\n")
        #expect(doc.currentMarkdown.hasPrefix("1. a\n   1. b\n"))
    }

    @Test func taskEnterGivesUncheckedAndToggle() {
        let (doc, vc) = makeEditor()
        vc.textView.type("[x] a\nb")
        #expect(doc.currentMarkdown == "- [x] a\n- [ ] b\n")
        vc.textView.select(0)
        vc.textView.jotToggleCheckOrExit(nil)
        #expect(doc.currentMarkdown == "- [ ] a\n- [ ] b\n")
        vc.textView.jotToggleCheckOrExit(nil)
        #expect(doc.currentMarkdown == "- [x] a\n- [ ] b\n")
        // ข้อความของรายการที่ติ๊กแล้วถูกขีดฆ่าและจาง
        #expect(doc.textStorage.attribute(.strikethroughStyle, at: 0, effectiveRange: nil) != nil)
        // คลิกกล่อง
        vc.textView.toggleTaskChecked(at: 0)
        #expect(doc.currentMarkdown == "- [ ] a\n- [ ] b\n")
    }

    @Test func quoteEnterAndExit() {
        let (doc, vc) = makeEditor()
        vc.textView.type("> a\nb\n\nc")
        #expect(doc.currentMarkdown == "> a\n>\n> b\n\nc\n")
    }

    @Test(arguments: ["# หัวข้อ", "- รายการ", "1. รายการ", "[ ] งาน", "> อ้างอิง"])
    func backspaceAtStartBecomesParagraph(typed: String) {
        let (doc, vc) = makeEditor()
        vc.textView.type(typed)
        let text = doc.textStorage.string
        vc.textView.select(0)
        vc.textView.type("\u{8}")
        #expect(doc.textStorage.string == text, "ห้ามลบข้อความ")
        #expect(doc.textStorage.blockKind(at: 0) == .paragraph)
        #expect(doc.currentMarkdown.hasPrefix(text.replacingOccurrences(of: "[", with: "\\[")))
    }

    @Test func backspaceInEmptyItemAtEnd() {
        let (doc, vc) = makeEditor()
        vc.textView.type("- a\nb")
        vc.textView.type("\u{8}\u{8}")      // ลบ b แล้ว Backspace ต้นรายการว่าง => ย่อหน้า
        vc.textView.type("z")
        #expect(doc.currentMarkdown == "- a\n\nz\n")
    }

    // MARK: - คีย์ลัดจัดรูปแบบ
    @Test func toggleInlineOnSelection() {
        let (doc, vc) = makeEditor("abcdef\n")
        let tv = vc.textView!
        tv.select(2, 2)
        tv.toggleInline(.bold)
        #expect(doc.currentMarkdown == "ab**cd**ef\n")
        #expect(tv.selectedRange() == NSRange(location: 2, length: 2))
        tv.toggleInline(.bold)
        #expect(doc.currentMarkdown == "abcdef\n")
        // บางส่วนมีอยู่แล้ว = ใส่ให้ทั้งช่วง
        tv.select(2, 1); tv.toggleInline(.bold)
        tv.select(1, 4); tv.toggleInline(.bold)
        #expect(doc.currentMarkdown == "a**bcde**f\n")
        tv.toggleInline(.bold)
        #expect(doc.currentMarkdown == "abcdef\n")
        tv.select(0, 6); tv.toggleInline(.italic); tv.toggleInline(.strike); tv.toggleInline(.code)
        #expect(doc.currentMarkdown == "~~*`abcdef`*~~\n" || doc.currentMarkdown == "*~~`abcdef`~~*\n", "ได้ \(doc.currentMarkdown)")
    }

    @Test func toggleInlineAcrossParagraphsSkipsCode() {
        let (doc, vc) = makeEditor("ab\n\n```\ncd\n```\n\nef\n")
        let tv = vc.textView!
        tv.select(0, doc.textStorage.length)
        tv.toggleInline(.bold)
        #expect(doc.currentMarkdown == "**ab**\n\n```\ncd\n```\n\n**ef**\n")
    }

    @Test func toggleInlineTypingAttributes() {
        let (doc, vc) = makeEditor()
        let tv = vc.textView!
        tv.type("a ")
        tv.toggleInline(.bold)
        tv.type("b")
        tv.toggleInline(.bold)
        tv.type(" c")
        #expect(doc.currentMarkdown == "a **b** c\n")
    }

    @Test func formattingUndo() {
        let (doc, vc) = makeEditor("abc\n")
        vc.textView.select(0, 3)
        vc.textView.toggleInline(.bold)
        #expect(doc.currentMarkdown == "**abc**\n")
        doc.undoManager?.undo()
        #expect(doc.currentMarkdown == "abc\n")
        doc.undoManager?.redo()
        #expect(doc.currentMarkdown == "**abc**\n")
    }

    @Test func blockMenuActions() {
        let (doc, vc) = makeEditor("abc\n")
        let tv = vc.textView!
        tv.select(1)
        for l in 1...6 {
            tv.setHeading(l)
            #expect(doc.currentMarkdown == String(repeating: "#", count: l) + " abc\n")
        }
        tv.setHeading(6); #expect(doc.currentMarkdown == "abc\n")
        tv.jotToggleBullet(nil); #expect(doc.currentMarkdown == "- abc\n")
        tv.jotToggleOrdered(nil); #expect(doc.currentMarkdown == "1. abc\n")
        tv.jotToggleTask(nil); #expect(doc.currentMarkdown == "- [ ] abc\n")
        tv.jotToggleTask(nil); #expect(doc.currentMarkdown == "abc\n")
        tv.jotToggleQuote(nil); #expect(doc.currentMarkdown == "> abc\n")
        tv.jotToggleQuote(nil); #expect(doc.currentMarkdown == "abc\n")
        tv.jotToggleCodeBlock(nil); #expect(doc.currentMarkdown == "```\nabc\n```\n")
        tv.jotToggleCodeBlock(nil); #expect(doc.currentMarkdown == "abc\n")
        tv.setHeading(2); tv.jotSetParagraph(nil); #expect(doc.currentMarkdown == "abc\n")
    }

    @Test func blockActionsOnMultipleParagraphs() {
        let (doc, vc) = makeEditor("a\n\nb\n\nc\n")
        vc.textView.select(0, doc.textStorage.length)
        vc.textView.jotToggleBullet(nil)
        #expect(doc.currentMarkdown == "- a\n- b\n- c\n")
    }

    @Test func linkApplyAndRemove() {
        let (doc, vc) = makeEditor("abc def\n")
        let tv = vc.textView!
        tv.applyLink("https://x.y", in: NSRange(location: 4, length: 3))
        #expect(doc.currentMarkdown == "abc [def](https://x.y)\n")
        #expect(doc.textStorage.attribute(.underlineStyle, at: 5, effectiveRange: nil) != nil)
        tv.select(5)
        #expect(tv.linkRangeAtSelection()?.1 == "https://x.y")
        #expect(tv.linkRangeAtSelection()?.0 == NSRange(location: 4, length: 3))
        tv.applyLink(nil, in: NSRange(location: 4, length: 3))
        #expect(doc.currentMarkdown == "abc def\n")
        // พิมพ์ต่อท้ายลิงก์ไม่ขยายลิงก์
        tv.applyLink("https://x.y", in: NSRange(location: 4, length: 3))
        tv.select(7); tv.type("!")
        #expect(doc.currentMarkdown == "abc [def](https://x.y)!\n")
    }

    @Test func menuHasAllFormatItems() {
        _ = NSApplication.shared
        let menu = MainMenu.build()
        let format = menu.items.first { $0.title == "Format" }!.submenu!
        func key(_ title: String) -> (String, NSEvent.ModifierFlags)? {
            guard let i = format.items.first(where: { $0.title == title }) else { return nil }
            return (i.keyEquivalent, i.keyEquivalentModifierMask)
        }
        #expect(key("Bold")?.0 == "b"); #expect(key("Bold")?.1 == [.command])
        #expect(key("Italic")?.0 == "i")
        #expect(key("Strikethrough")?.1 == [.command, .shift])
        #expect(key("Inline Code")?.0 == "e")
        #expect(key("Link…")?.0 == "k")
        #expect(key("Paragraph")?.0 == "0")
        for l in 1...6 { #expect(key("Heading \(l)")?.0 == "\(l)"); #expect(key("Heading \(l)")?.1 == [.command, .option]) }
        #expect(key("Bulleted List")?.0 == "8"); #expect(key("Numbered List")?.0 == "7"); #expect(key("Checklist")?.0 == "9")
        #expect(key("Quote")?.0 == "."); #expect(key("Code Block")?.1 == [.command, .option])
        #expect(format.items.contains { $0.keyEquivalent == "\r" })
        // ⌘U ต้องไม่ถูกใช้
        #expect(!menu.items.compactMap(\.submenu).flatMap(\.items).contains { $0.keyEquivalent == "u" && $0.keyEquivalentModifierMask == [.command] })
        // ⌘E ซ้ำกับค้นหาไม่ได้
        let es = menu.items.compactMap(\.submenu).flatMap(\.items).filter { $0.keyEquivalent == "e" && $0.keyEquivalentModifierMask == [.command] }
        #expect(es.count == 1)
    }

    @Test func menuStateFollowsCaret() {
        let (_, vc) = makeEditor("ab **cd** ef\n\n# หัวข้อ\n")
        let tv = vc.textView!
        let bold = NSMenuItem(title: "b", action: #selector(EditorTextView.jotToggleBold(_:)), keyEquivalent: "b")
        tv.select(4)
        #expect(tv.validateMenuItem(bold)); #expect(bold.state == .on)
        tv.select(0)
        _ = tv.validateMenuItem(bold); #expect(bold.state == .off)
        tv.select(0, 2); _ = tv.validateMenuItem(bold); #expect(bold.state == .off)
        tv.select(3, 2); _ = tv.validateMenuItem(bold); #expect(bold.state == .on)
        let h1 = NSMenuItem(title: "h", action: #selector(EditorTextView.jotSetHeading(_:)), keyEquivalent: "1"); h1.tag = 1
        tv.select(15); _ = tv.validateMenuItem(h1); #expect(h1.state == .on)
        tv.select(0); _ = tv.validateMenuItem(h1); #expect(h1.state == .off)
    }

    // MARK: - clipboard
    @Test func pasteMarkdown() {
        let (doc, vc) = makeEditor("ก\n")
        let pb = NSPasteboard.withUniqueName()
        pb.clearContents(); pb.setString("# หัวข้อ\n\nข้อความ **หนา** และ `โค้ด`\n\n- ข้อ 1\n- ข้อ 2\n", forType: .string)
        vc.textView.select(doc.textStorage.length)
        vc.textView.type("\n")
        vc.textView.pasteFrom(pb)
        #expect(doc.currentMarkdown == "ก\n\n# หัวข้อ\n\nข้อความ **หนา** และ `โค้ด`\n\n- ข้อ 1\n- ข้อ 2\n")
        #expect(!doc.textStorage.string.contains("**"))
    }

    @Test func pasteMarkdownIntoMiddleSplitsParagraph() {
        let (doc, vc) = makeEditor("abcd\n")
        let pb = NSPasteboard.withUniqueName()
        pb.clearContents(); pb.setString("## H\n\n- x\n", forType: .string)
        vc.textView.select(2)
        vc.textView.pasteFrom(pb)
        #expect(doc.currentMarkdown == "ab\n\n## H\n\n- x\n\ncd\n")
    }

    @Test func pasteInlineMarkdownStaysInline() {
        let (doc, vc) = makeEditor("ab\n")
        let pb = NSPasteboard.withUniqueName()
        pb.clearContents(); pb.setString("**x**", forType: .string)
        vc.textView.select(1)
        vc.textView.pasteFrom(pb)
        #expect(doc.currentMarkdown == "a**x**b\n")
    }

    @Test func pasteHTML() {
        let (doc, vc) = makeEditor()
        let pb = NSPasteboard.withUniqueName()
        let html = "<html><body><h2>หัวข้อ</h2><p>ข้อความ <b>หนา</b> <i>เอียง</i> <a href=\"https://x.y\">ลิงก์</a> &amp; <code>โค้ด</code></p><ul><li>หนึ่ง</li><li>สอง</li></ul><ol><li>ก</li><li>ข</li></ol><blockquote><p>อ้างอิง</p></blockquote><pre><code class=\"language-js\">let a = 1;\nlet b = 2;</code></pre><hr><p>จบ<br>บรรทัดใหม่</p></body></html>"
        pb.clearContents(); pb.setString(html, forType: .html); pb.setString("หัวข้อ ข้อความ หนา เอียง ลิงก์", forType: .string)
        vc.textView.pasteFrom(pb)
        #expect(doc.currentMarkdown == "## หัวข้อ\n\nข้อความ **หนา** *เอียง* [ลิงก์](https://x.y) & `โค้ด`\n\n- หนึ่ง\n- สอง\n\n1. ก\n2. ข\n\n> อ้างอิง\n\n```js\nlet a = 1;\nlet b = 2;\n```\n\n---\n\nจบ\nบรรทัดใหม่\n")
    }

    @Test func pasteHTMLWithSpanStyles() {
        let blocks = HTMLImporter.blocks(from: "<meta charset='utf-8'><b style=\"font-weight:normal;\" id=\"docs\"><p><span style=\"font-weight:700\">หนา</span><span> ปกติ</span><span style=\"font-style:italic\"> เอียง</span></p></b>")
        #expect(MarkdownSerializer.serialize(blocks) == "**หนา** ปกติ *เอียง*\n")
    }

    @Test func pasteURLOverSelectionMakesLink() {
        let (doc, vc) = makeEditor("ดูที่นี่\n")
        let pb = NSPasteboard.withUniqueName()
        pb.clearContents(); pb.setString("https://example.com/a", forType: .string)
        vc.textView.select(0, 5)
        vc.textView.pasteFrom(pb)
        #expect(doc.currentMarkdown == "[ดูที่](https://example.com/a)นี่\n")
    }

    @Test func pastePlainTextStyleFollowsParagraph() {
        let (doc, vc) = makeEditor("# หัวข้อ\n")
        let pb = NSPasteboard.withUniqueName()
        pb.clearContents(); pb.writeObjects([NSAttributedString(string: "ตัวหนา", attributes: [.font: NSFont.boldSystemFont(ofSize: 40)])])
        vc.textView.select(3)
        vc.textView.pasteFrom(pb)
        let f = doc.textStorage.attribute(.font, at: 3, effectiveRange: nil) as? NSFont
        #expect((f?.pointSize ?? 0) <= 28)
        #expect(doc.textStorage.string.contains("ตัวหนา"))
    }

    @Test func pasteMultilinePlainInCodeBlock() {
        let (doc, vc) = makeEditor()
        vc.textView.type("```\n")
        let pb = NSPasteboard.withUniqueName()
        pb.clearContents(); pb.setString("a\nb\n\nc", forType: .string)
        vc.textView.pasteFrom(pb)
        #expect(doc.currentMarkdown == "```\na\nb\n\nc\n```\n")
    }

    @Test func copyPutsMarkdownAndRTF() {
        let (_, vc) = makeEditor("ab **cd** ef\n\n- x\n- y\n")
        let tv = vc.textView!
        tv.select(3, 2)
        tv.copy(nil)
        let pb = NSPasteboard.general
        #expect(pb.string(forType: .string) == "**cd**")
        #expect(pb.data(forType: .rtf) != nil)
        tv.select(0, tv.storage.length)
        tv.copy(nil)
        #expect(pb.string(forType: .string) == "ab **cd** ef\n\n- x\n- y")
        // วางกลับได้เหมือนเดิม
        let (doc2, vc2) = makeEditor()
        vc2.textView.paste(nil)
        #expect(doc2.currentMarkdown == "ab **cd** ef\n\n- x\n- y\n")
    }

    // MARK: - ความเร็ว
    @Test func largeDocumentIsFast() {
        var md = ""
        for i in 0..<1000 {
            md += "## หัวข้อที่ \(i)\n\nย่อหน้า **หนา** และ *เอียง* และ `โค้ด` [ลิงก์](https://example.com/\(i)) ข้อความภาษาไทยยาว ๆ เพื่อทดสอบ\nบรรทัดสอง\n\n- รายการ \(i)\n  - ซ้อน\n- [ ] งาน\n\n"
        }
        let lines = md.split(separator: "\n", omittingEmptySubsequences: false).count
        #expect(lines >= 5000)
        let t0 = Date()
        let a = MarkdownParser.parse(md)
        let parse = Date().timeIntervalSince(t0)
        #expect(parse < 1.5, "parse \(lines) บรรทัด ใช้ \(parse)s")
        let (doc, vc) = makeEditor()
        let t1 = Date()
        doc.load(markdown: md)
        let load = Date().timeIntervalSince(t1)
        #expect(load < 2.0, "load ใช้ \(load)s")
        // พิมพ์กลางเอกสาร: ต้องไม่ re-parse ทั้งเอกสาร
        let tv = vc.textView!
        tv.select(a.length / 2)
        let t2 = Date()
        for _ in 0..<20 { tv.type("ก") }
        let typing = Date().timeIntervalSince(t2) / 20
        #expect(typing < 0.05, "พิมพ์ 1 ตัวอักษรใช้ \(typing)s")
        let t3 = Date()
        let out = doc.currentMarkdown
        let ser = Date().timeIntervalSince(t3)
        #expect(ser < 1.5, "serialize ใช้ \(ser)s")
        #expect(out.count > md.count / 2)
    }
}
