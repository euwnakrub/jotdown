import AppKit
import CoreText

/// ฟอนต์ IBM Plex Sans Thai (หัวข้อ) และ Looped (เนื้อความ) — ลงทะเบียนครั้งเดียวต่อกระบวนการ
/// ถ้าหาไม่เจอ ใช้ฟอนต์ระบบแทน (ห้าม crash)
enum Fonts {
    enum Weight: String { case regular = "Regular", medium = "Medium", semibold = "SemiBold", bold = "Bold" }

    /// ลำดับค้นหา: env JOTDOWN_FONTS_DIR → Bundle.main/Resources/Fonts → <repo>/Resources/Fonts
    static func candidateDirectories() -> [URL] {
        var dirs: [URL] = []
        if let env = ProcessInfo.processInfo.environment["JOTDOWN_FONTS_DIR"], !env.isEmpty {
            dirs.append(URL(fileURLWithPath: env, isDirectory: true))
        }
        if let r = Bundle.main.resourceURL { dirs.append(r.appendingPathComponent("Fonts", isDirectory: true)) }
        // Sources/Jotdown/Style/Fonts.swift -> root
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        dirs.append(root.appendingPathComponent("Resources/Fonts", isDirectory: true))
        return dirs
    }

    @discardableResult
    static func registerAll() -> Int { registered }

    private static let registered: Int = {
        let fm = FileManager.default
        for dir in candidateDirectories() {
            guard let files = try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil) else { continue }
            let fonts = files.filter { ["ttf", "otf"].contains($0.pathExtension.lowercased()) }
            if fonts.isEmpty { continue }
            var n = 0
            for f in fonts {
                var err: Unmanaged<CFError>?
                // error "already registered" ไม่ใช่ปัญหา
                if CTFontManagerRegisterFontsForURL(f as CFURL, .process, &err) { n += 1 }
            }
            return n
        }
        return 0
    }()

    private static func weightFallback(_ w: Weight) -> NSFont.Weight {
        switch w { case .regular: return .regular; case .medium: return .medium; case .semibold: return .semibold; case .bold: return .bold }
    }

    /// เนื้อความ: Plex Sans Thai Looped
    static func body(_ weight: Weight = .regular, size: CGFloat = Theme.bodySize) -> NSFont {
        font("IBMPlexSansThaiLooped-\(weight.rawValue)", size: size, weight: weight)
    }

    /// หัวข้อ: Plex Sans Thai
    static func heading(_ weight: Weight, size: CGFloat) -> NSFont {
        font("IBMPlexSansThai-\(weight.rawValue)", size: size, weight: weight)
    }

    private static func font(_ name: String, size: CGFloat, weight: Weight) -> NSFont {
        registerAll()
        return NSFont(name: name, size: size) ?? NSFont.systemFont(ofSize: size, weight: weightFallback(weight))
    }
}
