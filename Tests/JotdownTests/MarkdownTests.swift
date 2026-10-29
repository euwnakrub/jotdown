import Testing
import AppKit
@testable import Jotdown

func fixture(_ name: String) throws -> String {
    let url = try #require(Bundle.module.url(forResource: name, withExtension: "md", subdirectory: "Fixtures"))
    return try String(contentsOf: url, encoding: .utf8)
}

@Suite struct MarkdownTests {
    @Test func headings1to6() {
        for l in 1...6 {
            let md = String(repeating: "#", count: l) + " หัวข้อ \(l)\n"
            let a = MarkdownParser.parse(md)
            #expect(a.string == "หัวข้อ \(l)")
            #expect(a.blockKind(at: 0) == .heading(l))
            #expect(MarkdownSerializer.serialize(a) == md)
        }
    }

    @Test func multiLineParagraphKeepsSoftBreak() {
        let md = "บรรทัดหนึ่ง\nบรรทัดสอง\n\nย่อหน้าสอง\n"
        let a = MarkdownParser.parse(md)
        #expect(a.string.contains(String(softBreakCharacter)))
        #expect(a.string.components(separatedBy: "\n").count == 2)   // 2 ย่อหน้า
        #expect(MarkdownSerializer.serialize(a) == md)
    }

    @Test func emptyFile() {
        let a = MarkdownParser.parse("")
        #expect(a.length == 0)
        #expect(MarkdownSerializer.serialize(a) == "")
        #expect(MarkdownSerializer.serialize(MarkdownParser.parse("\n\n  \n")) == "")
    }

    @Test func thaiOnly() {
        let md = "สวัสดีชาวโลก ผู้ใหญ่ลีซื้อเกี๊ยวที่ปั้นเอง\n"
        #expect(MarkdownSerializer.serialize(MarkdownParser.parse(md)) == md)
    }

    @Test func crlfAndBOM() {
        let md = "\u{FEFF}# หัวข้อ\r\n\r\nบรรทัดหนึ่ง\r\nบรรทัดสอง\r\n"
        let out = MarkdownSerializer.serialize(MarkdownParser.parse(md))
        #expect(out == "# หัวข้อ\n\nบรรทัดหนึ่ง\nบรรทัดสอง\n")
        #expect(!out.contains("\r") && !out.hasPrefix("\u{FEFF}"))
    }

    @Test func atxClosingAndSetext() {
        #expect(MarkdownSerializer.serialize(MarkdownParser.parse("## ชื่อ ##\n")) == "## ชื่อ\n")
        #expect(MarkdownSerializer.serialize(MarkdownParser.parse("ชื่อ\n===\n")) == "# ชื่อ\n")
    }

    @Test func canonicalFixtureRoundTrips() throws {
        let md = try fixture("thai-canonical")
        #expect(MarkdownSerializer.serialize(MarkdownParser.parse(md)) == md)
        let a = MarkdownParser.parse(md)
        #expect(a.blockKind(at: 0) == .heading(1))
        #expect(!a.string.contains("#"))
    }

    @Test func fullFixtureRoundTrips() throws {
        let md = try fixture("full-canonical")
        let out = MarkdownSerializer.serialize(MarkdownParser.parse(md))
        #expect(out == md)
        let a = MarkdownParser.parse(md)
        #expect(!a.string.contains("**") && !a.string.contains("- [") && !a.string.contains("```"))
    }

    @Test func nonCanonicalDoesNotLoseContent() {
        let md = "Setext\n======\n\n* a\n* b\n\n+ c\n\n1) x\n\n    indented code\n\n<div>html</div>\n\n~~~\ntilde\n~~~\n"
        let out = MarkdownSerializer.serialize(MarkdownParser.parse(md))
        for n in ["# Setext", "- a", "- b", "- c", "1) x", "    indented code", "<div>html</div>", "tilde"] { #expect(out.contains(n), "หาย: \(n)") }
        #expect(MarkdownSerializer.serialize(MarkdownParser.parse(out)) == out)
    }

    @Test func listMarkersAreNotInStorage() {
        let a = MarkdownParser.parse("# A\n\n- x\n")
        #expect(a.string == "A\nx")
        #expect(a.blockKind(at: a.length - 1) == .bullet(0))
    }
}
