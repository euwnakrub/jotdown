import AppKit

extension EditorTextView {
    // MARK: - พิมพ์
    /// ใส่ตัวอักษรที่ผู้ใช้เพิ่งพิมพ์ โดยไม่บันทึก undo เพื่อให้การแปลงพิมพ์ลัดเป็น undo ครั้งเดียว
    /// (⌘Z แล้วได้ข้อความตามที่พิมพ์ เช่น "# ") ไม่ต้องจัดกลุ่ม undo เอง
    private func insertSilently(_ s: String, at loc: Int, kind: BlockKind) {
        let um = undoManager
        um?.disableUndoRegistration()
        internalEdit = true
        storage.replaceCharacters(in: NSRange(location: loc, length: 0), with: NSAttributedString(string: s, attributes: Theme.attributes(for: kind)))
        internalEdit = false
        um?.enableUndoRegistration()
    }

    override func insertText(_ string: Any, replacementRange: NSRange) {
        // ในกล่องโค้ด/ข้อความดิบ: "\n" ที่วางหรือพิมพ์ต้องเป็นขึ้นบรรทัดในบล็อกเดียว
        if !internalEdit, blockKindAtCaret.isCodeLike, let s = string as? String, s.contains("\n") {
            super.insertText(s.replacingOccurrences(of: "\n", with: softBreakString), replacementRange: replacementRange)
            return
        }
        let s = (string as? String) ?? (string as? NSAttributedString)?.string ?? ""
        let sel = selectedRange()
        if !internalEdit, sel.length == 0, s.count == 1, replacementRange.location == NSNotFound || replacementRange == sel {
            if s == " " { autolinkWordBeforeCaret() }
            if s == " ", applyBlockShortcut() { return }
            if "*_`~".contains(s), applyInlineShortcut(typed: s) { return }
        }
        super.insertText(string, replacementRange: replacementRange)
    }

    /// `# ` `- ` `1. ` `[] ` `> ` ต้นย่อหน้า -> บล็อกชนิดนั้น (เรียกก่อนแทรกช่องว่างจริง)
    func applyBlockShortcut() -> Bool {
        let caret = selectedRange().location
        let pr = paragraphRange(containing: caret)
        guard pr.length > 0, caret > pr.location else { return false }
        let kind = storage.blockKind(at: pr.location)
        let prefix = nsString.substring(with: NSRange(location: pr.location, length: caret - pr.location))
        var new: BlockKind?
        switch kind {
        case .paragraph:
            if prefix.count <= 6, prefix.allSatisfy({ $0 == "#" }) { new = .heading(prefix.count) }
            else if ["-", "*", "+"].contains(prefix) { new = .bullet(0) }
            else if prefix == ">" { new = .quote }
            else if prefix.range(of: #"^\d{1,9}\.$"#, options: .regularExpression) != nil { new = .ordered(0) }
            else if ["[]", "[ ]"].contains(prefix) { new = .task(0, false) }
            else if ["[x]", "[X]"].contains(prefix) { new = .task(0, true) }
        case .bullet(let l):
            if ["[]", "[ ]"].contains(prefix) { new = .task(l, false) }
            else if ["[x]", "[X]"].contains(prefix) { new = .task(l, true) }
        default: break
        }
        guard let target = new else { return false }
        insertSilently(" ", at: caret, kind: kind)
        let removeLen = caret + 1 - pr.location
        transformParagraphs(in: NSRange(location: pr.location, length: 0), keepSelection: false) { sub in
            sub.deleteCharacters(in: NSRange(location: 0, length: removeLen))
            if sub.length > 0 { sub.addAttribute(.jotBlock, value: target.code, range: NSRange(location: 0, length: sub.length)) }
        }
        setSelectedRange(NSRange(location: pr.location, length: 0))
        if paragraphRange(containing: pr.location).length == 0 { pendingEmptyBlock = (pr.location, target) }
        syncTypingAttributes()
        return true
    }

    /// `**x**` `*x*` `_x_` `` `x` `` `~~x~~` -> inline style (เรียกก่อนแทรกเครื่องหมายปิดจริง)
    func applyInlineShortcut(typed: String) -> Bool {
        let caret = selectedRange().location
        let pr = paragraphRange(containing: caret)
        guard pr.length > 0, caret > pr.location else { return false }
        let kind = storage.blockKind(at: pr.location)
        guard kind.allowsInline else { return false }
        let text = nsString.substring(with: NSRange(location: pr.location, length: caret - pr.location)) + typed
        let tries: [(String, InlineStyle)] = [
            (#"(?<!\\)\*\*([^*\s](?:[^*]*[^*\s])?)\*\*$"#, .bold),
            (#"(?<![*\\])\*([^*\s](?:[^*]*[^*\s])?)\*$"#, .italic),
            (#"(?<![_\w\\])_([^_\s](?:[^_]*[^_\s])?)_$"#, .italic),
            (#"(?<!\\)~~([^~\s](?:[^~]*[^~\s])?)~~$"#, .strike),
            (#"(?<![`\\])`([^`]+)`$"#, .code),
        ]
        for (pattern, flag) in tries {
            guard let re = try? NSRegularExpression(pattern: pattern),
                  let m = re.firstMatch(in: text, range: NSRange(location: 0, length: (text as NSString).length)),
                  m.numberOfRanges > 1 else { continue }
            let inner = NSRange(location: pr.location + m.range(at: 1).location, length: m.range(at: 1).length)
            let whole = NSRange(location: pr.location + m.range.location, length: m.range.length)   // รวมเครื่องหมายปิดที่เพิ่งพิมพ์
            insertSilently(typed, at: caret, kind: kind)
            let content = NSMutableAttributedString(attributedString: storage.attributedSubstring(from: inner))
            content.enumerateAttribute(.jotInline, in: NSRange(location: 0, length: content.length), options: []) { v, r, _ in
                let old = InlineStyle(rawValue: (v as? Int) ?? 0)
                content.addAttribute(.jotInline, value: old.union(flag).rawValue, range: r)
            }
            content.restyleParagraphs(in: NSRange(location: 0, length: content.length))
            replaceRange(whole, with: content, selection: NSRange(location: whole.location + content.length, length: 0))
            plainTypingAt = selectedRange().location
            syncTypingAttributes()
            return true
        }
        return false
    }

    // MARK: - Enter
    override func insertNewline(_ sender: Any?) {
        // ⇧Enter ในแอปจริงมาทาง insertNewline: พร้อม modifier ของเหตุการณ์ปัจจุบัน
        if let e = NSApp.currentEvent, e.type == .keyDown, e.modifierFlags.contains(.shift), shiftEnterIsSoftBreak {
            insertText(softBreakString, replacementRange: selectedRange())
            return
        }
        let sel = selectedRange()
        guard sel.length == 0 else { super.insertNewline(sender); return }
        let kind = blockKindAtCaret
        let pr = paragraphRange(containing: sel.location)
        let content = contentRange(of: pr)

        switch kind {
        case .codeBlock, .raw:
            let atEnd = sel.location >= NSMaxRange(content)
            if atEnd, content.length > 0, nsString.character(at: NSMaxRange(content) - 1) == 0x2028 {
                // บรรทัดว่างท้ายกล่อง: Enter อีกครั้ง = ออกจากกล่อง
                internalEdit = true
                insertText("", replacementRange: NSRange(location: NSMaxRange(content) - 1, length: 1))
                internalEdit = false
                exitCodeBlock()
            } else {
                insertText(softBreakString, replacementRange: sel)
            }
            return
        case .thematicBreak:
            setSelectedRange(NSRange(location: NSMaxRange(content), length: 0))
            super.insertNewline(sender)
            finishNewParagraph(.paragraph)
            return
        case .heading:
            let atEnd = sel.location >= NSMaxRange(content)
            super.insertNewline(sender)
            if atEnd { finishNewParagraph(.paragraph) } else { finishNewParagraph(kind) }
            return
        case .bullet(let l), .ordered(let l), .task(let l, _):
            if content.length == 0 {
                // รายการว่าง: ลดระดับ หรือออกจากลิสต์
                applyKind { k in l > 0 ? k.withListLevel(l - 1) : .paragraph }
                return
            }
            super.insertNewline(sender)
            if case .task = kind { finishNewParagraph(.task(l, false)) } else { finishNewParagraph(kind) }
            return
        case .quote:
            if content.length == 0 { applyKind { _ in .paragraph }; return }
            super.insertNewline(sender)
            finishNewParagraph(.quote)
            return
        case .tableCell:
            moveVertically(by: 1)
            return
        case .paragraph:
            if sel.location >= NSMaxRange(content), content.length >= 2, let m = tableModelFromTypedRow(nsString.substring(with: content)) {
                placeTable(m, replacing: pr, selectCell: (1, 0))
                return
            }
            if sel.location >= NSMaxRange(content), content.length >= 3 {
                let text = nsString.substring(with: content)
                if let m = text.range(of: #"^```([^`\s]*)$"#, options: .regularExpression) {
                    let lang = String(text[m].dropFirst(3))
                    transformParagraphs(in: sel, keepSelection: false) { sub in
                        let hasNL = sub.string.hasSuffix("\n")
                        sub.replaceCharacters(in: NSRange(location: 0, length: sub.length - (hasNL ? 1 : 0)), with: "")
                        if sub.length > 0 { sub.addAttribute(.jotBlock, value: BlockKind.codeBlock(lang).code, range: NSRange(location: 0, length: sub.length)) }
                    }
                    setSelectedRange(NSRange(location: pr.location, length: 0))
                    if paragraphRange(containing: pr.location).length == 0 { pendingEmptyBlock = (pr.location, .codeBlock(lang)) }
                    syncTypingAttributes()
                    return
                }
                if text == "---" {
                    // แทนที่ทั้งย่อหน้าด้วย [เส้นคั่น] + ย่อหน้าว่างใหม่ ในการแก้ครั้งเดียว
                    let hasNL = pr.length > content.length
                    let out = NSMutableAttributedString(string: thematicBreakText + "\n", attributes: Theme.attributes(for: .thematicBreak))
                    if hasNL { out.append(NSAttributedString(string: "\n", attributes: Theme.attributes(for: .paragraph))) }
                    replaceRange(pr, with: out, selection: NSRange(location: pr.location + 2, length: 0))
                    if paragraphRange(containing: pr.location + 2).length == 0 { pendingEmptyBlock = (pr.location + 2, .paragraph) }
                    syncTypingAttributes()
                    return
                }
            }
            super.insertNewline(sender)
            finishNewParagraph(.paragraph)
        }
    }

    /// หลังแทรกย่อหน้าใหม่: ตั้งชนิดบล็อกของย่อหน้าที่เคอร์เซอร์อยู่
    func finishNewParagraph(_ kind: BlockKind) {
        let loc = selectedRange().location
        let pr = paragraphRange(containing: loc)
        if pr.length == 0 {
            pendingEmptyBlock = (loc, kind)
        } else if storage.blockKind(at: pr.location) != kind {
            applyKind { _ in kind }
            return
        }
        syncTypingAttributes()
    }

    /// ออกจากกล่องโค้ด: ขึ้นย่อหน้าใหม่ต่อท้ายบล็อก
    func exitCodeBlock() {
        let pr = paragraphRange(containing: selectedRange().location)
        setSelectedRange(NSRange(location: NSMaxRange(contentRange(of: pr)), length: 0))
        internalEdit = true
        insertText("\n", replacementRange: selectedRange())
        internalEdit = false
        finishNewParagraph(.paragraph)
    }

    // ⇧Enter = ขึ้นบรรทัดใหม่ในบล็อกเดิม (ลิสต์/quote/เซลล์ตาราง) ไม่สร้างรายการใหม่ — เขียนออกเป็นบรรทัดต่อเนื่องที่เยื้องตามรายการ
    var shiftEnterIsSoftBreak: Bool {
        let k = blockKindAtCaret
        return k.isList || k == .quote || k.isTableCell
    }
    override func insertLineBreak(_ sender: Any?) {
        if shiftEnterIsSoftBreak { insertText(softBreakString, replacementRange: selectedRange()); return }
        super.insertLineBreak(sender)
    }
    override func insertNewlineIgnoringFieldEditor(_ sender: Any?) {
        if shiftEnterIsSoftBreak { insertText(softBreakString, replacementRange: selectedRange()); return }
        super.insertNewlineIgnoringFieldEditor(sender)
    }

    // MARK: - Backspace
    override func deleteBackward(_ sender: Any?) {
        let sel = selectedRange()
        guard sel.length == 0 else { super.deleteBackward(sender); return }
        let loc = sel.location
        let pr = paragraphRange(containing: loc)
        let kind = blockKindAtCaret
        if kind.isTableCell { return }      // ไม่ลบโครงตาราง
        if kind == .thematicBreak {
            applyKind { _ in .paragraph }
            return
        }
        if loc == pr.location, let l = kind.listLevel, l > 0 {
            // รายการซ้อน: markdown เก็บระยะเยื้องของย่อหน้าไม่ได้ จึงลดระดับก่อน (ถึงระดับบนสุดค่อยเป็นย่อหน้า)
            applyKind { $0.withListLevel(l - 1) }
            return
        }
        if loc == pr.location, kind != .paragraph {
            applyKind { _ in .paragraph }
            return
        }
        if loc == pr.location, loc > 0, kind == .paragraph {
            let prev = paragraphRange(containing: loc - 1)
            if storage.blockKind(at: prev.location) == .thematicBreak {
                replaceRange(prev, with: NSAttributedString(), selection: NSRange(location: prev.location, length: 0))
                syncTypingAttributes()
                return
            }
        }
        let lastChar = pr.length == 1 && NSMaxRange(pr) == storage.length && kind != .paragraph
        super.deleteBackward(sender)
        if lastChar {
            // ลบตัวสุดท้ายของย่อหน้าท้ายเอกสาร: ย่อหน้ายังเป็นชนิดเดิม (ว่าง)
            pendingEmptyBlock = (selectedRange().location, kind)
            syncTypingAttributes()
        }
    }

    // MARK: - Tab / ⇧Tab ระดับลิสต์
    override func insertTab(_ sender: Any?) { if blockKindAtCaret.isTableCell { moveCell(by: 1); return }; if !changeListLevel(by: 1) { super.insertTab(sender) } }
    override func insertBacktab(_ sender: Any?) { if blockKindAtCaret.isTableCell { moveCell(by: -1); return }; if !changeListLevel(by: -1) { super.insertBacktab(sender) } }

    @discardableResult
    func changeListLevel(by delta: Int) -> Bool {
        let sel = selectedRange()
        let first = paragraphRange(containing: sel.location)
        guard blockKindAtCaret.isList || (sel.length > 0 && storage.blockKind(at: first.location).isList) else { return false }
        var prev: Int? = nil
        if first.location > 0 { prev = storage.blockKind(at: paragraphRange(containing: first.location - 1).location).listLevel }
        applyKind { k in
            guard let l = k.listLevel else { prev = nil; return k }
            let n = delta > 0 ? min(l + 1, (prev ?? -1) + 1) : max(l - 1, 0)
            let nl = max(n, 0)
            prev = nl
            return k.withListLevel(nl)
        }
        return true
    }

    // MARK: - เช็กลิสต์
    func toggleTaskChecked(at idx: Int) {
        let keep = selectedRange()
        transformParagraphs(in: NSRange(location: idx, length: 0)) { sub in
            if case .task(let l, let c) = sub.blockKind(at: 0) {
                sub.addAttribute(.jotBlock, value: BlockKind.task(l, !c).code, range: NSRange(location: 0, length: sub.length))
            }
        }
        setSelectedRange(keep)
    }

    /// ⌘Enter: ติ๊ก/ยกเลิกเช็กลิสต์ (นอกกล่องโค้ด) หรือออกจากกล่องโค้ด
    @objc func jotToggleCheckOrExit(_ sender: Any?) {
        let kind = blockKindAtCaret
        if kind.isCodeLike { exitCodeBlock(); return }
        if case .task = kind {
            let pr = paragraphRange(containing: selectedRange().location)
            if pr.length == 0 { applyKind { k in if case .task(let l, let c) = k { return .task(l, !c) } else { return k } } }
            else { toggleTaskChecked(at: pr.location) }
        }
    }
}
