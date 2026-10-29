import Testing
import AppKit
@testable import Jotdown

@MainActor @Suite(.serialized) struct ToolbarTests {
    func make(_ md: String = "") -> (JotdownDocument, EditorViewController, FormatToolbar) {
        let (doc, vc) = makeEditor(md)
        let tb = FormatToolbar(editor: vc)
        vc.toolbarController = tb
        for id in tb.toolbarDefaultItemIdentifiers(tb.toolbar) { _ = tb.toolbar(tb.toolbar, itemForItemIdentifier: id, willBeInsertedIntoToolbar: true) }
        return (doc, vc, tb)
    }

    func group(_ tb: FormatToolbar, _ id: String) -> ToolGroupView {
        tb.toolbar(tb.toolbar, itemForItemIdentifier: NSToolbarItem.Identifier(id), willBeInsertedIntoToolbar: true)!.view as! ToolGroupView
    }

    @Test func allButtonsHaveSymbolsAndEnglishTooltips() {
        let (_, _, tb) = make()
        var count = 0
        for g in FormatToolbar.groups {
            let item = tb.toolbar(tb.toolbar, itemForItemIdentifier: NSToolbarItem.Identifier(g.id), willBeInsertedIntoToolbar: true)!
            let gv = item.view as! ToolGroupView
            #expect(gv.buttons.count == g.tools.count)
            #expect(item.menuFormRepresentation?.submenu?.items.count == g.tools.count)   // overflow (») มีทุกปุ่ม
            for (i, t) in g.tools.enumerated() {
                #expect(NSImage(systemSymbolName: t.symbol, accessibilityDescription: nil) != nil, Comment(rawValue: t.symbol))
                #expect(gv.buttons[i].toolTip == t.tip)
                #expect(t.tip.range(of: #"^[A-Za-z …]+ \(.+\)$"#, options: .regularExpression) != nil, Comment(rawValue: t.tip))
                count += 1
            }
        }
        #expect(count == 13)
        let style = tb.toolbar(tb.toolbar, itemForItemIdentifier: FormatToolbar.textStyleID, willBeInsertedIntoToolbar: true) as! NSMenuToolbarItem
        #expect(style.menu.items.map(\.title) == ["Body", "Heading 1", "Heading 2", "Heading 3", "Heading 4", "Heading 5", "Heading 6"])
        #expect(style.menuFormRepresentation != nil)
        #expect(tb.toolbar.allowsUserCustomization && tb.toolbar.autosavesConfiguration)
    }

    @Test func buttonsRunSameActionsAsShortcuts() {
        let (doc, vc, tb) = make("abc\n")
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 600, height: 400), styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentViewController = vc
        window.makeFirstResponder(vc.textView)
        let tv = vc.textView!
        func press(_ id: String) { tb.menuToolChosen(NSMenuItem(title: "", action: nil, keyEquivalent: "").withID(id)) }
        tv.select(0, 3)
        press("bold"); #expect(doc.currentMarkdown == "**abc**\n")
        press("bold"); #expect(doc.currentMarkdown == "abc\n")
        press("italic"); #expect(doc.currentMarkdown == "*abc*\n")
        press("italic")
        press("strike"); #expect(doc.currentMarkdown == "~~abc~~\n"); press("strike")
        press("code"); #expect(doc.currentMarkdown == "`abc`\n"); press("code")
        press("bullet"); #expect(doc.currentMarkdown == "- abc\n")
        press("ordered"); #expect(doc.currentMarkdown == "1. abc\n")
        press("task"); #expect(doc.currentMarkdown == "- [ ] abc\n")
        press("task")
        press("quote"); #expect(doc.currentMarkdown == "> abc\n"); press("quote")
        press("codeblock"); #expect(doc.currentMarkdown == "```\nabc\n```\n"); press("codeblock")
        // popup สไตล์
        tb.styleChosen(NSMenuItem(title: "Heading 2", action: nil, keyEquivalent: "").withTag(2)); #expect(doc.currentMarkdown == "## abc\n")
        tb.styleChosen(NSMenuItem(title: "Heading 2", action: nil, keyEquivalent: "").withTag(2)); #expect(doc.currentMarkdown == "## abc\n")   // เลือกซ้ำ = คงเดิม
        tb.styleChosen(NSMenuItem(title: "Body", action: nil, keyEquivalent: "").withTag(0)); #expect(doc.currentMarkdown == "abc\n")
        // โฟกัสอยู่ที่ text view เสมอ
        #expect(window.firstResponder === tv)
        // undo ได้เหมือนคีย์ลัด
        tv.select(0, 3)
        press("bold")
        doc.undoManager?.undo()
        #expect(doc.currentMarkdown == "abc\n")
        press("table"); #expect(doc.currentMarkdown.contains("| --- |"))
    }

    @Test func stateFollowsCaret() {
        let (_, vc, tb) = make("ab **cd** ef\n\n- x\n\n```\ncode\n```\n\n# หัวข้อ\n")
        let tv = vc.textView!
        let inline = group(tb, "jotdown.inline"), lists = group(tb, "jotdown.lists")
        _ = inline; _ = lists
        // ผ่าน validate เดียวกับเมนู: ในตัวหนา
        let boldProbe = NSMenuItem(title: "", action: #selector(EditorTextView.jotToggleBold(_:)), keyEquivalent: "")
        tv.select(4); #expect(tv.validateMenuItem(boldProbe)); #expect(boldProbe.state == .on)
        tv.select(0); _ = tv.validateMenuItem(boldProbe); #expect(boldProbe.state == .off)
        let bullet = NSMenuItem(title: "", action: #selector(EditorTextView.jotToggleBullet(_:)), keyEquivalent: "")
        let xi = tv.nsString.range(of: "x\n").location
        tv.select(xi); _ = tv.validateMenuItem(bullet); #expect(bullet.state == .on)
        // ในกล่องโค้ด inline ใช้ไม่ได้
        tv.select(tv.nsString.range(of: "code").location + 1)
        #expect(!tv.validateMenuItem(boldProbe))
        // ชื่อสไตล์ของ popup
        #expect(FormatToolbar.styleName(for: .paragraph) == "Body")
        tv.select(tv.nsString.range(of: "หัวข้อ").location)
        tb.update()
        let style = tb.toolbar(tb.toolbar, itemForItemIdentifier: FormatToolbar.textStyleID, willBeInsertedIntoToolbar: true) as! NSMenuToolbarItem
        _ = style
        #expect(FormatToolbar.styleName(for: tv.blockKindAtCaret) == "Heading 1")
    }

    @Test func updateRefreshesActiveAndDisabledButtons() {
        let (_, vc, tb) = make("ab **cd** ef\n\n- x\n\n```\ncode\n```\n")
        let tv = vc.textView!
        let inline = group(tb, "jotdown.inline"), lists = group(tb, "jotdown.lists")
        tb.update()
        tv.select(4); tb.update()
        #expect(inline.buttons[0].active)           // Bold
        #expect(!inline.buttons[1].active)
        tv.select(tv.nsString.range(of: "x\n").location); tb.update()
        #expect(lists.buttons[0].active)            // Bulleted
        // ในกล่องโค้ด inline ใช้ไม่ได้
        tv.select(tv.nsString.range(of: "code").location + 1); tb.update()
        #expect(!inline.buttons[0].isEnabled && !inline.buttons[0].active)
        #expect(lists.buttons[0].isEnabled)
    }

    @Test func activeButtonFillsWholeButtonInAccent() {
        let (_, _, tb) = make("**a**\n")
        let gv = group(tb, "jotdown.inline")
        let b = gv.buttons[0]
        b.active = true
        #expect(b.highlightFill != nil)
        // พื้นเหลืองอยู่ในแคปซูล: inset 3pt ทุกด้านจากความสูงแคปซูล, มุมมนเป็นแคปซูล
        #expect(b.highlightRect.height == b.bounds.height - 2 * ToolButton.capsuleInsetY)
        #expect(b.highlightRect.minY >= ToolButton.capsuleInsetY && b.highlightRect.maxY <= b.bounds.height - ToolButton.capsuleInsetY)
        #expect(b.acceptsFirstResponder == false)
        b.active = false
        #expect(b.highlightFill == nil)
    }

    @Test func menuKeyEquivalentsAreUnique() {
        _ = NSApplication.shared
        let menu = MainMenu.build()
        var seen: [String: String] = [:]
        func walk(_ m: NSMenu) {
            for i in m.items {
                if !i.keyEquivalent.isEmpty {
                    let key = "\(i.keyEquivalentModifierMask.intersection([.command, .option, .control, .shift]).rawValue)+\(i.keyEquivalent)"
                    #expect(seen[key] == nil, Comment(rawValue: "ซ้ำ: \(i.title) กับ \(seen[key] ?? "")"))
                    seen[key] = i.title
                }
                if let s = i.submenu { walk(s) }
            }
        }
        walk(menu)
        let view = menu.items.first { $0.title == "View" }!.submenu!
        let tb = view.items.first { $0.title == "Hide Toolbar" }
        #expect(tb?.keyEquivalent == "t" && tb?.keyEquivalentModifierMask == [.command, .option])
        let insertImage = menu.items.first { $0.title == "Format" }!.submenu!.items.first { $0.title == "Insert Image…" }
        #expect(insertImage?.keyEquivalent == "i" && insertImage?.keyEquivalentModifierMask == [.command, .shift])
    }
}

extension NSMenuItem {
    func withTag(_ t: Int) -> NSMenuItem { tag = t; return self }
    func withID(_ id: String) -> NSMenuItem { representedObject = id; return self }
}
