import AppKit

/// ตารางกลาง action -> SF Symbol ใช้ร่วมกันระหว่างแถบเครื่องมือ เมนูหลัก และเมนูคลิกขวา
/// (ปุ่มกับเมนูของ action เดียวกันได้ไอคอนเดียวกัน) เมนูมาตรฐานของระบบ (Cut/Copy/Find ฯลฯ) ไม่อยู่ในตาราง
enum MenuIcons {
    /// ชื่อ selector -> symbol (action ที่ต่างกันตาม tag ดู `name(for:tag:)`)
    static let symbols: [String: String] = [
        // inline
        "jotToggleBold:": "bold",
        "jotToggleItalic:": "italic",
        "jotToggleStrike:": "strikethrough",
        "jotToggleCode:": "chevron.left.forwardslash.chevron.right",
        // ลิงก์
        "jotEditLink:": "link",
        "jotOpenLink:": "arrow.up.right.square",
        "jotCopyLinkAddress:": "doc.on.doc",
        "jotRemoveLink:": "xmark.circle",
        // บล็อก
        "jotSetParagraph:": "paragraphsign",
        "jotToggleBullet:": "list.bullet",
        "jotToggleOrdered:": "list.number",
        "jotToggleTask:": "checklist",
        "jotToggleCheckOrExit:": "checkmark.square",
        "jotIndent:": "increase.indent",
        "jotOutdent:": "decrease.indent",
        "jotToggleQuote:": "text.quote",
        "jotToggleCodeBlock:": "curlybraces",
        "jotInsertImage:": "photo",
        "jotInsertVideo:": "play.rectangle",
        "jotInsertTable:": "tablecells",
        // ตาราง
        "jotSelectTable:": "rectangle.dashed",
        "jotTableRowAbove:": "arrow.up.to.line",
        "jotTableRowBelow:": "arrow.down.to.line",
        "jotTableColumnLeft:": "arrow.left.to.line",
        "jotTableColumnRight:": "arrow.right.to.line",
        "jotTableDeleteRow:": "minus.rectangle",
        "jotTableDeleteColumn:": "minus.rectangle.portrait",
        "jotTableDelete:": "trash",
        "jotTableAlignLeft:": "text.alignleft",
        "jotTableAlignCenter:": "text.aligncenter",
        "jotTableAlignRight:": "text.alignright",
        // รูปภาพ / วิดีโอ (เมนูคลิกขวา)
        "jotRevealImage:": "folder",
        "jotCopyImage:": "doc.on.doc",
        "jotEditImageAlt:": "pencil",
        "jotPlayVideo:": "play",
        "jotOpenVideoInYouTube:": "arrow.up.right.square",
        "jotCopyVideoLink:": "doc.on.doc",
        // มุมมอง
        "jotZoomIn:": "plus.magnifyingglass",
        "jotZoomOut:": "minus.magnifyingglass",
        "jotZoomReset:": "1.magnifyingglass",
    ]

    /// เมนูย่อยที่ไม่มี action ของตัวเอง (ชื่อเมนู -> symbol)
    static let submenuSymbols: [String: String] = ["Table": "tablecells", "Code Language": "curlybraces"]

    /// หัวข้อ: ระดับ 1 ใหญ่สุด -> 6 เล็กสุด
    static func headingSymbol(_ level: Int) -> String {
        level <= 1 ? "textformat.size.larger" : (level >= 5 ? "textformat.size.smaller" : "textformat.size")
    }

    static func name(for action: Selector?, tag: Int = 0) -> String? {
        guard let action else { return nil }
        let s = NSStringFromSelector(action)
        if s == "jotSetHeading:" { return headingSymbol(tag) }
        return symbols[s]
    }

    static func image(for action: Selector?, tag: Int = 0, label: String? = nil) -> NSImage? {
        guard let n = name(for: action, tag: tag) else { return nil }
        return NSImage(systemSymbolName: n, accessibilityDescription: label)
    }

    /// ใส่ไอคอนให้ทุกรายการ (รวมเมนูย่อย) ที่ action อยู่ในตาราง; ไม่แตะรายการที่มี image อยู่แล้ว
    static func decorate(_ menu: NSMenu) {
        for item in menu.items {
            if item.image == nil {
                if let img = image(for: item.action, tag: item.tag, label: item.title) { item.image = img }
                else if item.submenu != nil, let n = submenuSymbols[item.title] { item.image = NSImage(systemSymbolName: n, accessibilityDescription: item.title) }
            }
            if let sub = item.submenu { decorate(sub) }
        }
    }
}
