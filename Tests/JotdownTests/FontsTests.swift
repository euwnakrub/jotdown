import Testing
import AppKit
@testable import Jotdown

@Suite struct FontsTests {
    @Test func registersBothFamilies() {
        // JOTDOWN_FONTS_DIR ไม่ได้ตั้ง => ใช้ <repo>/Resources/Fonts ผ่าน fallback; ตั้งชัดเจนให้ผ่าน env ใน test.sh ไม่ได้ จึงเช็กตรง ๆ
        setenv("JOTDOWN_FONTS_DIR", projectRoot.appendingPathComponent("Resources/Fonts").path, 1)
        #expect(Fonts.registerAll() > 0 || NSFont(name: "IBMPlexSansThai-Regular", size: 16) != nil)
        for w in ["Regular", "Medium", "SemiBold", "Bold"] {
            #expect(NSFont(name: "IBMPlexSansThai-\(w)", size: 16) != nil, "Plex \(w)")
            #expect(NSFont(name: "IBMPlexSansThaiLooped-\(w)", size: 16) != nil, "Looped \(w)")
        }
        #expect(Theme.font(for: .paragraph).fontName == "IBMPlexSansThaiLooped-Regular")
        #expect(Theme.font(for: .heading(1)).fontName == "IBMPlexSansThai-SemiBold")
    }

    @Test func missingDirectoryFallsBackWithoutCrash() {
        #expect(Fonts.body(.bold, size: 12).pointSize == 12)
    }

    @Test func columnInsetCentersAt720() {
        #expect(EditorTextView.horizontalInset(forWidth: 900) == 90)
        #expect(EditorTextView.horizontalInset(forWidth: 480) == 24)
        #expect(EditorTextView.horizontalInset(forWidth: 1440) == 360)
    }
}
