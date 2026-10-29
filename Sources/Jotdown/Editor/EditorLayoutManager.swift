import AppKit

/// วาง bullet / เลขลิสต์ / checkbox / เส้นแนวตั้งของ quote / พื้นกล่องโค้ด / เส้นคั่น / พื้นโค้ดในบรรทัด ด้วยตัวเอง
/// ข้อความใน storage ไม่มีเครื่องหมายเหล่านี้เลย
final class EditorLayoutManager: NSLayoutManager {
    static var checkboxSize: CGFloat { Theme.s(14) }

    private struct Geometry { var first: NSRect; var firstUsed: NSRect; var lastUsed: NSRect; var baseline: CGFloat; var minY: CGFloat; var maxY: CGFloat }

    private func geometry(for pr: NSRange) -> Geometry? {
        let g = glyphRange(forCharacterRange: pr, actualCharacterRange: nil)
        guard g.length > 0 else { return nil }
        var geo: Geometry?
        enumerateLineFragments(forGlyphRange: g) { rect, used, _, glyphs, _ in
            if geo == nil {
                let loc = self.location(forGlyphAt: glyphs.location)
                geo = Geometry(first: rect, firstUsed: used, lastUsed: used, baseline: rect.minY + loc.y, minY: used.minY, maxY: used.maxY)
            } else {
                geo!.lastUsed = used; geo!.maxY = used.maxY
            }
        }
        return geo
    }

    /// ตำแหน่งกล่อง checkbox/เครื่องหมายของย่อหน้า (พิกัด text container) — ใช้ทั้งวาดและ hit test
    func markerRect(forParagraphAt charIndex: Int) -> NSRect? {
        guard let storage = textStorage, storage.length > 0 else { return nil }
        let ns = storage.string as NSString
        let pr = ns.paragraphRange(for: NSRange(location: min(charIndex, ns.length - 1), length: 0))
        let kind = storage.blockKind(at: pr.location)
        guard let level = kind.listLevel, let geo = geometry(for: pr) else { return nil }
        let size = Self.checkboxSize
        let x = CGFloat(level) * Theme.listIndent + (Theme.listIndent - size) / 2 + 1
        return NSRect(x: x, y: geo.baseline - size + Theme.s(3), width: size, height: size)
    }

    // MARK: - ป้ายภาษาของกล่องโค้ด (มุมบนขวา คลิกเพื่อเลือกภาษา)
    static let labelPadding: CGFloat = 6

    static func languageTitle(_ info: String) -> String {
        guard let canon = SyntaxHighlighter.canonical(info) else { return "Plain Text" }
        if let m = SyntaxHighlighter.menuLanguages.first(where: { $0.id == canon }) { return m.title }
        return info.split(separator: " ").first.map(String.init) ?? info
    }

    private func languageLabel(forParagraphAt loc: Int, geo: Geometry) -> (rect: NSRect, text: NSAttributedString)? {
        guard let storage = textStorage, let container = textContainers.first, case .codeBlock(let lang) = storage.blockKind(at: loc) else { return nil }
        let text = NSAttributedString(string: Self.languageTitle(lang) + " ▾", attributes: [
            .font: NSFont.monospacedSystemFont(ofSize: Theme.s(10.5), weight: .regular), .foregroundColor: Palette.secondaryText])
        let w = text.size().width + Self.labelPadding * 2
        let top = geo.minY - 8 - Theme.codeHeaderHeight
        let h = Theme.codeHeaderHeight + 4
        return (NSRect(x: container.size.width - Theme.codePadding + 4 - w, y: top + 2, width: w, height: h), text)
    }

    /// ตำแหน่งป้ายภาษา (พิกัด text container) ใช้ทั้งวาดและ hit test
    func languageLabelRect(forParagraphAt charIndex: Int) -> NSRect? {
        guard let storage = textStorage, storage.length > 0 else { return nil }
        let ns = storage.string as NSString
        let pr = ns.paragraphRange(for: NSRange(location: min(charIndex, ns.length - 1), length: 0))
        guard let geo = geometry(for: pr) else { return nil }
        return languageLabel(forParagraphAt: pr.location, geo: geo)?.rect
    }

    private func orderedNumber(at start: Int, level: Int, storage: NSTextStorage) -> Int {
        let ns = storage.string as NSString
        var count = 1
        var p = start
        while p > 0 {
            let prev = ns.paragraphRange(for: NSRange(location: p - 1, length: 0))
            let k = storage.blockKind(at: prev.location)
            guard let l = k.listLevel else { break }
            if l > level { p = prev.location; continue }
            if l < level { break }
            if case .ordered = k { count += 1; p = prev.location } else { break }
        }
        return count
    }

    /// เลือกครอบเนื้อหาทั้งช่อง (ไม่นับตัวขึ้นบรรทัดท้ายย่อหน้า) และคลุมมากกว่าเนื้อหาของช่องนั้นเอง = เลือกหลายช่อง
    static func selectionCoversCell(_ selected: NSRange, paragraph pr: NSRange, in ns: NSString) -> Bool {
        var content = pr
        if content.length > 0, ns.character(at: NSMaxRange(content) - 1) == 0x0A { content.length -= 1 }
        guard NSMaxRange(selected) >= NSMaxRange(content), selected.location <= content.location else { return false }
        // เลือกแค่เนื้อหาของช่องเดียวพอดี = เลือกข้อความธรรมดา ไม่ใช่เลือกช่อง
        return selected.location < content.location || NSMaxRange(selected) > NSMaxRange(content)
    }

    /// พื้นที่ฟิลล์ของเซลล์: ตัด margin (ระยะนอกเส้นขอบ เช่นเหนือหัวตาราง/ใต้แถวสุดท้าย) และความหนาเส้นขอบออก
    /// `boundsRect(for:)` รวม margin ไว้ด้วย ฟิลล์ตรง ๆ จึงล้นออกนอกเส้นขอบของเซลล์
    static func cellFillRect(_ r: NSRect, block: NSTextTableBlock) -> NSRect {
        func w(_ layer: NSTextBlock.Layer, _ e: NSRectEdge) -> CGFloat { block.width(for: layer, edge: e) }
        let l = w(.margin, .minX) + w(.border, .minX)
        let t = w(.margin, .minY) + w(.border, .minY)
        let rr = w(.margin, .maxX) + w(.border, .maxX)
        let b = w(.margin, .maxY) + w(.border, .maxY)
        return NSRect(x: r.minX + l, y: r.minY + t, width: max(0, r.width - l - rr), height: max(0, r.height - t - b))
    }

    override func drawBackground(forGlyphRange glyphsToShow: NSRange, at origin: NSPoint) {
        super.drawBackground(forGlyphRange: glyphsToShow, at: origin)
        guard let storage = textStorage, storage.length > 0, let container = textContainers.first else { return }
        let ns = storage.string as NSString
        let chars = characterRange(forGlyphRange: glyphsToShow, actualGlyphRange: nil)

        // ตารางที่ถูกเลือก: ไฮไลต์พื้นเหลืองทั้งเซลล์ เฉพาะเซลล์ที่เนื้อหาถูกเลือกครบทั้งช่อง (เลือกหลายช่อง/ทั้งตาราง)
        // เลือกแค่บางส่วนในช่องเดียวให้ใช้ไฮไลต์ข้อความปกติของระบบ ไม่ฟิลล์ทั้งช่อง
        if let tv = firstTextView, tv.selectedRange().length > 0 {
            let selected = tv.selectedRange()
            let sel = NSIntersectionRange(selected, chars)
            var q = sel.location
            while sel.length > 0, q < NSMaxRange(sel) {
                let pr = ns.paragraphRange(for: NSRange(location: q, length: 0))
                q = NSMaxRange(pr)
                guard storage.blockKind(at: pr.location).isTableCell,
                      let block = (storage.attribute(.paragraphStyle, at: pr.location, effectiveRange: nil) as? NSParagraphStyle)?.textBlocks.first as? NSTextTableBlock else { continue }
                guard Self.selectionCoversCell(selected, paragraph: pr, in: ns) else { continue }
                let g = glyphRange(forCharacterRange: pr, actualCharacterRange: nil)
                let r = Self.cellFillRect(boundsRect(for: block, glyphRange: g), block: block).offsetBy(dx: origin.x, dy: origin.y)
                Palette.selection.setFill()
                r.fill()
            }
        }

        // โค้ดในบรรทัด: พื้นมุมโค้ง
        Palette.codeBackground.setFill()
        storage.enumerateAttribute(.jotInline, in: chars, options: []) { v, r, _ in
            guard let raw = v as? Int, InlineStyle(rawValue: raw).contains(.code), !storage.blockKind(at: r.location).isCode else { return }
            let g = self.glyphRange(forCharacterRange: r, actualCharacterRange: nil)
            // ต่อบรรทัด: พื้นพอดีข้อความของบรรทัดนั้น (เดิมบรรทัดที่ตัดไปต่อบรรทัดใหม่ยืดเต็มความกว้างช่อง)
            self.enumerateLineFragments(forGlyphRange: g) { lineRect, used, _, fragGlyphs, _ in
                let inter = NSIntersectionRange(fragGlyphs, g)
                guard inter.length > 0 else { return }
                var tight = NSRect.zero
                self.enumerateEnclosingRects(forGlyphRange: inter, withinSelectedGlyphRange: NSRange(location: NSNotFound, length: 0), in: container) { r, stop in
                    tight = tight == .zero ? r : tight.union(r)
                }
                guard tight.width > 0 else { return }
                let h = Theme.monoSize + 6
                // ตำแหน่งแนวตั้งอิงเส้นฐานของข้อความ (บรรทัดที่มีรูปแทรกจะสูงกว่าปกติ ใช้กึ่งกลางบรรทัดไม่ได้)
                let baseline = lineRect.minY + self.location(forGlyphAt: inter.location).y
                let rr = NSRect(x: tight.minX + origin.x - 2, y: baseline + origin.y - Theme.monoSize * 0.78 - 3, width: tight.width + 4, height: h)
                NSBezierPath(roundedRect: rr, xRadius: 4, yRadius: 4).fill()
            }
        }

        // ระดับย่อหน้า
        var loc = chars.location
        while loc < NSMaxRange(chars) {
            let pr = ns.paragraphRange(for: NSRange(location: loc, length: 0))
            loc = NSMaxRange(pr)
            let kind = storage.blockKind(at: pr.location)
            guard kind != .paragraph, !kind.isHeading, !kind.isTableCell, let geo = geometry(for: pr) else { continue }
            let ox = origin.x, oy = origin.y
            switch kind {
            case .codeBlock, .raw:
                let hh = kind.isCode ? Theme.codeHeaderHeight : 0
                let r = NSRect(x: ox, y: oy + geo.minY - 8 - hh, width: container.size.width, height: geo.maxY - geo.minY + 16 + hh)
                Palette.codeBackground.setFill()
                NSBezierPath(roundedRect: r, xRadius: 6, yRadius: 6).fill()
                if kind.isCode, let l = languageLabel(forParagraphAt: pr.location, geo: geo) {
                    l.text.draw(at: NSPoint(x: l.rect.minX + ox + Self.labelPadding, y: l.rect.minY + oy + (l.rect.height - l.text.size().height) / 2))
                }
            case .quote:
                var bottom = geo.maxY
                if NSMaxRange(pr) < ns.length, storage.blockKind(at: NSMaxRange(pr)) == .quote { bottom += 4 }
                Palette.accent.setFill()
                NSBezierPath(roundedRect: NSRect(x: ox + 2, y: oy + geo.minY, width: 3, height: bottom - geo.minY), xRadius: 1.5, yRadius: 1.5).fill()
            case .thematicBreak:
                Palette.rule.setFill()
                NSRect(x: ox, y: oy + (geo.minY + geo.maxY) / 2 - 0.5, width: container.size.width, height: 1).fill()
            case .bullet(let level):
                Palette.text.setFill()
                let d: CGFloat = Theme.s(level % 2 == 0 ? 5 : 4.5)
                let cx = ox + CGFloat(level) * Theme.listIndent + Theme.listIndent / 2
                let cy = oy + geo.baseline - Theme.s(5)
                let dot = NSRect(x: cx - d / 2, y: cy - d / 2, width: d, height: d)
                if level % 2 == 0 { NSBezierPath(ovalIn: dot).fill() }
                else { Palette.text.setStroke(); let p = NSBezierPath(ovalIn: dot.insetBy(dx: 0.5, dy: 0.5)); p.lineWidth = 1; p.stroke() }
            case .ordered(let level):
                let n = orderedNumber(at: pr.location, level: level, storage: storage)
                let s = NSAttributedString(string: "\(n).", attributes: [.font: Fonts.body(.regular), .foregroundColor: Palette.secondaryText])
                let w = s.size().width
                let right = ox + CGFloat(level + 1) * Theme.listIndent - Theme.s(5)
                // วางบนฐานบรรทัดเดียวกับข้อความ
                let asc = Fonts.body(.regular).ascender
                s.draw(at: NSPoint(x: right - w, y: oy + geo.baseline - asc))
            case .task(let level, let checked):
                let size = Self.checkboxSize
                let box = NSRect(x: ox + CGFloat(level) * Theme.listIndent + (Theme.listIndent - size) / 2 + 1,
                                 y: oy + geo.baseline - size + Theme.s(3), width: size, height: size)
                let path = NSBezierPath(roundedRect: box.insetBy(dx: 0.75, dy: 0.75), xRadius: 4, yRadius: 4)
                if checked {
                    Palette.accent.setFill(); path.fill()
                    let c = NSBezierPath()
                    c.move(to: NSPoint(x: box.minX + 4, y: box.midY))
                    c.line(to: NSPoint(x: box.minX + 7, y: box.midY + 3.2))
                    c.line(to: NSPoint(x: box.maxX - 3.5, y: box.midY - 3.5))
                    c.lineWidth = 1.8; c.lineCapStyle = .round; c.lineJoinStyle = .round
                    Palette.onAccent.setStroke(); c.stroke()
                } else {
                    Palette.secondaryText.setStroke(); path.lineWidth = 1.5; path.stroke()
                }
            default: break
            }
        }
    }
}
