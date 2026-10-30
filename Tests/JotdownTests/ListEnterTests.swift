import Testing
import AppKit
@testable import Jotdown

/// Enter/⇧Enter/Backspace/Tab ในลิสต์และ quote ตามสเปก "เหมือน Notion" (ข้อ 1–10)
@MainActor @Suite(.serialized) struct ListEnterTests {
    @Test func enterAtEndKeepsKindLevelAndDropsInlineStyle() {
        let (doc, vc) = makeEditor("- **bold**\n")
        vc.textView.select(doc.textStorage.length)
        vc.textView.type("\nx")
        #expect(doc.currentMarkdown == "- **bold**\n- x\n")
    }

    @Test func orderedRenumbersFollowingItems() {
        let (doc, vc) = makeEditor("1. a\n2. b\n")
        vc.textView.select(1)
        vc.textView.type("\nn")
        #expect(doc.currentMarkdown == "1. a\n2. n\n3. b\n")
    }

    @Test func checkedTaskGivesUncheckedNewItem() {
        let (doc, vc) = makeEditor("- [x] a\n")
        vc.textView.select(1)
        vc.textView.type("\nn")
        #expect(doc.currentMarkdown == "- [x] a\n- [ ] n\n")
    }

    @Test func nestedKeepsLevel() {
        let (doc, vc) = makeEditor("- a\n  - b\n")
        vc.textView.select(doc.textStorage.length)
        vc.textView.type("\nc")
        #expect(doc.currentMarkdown == "- a\n  - b\n  - c\n")
    }

    @Test func enterInMiddleSplitsAndKeepsInlineStyle() {
        let (doc, vc) = makeEditor("- foobar\n")
        vc.textView.select(3)
        vc.textView.type("\nX")
        #expect(doc.currentMarkdown == "- foo\n- Xbar\n")
        let (d2, v2) = makeEditor("- foo **barbaz**\n")
        v2.textView.select(7)
        v2.textView.insertNewline(nil)
        #expect(v2.textView.selectedRange().location == 8)         // ต้นรายการใหม่
        #expect(d2.currentMarkdown == "- foo **bar**\n- **baz**\n")
    }

    @Test func enterAtStartInsertsEmptyItemAbove() {
        let (doc, vc) = makeEditor("- abc\n")
        vc.textView.select(0)
        vc.textView.type("\nX")
        #expect(doc.currentMarkdown == "-\n- Xabc\n")
    }

    @Test func enterInEmptyNestedItemOutdents() {
        let (doc, vc) = makeEditor("- a\n  - b\n\nz\n")
        let tv = vc.textView!
        tv.select(tv.nsString.range(of: "b").location + 1)
        tv.type("\u{8}\n")
        #expect(doc.currentMarkdown == "- a\n-\n\nz\n")
    }

    @Test func enterInEmptyTopLevelItemExitsList() {
        let (doc, vc) = makeEditor("- a\n\nz\n")
        vc.textView.select(1)
        vc.textView.type("\n\np")
        #expect(doc.currentMarkdown == "- a\n\np\n\nz\n")
    }

    @Test func shiftEnterIsSoftBreakInListAndQuote() {
        let (doc, vc) = makeEditor("- ab\n")
        vc.textView.select(2)
        vc.textView.insertLineBreak(nil)
        vc.textView.type("c")
        #expect(doc.currentMarkdown == "- ab\n  c\n")
        #expect(doc.textStorage.string.components(separatedBy: "\n").count == 1)   // ยังเป็นรายการเดียว
        let (d2, v2) = makeEditor("> a\n")
        v2.textView.select(1)
        v2.textView.insertNewlineIgnoringFieldEditor(nil)
        v2.textView.type("b")
        #expect(d2.currentMarkdown == "> a\n> b\n")
    }

    @Test func backspaceAtStartOfItem() {
        let (doc, vc) = makeEditor("x\n\n- abc\n")
        vc.textView.select(doc.textStorage.length - 3)
        vc.textView.type("\u{8}")
        #expect(doc.currentMarkdown == "x\n\nabc\n")
        vc.textView.type("\u{8}")
        #expect(doc.currentMarkdown == "xabc\n")
        // รายการซ้อน: ลดระดับก่อน (markdown เก็บระยะเยื้องของย่อหน้าไม่ได้) แล้วค่อยเป็นย่อหน้า
        let (d2, v2) = makeEditor("- a\n  - b\n")
        v2.textView.select(d2.textStorage.length - 1)
        v2.textView.type("\u{8}")
        #expect(d2.currentMarkdown == "- a\n- b\n")
        v2.textView.type("\u{8}")
        #expect(d2.currentMarkdown == "- a\n\nb\n")
    }

    @Test func quoteEnterAndExit() {
        let (doc, vc) = makeEditor("> a\n")
        vc.textView.select(1)
        vc.textView.type("\nb")
        #expect(doc.currentMarkdown == "> a\n>\n> b\n")
        let (d2, v2) = makeEditor("> a\n\nz\n")
        v2.textView.select(1)
        v2.textView.type("\n\np")
        #expect(d2.currentMarkdown == "> a\n\np\n\nz\n")
    }

    @Test func tabAnywhereInItemKeepsCaretAndFirstItemIsNoop() {
        let (doc, vc) = makeEditor("- a\n- bcd\n")
        let tv = vc.textView!
        tv.select(tv.nsString.range(of: "bcd").location + 1)
        tv.insertTab(nil)
        #expect(tv.selectedRange().location == tv.nsString.range(of: "bcd").location + 1)
        tv.type("X")
        #expect(doc.currentMarkdown == "- a\n  - bXcd\n")
        tv.insertBacktab(nil)
        #expect(doc.currentMarkdown == "- a\n- bXcd\n")
        let (d2, v2) = makeEditor("- a\n")
        v2.textView.select(1)
        v2.textView.insertTab(nil)
        #expect(d2.currentMarkdown == "- a\n")
        #expect(!d2.textStorage.string.contains("\t"))
    }

    @Test func undoRevertsEachEnterExactly() {
        let (doc, vc) = makeEditor("- a\n", explicitUndo: true)
        let tv = vc.textView!
        tv.select(1)
        tv.type("\n")
        let afterOne = doc.currentMarkdown
        tv.type("b\n")
        doc.undoManager?.undo()
        #expect(afterOne == "- a\n")                    // รายการว่างท้ายเอกสารยังไม่ถูกเขียนลงไฟล์
        #expect(doc.currentMarkdown == "- a\n- b\n")   // ⌘Z ย้อนเฉพาะ Enter ที่สอง (b ยังอยู่)
        let (d3, v3) = makeEditor("- foobar\n", explicitUndo: true)
        v3.textView.select(3)
        v3.textView.type("\n")
        d3.undoManager?.undo()
        #expect(d3.currentMarkdown == "- foobar\n")
    }

    // MARK: - เครื่องหมายลิสต์บนบรรทัดว่าง
    func markerY(_ tv: EditorTextView, _ loc: Int) -> CGFloat? {
        let lm = tv.layoutManager as! EditorLayoutManager
        lm.ensureLayout(for: tv.textContainer!)
        guard let m = lm.markerRect(forParagraphAt: loc) else { return nil }
        let line: NSRect
        if loc == tv.nsString.length { line = lm.extraLineFragmentUsedRect }
        else { line = lm.lineFragmentUsedRect(forGlyphAt: lm.glyphIndexForCharacter(at: loc), effectiveRange: nil) }
        return m.minY - line.minY
    }

    @Test func enterAtEndOfLastListItemShowsMarkerRightAway() {
        for md in ["1. one\n2. two\n", "- one\n- two\n", "- [ ] one\n- [ ] two\n"] {
            let (_, vc) = makeEditor(md)
            let tv = vc.textView!
            let normal = markerY(tv, 0)
            tv.select(tv.nsString.length)
            tv.event { tv.insertNewline(nil) }
            #expect(tv.nsString.length > 0 && tv.selectedRange().location == tv.nsString.length)
            #expect(markerY(tv, tv.nsString.length) != nil, Comment(rawValue: md))
            #expect(markerY(tv, tv.nsString.length) == normal, Comment(rawValue: md))
        }
    }

    @Test func emptyListItemInMiddleKeepsMarkerOnBaseline() {
        let (_, vc) = makeEditor("1. one\n2. two\n3. three\n")
        let tv = vc.textView!
        let normal = markerY(tv, 0)
        tv.select(tv.nsString.range(of: "two").location + 3)
        tv.event { tv.insertNewline(nil) }
        let empty = tv.selectedRange().location
        #expect(tv.nsString.character(at: empty) == 0x0A)
        #expect(markerY(tv, empty) == normal)
    }

    // MARK: - Backspace/Delete รวมย่อหน้า: เคอร์เซอร์อยู่ที่รอยต่อ
    @Test func backspaceOnEmptyLineAfterListPutsCaretAtEndOfPreviousItem() {
        let (doc, vc) = makeEditor("- one\n  - Document\n- Manual\n")
        let tv = vc.textView!
        tv.select(NSMaxRange(tv.nsString.range(of: "Document")))
        tv.event { tv.insertNewline(nil) }
        for _ in 0..<3 { tv.event { tv.deleteBackward(nil) } }
        #expect(doc.currentMarkdown == "- one\n  - Document\n- Manual\n")
        #expect(tv.selectedRange().location == NSMaxRange(tv.nsString.range(of: "Document")))
    }

    @Test func backspaceMergeKeepsCaretAtJoin() {
        let (doc, vc) = makeEditor("- Document\n\nabc\n")
        let tv = vc.textView!
        tv.select(tv.nsString.range(of: "abc").location)
        tv.event { tv.deleteBackward(nil) }
        #expect(doc.currentMarkdown == "- Documentabc\n")
        #expect(tv.selectedRange().location == tv.nsString.range(of: "abc").location)
    }

    @Test func forwardDeleteMergeKeepsCaret() {
        let (doc, vc) = makeEditor("- Document\n\nabc\n")
        let tv = vc.textView!
        let end = NSMaxRange(tv.nsString.range(of: "Document"))
        tv.select(end)
        tv.event { tv.deleteForward(nil) }
        #expect(doc.currentMarkdown == "- Documentabc\n")
        #expect(tv.selectedRange().location == end)
    }

    @Test func enterInSublistKeepsFollowingItems() {
        let (doc, vc) = makeEditor("- a\n  - b\n    - c\n  - Document\n- Manual\n")
        let tv = vc.textView!
        tv.select(NSMaxRange(tv.nsString.range(of: "c")))
        tv.event { tv.insertNewline(nil) }
        tv.type("d")
        #expect(doc.currentMarkdown == "- a\n  - b\n    - c\n    - d\n  - Document\n- Manual\n")
    }
}
