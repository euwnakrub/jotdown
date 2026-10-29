import Foundation

/// ปลายทางของลิงก์หลัง resolve (ฟังก์ชันล้วน ทดสอบได้โดยไม่เปิดอะไรจริง)
enum LinkDestination: Equatable {
    case web(URL)              // http(s), mailto, tel
    case file(URL)             // ไฟล์ที่มีอยู่ (เปิดด้วยแอปค่าเริ่มต้น)
    case markdown(URL)         // .md / .markdown ที่มีอยู่ (เปิดใน Jotdown)
    case anchor(String)        // #หัวข้อ
    case missingFile(String)   // ไม่พบไฟล์ (path ที่ resolve แล้ว)
    case needsSave             // path สัมพัทธ์ในเอกสารที่ยังไม่ได้บันทึก
    case invalid
}

enum LinkResolver {
    static let fileExtensions: Set<String> = ["md", "markdown", "txt", "pdf", "png", "jpg", "jpeg", "gif", "webp", "svg", "heic", "doc", "docx", "xls", "xlsx", "ppt", "pptx", "csv", "json", "zip", "html", "htm", "rtf", "swift", "py", "js", "key", "pages", "numbers"]

    static func looksLikeDomain(_ s: String) -> Bool {
        if s.lowercased().hasPrefix("www.") { return true }
        let host = s.split(separator: "/", maxSplits: 1, omittingEmptySubsequences: false).first.map(String.init) ?? s
        guard host.range(of: #"^[A-Za-z0-9][A-Za-z0-9-]*(\.[A-Za-z0-9-]+)+(:\d+)?$"#, options: .regularExpression) != nil else { return false }
        let tld = host.split(separator: ".").last.map { String($0).lowercased() } ?? ""
        return !fileExtensions.contains(tld) || s.contains("/") && !(s.hasSuffix("." + tld))
    }

    static func resolve(_ raw: String, base: URL?, fileExists: (URL) -> Bool = { FileManager.default.fileExists(atPath: $0.path) }) -> LinkDestination {
        let s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !s.isEmpty else { return .invalid }
        if s.hasPrefix("#") { return s.count > 1 ? .anchor(String(s.dropFirst())) : .invalid }
        let lower = s.lowercased()
        for scheme in ["http://", "https://", "mailto:", "tel:"] where lower.hasPrefix(scheme) {
            return URL(string: s).map { .web($0) } ?? .invalid
        }
        if lower.hasPrefix("file:") {
            guard let u = URL(string: s) else { return .invalid }
            return classify(fileURL: URL(fileURLWithPath: u.path), fileExists: fileExists)
        }
        if looksLikeDomain(s) { return URL(string: "https://" + s).map { .web($0) } ?? .invalid }
        // path: ตัด #fragment / ?query ออก
        var path = s
        if let h = path.firstIndex(of: "#") { path = String(path[..<h]) }
        path = path.removingPercentEncoding ?? path
        let url: URL
        if path.hasPrefix("/") { url = URL(fileURLWithPath: path) }
        else if path.hasPrefix("~") { url = URL(fileURLWithPath: (path as NSString).expandingTildeInPath) }
        else {
            guard let base else { return .needsSave }
            url = base.appendingPathComponent(path).standardizedFileURL
        }
        return classify(fileURL: url, fileExists: fileExists)
    }

    private static func classify(fileURL url: URL, fileExists: (URL) -> Bool) -> LinkDestination {
        guard fileExists(url) else { return .missingFile(url.path) }
        let ext = url.pathExtension.lowercased()
        return ext == "md" || ext == "markdown" ? .markdown(url) : .file(url)
    }

    // MARK: - slug ของหัวข้อ (แบบ GitHub: ตัวพิมพ์เล็ก ตัดเครื่องหมาย เว้นวรรค -> "-", รองรับภาษาไทย)
    static func slug(_ s: String) -> String {
        var out = ""
        for ch in s.lowercased() {
            if ch == " " || ch == "\t" { out.append("-"); continue }
            if ch == "-" || ch == "_" { out.append(ch); continue }
            let isMark = ch.unicodeScalars.contains { [.nonspacingMark, .spacingMark].contains($0.properties.generalCategory) }
            if ch.isLetter || ch.isNumber || isMark { out.append(ch) }
        }
        return out
    }

    /// slug ของหัวข้อทั้งเอกสารตามลำดับ (หัวข้อซ้ำต่อท้าย -1, -2 แบบ GitHub)
    static func slugs(forHeadings titles: [String]) -> [String] {
        var seen: [String: Int] = [:]
        return titles.map { t in
            let base = slug(t)
            let n = seen[base, default: 0]
            seen[base] = n + 1
            return n == 0 ? base : "\(base)-\(n)"
        }
    }

    /// ตัดกลางด้วย … เมื่อยาวเกิน `max` อักขระ (สำหรับแสดงในแถบลิงก์)
    static func display(_ url: String, max: Int = 44) -> String {
        let s = (url.hasPrefix("wiki:") ? String(url.dropFirst(5)) : url).replacingOccurrences(of: "https://", with: "").replacingOccurrences(of: "http://", with: "")
        guard s.count > max, max > 3 else { return s }
        let head = (max - 1) / 2 + (max - 1) % 2, tail = (max - 1) / 2
        return String(s.prefix(head)) + "…" + String(s.suffix(tail))
    }

    /// ไอคอนของแถบ: globe สำหรับเว็บ, doc สำหรับไฟล์/อื่น ๆ
    static func symbol(for raw: String) -> String {
        let l = raw.lowercased()
        if l.hasPrefix("wiki:") { return "doc" }
        if l.hasPrefix("mailto:") { return "envelope" }
        if l.hasPrefix("#") { return "number" }
        if l.hasPrefix("http://") || l.hasPrefix("https://") || looksLikeDomain(raw) { return "globe" }
        return "doc"
    }
}

/// ลิงก์ที่ชี้/เคอร์เซอร์อยู่
struct LinkHit: Equatable {
    var range: NSRange
    var url: String
}

/// สถานะแสดง/ซ่อนแถบลิงก์ (ฟังก์ชันล้วนตามเวลาที่ฉีดเข้ามา)
struct LinkBarState {
    static let hoverDelay: TimeInterval = 0.4
    static let leaveDelay: TimeInterval = 0.3

    private var hover: LinkHit?
    private var hoverSince: TimeInterval = 0
    private var leftAt: TimeInterval?
    private var shown: LinkHit?              // ลิงก์ที่แสดงอยู่เพราะเมาส์
    private var caret: LinkHit?
    private var panelHover = false
    private var suppressed = false           // พิมพ์/scroll/หน้าต่างไม่ active: ซ่อนจนกว่าจะมีการชี้/ย้ายเคอร์เซอร์ใหม่

    mutating func mouseOver(_ hit: LinkHit?, at t: TimeInterval) {
        if let hit {
            if hit != hover { hoverSince = t; if shown != nil && shown != hit { shown = nil }; suppressed = false }
            hover = hit; leftAt = nil
        } else if hover != nil {
            hover = nil; leftAt = t
        }
    }
    mutating func panelMouse(inside: Bool, at t: TimeInterval) {
        panelHover = inside
        if !inside, hover == nil, leftAt == nil { leftAt = t }
    }
    mutating func caretMoved(_ hit: LinkHit?) { caret = hit; if hit != nil { suppressed = false } }
    mutating func invalidate() { suppressed = true; shown = nil; hover = nil; leftAt = nil; caret = nil }
    mutating func windowResigned() { invalidate(); caret = nil }

    /// ลิงก์ที่ควรแสดงแถบ ณ เวลา t (nil = ซ่อน)
    mutating func visible(at t: TimeInterval) -> LinkHit? {
        if suppressed { return nil }
        if let h = hover, t - hoverSince >= Self.hoverDelay { shown = h }
        if hover == nil, !panelHover, let l = leftAt, t - l >= Self.leaveDelay { shown = nil; leftAt = nil }
        return shown ?? caret
    }
}
