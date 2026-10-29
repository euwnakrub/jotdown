import AppKit
import ImageIO

extension Notification.Name {
    static let jotImageLoaded = Notification.Name("JotImageLoaded")
}

// MARK: - โหลดรูปเบื้องหลัง + cache ในหน่วยความจำ
final class ImageLoader {
    enum State {
        case loading
        case loaded(CGImage, CGSize)      // รูปที่ย่อแล้ว, ขนาดจริงเป็นพิกเซล
        case failed(String)
    }

    static let shared = ImageLoader()
    /// เทสต์ใส่ URLSession ที่ใช้ URLProtocol ปลอมได้
    var session: URLSession = .shared
    private var cache: [String: State] = [:]
    private let lock = NSLock()
    private let queue = DispatchQueue(label: "jot.image-loader", qos: .userInitiated, attributes: .concurrent)

    static var maxPixel: Int { Int(Theme.columnMaxWidth * (NSScreen.main?.backingScaleFactor ?? 2)) }

    func state(for url: URL, maxPixel: Int = ImageLoader.maxPixel) -> State {
        let key = "\(url.absoluteString)@\(maxPixel)"
        lock.lock()
        if let s = cache[key] { lock.unlock(); return s }
        cache[key] = .loading
        lock.unlock()
        if url.isFileURL {
            queue.async { [self] in
                guard FileManager.default.fileExists(atPath: url.path) else { finish(key, .failed("Image not found: \(url.path)")); return }
                guard let src = CGImageSourceCreateWithURL(url as CFURL, nil) else { finish(key, .failed("Can’t open image: \(url.lastPathComponent)")); return }
                finish(key, Self.decode(src, maxPixel: maxPixel, failure: "Can’t open image: \(url.lastPathComponent)"))
            }
        } else {
            session.dataTask(with: url) { [self] data, _, error in
                guard let data, error == nil, let src = CGImageSourceCreateWithData(data as CFData, nil) else {
                    finish(key, .failed("Can’t load image: \(url.absoluteString)")); return
                }
                finish(key, Self.decode(src, maxPixel: maxPixel, failure: "Can’t load image: \(url.absoluteString)"))
            }.resume()
        }
        return .loading
    }

    func clear() { lock.lock(); cache = [:]; lock.unlock() }

    private func finish(_ key: String, _ s: State) {
        lock.lock(); cache[key] = s; lock.unlock()
        DispatchQueue.main.async { NotificationCenter.default.post(name: .jotImageLoaded, object: nil) }
    }

    static func decode(_ src: CGImageSource, maxPixel: Int, failure: String) -> State {
        var size = CGSize.zero
        if let props = CGImageSourceCopyPropertiesAtIndex(src, 0, nil) as? [CFString: Any],
           let w = props[kCGImagePropertyPixelWidth] as? CGFloat, let h = props[kCGImagePropertyPixelHeight] as? CGFloat {
            size = CGSize(width: w, height: h)
            // ภาพที่ EXIF หมุน 90 องศา สลับกว้าง/สูง
            if let o = props[kCGImagePropertyOrientation] as? Int, o >= 5 { size = CGSize(width: h, height: w) }
        }
        let opts: [CFString: Any] = [kCGImageSourceCreateThumbnailFromImageAlways: true, kCGImageSourceCreateThumbnailWithTransform: true,
                                     kCGImageSourceThumbnailMaxPixelSize: maxPixel, kCGImageSourceShouldCacheImmediately: true]
        guard let img = CGImageSourceCreateThumbnailAtIndex(src, 0, opts as CFDictionary) else { return .failed(failure) }
        if size == .zero { size = CGSize(width: img.width, height: img.height) }
        return .loaded(img, size)
    }
}

// MARK: - path ของรูป
enum ImageAssets {
    static func isRemote(_ src: String) -> Bool { let l = src.lowercased(); return l.hasPrefix("http://") || l.hasPrefix("https://") }

    /// src ใน markdown -> URL จริง (สัมพัทธ์จากโฟลเดอร์ของไฟล์ .md)
    static func resolve(_ src: String, base: URL?) -> URL? {
        if isRemote(src) { return URL(string: src) }
        if src.lowercased().hasPrefix("file://") { return URL(string: src) }
        let decoded = src.removingPercentEncoding ?? src
        if decoded.hasPrefix("/") { return URL(fileURLWithPath: decoded) }
        if decoded.hasPrefix("~") { return URL(fileURLWithPath: (decoded as NSString).expandingTildeInPath) }
        guard let base else { return nil }
        return base.appendingPathComponent(decoded).standardizedFileURL
    }

    /// เข้ารหัสเฉพาะอักขระที่ทำให้ markdown พัง (ช่องว่าง วงเล็บ % < >)
    static func encodePath(_ p: String) -> String {
        var out = ""
        for c in p {
            switch c {
            case " ": out += "%20"
            case "(": out += "%28"
            case ")": out += "%29"
            case "%": out += "%25"
            case "<": out += "%3C"
            case ">": out += "%3E"
            default: out.append(c)
            }
        }
        return out
    }

    /// path สัมพัทธ์ของ `file` ใต้ `base` (nil ถ้าไม่ได้อยู่ใต้)
    static func relativePath(from base: URL, to file: URL) -> String? {
        let b = base.standardizedFileURL.resolvingSymlinksInPath().pathComponents
        let f = file.standardizedFileURL.resolvingSymlinksInPath().pathComponents
        guard f.count > b.count, Array(f[0..<b.count]) == b else { return nil }
        return f[b.count...].joined(separator: "/")
    }

    static func uniqueName(_ name: String, in dir: URL) -> String {
        let fm = FileManager.default
        if !fm.fileExists(atPath: dir.appendingPathComponent(name).path) { return name }
        let ns = name as NSString
        let stem = ns.deletingPathExtension, ext = ns.pathExtension
        var i = 1
        while true {
            let n = ext.isEmpty ? "\(stem)-\(i)" : "\(stem)-\(i).\(ext)"
            if !fm.fileExists(atPath: dir.appendingPathComponent(n).path) { return n }
            i += 1
        }
    }

    /// นำไฟล์รูปเข้าเอกสาร คืน src (path สัมพัทธ์ที่เข้ารหัสแล้ว): ถ้าอยู่ใต้โฟลเดอร์ของเอกสารอยู่แล้วไม่คัดลอก
    static func importFile(_ file: URL, baseDir: URL) throws -> String {
        if let rel = relativePath(from: baseDir, to: file) { return encodePath(rel) }
        let assets = baseDir.appendingPathComponent("assets", isDirectory: true)
        try FileManager.default.createDirectory(at: assets, withIntermediateDirectories: true)
        let name = uniqueName(file.lastPathComponent, in: assets)
        try FileManager.default.copyItem(at: file, to: assets.appendingPathComponent(name))
        return encodePath("assets/" + name)
    }

    /// รูปจาก clipboard: เขียนเป็น assets/image-YYYYMMDD-HHmmss.png
    static func importImageData(_ png: Data, baseDir: URL, now: Date = Date()) throws -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX"); f.dateFormat = "yyyyMMdd-HHmmss"
        let assets = baseDir.appendingPathComponent("assets", isDirectory: true)
        try FileManager.default.createDirectory(at: assets, withIntermediateDirectories: true)
        let name = uniqueName("image-\(f.string(from: now)).png", in: assets)
        try png.write(to: assets.appendingPathComponent(name), options: .atomic)
        return "assets/" + name
    }

    static func pngData(from image: NSImage) -> Data? {
        guard let tiff = image.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff) else { return nil }
        return rep.representation(using: .png, properties: [:])
    }

    static let imageExtensions: Set<String> = ["png", "jpg", "jpeg", "gif", "webp", "heic", "tiff", "tif", "bmp", "svg"]
    static func isImageFile(_ url: URL) -> Bool { imageExtensions.contains(url.pathExtension.lowercased()) }
}

// MARK: - attachment ที่วาดรูปเอง (TextKit 1)
final class ImageAttachment: NSTextAttachment {
    let ref: ImageRef
    init(ref: ImageRef) {
        self.ref = ref
        super.init(data: nil, ofType: nil)
        attachmentCell = ImageCell(ref: ref)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) not supported") }
}

final class ImageCell: NSTextAttachmentCell {
    let ref: ImageRef
    init(ref: ImageRef) { self.ref = ref; super.init(textCell: "") }
    required init(coder: NSCoder) { fatalError("init(coder:) not supported") }

    private func resolve(_ view: NSView?) -> (URL?, ImageLoader.State) {
        if ref.raw != nil, let tv = view as? EditorTextView {
            // Obsidian: หาไฟล์แบบ vault
            if ref.noteEmbed { return (nil, .failed("")) }
            guard let dir = tv.linkBaseProvider?() ?? tv.imageBaseDirectory else { return (nil, .failed("Image not found: \(ref.src)")) }
            switch ObsidianVault.vault(for: dir).resolve(ref.src, docDir: dir, isNote: false) {
            case .found(let u): return (u, ImageLoader.shared.state(for: u))
            case .pending: return (nil, .loading)
            case .notFound: return (nil, .failed("Image not found: \(ref.src)"))
            }
        }
        let base = (view as? EditorTextView)?.imageBaseDirectory
        guard let url = ImageAssets.resolve(ref.src, base: base) else { return (nil, .failed("Image not found: \(ref.src)")) }
        return (url, ImageLoader.shared.state(for: url))
    }

    static let placeholderHeight: CGFloat = 52

    private func size(in container: NSTextContainer?, available: CGFloat, view: NSView?) -> NSSize {
        let avail = max(40, available)
        if ref.noteEmbed { return NSSize(width: min(avail, 340), height: 40) }
        switch resolve(view).1 {
        case .loaded(_, let px):
            // Obsidian `|300` / `|300x200`: กำหนดความกว้าง (และความสูง) เอง
            let wanted = CGFloat(ref.width ?? Int(px.width))
            let w = min(wanted, avail, Theme.columnMaxWidth)
            var h = px.width > 0 ? px.height * w / px.width : px.height
            if let rh = ref.height, let rw = ref.width, rw > 0 { h = CGFloat(rh) * w / CGFloat(rw) }
            return NSSize(width: w, height: max(1, h))
        default:
            return NSSize(width: min(avail, 360), height: Self.placeholderHeight)
        }
    }

    override func cellFrame(for textContainer: NSTextContainer, proposedLineFragment lineFrag: NSRect, glyphPosition position: NSPoint, characterIndex charIndex: Int) -> NSRect {
        var available = lineFrag.width - position.x
        // ในเซลล์ตาราง ความกว้างที่เสนอมาตอนวัดครั้งแรกยังไม่ใช่ความกว้างจริง: ประมาณจากความกว้างตาราง / จำนวนคอลัมน์
        if let tv = textContainer.textView, charIndex < tv.textStorage?.length ?? 0,
           let block = (tv.textStorage?.attribute(.paragraphStyle, at: charIndex, effectiveRange: nil) as? NSParagraphStyle)?.textBlocks.first as? NSTextTableBlock {
            let cols = max(block.table.numberOfColumns, 1)
            available = max(available, textContainer.size.width / CGFloat(cols) - 16)
        }
        let s = size(in: textContainer, available: available, view: textContainer.textView)
        return NSRect(origin: .zero, size: s)
    }
    override func cellSize() -> NSSize { NSSize(width: 200, height: Self.placeholderHeight) }
    override func cellBaselineOffset() -> NSPoint { .zero }
    override func wantsToTrackMouse() -> Bool { false }

    override func draw(withFrame cellFrame: NSRect, in controlView: NSView?, characterIndex charIndex: Int, layoutManager: NSLayoutManager) {
        let selected: Bool = {
            guard let tv = controlView as? NSTextView else { return false }
            let r = tv.selectedRange()
            return r.length > 0 && NSLocationInRange(charIndex, r)
        }()
        let (_, state) = resolve(controlView)
        let radius: CGFloat = 6
        let path = NSBezierPath(roundedRect: cellFrame, xRadius: radius, yRadius: radius)
        if ref.noteEmbed {
            // ฝังโน้ต: การ์ดลิงก์เล็ก (ไอคอน doc + ชื่อโน้ต) ไม่ดึงเนื้อหามาแสดง
            Palette.codeBackground.setFill(); path.fill()
            Palette.tableBorder.setStroke(); path.lineWidth = 1; path.stroke()
            if let icon = NSImage(systemSymbolName: "doc.text", accessibilityDescription: nil)?.withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: 16, weight: .regular)) {
                let tinted = icon.copy() as! NSImage
                tinted.lockFocus(); Palette.link.set(); NSRect(origin: .zero, size: tinted.size).fill(using: .sourceAtop); tinted.unlockFocus()
                tinted.draw(in: NSRect(x: cellFrame.minX + 12, y: cellFrame.midY - 10, width: 20, height: 20), from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
            }
            let para = NSMutableParagraphStyle(); para.lineBreakMode = .byTruncatingMiddle
            let title = ref.alt.isEmpty ? ref.src : ref.alt
            NSAttributedString(string: title, attributes: [.font: Fonts.body(.medium, size: 14), .foregroundColor: Palette.link, .paragraphStyle: para])
                .draw(in: NSRect(x: cellFrame.minX + 40, y: cellFrame.midY - 10, width: cellFrame.width - 52, height: 20))
            if selected { Palette.accent.setStroke(); let b = NSBezierPath(roundedRect: cellFrame.insetBy(dx: 1, dy: 1), xRadius: radius, yRadius: radius); b.lineWidth = 2.5; b.stroke() }
            return
        }
        switch state {
        case .loaded(let img, _):
            NSGraphicsContext.saveGraphicsState()
            path.addClip()
            if let ctx = NSGraphicsContext.current?.cgContext {
                // view ของ NSTextView เป็นแบบ flipped: พลิกกลับให้รูปไม่หัวกลับ
                ctx.saveGState()
                ctx.translateBy(x: cellFrame.minX, y: cellFrame.maxY)
                ctx.scaleBy(x: 1, y: -1)
                ctx.interpolationQuality = .high
                ctx.draw(img, in: CGRect(origin: .zero, size: cellFrame.size))
                ctx.restoreGState()
            }
            NSGraphicsContext.restoreGraphicsState()
        case .loading, .failed:
            Palette.codeBackground.setFill(); path.fill()
            Palette.tableBorder.setStroke(); path.lineWidth = 1; path.stroke()
            var message = ref.alt.isEmpty ? ref.src : ref.alt
            var color = Palette.secondaryText
            if case .failed(let m) = state { message = m.hasPrefix("Image not found") ? "Image not found: \(ref.src)" : m }
            let icon = NSImage(systemSymbolName: "photo", accessibilityDescription: nil)
            let iconRect = NSRect(x: cellFrame.minX + 14, y: cellFrame.midY - 11, width: 26, height: 22)
            if let icon {
                NSGraphicsContext.saveGraphicsState()
                let tinted = icon.copy() as! NSImage
                tinted.lockFocus(); color.set(); NSRect(origin: .zero, size: tinted.size).fill(using: .sourceAtop); tinted.unlockFocus()
                tinted.draw(in: iconRect, from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
                NSGraphicsContext.restoreGraphicsState()
            }
            let para = NSMutableParagraphStyle(); para.lineBreakMode = .byTruncatingMiddle
            let text = NSAttributedString(string: message, attributes: [.font: Fonts.body(.regular, size: 13), .foregroundColor: color, .paragraphStyle: para])
            let tr = NSRect(x: iconRect.maxX + 10, y: cellFrame.midY - 10, width: cellFrame.width - iconRect.width - 38, height: 20)
            text.draw(in: tr)
        }
        if selected {
            Palette.accent.setStroke()
            let b = NSBezierPath(roundedRect: cellFrame.insetBy(dx: 1, dy: 1), xRadius: radius, yRadius: radius)
            b.lineWidth = 2.5; b.stroke()
        }
    }
}
