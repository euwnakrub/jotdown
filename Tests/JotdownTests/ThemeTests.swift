import Testing
import AppKit
@testable import Jotdown

@Suite struct ThemeTests {
    @Test func textAndLinkContrastMeetsAA() {
        let p = Palette.self
        for (name, fg, bg) in [("text light", p.textHex.light, p.paperHex.light), ("text dark", p.textHex.dark, p.paperHex.dark),
                               ("link light", p.linkHex.light, p.paperHex.light), ("link dark", p.linkHex.dark, p.paperHex.dark),
                               ("secondary light", p.secondaryTextHex.light, p.paperHex.light), ("secondary dark", p.secondaryTextHex.dark, p.paperHex.dark),
                               ("text on code bg light", p.textHex.light, p.codeBackgroundHex.light), ("text on code bg dark", p.textHex.dark, p.codeBackgroundHex.dark),
                               ("text on selection light", p.textHex.light, p.selectionHex.light), ("text on selection dark", p.textHex.dark, p.selectionHex.dark),
                               ("text on table header light", p.textHex.light, p.tableHeaderHex.light), ("text on table header dark", p.textHex.dark, p.tableHeaderHex.dark)] {
            let c = Palette.contrast(fg, bg)
            #expect(c >= 4.5, Comment(rawValue: "\(name): \(c)"))
        }
    }

    @Test func paperIsWarmNotBrightYellow() {
        #expect(Palette.paperHex.light == 0xFFFDF5)
        #expect(Palette.paperHex.dark == 0x1F1C17)
    }

    @Test func colorsAreDynamic() {
        let light = NSAppearance(named: .aqua)!, dark = NSAppearance(named: .darkAqua)!
        func rgb(_ c: NSColor, _ a: NSAppearance) -> UInt32 {
            var v: UInt32 = 0
            a.performAsCurrentDrawingAppearance {
                let s = c.usingColorSpace(.sRGB)!
                v = (UInt32((s.redComponent * 255).rounded()) << 16) | (UInt32((s.greenComponent * 255).rounded()) << 8) | UInt32((s.blueComponent * 255).rounded())
            }
            return v
        }
        #expect(rgb(Palette.paper, light) == Palette.paperHex.light)
        #expect(rgb(Palette.paper, dark) == Palette.paperHex.dark)
        #expect(rgb(Palette.link, light) == Palette.linkHex.light)
        #expect(rgb(Palette.link, dark) == Palette.linkHex.dark)
    }

    @Test func editorUsesPalette() {
        let a = Theme.attributes(for: .paragraph, inline: [], link: "https://x.y")
        #expect(a[.foregroundColor] as? NSColor === Palette.link)
        #expect(a[.underlineColor] as? NSColor === Palette.linkUnderline)
        #expect(Theme.attributes(for: .paragraph)[.foregroundColor] as? NSColor === Palette.text)
    }
}
