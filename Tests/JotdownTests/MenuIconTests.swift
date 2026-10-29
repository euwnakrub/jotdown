import Testing
import AppKit
@testable import Jotdown

@MainActor @Suite(.serialized) struct MenuIconTests {
    func allItems(_ m: NSMenu) -> [NSMenuItem] {
        m.items.flatMap { [$0] + ($0.submenu.map(allItems) ?? []) }
    }
    func missingImages(_ m: NSMenu) -> [String] {
        allItems(m).filter { !$0.isSeparatorItem && $0.image == nil }.map(\.title)
    }

    @Test func formatMenuItemsAllHaveImages() {
        let format = MainMenu.build().items.first { $0.title == "Format" }!.submenu!
        #expect(missingImages(format).isEmpty, Comment(rawValue: "\(missingImages(format))"))
        #expect(allItems(format).count > 30)
    }

    @Test func viewZoomItemsHaveImages() {
        let view = MainMenu.build().items.first { $0.title == "View" }!.submenu!
        for t in ["Zoom In", "Zoom Out", "Actual Size"] { #expect(view.items.first { $0.title == t }?.image != nil, Comment(rawValue: t)) }
    }

    @Test func tableContextMenuItemsAllHaveImages() {
        let (_, vc) = makeEditor("| a | b |\n|---|---|\n| 1 | 2 |\n")
        let m = vc.textView.tableContextMenu()
        #expect(missingImages(m).isEmpty, Comment(rawValue: "\(missingImages(m))"))
        #expect(m.items.filter { !$0.isSeparatorItem }.count == 11)
    }

    @Test func linkAndVideoContextItemsHaveImages() {
        let (_, vc) = makeEditor("x\n")
        for i in vc.textView.linkContextItems() { #expect(i.image != nil, Comment(rawValue: i.title)) }
        let v = vc.textView.videoContextMenu(index: 0)
        #expect(missingImages(v).isEmpty)
        #expect(v.items.count == 3)
    }

    @Test func toolbarAndMenuShareTheSameSymbols() {
        let format = MainMenu.build().items.first { $0.title == "Format" }!.submenu!
        for g in FormatToolbar.groups {
            for t in g.tools {
                #expect(t.symbol == MenuIcons.name(for: t.action))
                if let item = allItems(format).first(where: { $0.action == t.action }) {
                    #expect(item.image != nil)
                }
            }
        }
        // ทุกสัญลักษณ์ในตารางมีอยู่จริงใน SF Symbols
        for (sel, name) in MenuIcons.symbols { #expect(NSImage(systemSymbolName: name, accessibilityDescription: nil) != nil, Comment(rawValue: "\(sel) \(name)")) }
        for l in 1...6 { #expect(NSImage(systemSymbolName: MenuIcons.headingSymbol(l), accessibilityDescription: nil) != nil) }
    }

    @Test func codeBlockLanguageSubmenuHasImage() {
        MenuIcons.decorate({ let m = NSMenu(); let h = NSMenuItem(title: "Code Language", action: nil, keyEquivalent: ""); h.submenu = NSMenu(); m.addItem(h); return m }())
        #expect(MenuIcons.submenuSymbols["Code Language"] != nil)
    }
}
