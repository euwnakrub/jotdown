import Testing
import AppKit
@testable import Jotdown

@Suite struct InlineTests {
    func rt(_ md: String) -> String { MarkdownSerializer.serialize(MarkdownParser.parse(md)) }

    @Test func basicStyles() {
        for md in ["**หนา**\n", "*เอียง*\n", "~~ขีดฆ่า~~\n", "`โค้ด`\n", "[ลิงก์](https://a.b/c)\n", "***หนาเอียง***\n",
                   "ก่อน **หนา** หลัง\n", "คำ**หนา**ต่อ\n", "**หนา *เอียงใน* หนา**\n", "*เอียง **หนาใน** เอียง*\n", "[**ลิงก์หนา**](https://x.y)\n",
                   "**`โค้ดหนา`**\n", "~~**ขีดหนา**~~\n"] {
            #expect(rt(md) == md, "round-trip ล้ม: \(md)")
        }
    }

    @Test func attributesAreSemantic() {
        let a = MarkdownParser.parse("a **b** *c* ~~d~~ `e` [f](https://x.y)")
        #expect(a.string == "a b c d e f")
        #expect(a.inlineStyle(at: 2).contains(.bold))
        #expect(a.inlineStyle(at: 4).contains(.italic))
        #expect(a.inlineStyle(at: 6).contains(.strike))
        #expect(a.inlineStyle(at: 8).contains(.code))
        #expect(a.link(at: 10) == "https://x.y")
        let f = a.attribute(.font, at: 2, effectiveRange: nil) as? NSFont
        #expect(f?.fontName.contains("Bold") == true)
        #expect(a.attribute(.obliqueness, at: 4, effectiveRange: nil) as? CGFloat == Theme.italicObliqueness)
        #expect(a.attribute(.strikethroughStyle, at: 6, effectiveRange: nil) != nil)
    }

    @Test func whitespaceMovesOutsideMarkers() {
        let bold = InlineSegment(text: " x ", style: .bold)
        #expect(InlineWriter.write([InlineSegment(text: "a"), bold, InlineSegment(text: "b")]) == "a **x** b")
        let it = InlineSegment(text: "x  ", style: .italic)
        #expect(InlineWriter.write([it, InlineSegment(text: "z")]) == "*x*  z")
        // ช่องว่างล้วนไม่เปิดเครื่องหมาย
        #expect(InlineWriter.write([InlineSegment(text: "  ", style: .bold)]) == "  ")
    }

    @Test func adjacentDifferentStyles() {
        let segs = [InlineSegment(text: "a", style: .italic), InlineSegment(text: "b", style: [.bold, .italic]), InlineSegment(text: "c", style: .italic)]
        let md = InlineWriter.write(segs)
        let back = MarkdownParser.inlineSegments(from: md)
        #expect(back.map(\.text).joined() == "abc")
        #expect(back.first?.style == .italic)
        #expect(back.last?.style == .italic)
        #expect(back.contains { $0.text == "b" && $0.style == [.bold, .italic] })
    }

    @Test func escapes() {
        let cases = ["2 * 3 * 4", "a_b_c", "snake_case_name", "_x_ y", "1 < 2", "x [y] z", "back`tick", "tilde ~~ x", "a\\b", "a & b", "&amp; entity",
                     "# not heading", "#hashtag", "> not quote", "- not list", "+ plus", "1. not ordered", "1) paren", "---", "===", "***", "<b>tag</b>", "![img](x)", "end \\",
                     "10. x", "text #", "line1\u{2028}# line2", "line1\u{2028}- item"]
        for text in cases {
            let a = NSAttributedString(string: text, attributes: Theme.attributes(for: .paragraph))
            let md = MarkdownSerializer.serialize(a)
            let back = MarkdownParser.parse(md)
            #expect(back.string == text, "escape ล้ม: \(text) -> \(md.debugDescription) -> \(back.string.debugDescription)")
            #expect(back.blockKind(at: 0) == .paragraph, "กลายเป็นบล็อกอื่น: \(text)")
        }
    }

    @Test func escapesInHeadingAndList() {
        for kind in [BlockKind.heading(2), .bullet(0), .ordered(0), .task(0, false), .quote] {
            for text in ["# x", "- y", "[ ] z", "1. q", "tail #"] {
                let a = NSAttributedString(string: text, attributes: Theme.attributes(for: kind))
                let md = MarkdownSerializer.serialize(a)
                let back = MarkdownParser.parse(md)
                #expect(back.string == text, "\(kind) \(text) -> \(md.debugDescription) -> \(back.string.debugDescription)")
                #expect(back.blockKind(at: 0) == kind, "\(kind) \(text) -> \(md.debugDescription)")
            }
        }
    }

    @Test func inlineCodeWithBackticks() {
        let a = NSAttributedString(string: "a`b``c", attributes: Theme.attributes(for: .paragraph, inline: .code))
        let md = MarkdownSerializer.serialize(a)
        let back = MarkdownParser.parse(md)
        #expect(back.string == "a`b``c")
        #expect(back.inlineStyle(at: 0).contains(.code))
    }

    @Test func linkWithSpecialDestination() {
        let a = NSAttributedString(string: "x", attributes: Theme.attributes(for: .paragraph, inline: [], link: "https://a.b/c d(e)"))
        let back = MarkdownParser.parse(MarkdownSerializer.serialize(a))
        #expect(back.link(at: 0) == "https://a.b/c d(e)")
    }

    @Test func hardBreakAndImageAreKept() {
        let md = "บรรทัด\\\nสอง ![x](y.png)\n"
        #expect(rt(md) == md)
    }

    @Test func codeBlockEscapingFence() {
        let a = NSAttributedString(string: "```\u{2028}x", attributes: Theme.attributes(for: .codeBlock("md")))
        let md = MarkdownSerializer.serialize(a)
        #expect(md.hasPrefix("````md\n"))
        #expect(MarkdownParser.parse(md).string == "```\u{2028}x")
    }
}

