import Testing
import AppKit
@testable import Jotdown

@MainActor @Suite(.serialized) struct TableHeaderFontTests {
    static let md = "| ชื่อ | อายุ |\n| --- | --- |\n| กา | 1 |\n"

    func fontName(_ doc: JotdownDocument, containing s: String) -> String? {
        let r = (doc.textStorage.string as NSString).range(of: s)
        guard r.location != NSNotFound else { return nil }
        return (doc.textStorage.attribute(.font, at: r.location, effectiveRange: nil) as? NSFont)?.fontName
    }
    func expectFonts(_ doc: JotdownDocument, header: String, body: String) {
        #expect(fontName(doc, containing: header) == "IBMPlexSansThai-Bold")
        #expect(fontName(doc, containing: body) == "IBMPlexSansThaiLooped-Regular")
    }

    @Test func loadedHeaderUsesPlexNotLooped() {
        let (doc, _) = makeEditor(Self.md)
        expectFonts(doc, header: "ชื่อ", body: "กา")
        #expect(MarkdownSerializer.serialize(MarkdownParser.parse(doc.currentMarkdown)) == doc.currentMarkdown)
    }

    @Test func boldBodyCellStillLooped() {
        #expect(Theme.font(for: .tableCell(1, 0, 2), inline: .bold).fontName == "IBMPlexSansThaiLooped-Bold")
    }

    @Test func survivesTypingRowInsertAndZoom() {
        let (doc, vc) = makeEditor(Self.md)
        let tv = vc.textView!
        let loc = (doc.textStorage.string as NSString).range(of: "ชื่อ").location
        tv.select(loc + 2)
        tv.type("ๆ")
        expectFonts(doc, header: "ชื่อ", body: "กา")
        tv.insertRow(below: true)
        expectFonts(doc, header: "ชื่อ", body: "กา")
        tv.insertColumn(right: true)
        expectFonts(doc, header: "ชื่อ", body: "กา")
        Theme.setZoom(1.5, persist: false)
        defer { Theme.setZoom(1.0, persist: false) }
        #expect(Theme.font(for: .tableCell(0, 0, 2)).fontName == "IBMPlexSansThai-Bold")
    }

    @Test func snapshots() throws {
        for ap in [NSAppearance.Name.aqua, .darkAqua] {
            let (_, vc) = makeEditor("# ตาราง\n\n" + Self.md)
            let shot = try snapshot("table-header-font", size: CGSize(width: 700, height: 300), appearance: ap, viewController: vc)
            print("SNAPSHOT \(shot.png.path)")
        }
    }
}
