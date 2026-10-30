import Testing
import AppKit
@testable import Jotdown

@MainActor @Suite(.serialized) struct DividerTests {
    func formatMenu() -> NSMenu { _ = NSApplication.shared; return fm() }
    func fm() -> NSMenu { MainMenu.build().items.first { $0.title == "Format" }!.submenu! }

    @Test func menuItemHasIconAndUniqueShortcut() {
        let all = formatMenu().items.flatMap { [$0] + ($0.submenu?.items ?? []) }
        let it = all.first { $0.title == "Insert Divider" }!
        #expect(it.image != nil)
        #expect(it.keyEquivalent == "-" && it.keyEquivalentModifierMask == [.command, .control])
        let main = MainMenu.build().items.flatMap { m in (m.submenu?.items ?? []).flatMap { [$0] + ($0.submenu?.items ?? []) } }
        let clash = main.filter { $0.keyEquivalent == "-" && $0.keyEquivalentModifierMask == [.command, .control] }
        #expect(clash.count == 1)
    }

    @Test func emptyLineBecomesDivider() {
        let (doc, vc) = makeEditor("ก\n\n")
        let tv = vc.textView!
        tv.select(2)
        #expect(tv.insertDivider())
        #expect(doc.currentMarkdown == "ก\n\n---\n")
        #expect(tv.blockKindAtCaret == .paragraph)
        #expect(doc.textStorage.blockKind(at: 2) == .thematicBreak)
    }

    @Test func textLineGetsDividerBelowAndCaretOnNewParagraph() {
        let (doc, vc) = makeEditor("ก\n\nข\n")
        let tv = vc.textView!
        tv.select(1)
        tv.insertDivider()
        #expect(doc.currentMarkdown == "ก\n\n---\n\nข\n")
        tv.type("ใหม่")
        #expect(doc.currentMarkdown == "ก\n\n---\n\nใหม่\n\nข\n")
    }

    @Test func lastLineGetsDivider() {
        let (doc, vc) = makeEditor("ก")
        let tv = vc.textView!
        tv.insertDivider()
        tv.type("ข")
        #expect(doc.currentMarkdown == "ก\n\n---\n\nข\n")
    }

    @Test func undoIsSingleStep() {
        let (doc, vc) = makeEditor("ก\n\nข\n")
        let tv = vc.textView!
        tv.select(1)
        tv.insertDivider()
        doc.undoManager?.undo()
        #expect(doc.currentMarkdown == "ก\n\nข\n")
        doc.undoManager?.redo()
        #expect(doc.currentMarkdown == "ก\n\n---\n\nข\n")
    }

    @Test func disabledInCodeBlock() {
        let (_, vc) = makeEditor("```\nx\n```\n")
        let tv = vc.textView!
        tv.select(1)
        #expect(!tv.insertDivider())
        let it = NSMenuItem(title: "", action: #selector(EditorTextView.jotInsertDivider(_:)), keyEquivalent: "")
        #expect(!tv.validateMenuItem(it))
    }
}
