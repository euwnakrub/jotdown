import AppKit

enum MainMenu {
    private static func item(_ title: String, _ action: Selector?, _ key: String = "",
                             _ mods: NSEvent.ModifierFlags = [.command], tag: Int = 0) -> NSMenuItem {
        let i = NSMenuItem(title: title, action: action, keyEquivalent: key)
        if !key.isEmpty { i.keyEquivalentModifierMask = mods }
        i.tag = tag
        return i
    }

    private static func submenu(_ title: String, _ items: [NSMenuItem]) -> NSMenuItem {
        let m = NSMenu(title: title)
        items.forEach { m.addItem($0) }
        let host = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        host.submenu = m
        return host
    }

    static func build() -> NSMenu {
        let name = "Jotdown"
        let main = NSMenu(title: "main")

        // Jot
        let services = NSMenu(title: "Services")
        let servicesItem = NSMenuItem(title: "Services", action: nil, keyEquivalent: "")
        servicesItem.submenu = services
        NSApp.servicesMenu = services
        main.addItem(submenu(name, [
            item("About \(name)", #selector(NSApplication.orderFrontStandardAboutPanel(_:))),
            .separator(),
            servicesItem,
            .separator(),
            item("Hide \(name)", #selector(NSApplication.hide(_:)), "h"),
            item("Hide Others", #selector(NSApplication.hideOtherApplications(_:)), "h", [.command, .option]),
            item("Show All", #selector(NSApplication.unhideAllApplications(_:))),
            .separator(),
            item("Quit \(name)", #selector(NSApplication.terminate(_:)), "q"),
        ]))

        // ไฟล์
        let recent = NSMenu(title: "Open Recent")
        recent.addItem(item("Clear Menu", NSSelectorFromString("clearRecentDocuments:")))
        let recentItem = NSMenuItem(title: "Open Recent", action: nil, keyEquivalent: "")
        recentItem.submenu = recent
        let revert = submenu("Revert To…", [
            item("Last Saved Version", #selector(NSDocument.revertToSaved(_:))),
            item("Browse All Versions…", #selector(NSDocument.browseVersions(_:))),
        ])
        main.addItem(submenu("File", [
            item("New", #selector(NSDocumentController.newDocument(_:)), "n"),
            item("New Tab", NSSelectorFromString("newWindowForTab:"), "t"),
            item("Open…", #selector(NSDocumentController.openDocument(_:)), "o"),
            recentItem,
            .separator(),
            item("Close", #selector(NSWindow.performClose(_:)), "w"),
            item("Save", #selector(NSDocument.save(_:)), "s"),
            item("Save As…", #selector(NSDocument.saveAs(_:)), "s", [.command, .shift]),
            item("Rename…", #selector(NSDocument.rename(_:))),
            item("Move To…", #selector(NSDocument.move(_:))),
            revert,
        ]))

        // แก้ไข
        func find(_ t: String, _ k: String, _ mods: NSEvent.ModifierFlags = [.command], _ tag: Int) -> NSMenuItem {
            item(t, #selector(NSTextView.performFindPanelAction(_:)), k, mods, tag: tag)
        }
        main.addItem(submenu("Edit", [
            item("Undo", Selector(("undo:")), "z"),
            item("Redo", Selector(("redo:")), "z", [.command, .shift]),
            .separator(),
            item("Cut", #selector(NSText.cut(_:)), "x"),
            item("Copy", #selector(NSText.copy(_:)), "c"),
            item("Paste", #selector(NSText.paste(_:)), "v"),
            item("Select All", #selector(NSText.selectAll(_:)), "a"),
            .separator(),
            submenu("Find", [
                find("Find…", "f", [.command], 1),
                find("Find Next", "g", [.command], 2),
                find("Find Previous", "g", [.command, .shift], 3),
                find("Use Selection for Find", "e", [.command, .option], 7),
            ]),
        ]))

        // รูปแบบ
        func fmt(_ t: String, _ sel: String, _ k: String, _ mods: NSEvent.ModifierFlags, tag: Int = 0) -> NSMenuItem {
            item(t, NSSelectorFromString(sel), k, mods, tag: tag)
        }
        var headings: [NSMenuItem] = []
        for l in 1...6 { headings.append(fmt("Heading \(l)", "jotSetHeading:", "\(l)", [.command, .option], tag: l)) }
        main.addItem(submenu("Format", [
            fmt("Bold", "jotToggleBold:", "b", [.command]),
            fmt("Italic", "jotToggleItalic:", "i", [.command]),
            fmt("Strikethrough", "jotToggleStrike:", "x", [.command, .shift]),
            fmt("Inline Code", "jotToggleCode:", "e", [.command]),
            fmt("Link…", "jotEditLink:", "k", [.command]),
            fmt("Open Link", "jotOpenLink:", "\r", [.option]),
            fmt("Copy Link Address", "jotCopyLinkAddress:", "", []),
            .separator(),
            fmt("Paragraph", "jotSetParagraph:", "0", [.command, .option]),
        ] + headings + [
            .separator(),
            fmt("Bulleted List", "jotToggleBullet:", "8", [.command, .shift]),
            fmt("Numbered List", "jotToggleOrdered:", "7", [.command, .shift]),
            fmt("Checklist", "jotToggleTask:", "9", [.command, .shift]),
            fmt("Toggle Checkbox / Exit Code Block", "jotToggleCheckOrExit:", "\r", [.command]),
            .separator(),
            fmt("Indent", "jotIndent:", "", [.command]),
            fmt("Outdent", "jotOutdent:", "", [.command]),
            .separator(),
            fmt("Quote", "jotToggleQuote:", ".", [.command, .shift]),
            fmt("Code Block", "jotToggleCodeBlock:", "c", [.command, .option]),
            fmt("Insert Image…", "jotInsertImage:", "i", [.command, .shift]),
            fmt("Insert YouTube Video…", "jotInsertVideo:", "y", [.command, .control]),
            fmt("Insert Divider", "jotInsertDivider:", "-", [.command, .control]),
            .separator(),
            submenu("Table", [
                fmt("Insert Table", "jotInsertTable:", "t", [.command, .control]),
                .separator(),
                fmt("Select Table", "jotSelectTable:", "", []),
                .separator(),
                fmt("Insert Row Above", "jotTableRowAbove:", "", []),
                fmt("Insert Row Below", "jotTableRowBelow:", "", []),
                fmt("Insert Column Left", "jotTableColumnLeft:", "", []),
                fmt("Insert Column Right", "jotTableColumnRight:", "", []),
                .separator(),
                fmt("Delete Row", "jotTableDeleteRow:", "", []),
                fmt("Delete Column", "jotTableDeleteColumn:", "", []),
                fmt("Delete Table", "jotTableDelete:", "", []),
                .separator(),
                fmt("Align Column Left", "jotTableAlignLeft:", "", []),
                fmt("Align Column Center", "jotTableAlignCenter:", "", []),
                fmt("Align Column Right", "jotTableAlignRight:", "", []),
            ]),
        ]))

        // มุมมอง
        main.addItem(submenu("View", [
            item("Zoom In", NSSelectorFromString("jotZoomIn:"), "+", [.command]),
            { let i = item("Zoom In", NSSelectorFromString("jotZoomIn:"), "=", [.command]); i.isHidden = true; return i }(),
            item("Zoom Out", NSSelectorFromString("jotZoomOut:"), "-", [.command]),
            item("Actual Size", NSSelectorFromString("jotZoomReset:"), "0", [.command]),
            .separator(),
            item("Hide Toolbar", NSSelectorFromString("toggleToolbarShown:"), "t", [.command, .option]),
            item("Customize Toolbar…", NSSelectorFromString("runToolbarCustomizationPalette:")),
            .separator(),
            item("Show Tab Bar", NSSelectorFromString("toggleTabBar:")),
            item("Enter Full Screen", #selector(NSWindow.toggleFullScreen(_:)), "f", [.command, .control]),
        ]))

        // หน้าต่าง
        let windowMenu = NSMenu(title: "Window")
        [
            item("Minimize", #selector(NSWindow.performMiniaturize(_:)), "m"),
            item("Zoom", #selector(NSWindow.performZoom(_:))),
            .separator(),
            item("Show Previous Tab", NSSelectorFromString("selectPreviousTab:"), "\t", [.control, .shift]),
            item("Show Next Tab", NSSelectorFromString("selectNextTab:"), "\t", [.control]),
            item("Move Tab to New Window", NSSelectorFromString("moveTabToNewWindow:")),
            item("Merge All Windows", NSSelectorFromString("mergeAllWindows:")),
            .separator(),
            item("Bring All to Front", #selector(NSApplication.arrangeInFront(_:))),
        ].forEach { windowMenu.addItem($0) }
        let windowItem = NSMenuItem(title: "Window", action: nil, keyEquivalent: "")
        windowItem.submenu = windowMenu
        main.addItem(windowItem)
        NSApp.windowsMenu = windowMenu

        let helpMenu = NSMenu(title: "Help")
        helpMenu.addItem(item("Jotdown Help", #selector(NSApplication.showHelp(_:)), "?"))
        let helpItem = NSMenuItem(title: "Help", action: nil, keyEquivalent: "")
        helpItem.submenu = helpMenu
        main.addItem(helpItem)
        NSApp.helpMenu = helpMenu

        MenuIcons.decorate(main)      // ไอคอนจากตารางกลาง (เมนูระบบไม่อยู่ในตาราง จึงไม่เปลี่ยน)
        return main
    }
}
