import AppKit

/// ภาพตัวอย่าง + ชื่อวิดีโอ/ช่อง (oEmbed ไม่ต้องใช้ key) โหลดเบื้องหลัง cache ในหน่วยความจำ ไม่บล็อก main thread
final class YouTubeMeta {
    struct Info {
        var thumbnail: CGImage?
        var title: String?
        var channel: String?
        var thumbFailed = false
        var metaFailed = false
        var isLoading: Bool { thumbnail == nil && !thumbFailed }
    }

    static let shared = YouTubeMeta()
    /// เทสต์ใส่ URLSession ที่ใช้ URLProtocol ปลอม
    var session: URLSession = .shared
    private var cache: [String: Info] = [:]
    private var started: Set<String> = []
    private let lock = NSLock()

    func info(for ref: YouTubeRef) -> Info {
        lock.lock()
        let existing = cache[ref.id]
        let isStarted = started.contains(ref.id)
        if !isStarted { started.insert(ref.id); cache[ref.id] = Info() }
        lock.unlock()
        if !isStarted { fetch(ref) }
        return existing ?? Info()
    }

    func clear() { lock.lock(); cache = [:]; started = []; lock.unlock() }

    private func update(_ id: String, _ f: (inout Info) -> Void) {
        lock.lock(); var i = cache[id] ?? Info(); f(&i); cache[id] = i; lock.unlock()
        DispatchQueue.main.async { NotificationCenter.default.post(name: .jotImageLoaded, object: nil) }
    }

    private func fetch(_ ref: YouTubeRef) {
        session.dataTask(with: ref.thumbnailURL) { [self] data, resp, error in
            if let data, error == nil, (resp as? HTTPURLResponse).map({ (200..<300).contains($0.statusCode) }) ?? true,
               let src = CGImageSourceCreateWithData(data as CFData, nil),
               let img = CGImageSourceCreateThumbnailAtIndex(src, 0, [kCGImageSourceCreateThumbnailFromImageAlways: true, kCGImageSourceCreateThumbnailWithTransform: true, kCGImageSourceThumbnailMaxPixelSize: 1440, kCGImageSourceShouldCacheImmediately: true] as CFDictionary) {
                update(ref.id) { $0.thumbnail = img }
            } else { update(ref.id) { $0.thumbFailed = true } }
        }.resume()
        session.dataTask(with: ref.oEmbedURL(for: "")) { [self] data, _, error in
            if let data, error == nil, let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any], let title = obj["title"] as? String {
                update(ref.id) { $0.title = title; $0.channel = obj["author_name"] as? String }
            } else { update(ref.id) { $0.metaFailed = true } }
        }.resume()
    }
}

// MARK: - attachment ของการ์ดวิดีโอ (TextKit 1)
final class VideoAttachment: NSTextAttachment {
    let ref: VideoRef
    init(ref: VideoRef) {
        self.ref = ref
        super.init(data: nil, ofType: nil)
        attachmentCell = VideoCell(ref: ref)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) not supported") }
}

final class VideoCell: NSTextAttachmentCell {
    static let barHeight: CGFloat = 44
    let ref: VideoRef
    init(ref: VideoRef) { self.ref = ref; super.init(textCell: "") }
    required init(coder: NSCoder) { fatalError("init(coder:) not supported") }

    /// ส่วนภาพ 16:9 ของการ์ด (ที่ player จะวางทับ) ในพิกัดของ cellFrame
    static func videoArea(in frame: NSRect) -> NSRect { NSRect(x: frame.minX, y: frame.minY, width: frame.width, height: max(frame.height - barHeight, 1)) }

    override func cellFrame(for textContainer: NSTextContainer, proposedLineFragment lineFrag: NSRect, glyphPosition position: NSPoint, characterIndex charIndex: Int) -> NSRect {
        let w = max(min(lineFrag.width - position.x, Theme.columnMaxWidth), 200)
        return NSRect(x: 0, y: 0, width: w, height: (w * 9 / 16).rounded() + Self.barHeight)
    }
    override func cellSize() -> NSSize { NSSize(width: 320, height: 180 + Self.barHeight) }
    override func cellBaselineOffset() -> NSPoint { .zero }
    override func wantsToTrackMouse() -> Bool { false }

    static func playButtonRect(in area: NSRect) -> NSRect {
        let d: CGFloat = 64
        return NSRect(x: area.midX - d / 2, y: area.midY - d / 2, width: d, height: d)
    }

    override func draw(withFrame cellFrame: NSRect, in controlView: NSView?, characterIndex charIndex: Int, layoutManager: NSLayoutManager) {
        let selected: Bool = {
            guard let tv = controlView as? NSTextView else { return false }
            let r = tv.selectedRange()
            return r.length > 0 && NSLocationInRange(charIndex, r)
        }()
        let radius: CGFloat = 10
        let card = NSBezierPath(roundedRect: cellFrame, xRadius: radius, yRadius: radius)
        let area = Self.videoArea(in: cellFrame)
        let yt = YouTubeLink.parse(ref.url)
        let info = yt.map { YouTubeMeta.shared.info(for: $0) } ?? YouTubeMeta.Info(thumbFailed: true)

        NSGraphicsContext.saveGraphicsState()
        card.addClip()
        // พื้นการ์ด + แถบล่าง
        Palette.codeBackground.setFill(); cellFrame.fill()
        if let thumb = info.thumbnail, let ctx = NSGraphicsContext.current?.cgContext {
            // aspect-fill ในพื้นที่ 16:9 (ภาพ hqdefault มีแถบดำบน-ล่าง จึงตัดขอบออกเล็กน้อย)
            let iw = CGFloat(thumb.width), ih = CGFloat(thumb.height)
            let scale = max(area.width / iw, area.height / (ih * 0.75))
            let dw = iw * scale, dh = ih * scale
            ctx.saveGState()
            ctx.clip(to: area)
            ctx.translateBy(x: area.midX - dw / 2, y: area.midY + dh / 2)   // view flipped: พลิกให้ภาพไม่หัวกลับ
            ctx.scaleBy(x: 1, y: -1)
            ctx.interpolationQuality = .high
            ctx.draw(thumb, in: CGRect(x: 0, y: 0, width: dw, height: dh))
            ctx.restoreGState()
        } else {
            NSColor.black.withAlphaComponent(0.08).setFill(); area.fill()
        }
        // ปุ่ม ▶ กลางภาพ (การ์ดจางเมื่อไม่มีภาพ)
        let ok = info.thumbnail != nil
        let pb = Self.playButtonRect(in: area)
        NSColor.black.withAlphaComponent(ok ? 0.62 : 0.28).setFill()
        NSBezierPath(ovalIn: pb).fill()
        let tri = NSBezierPath()
        tri.move(to: NSPoint(x: pb.midX - 8, y: pb.midY - 13))
        tri.line(to: NSPoint(x: pb.midX - 8, y: pb.midY + 13))
        tri.line(to: NSPoint(x: pb.midX + 14, y: pb.midY))
        tri.close()
        NSColor.white.setFill(); tri.fill()
        if !ok, info.thumbFailed {
            // โหลดภาพไม่ได้: ไอคอน + URL
            let t = NSAttributedString(string: LinkResolver.display(ref.url, max: 60), attributes: [.font: Fonts.body(.regular, size: 12), .foregroundColor: Palette.secondaryText])
            t.draw(at: NSPoint(x: area.minX + 14, y: area.minY + 12))
        }
        // แถบล่าง: ชื่อ · ช่อง + เวลาเริ่ม
        let bar = NSRect(x: cellFrame.minX, y: cellFrame.maxY - Self.barHeight, width: cellFrame.width, height: Self.barHeight)
        Palette.paper.withAlphaComponent(0.55).setFill(); bar.fill()
        let title = ref.title ?? info.title ?? LinkResolver.display(ref.url, max: 48)
        var sub = info.channel ?? ""
        if let l = yt?.startLabel { sub += (sub.isEmpty ? "" : " · ") + "starts at " + l }
        if sub.isEmpty { sub = "YouTube" }
        let para = NSMutableParagraphStyle(); para.lineBreakMode = .byTruncatingTail
        NSAttributedString(string: title, attributes: [.font: Fonts.body(.semibold, size: 13), .foregroundColor: Palette.text, .paragraphStyle: para])
            .draw(in: NSRect(x: bar.minX + 14, y: bar.minY + 5, width: bar.width - 28, height: 18))
        NSAttributedString(string: sub, attributes: [.font: Fonts.body(.regular, size: 11.5), .foregroundColor: Palette.secondaryText, .paragraphStyle: para])
            .draw(in: NSRect(x: bar.minX + 14, y: bar.minY + 23, width: bar.width - 28, height: 16))
        NSGraphicsContext.restoreGraphicsState()

        Palette.tableBorder.setStroke(); card.lineWidth = 1; card.stroke()
        if selected {
            Palette.accent.setStroke()
            let b = NSBezierPath(roundedRect: cellFrame.insetBy(dx: 1, dy: 1), xRadius: radius, yRadius: radius)
            b.lineWidth = 2.5; b.stroke()
        }
    }
}
