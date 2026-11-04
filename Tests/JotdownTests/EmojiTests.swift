import Testing
import AppKit
@testable import Jotdown

/// อีโมจิใช้ฟอนต์สำรอง (Apple Color Emoji) ที่ระบบใส่ให้เอง — restyle ต้องไม่รีเซ็ตฟอนต์นั้นทุกครั้งที่พิมพ์
@MainActor @Suite(.serialized) struct EmojiTests {
    @Test func typingInEarlierLineOfItemWithEmojiKeepsCaret() {
        let (doc, vc) = makeEditor("- one\n- two\u{2028}39 ✅\n- three\u{2028}29\n")
        let tv = vc.textView!
        let start = tv.nsString.range(of: "two").location + 3
        tv.select(start)
        tv.type("ab")
        #expect(tv.selectedRange().location == start + 2)
        #expect(doc.currentMarkdown.contains("twoab"))
    }

    @Test func typingAfterEmojiLineInSameItemKeepsCaret() {
        let (_, vc) = makeEditor("- url\u{2028}39 ✅\n- next\n")
        let tv = vc.textView!
        let start = tv.nsString.range(of: "url").location + 3
        tv.select(start)
        tv.type("x")
        #expect(tv.selectedRange().location == start + 1)
        tv.type("y")
        #expect(tv.selectedRange().location == start + 2)
    }

    @Test func restyleLeavesFallbackFontAlone() {
        let (doc, _) = makeEditor("- a ✅\n")
        let s = doc.textStorage
        let i = (s.string as NSString).range(of: "✅").location
        let before = s.attribute(.font, at: i, effectiveRange: nil) as? NSFont
        s.beginEditing(); s.restyleParagraphs(in: NSRange(location: 0, length: s.length)); s.endEditing()
        let after = s.attribute(.font, at: i, effectiveRange: nil) as? NSFont
        #expect(before?.fontName == after?.fontName)
    }
}

@MainActor @Suite(.serialized) struct EmojiEditTests {
    static let md = "- url1\u{2028}8:10\n- url2\u{2028}39:25 ✅\n- url3\u{2028}29:20\n"

    @Test func enterAtStartOfEmojiLineKeepsOtherItems() {
        let (doc, vc) = makeEditor(Self.md)
        let tv = vc.textView!
        tv.select(tv.nsString.range(of: "39:25").location)
        tv.type("\n")
        let out = doc.currentMarkdown
        #expect(out.contains("url3"))
        #expect(out.contains("29:20"))
        #expect(out.contains("url1"))
    }

    @Test func enterAtEndOfEmojiLineAddsItem() {
        let (doc, vc) = makeEditor(Self.md)
        let tv = vc.textView!
        tv.select(NSMaxRange(tv.nsString.range(of: "✅")))
        tv.type("\nx")
        let out = doc.currentMarkdown
        #expect(out.contains("url3"))
        #expect(out.contains("- x"))
    }

    @Test func pasteIntoEmojiItemKeepsLine() {
        let (doc, vc) = makeEditor(Self.md)
        let tv = vc.textView!
        let pb = NSPasteboard(name: NSPasteboard.Name("jot-emoji-test"))
        pb.clearContents(); pb.setString("ZZ", forType: .string)
        let at = tv.nsString.range(of: "39:25").location
        tv.select(at)
        tv.pasteFrom(pb)
        let out = doc.currentMarkdown
        #expect(out.contains("ZZ39:25 ✅"))
        #expect(out.contains("url2"))
        #expect(tv.selectedRange().location == at + 2)
    }
}

@MainActor @Suite(.serialized) struct EmojiLayoutTests {
    /// ตำแหน่ง y ของทุกบรรทัดหลังแก้ไข ต้องเท่ากับวางใหม่ทั้งเอกสาร (ไม่มีบรรทัดค้างตำแหน่งเก่า = ไม่มีข้อความ "หาย")
    func lineTops(_ tv: EditorTextView) -> [CGFloat] {
        let lm = tv.layoutManager!
        lm.ensureLayout(for: tv.textContainer!)
        var tops: [CGFloat] = []
        lm.enumerateLineFragments(forGlyphRange: NSRange(location: 0, length: lm.numberOfGlyphs)) { r, _, _, _, _ in tops.append(r.minY) }
        return tops
    }

    @Test(arguments: ["start", "end", "paste"]) func layoutMatchesFreshLayout(_ action: String) {
        let (doc, vc) = makeEditor(EmojiEditTests.md)
        let tv = vc.textView!
        let win = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 700, height: 500), styleMask: [.borderless], backing: .buffered, defer: false)
        win.contentViewController = vc
        _ = lineTops(tv)
        switch action {
        case "start": tv.select(tv.nsString.range(of: "39:25").location); tv.type("\n")
        case "end": tv.select(NSMaxRange(tv.nsString.range(of: "✅"))); tv.type("\n")
        default:
            let pb = NSPasteboard(name: NSPasteboard.Name("jot-emoji-test2"))
            pb.clearContents(); pb.setString("ZZ", forType: .string)
            tv.select(tv.nsString.range(of: "39:25").location); tv.pasteFrom(pb)
        }
        let edited = lineTops(tv)
        let lm = tv.layoutManager!
        lm.invalidateLayout(forCharacterRange: NSRange(location: 0, length: tv.textStorage!.length), actualCharacterRange: nil)
        #expect(edited == lineTops(tv), "\(doc.currentMarkdown)")
        win.contentViewController = nil
    }
}
