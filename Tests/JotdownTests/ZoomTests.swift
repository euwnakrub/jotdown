import Testing
import AppKit
@testable import Jotdown

@MainActor @Suite(.serialized) struct ZoomTests {
    init() { Theme.setZoom(1, persist: false) }

    @Test func defaultSizes() {
        #expect(Theme.bodySize == 14)
        #expect(Theme.headingSpec(1).size == 24 && Theme.headingSpec(2).size == 19 && Theme.headingSpec(3).size == 16)
        #expect(Theme.headingSpec(4).size == Theme.bodySize && Theme.headingSpec(6).weight == .bold)
        #expect(Theme.monoSize == 12.5)
        #expect(Theme.font(for: .paragraph).pointSize == 14)
        #expect(Theme.font(for: .heading(1)).pointSize == 24)
        #expect(Theme.font(for: .codeBlock("")).pointSize == 12.5)
        #expect(Theme.columnMaxWidth == 720)        // คอลัมน์สูงสุดคงเดิม
    }

    @Test func zoomClampsAndSnapsToTenPercent() {
        defer { Theme.setZoom(1, persist: false) }
        #expect(Theme.setZoom(1.04, persist: false) == false && Theme.zoom == 1)     // ปัดเป็น 1.0 = ไม่เปลี่ยน
        #expect(Theme.setZoom(5, persist: false) && Theme.zoom == 2.0)
        #expect(Theme.setZoom(0.1, persist: false) && abs(Theme.zoom - 0.7) < 0.001)
        #expect(Theme.setZoom(1.26, persist: false) && abs(Theme.zoom - 1.3) < 0.001)
        // ขนาดตามสัดส่วน
        Theme.setZoom(2.0, persist: false)
        #expect(Theme.bodySize == 28 && Theme.font(for: .paragraph).pointSize == 28 && Theme.headingSpec(1).size == 48)
        #expect(Theme.listIndent == 44)
    }

    @Test func stepsOfTenPercentAcrossTheRange() {
        defer { Theme.setZoom(1, persist: false) }
        var seen: [CGFloat] = [Theme.zoom]
        for _ in 0..<20 where Theme.setZoom(Theme.zoom + Theme.zoomStep, persist: false) { seen.append(Theme.zoom) }
        #expect(abs(seen.last! - 2.0) < 0.001 && seen.count == 11)          // 1.0 ... 2.0
        var down = 0
        for _ in 0..<20 where Theme.setZoom(Theme.zoom - Theme.zoomStep, persist: false) { down += 1 }
        #expect(abs(Theme.zoom - 0.7) < 0.001 && down == 13)                // 2.0 ... 0.7
    }

    @Test func persistsInUserDefaults() {
        defer { Theme.setZoom(1, persist: false); UserDefaults.standard.removeObject(forKey: Theme.zoomKey) }
        Theme.setZoom(1.5)
        #expect(UserDefaults.standard.double(forKey: Theme.zoomKey) == 1.5)
    }

    @Test func zoomRestylesAllOpenDocumentsWithoutChangingTheFile() {
        defer { Theme.setZoom(1, persist: false) }
        let (doc1, vc1) = makeEditor("# หัวข้อ\n\nเนื้อหา **หนา** `โค้ด`\n\n- รายการ\n\n| a | b |\n| --- | --- |\n| 1 | 2 |\n\n```\ncode\n```\n")
        let (doc2, vc2) = makeEditor("ย่อหน้าอื่น\n")
        let before1 = doc1.currentMarkdown, before2 = doc2.currentMarkdown
        func size(_ doc: JotdownDocument, _ needle: String) -> CGFloat {
            let r = (doc.textStorage.string as NSString).range(of: needle)
            return (doc.textStorage.attribute(.font, at: r.location, effectiveRange: nil) as! NSFont).pointSize
        }
        #expect(size(doc1, "เนื้อหา") == 14 && size(doc1, "หัวข้อ") == 24 && size(doc1, "code") == 12.5)
        // ผ่าน action ของเมนูเหมือนผู้ใช้กด
        let delegate = AppDelegate()
        NSDocumentController.shared.addDocument(doc1)
        NSDocumentController.shared.addDocument(doc2)
        defer { NSDocumentController.shared.removeDocument(doc1); NSDocumentController.shared.removeDocument(doc2) }
        delegate.jotZoomIn(nil); delegate.jotZoomIn(nil)                   // 120%
        #expect(abs(Theme.zoom - 1.2) < 0.001)
        #expect(abs(size(doc1, "เนื้อหา") - 16.8) < 0.01 && abs(size(doc1, "หัวข้อ") - 28.8) < 0.01 && abs(size(doc1, "code") - 15) < 0.01)
        #expect(abs(size(doc2, "ย่อหน้าอื่น") - 16.8) < 0.01)
        #expect(doc1.currentMarkdown == before1 && doc2.currentMarkdown == before2)
        #expect(!doc1.saveDebouncer.isPending)
        // ตารางยังถูกคอลัมน์หลังซูม
        vc1.textView.layoutManager!.ensureLayout(for: vc1.textView.textContainer!)
        vc1.textView.repairTableLayoutIfNeeded()
        #expect(vc1.textView.tableLayoutIsConsistent())
        delegate.jotZoomOut(nil)                                           // 110%
        #expect(size(doc1, "เนื้อหา") > 15 && size(doc1, "เนื้อหา") < 16)
        delegate.jotZoomReset(nil)
        #expect(Theme.zoom == 1 && size(doc1, "เนื้อหา") == 14 && size(doc2, "ย่อหน้าอื่น") == 14)
        _ = vc2
    }

    @Test func typingAttributesFollowZoom() {
        defer { Theme.setZoom(1, persist: false) }
        let (doc, vc) = makeEditor("abc\n")
        NSDocumentController.shared.addDocument(doc); defer { NSDocumentController.shared.removeDocument(doc) }
        vc.textView.select(3)
        AppDelegate.changeZoom(1.5)
        #expect((vc.textView.typingAttributes[.font] as? NSFont)?.pointSize == 21)
    }

    @Test func menuItemsAndShortcuts() {
        _ = NSApplication.shared
        let menu = MainMenu.build()
        let view = menu.items.first { $0.title == "View" }!.submenu!
        let zi = view.items.filter { $0.title == "Zoom In" }
        #expect(zi.count == 2)
        #expect(zi.contains { $0.keyEquivalent == "+" && $0.keyEquivalentModifierMask == [.command] })
        #expect(zi.contains { $0.keyEquivalent == "=" && $0.keyEquivalentModifierMask == [.command] && $0.isHidden })
        let zo = view.items.first { $0.title == "Zoom Out" }!
        #expect(zo.keyEquivalent == "-" && zo.keyEquivalentModifierMask == [.command])
        let ac = view.items.first { $0.title == "Actual Size" }!
        #expect(ac.keyEquivalent == "0" && ac.keyEquivalentModifierMask == [.command])
        // ⌘0 ไม่ชนกับ Paragraph (⌥⌘0)
        let fmt = menu.items.first { $0.title == "Format" }!.submenu!
        let para = fmt.items.first { $0.title == "Paragraph" }!
        #expect(para.keyEquivalentModifierMask == [.command, .option])
        // เมนู enabled/disabled ตามช่วงซูม
        let d = AppDelegate()
        defer { Theme.setZoom(1, persist: false) }
        #expect(!d.validateMenuItem(ac))
        Theme.setZoom(2.0, persist: false); #expect(!d.validateMenuItem(zi[0])); #expect(d.validateMenuItem(zo)); #expect(d.validateMenuItem(ac))
        Theme.setZoom(0.7, persist: false); #expect(d.validateMenuItem(zi[0])); #expect(!d.validateMenuItem(zo))
    }
}
