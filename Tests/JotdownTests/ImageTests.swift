import Testing
import AppKit
@testable import Jotdown

func makePNG(_ url: URL, _ w: Int, _ h: Int, color: NSColor = .systemTeal) throws {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: w, pixelsHigh: h, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                               isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    NSGradient(colors: [color, color.blended(withFraction: 0.6, of: .white) ?? color])!.draw(in: NSRect(x: 0, y: 0, width: w, height: h), angle: 45)
    NSColor.white.setFill(); NSBezierPath(ovalIn: NSRect(x: CGFloat(w) / 2 - CGFloat(h) / 4, y: CGFloat(h) / 4, width: CGFloat(h) / 2, height: CGFloat(h) / 2)).fill()
    NSGraphicsContext.restoreGraphicsState()
    try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    try rep.representation(using: .png, properties: [:])!.write(to: url)
}

final class FakeImageProtocol: URLProtocol {
    nonisolated(unsafe) static var data: Data?
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        if let d = Self.data {
            client?.urlProtocol(self, didReceive: URLResponse(url: request.url!, mimeType: "image/png", expectedContentLength: d.count, textEncodingName: nil), cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: d)
            client?.urlProtocolDidFinishLoading(self)
        } else { client?.urlProtocol(self, didFailWithError: URLError(.notConnectedToInternet)) }
    }
    override func stopLoading() {}
}

@MainActor @Suite(.serialized) struct ImageTests {
    func rt(_ md: String) -> String { MarkdownSerializer.serialize(MarkdownParser.parse(md)) }

    @Test func roundTrips() {
        for md in ["![alt](a.png)\n", "![alt](a.png \"ชื่อรูป\")\n", "![](a.png)\n", "![x](<my pic.png>)\n", "![ก](รูป/ภาพ.png)\n", "![x](https://a.b/c.png)\n",
                   "ก ![a](b.png) ข\n", "![a](b.png)![c](d.png)\n", "- ข้อ ![a](b.png) จบ\n", "[![a](b.png)](https://x.y)\n", "![a \\[b\\]](c.png)\n",
                   "**หนา** ![a](b.png) ต่อ\n", "![x](a%20b.png)\n", "![x](p/q(1).png)\n".replacingOccurrences(of: "q(1)", with: "q%281%29")] {
            #expect(rt(md) == md, "round-trip ล้ม: \(md.debugDescription) -> \(rt(md).debugDescription)")
        }
        // ลิสต์ src ที่มีวงเล็บเขียนเป็น <...>
        #expect(rt("![x](<p/q(1).png>)\n") == "![x](<p/q(1).png>)\n")
    }

    @Test func storageHoldsAttachment() {
        let a = MarkdownParser.parse("ก ![alt](a.png \"t\") ข")
        #expect(a.string == "ก \(imageCharacter) ข")
        let att = a.attribute(.attachment, at: 2, effectiveRange: nil)
        #expect(att is ImageAttachment)
        let ref = ImageRef(encoded: a.attribute(.jotImage, at: 2, effectiveRange: nil) as! String)
        #expect(ref == ImageRef(src: "a.png", alt: "alt", title: "t"))
        // restyle ไม่ทำให้ attachment หาย
        let m = NSMutableAttributedString(attributedString: a)
        m.restyleParagraphs(in: NSRange(location: 0, length: m.length))
        #expect(m.attribute(.attachment, at: 2, effectiveRange: nil) is ImageAttachment)
        #expect(MarkdownSerializer.serialize(m) == "ก ![alt](a.png \"t\") ข\n")
    }

    @Test func resolvePaths() {
        let base = URL(fileURLWithPath: "/tmp/doc")
        #expect(ImageAssets.resolve("a/b.png", base: base)?.path == "/tmp/doc/a/b.png")
        #expect(ImageAssets.resolve("my%20pic.png", base: base)?.path == "/tmp/doc/my pic.png")
        #expect(ImageAssets.resolve("../x.png", base: base)?.path == "/tmp/x.png")
        #expect(ImageAssets.resolve("/abs/x.png", base: base)?.path == "/abs/x.png")
        #expect(ImageAssets.resolve("https://a.b/c.png", base: base)?.absoluteString == "https://a.b/c.png")
        #expect(ImageAssets.resolve("a.png", base: nil) == nil)
        #expect(ImageAssets.encodePath("assets/my pic (1).png") == "assets/my%20pic%20%281%29.png")
    }

    @Test func importCopiesToAssetsWithUniqueNames() throws {
        let dir = try tempDir(); defer { try? FileManager.default.removeItem(at: dir) }
        let doc = dir.appendingPathComponent("doc", isDirectory: true), other = dir.appendingPathComponent("other", isDirectory: true)
        try FileManager.default.createDirectory(at: doc, withIntermediateDirectories: true)
        let f = other.appendingPathComponent("my pic.png"); try makePNG(f, 20, 20)
        let s1 = try ImageAssets.importFile(f, baseDir: doc)
        let s2 = try ImageAssets.importFile(f, baseDir: doc)
        let s3 = try ImageAssets.importFile(f, baseDir: doc)
        #expect(s1 == "assets/my%20pic.png"); #expect(s2 == "assets/my%20pic-1.png"); #expect(s3 == "assets/my%20pic-2.png")
        for s in [s1, s2, s3] { #expect(FileManager.default.fileExists(atPath: ImageAssets.resolve(s, base: doc)!.path)) }
        // ไฟล์ที่อยู่ในโฟลเดอร์/โฟลเดอร์ย่อยแล้วไม่คัดลอก
        let inner = doc.appendingPathComponent("pics/ก.png"); try makePNG(inner, 10, 10)
        #expect(try ImageAssets.importFile(inner, baseDir: doc) == "pics/ก.png")
        #expect(!FileManager.default.fileExists(atPath: doc.appendingPathComponent("assets/ก.png").path))
        let sibling = doc.appendingPathComponent("top.png"); try makePNG(sibling, 10, 10)
        #expect(try ImageAssets.importFile(sibling, baseDir: doc) == "top.png")
    }

    @Test func clipboardImageNaming() throws {
        let dir = try tempDir(); defer { try? FileManager.default.removeItem(at: dir) }
        let png = Data([1, 2, 3])
        let date = Date(timeIntervalSince1970: 1_700_000_000)
        let a = try ImageAssets.importImageData(png, baseDir: dir, now: date)
        let b = try ImageAssets.importImageData(png, baseDir: dir, now: date)
        #expect(a.hasPrefix("assets/image-") && a.hasSuffix(".png"))
        #expect(a.range(of: #"^assets/image-\d{8}-\d{6}\.png$"#, options: .regularExpression) != nil)
        #expect(b == a.replacingOccurrences(of: ".png", with: "-1.png"))
    }

    func titledDoc(_ dir: URL, _ md: String) throws -> (JotdownDocument, EditorViewController) {
        _ = NSApplication.shared
        let url = dir.appendingPathComponent("note.md")
        try md.write(to: url, atomically: true, encoding: .utf8)
        let doc = try JotdownDocument(contentsOf: url, ofType: JotTypes.markdown)
        let vc = EditorViewController(document: doc); _ = vc.view
        vc.textView.setSelectedRange(NSRange(location: doc.textStorage.length, length: 0))
        return (doc, vc)
    }

    @Test func missingImageDoesNotCrashOrLoseContent() throws {
        let dir = try tempDir(); defer { try? FileManager.default.removeItem(at: dir) }
        let (doc, vc) = try titledDoc(dir, "![ไม่มี](nope/x.png)\n\nข้อความ\n")
        let url = ImageAssets.resolve("nope/x.png", base: doc.imageBaseDirectory)!
        ImageLoader.shared.clear()
        _ = ImageLoader.shared.state(for: url)
        waitFor { if case .failed = ImageLoader.shared.state(for: url) { return true } else { return false } }
        guard case .failed(let msg) = ImageLoader.shared.state(for: url) else { Issue.record("ต้อง failed"); return }
        #expect(msg.contains("Image not found") && msg.contains("nope/x.png"))
        #expect(doc.currentMarkdown == "![ไม่มี](nope/x.png)\n\nข้อความ\n")
        _ = vc
    }

    @Test func localImageIsDownsampledInBackground() throws {
        let dir = try tempDir(); defer { try? FileManager.default.removeItem(at: dir) }
        let f = dir.appendingPathComponent("big.png"); try makePNG(f, 4000, 1000)
        ImageLoader.shared.clear()
        guard case .loading = ImageLoader.shared.state(for: f, maxPixel: 800) else { Issue.record("ครั้งแรกต้อง loading (ไม่บล็อก)"); return }
        waitFor { if case .loaded = ImageLoader.shared.state(for: f, maxPixel: 800) { return true } else { return false } }
        guard case .loaded(let img, let px) = ImageLoader.shared.state(for: f, maxPixel: 800) else { Issue.record("ต้อง loaded"); return }
        #expect(px == CGSize(width: 4000, height: 1000))
        #expect(max(img.width, img.height) <= 800)
    }

    @Test func remoteImageUsesSession() throws {
        let dir = try tempDir(); defer { try? FileManager.default.removeItem(at: dir) }
        let f = dir.appendingPathComponent("r.png"); try makePNG(f, 300, 200)
        FakeImageProtocol.data = try Data(contentsOf: f)
        let cfg = URLSessionConfiguration.ephemeral; cfg.protocolClasses = [FakeImageProtocol.self]
        let old = ImageLoader.shared.session
        ImageLoader.shared.session = URLSession(configuration: cfg)
        defer { ImageLoader.shared.session = old; ImageLoader.shared.clear() }
        ImageLoader.shared.clear()
        let url = URL(string: "https://example.test/r.png")!
        guard case .loading = ImageLoader.shared.state(for: url) else { Issue.record("ต้อง loading"); return }
        waitFor { if case .loaded = ImageLoader.shared.state(for: url) { return true } else { return false } }
        guard case .loaded(_, let px) = ImageLoader.shared.state(for: url) else { Issue.record("ต้อง loaded"); return }
        #expect(px == CGSize(width: 300, height: 200))
        // โหลดไม่ได้ = failed ไม่ crash
        FakeImageProtocol.data = nil
        let bad = URL(string: "https://example.test/none.png")!
        _ = ImageLoader.shared.state(for: bad)
        waitFor { if case .failed = ImageLoader.shared.state(for: bad) { return true } else { return false } }
        if case .failed(let m) = ImageLoader.shared.state(for: bad) { #expect(m.contains("none.png")) } else { Issue.record("ต้อง failed") }
    }

    @Test func pasteImageDataCopiesToAssets() throws {
        let dir = try tempDir(); defer { try? FileManager.default.removeItem(at: dir) }
        let (doc, vc) = try titledDoc(dir, "ก\n")
        let src = dir.appendingPathComponent("tmp.png"); try makePNG(src, 40, 30)
        let pb = NSPasteboard.withUniqueName(); pb.clearContents()
        pb.setData(try Data(contentsOf: src), forType: .png)
        vc.textView.pasteFrom(pb)
        let md = doc.currentMarkdown
        let m = md.range(of: #"!\[image\]\(assets/image-\d{8}-\d{6}\.png\)"#, options: .regularExpression)
        #expect(m != nil, "ได้ \(md.debugDescription)")
        let assets = try FileManager.default.contentsOfDirectory(atPath: dir.appendingPathComponent("assets").path)
        #expect(assets.count == 1)
    }

    @Test func pasteAndDropFilesCopyOrReference() throws {
        let dir = try tempDir(); defer { try? FileManager.default.removeItem(at: dir) }
        let home = dir.appendingPathComponent("home", isDirectory: true)
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
        let (doc, vc) = try titledDoc(home, "")
        let outside = dir.appendingPathComponent("elsewhere/pic one.png"); try makePNG(outside, 10, 10)
        let inside = home.appendingPathComponent("imgs/two.png"); try makePNG(inside, 10, 10)
        let pb = NSPasteboard.withUniqueName(); pb.clearContents()
        pb.writeObjects([outside as NSURL, inside as NSURL])
        #expect(vc.textView.insertImages(from: pb, at: nil))
        #expect(doc.currentMarkdown == "![pic one](assets/pic%20one.png)\n\n![two](imgs/two.png)\n")
        #expect(FileManager.default.fileExists(atPath: home.appendingPathComponent("assets/pic one.png").path))
        #expect(!FileManager.default.fileExists(atPath: home.appendingPathComponent("assets/two.png").path))
        // ไฟล์ที่ไม่ใช่รูปไม่ถูกจัดการเป็นรูป
        let txt = dir.appendingPathComponent("a.txt"); try "x".write(to: txt, atomically: true, encoding: .utf8)
        let pb2 = NSPasteboard.withUniqueName(); pb2.clearContents(); pb2.writeObjects([txt as NSURL])
        #expect(!vc.textView.insertImages(from: pb2, at: nil))
    }

    @Test func webImageUrlIsReferencedNotCopied() throws {
        let dir = try tempDir(); defer { try? FileManager.default.removeItem(at: dir) }
        let (doc, vc) = try titledDoc(dir, "")
        let pb = NSPasteboard.withUniqueName(); pb.clearContents()
        pb.writeObjects([URL(string: "https://example.com/p/cat.png")! as NSURL])
        #expect(vc.textView.insertImages(from: pb, at: nil))
        #expect(doc.currentMarkdown == "![cat](https://example.com/p/cat.png)\n")
        #expect(!FileManager.default.fileExists(atPath: dir.appendingPathComponent("assets").path))
    }

    @Test func htmlImgBecomesImage() {
        let b = HTMLImporter.blocks(from: "<p>ก <img src=\"https://x.y/a.png\" alt=\"แมว\"> ข</p>")
        #expect(MarkdownSerializer.serialize(b) == "ก ![แมว](https://x.y/a.png) ข\n")
    }

    @Test func deletingImageKeepsFile() throws {
        let dir = try tempDir(); defer { try? FileManager.default.removeItem(at: dir) }
        let f = dir.appendingPathComponent("keep.png"); try makePNG(f, 10, 10)
        let (doc, vc) = try titledDoc(dir, "ก ![a](keep.png) ข\n")
        vc.textView.select(2, 1)       // เลือกรูป
        vc.textView.deleteBackward(nil)
        #expect(doc.currentMarkdown == "ก  ข\n")
        #expect(FileManager.default.fileExists(atPath: f.path))
        doc.undoManager?.undo()
        #expect(doc.currentMarkdown == "ก ![a](keep.png) ข\n")
        // Backspace หลังรูป
        vc.textView.select(3)
        vc.textView.deleteBackward(nil)
        #expect(doc.currentMarkdown == "ก  ข\n")
        #expect(FileManager.default.fileExists(atPath: f.path))
    }

    @Test func editAltKeepsOtherFields() throws {
        let dir = try tempDir(); defer { try? FileManager.default.removeItem(at: dir) }
        let (doc, vc) = try titledDoc(dir, "![เก่า](a.png \"ชื่อ\")\n")
        vc.textView.setImageAlt("ใหม่", at: 0)
        #expect(doc.currentMarkdown == "![ใหม่](a.png \"ชื่อ\")\n")
    }

    @Test func copyImagePutsMarkdownAndImage() throws {
        let dir = try tempDir(); defer { try? FileManager.default.removeItem(at: dir) }
        try makePNG(dir.appendingPathComponent("c.png"), 30, 20)
        let (_, vc) = try titledDoc(dir, "![a](c.png)\n")
        vc.textView.select(0, 1)
        vc.textView.copy(nil)
        #expect(NSPasteboard.general.string(forType: .string) == "![a](c.png)")
        #expect(NSPasteboard.general.data(forType: .tiff) != nil)
    }

    @Test func untitledImagesMoveOnFirstSave() throws {
        _ = NSApplication.shared
        let doc = JotdownDocument()
        let vc = EditorViewController(document: doc); _ = vc.view
        let tmp = try tempDir(); defer { try? FileManager.default.removeItem(at: tmp) }
        let pic = tmp.appendingPathComponent("p.png"); try makePNG(pic, 20, 20)
        let pb = NSPasteboard.withUniqueName(); pb.clearContents(); pb.writeObjects([pic as NSURL])
        vc.textView.insertImages(from: pb, at: nil)
        #expect(doc.currentMarkdown == "![p](assets/p.png)\n")
        let root = doc.untitledRoot
        #expect(FileManager.default.fileExists(atPath: root.appendingPathComponent("assets/p.png").path))
        let dest = try tempDir(); defer { try? FileManager.default.removeItem(at: dest) }
        // ที่ปลายทางมีชื่อซ้ำอยู่แล้ว -> เปลี่ยนชื่อและแก้ path
        try makePNG(dest.appendingPathComponent("assets/p.png"), 5, 5)
        try doc.migrateUntitledAssets(to: dest)
        #expect(doc.currentMarkdown == "![p](assets/p-1.png)\n")
        #expect(FileManager.default.fileExists(atPath: dest.appendingPathComponent("assets/p-1.png").path))
        #expect(!FileManager.default.fileExists(atPath: root.path))
        #expect(doc.textStorage.attribute(.attachment, at: 0, effectiveRange: nil) is ImageAttachment)
    }

    @Test func listSpacingBetweenDifferentBlocks() {
        func after(_ a: NSAttributedString, _ i: Int) -> CGFloat { (a.attribute(.paragraphStyle, at: i, effectiveRange: nil) as! NSParagraphStyle).paragraphSpacing }
        let a = MarkdownParser.parse("- a\n- b\n\n1. c\n2. d\n\nย่อหน้า\n\n> q\n")
        let ns = a.string as NSString
        func idx(_ s: String) -> Int { ns.range(of: s).location }
        #expect(after(a, idx("a")) == 4)          // ในลิสต์เดียวกัน
        #expect(after(a, idx("b")) == 10)         // bullet -> ตัวเลข
        #expect(after(a, idx("c")) == 4)
        #expect(after(a, idx("d")) == 6)          // ลิสต์ -> ย่อหน้า (บวก before ของย่อหน้า = เท่าย่อหน้าปกติ)
        // แก้ไขแล้วระยะย่อหน้าตามบล็อกถัดไป
        let (doc, vc) = makeEditor("- a\n\nx\n")
        vc.textView.select(doc.textStorage.length)
        vc.textView.jotToggleBullet(nil)
        let st = doc.textStorage
        #expect(after(st, 0) == 4, "รายการก่อนหน้าต้องปรับเป็นระยะในลิสต์ ได้ \(after(st, 0))")
    }

    @Test func iconScriptProducesAllSizes() throws {
        let out = try tempDir().appendingPathComponent("t.iconset"); defer { try? FileManager.default.removeItem(at: out.deletingLastPathComponent()) }
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/swift")
        p.arguments = [projectRoot.appendingPathComponent("scripts/make-icon.swift").path, out.path, projectRoot.appendingPathComponent("Resources/Fonts").path]
        p.standardOutput = FileHandle.nullDevice; p.standardError = FileHandle.nullDevice
        try p.run(); p.waitUntilExit()
        #expect(p.terminationStatus == 0)
        let files = try FileManager.default.contentsOfDirectory(atPath: out.path).sorted()
        #expect(files.count == 10)
        for (n, px) in [("icon_16x16.png", 16), ("icon_32x32@2x.png", 64), ("icon_512x512@2x.png", 1024)] {
            let rep = NSBitmapImageRep(data: try Data(contentsOf: out.appendingPathComponent(n)))
            #expect(rep?.pixelsWide == px, Comment(rawValue: n))
        }
    }

    // MARK: - snapshot
    func imageDoc(_ dir: URL) throws -> JotdownDocument {
        try makePNG(dir.appendingPathComponent("wide.png"), 1600, 700, color: .systemIndigo)
        try makePNG(dir.appendingPathComponent("small.png"), 160, 90, color: .systemOrange)
        try makePNG(dir.appendingPathComponent("tiny.png"), 60, 40, color: .systemPink)
        let md = "# รูปภาพ\n\nรูปบล็อกกว้าง (ย่อให้พอดีคอลัมน์):\n\n![wide](wide.png)\n\nรูปเล็กไม่ขยาย ![small](small.png) อยู่ในบรรทัดเดียวกับข้อความภาษาไทย แล้วต่อด้วยรูป ![tiny](tiny.png) อีกรูป\n\n![หาไฟล์ไม่เจอ](missing/none.png)\n\n![รูปที่เลือก](small.png)\n\n- ข้อในลิสต์\n\n1. ข้อเลข\n\n> คำพูด\n\nจบ\n"
        let url = dir.appendingPathComponent("img.md")
        try md.write(to: url, atomically: true, encoding: .utf8)
        return try JotdownDocument(contentsOf: url, ofType: JotTypes.markdown)
    }

    func snapImages(_ size: CGSize, _ appearance: NSAppearance.Name) throws {
        _ = NSApplication.shared
        let dir = try tempDir(); defer { try? FileManager.default.removeItem(at: dir) }
        ImageLoader.shared.clear()
        let doc = try imageDoc(dir)
        let vc = EditorViewController(document: doc); _ = vc.view
        // เลือกรูปที่ 4 (ตัวอักษรรูปตัวสุดท้ายที่เป็นบล็อก "รูปที่เลือก")
        var last = 0
        doc.textStorage.enumerateAttribute(.jotImage, in: NSRange(location: 0, length: doc.textStorage.length), options: []) { v, r, _ in
            if let e = v as? String, e.contains("รูปที่เลือก") { last = r.location }
        }
        let shot = try snapshot("editor-images", size: size, appearance: appearance, after: {
            // (ในเทสต์ main queue ไม่ถูกระบายระหว่าง spin จึงเรียกแทน notification ที่แอปจริงส่งหลังโหลดเสร็จ)
            spin(0.6, vc.view)
            vc.textView.refreshImages()
            vc.textView.setSelectedRange(NSRange(location: last, length: 1))
            spin(0.8, vc.view)
        }, viewController: vc)
        #expect(FileManager.default.fileExists(atPath: shot.png.path))
        let tv = vc.textView!
        #expect(tv.frame.width <= size.width + 0.5)
        // ไม่ล้นความกว้างคอลัมน์
        let lm = tv.layoutManager!, tc = tv.textContainer!
        doc.textStorage.enumerateAttribute(.jotImage, in: NSRange(location: 0, length: doc.textStorage.length), options: []) { v, r, _ in
            guard v != nil else { return }
            let rect = lm.boundingRect(forGlyphRange: lm.glyphRange(forCharacterRange: r, actualCharacterRange: nil), in: tc)
            #expect(rect.width <= min(Theme.columnMaxWidth, size.width) + 1)
        }
    }

    @Test func imagesAqua900() throws { try snapImages(CGSize(width: 900, height: 700), .aqua) }
    @Test func imagesAqua480() throws { try snapImages(CGSize(width: 480, height: 360), .aqua) }
    @Test func imagesDark900() throws { try snapImages(CGSize(width: 900, height: 700), .darkAqua) }
    @Test func imagesDark480() throws { try snapImages(CGSize(width: 480, height: 360), .darkAqua) }
    @Test func imagesTall() throws { try snapImages(CGSize(width: 900, height: 1500), .aqua) }

    @Test func promptSheetSnapshots() throws {
        _ = NSApplication.shared
        for (name, removable) in [("link-sheet-existing", true), ("link-sheet-new", false)] {
            let sheet = PromptSheet(title: "Link", message: "Enter a URL", initial: removable ? "https://example.com" : "", placeholder: "https://", removeTitle: removable ? "Remove Link" : nil)
            for (tag, ap) in [("aqua", NSAppearance.Name.aqua), ("dark", .darkAqua)] {
                sheet.window.appearance = NSAppearance(named: ap)
                let v = sheet.window.contentView!
                try snapshotWithWindowBackground(v, appearance: ap, to: SnapshotDir.url.appendingPathComponent("\(name)-\(tag).png"))
                #expect(v.bounds.width >= 380 && v.bounds.height > 100)
            }
        }
    }
}
