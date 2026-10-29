import AppKit

/// เลือก/เปลี่ยนภาษาของกล่องโค้ด (info string ของ fence): จากป้ายมุมบนขวาของกล่อง หรือเมนูคลิกขวา
extension EditorTextView {
    /// เมนูรายชื่อภาษา (ติ๊กภาษาปัจจุบัน) — action ส่งเข้า `jotSetCodeLanguage:` โดย representedObject = ค่า info string
    func languageMenu(forBlockAt idx: Int) -> NSMenu {
        languageTarget = paragraphRange(containing: idx).location
        var current = ""
        if case .codeBlock(let l) = storage.blockKind(at: languageTarget) { current = l }
        let canon = SyntaxHighlighter.canonical(current)
        let m = NSMenu(title: "Code Language")
        func add(_ title: String, _ id: String, on: Bool) {
            let i = NSMenuItem(title: title, action: #selector(jotSetCodeLanguage(_:)), keyEquivalent: "")
            i.target = self; i.representedObject = id; i.state = on ? .on : .off
            m.addItem(i)
        }
        add("Plain Text", "", on: canon == nil)
        m.addItem(.separator())
        for (title, id) in SyntaxHighlighter.menuLanguages { add(title, id, on: canon == id) }
        m.addItem(.separator())
        let other = NSMenuItem(title: "Other…", action: #selector(jotSetCodeLanguageOther(_:)), keyEquivalent: "")
        other.target = self
        other.state = canon == "generic" ? .on : .off
        m.addItem(other)
        return m
    }

    func showLanguageMenu(forBlockAt idx: Int) {
        guard let lm = layoutManager as? EditorLayoutManager, let label = lm.languageLabelRect(forParagraphAt: idx) else { return }
        let m = languageMenu(forBlockAt: idx)
        let o = textContainerOrigin
        m.popUp(positioning: nil, at: NSPoint(x: label.minX + o.x, y: label.maxY + o.y), in: self)
    }

    @objc func jotSetCodeLanguage(_ s: NSMenuItem) {
        guard let id = s.representedObject as? String else { return }
        setCodeLanguage(id, at: languageTarget)
    }

    @objc func jotSetCodeLanguageOther(_ s: Any?) {
        guard let window, languageTarget < storage.length, case .codeBlock(let current) = storage.blockKind(at: languageTarget) else { return }
        let sheet = PromptSheet(title: "Code Language", message: "Name shown after the opening ``` fence, such as swift or python", initial: current, placeholder: "e.g. swift")
        sheet.validator = { Self.isValidLanguage($0) ? nil : "Use a single word without spaces or backticks" }
        promptSheet = sheet
        let target = languageTarget
        sheet.present(on: window) { [weak self] r in
            guard let self else { return }
            self.promptSheet = nil
            if case .ok(let text) = r { self.setCodeLanguage(text.trimmingCharacters(in: .whitespaces), at: target) }
        }
    }

    static func isValidLanguage(_ s: String) -> Bool {
        let t = s.trimmingCharacters(in: .whitespaces)
        return !t.contains(where: { $0.isWhitespace || $0 == "`" })
    }

    /// เปลี่ยนภาษาของกล่องโค้ดที่ย่อหน้าเริ่มที่ `loc` (ผ่านระบบ undo; ระบายสีใหม่เฉพาะกล่องนี้)
    @discardableResult
    func setCodeLanguage(_ lang: String, at loc: Int) -> Bool {
        guard Self.isValidLanguage(lang), storage.length > 0, loc < storage.length, case .codeBlock(let old) = storage.blockKind(at: loc), old != lang else { return false }
        return transformParagraphs(in: NSRange(location: loc, length: 0)) { sub in
            sub.addAttribute(.jotBlock, value: BlockKind.codeBlock(lang).code, range: NSRange(location: 0, length: sub.length))
        }
    }
}
