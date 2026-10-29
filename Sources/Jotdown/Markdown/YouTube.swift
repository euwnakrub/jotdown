import Foundation

/// วิดีโอ YouTube ที่แยกจาก URL แล้ว
struct YouTubeRef: Equatable {
    var id: String
    var start: Int?          // วินาที (จาก t= / start=)

    var watchURL: URL { URL(string: "https://www.youtube.com/watch?v=\(id)" + (start.map { "&t=\($0)s" } ?? ""))! }
    /// URL ของ player ฝังแบบ privacy-enhanced
    var embedURL: URL {
        var q = "autoplay=1&rel=0&playsinline=1"
        if let s = start, s > 0 { q += "&start=\(s)" }
        return URL(string: "https://www.youtube-nocookie.com/embed/\(id)?\(q)")!
    }
    var thumbnailURL: URL { URL(string: "https://i.ytimg.com/vi/\(id)/hqdefault.jpg")! }
    func oEmbedURL(for original: String) -> URL {
        var c = URLComponents(string: "https://www.youtube.com/oembed")!
        c.queryItems = [URLQueryItem(name: "url", value: "https://www.youtube.com/watch?v=\(id)"), URLQueryItem(name: "format", value: "json")]
        return c.url!
    }
    /// "1:30" / "1:02:03" (nil ถ้าไม่มีเวลาเริ่ม)
    var startLabel: String? {
        guard let s = start, s > 0 else { return nil }
        let h = s / 3600, m = (s % 3600) / 60, sec = s % 60
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, sec) : String(format: "%d:%02d", m, sec)
    }
}

enum YouTubeLink {
    static let hosts: Set<String> = ["youtube.com", "youtu.be", "youtube-nocookie.com"]

    /// แยก ID/เวลาเริ่มจาก URL ทุกแบบ (watch, youtu.be, shorts, embed, live, v, m./music. subdomain) — nil ถ้าไม่ใช่ YouTube
    static func parse(_ raw: String) -> YouTubeRef? {
        var s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.hasPrefix("<"), s.hasSuffix(">") { s = String(s.dropFirst().dropLast()) }
        guard !s.isEmpty, !s.contains(where: { $0 == " " || $0 == "\n" }) else { return nil }
        let lower = s.lowercased()
        if !lower.hasPrefix("http://") && !lower.hasPrefix("https://") {
            guard lower.hasPrefix("www.") || lower.hasPrefix("m.") || lower.hasPrefix("music.") || hosts.contains(where: { lower.hasPrefix($0) }) else { return nil }
            s = "https://" + s
        }
        guard let c = URLComponents(string: s), var host = c.host?.lowercased() else { return nil }
        for p in ["www.", "m.", "music."] where host.hasPrefix(p) { host.removeFirst(p.count) }
        guard hosts.contains(host) else { return nil }
        let parts = c.path.split(separator: "/").map(String.init)
        var id: String?
        if host == "youtu.be" { id = parts.first }
        else if let first = parts.first {
            if first == "watch" { id = c.queryItems?.first(where: { $0.name == "v" })?.value }
            else if ["shorts", "embed", "live", "v"].contains(first), parts.count > 1 { id = parts[1] }
        }
        guard let id, isValidID(id) else { return nil }
        var start: Int?
        for name in ["t", "start"] { if let v = c.queryItems?.first(where: { $0.name == name })?.value, let t = parseTime(v) { start = t; break } }
        if start == nil, let f = c.fragment, f.hasPrefix("t="), let t = parseTime(String(f.dropFirst(2))) { start = t }
        return YouTubeRef(id: id, start: start)
    }

    static func isValidID(_ s: String) -> Bool { s.range(of: #"^[A-Za-z0-9_-]{11}$"#, options: .regularExpression) != nil }

    /// "90", "90s", "1m30s", "1h2m3s"
    static func parseTime(_ v: String) -> Int? {
        if let n = Int(v) { return n }
        guard v.range(of: #"^(\d+h)?(\d+m)?(\d+s)?$"#, options: .regularExpression) != nil, !v.isEmpty else { return nil }
        var total = 0, num = ""
        for ch in v {
            if ch.isNumber { num.append(ch); continue }
            let n = Int(num) ?? 0; num = ""
            total += ch == "h" ? n * 3600 : (ch == "m" ? n * 60 : n)
        }
        return total
    }
}

/// วิดีโอในเอกสาร: เก็บข้อความต้นฉบับ (`raw`) ไว้เขียนกลับตามเดิมทุกตัวอักษร (URL เปล่า / `[ชื่อ](url)` / `<url>`)
struct VideoRef: Equatable {
    var raw: String
    var url: String
    var title: String?

    var ref: YouTubeRef? { YouTubeLink.parse(url) }
    var encoded: String { [raw, url, title ?? "\u{2}"].joined(separator: "\u{1}") }
    init(raw: String, url: String, title: String? = nil) { self.raw = raw; self.url = url; self.title = title }
    init?(encoded: String) {
        let p = encoded.components(separatedBy: "\u{1}")
        guard p.count == 3 else { return nil }
        self.init(raw: p[0], url: p[1], title: p[2] == "\u{2}" ? nil : p[2])
    }
}

/// player ฝัง: HTML ที่โหลดด้วย baseURL ของ youtube-nocookie (ไม่งั้นเจอ error 153 เพราะไม่มี Referer) + รายงาน error ผ่าน IFrame API
enum YouTubePlayerHTML {
    static let baseURL = URL(string: "https://www.youtube-nocookie.com")!
    static let messageHandler = "jotYouTube"

    static func html(for ref: YouTubeRef) -> String {
        """
        <!doctype html><html><head><meta name="viewport" content="width=device-width,initial-scale=1">
        <style>html,body{margin:0;height:100%;background:#000;overflow:hidden}#p{position:absolute;inset:0;width:100%;height:100%}</style></head>
        <body><div id="p"></div>
        <script src="https://www.youtube.com/iframe_api"></script>
        <script>
        function post(m){ try { window.webkit.messageHandlers.\(messageHandler).postMessage(m) } catch(e) {} }
        function onYouTubeIframeAPIReady(){
          new YT.Player('p', { host: 'https://www.youtube-nocookie.com', videoId: '\(ref.id)',
            playerVars: { autoplay: 1, rel: 0, playsinline: 1, modestbranding: 1\(ref.start.map { ", start: \($0)" } ?? "") },
            events: { onReady: function(e){ e.target.playVideo(); post({ready:true}) }, onError: function(e){ post({error:e.data}) } } });
        }
        </script></body></html>
        """
    }

    /// ข้อความเมื่อเล่นไม่ได้ตามรหัส error ของ YouTube (nil = ไม่ใช่ error ที่ต้องแจ้ง)
    static func message(forError code: Int) -> String? {
        switch code {
        case 101, 150, 153: return "This video can't be played here"
        case 100: return "This video is unavailable"
        case 2, 5: return "This video can't be played here"
        default: return nil
        }
    }
}
