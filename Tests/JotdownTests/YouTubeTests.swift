import Testing
import AppKit
@testable import Jotdown

final class FakeYouTubeProtocol: URLProtocol {
    nonisolated(unsafe) static var thumb: Data?
    nonisolated(unsafe) static var oembed: Data?
    nonisolated(unsafe) static var requested: [URL] = []
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        let url = request.url!
        Self.requested.append(url)
        let d = url.host == "i.ytimg.com" ? Self.thumb : Self.oembed
        if let d {
            client?.urlProtocol(self, didReceive: URLResponse(url: url, mimeType: nil, expectedContentLength: d.count, textEncodingName: nil), cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: d)
            client?.urlProtocolDidFinishLoading(self)
        } else { client?.urlProtocol(self, didFailWithError: URLError(.notConnectedToInternet)) }
    }
    override func stopLoading() {}
}

@MainActor @Suite(.serialized) struct YouTubeTests {
    static let id = "dQw4w9WgXcQ"
    func rt(_ md: String) -> String { MarkdownSerializer.serialize(MarkdownParser.parse(md)) }

    func useFakeNetwork(thumb: Data?, title: String?) -> URLSession {
        FakeYouTubeProtocol.thumb = thumb
        FakeYouTubeProtocol.oembed = title.map { try! JSONSerialization.data(withJSONObject: ["title": $0, "author_name": "Sample Channel"]) }
        FakeYouTubeProtocol.requested = []
        let cfg = URLSessionConfiguration.ephemeral; cfg.protocolClasses = [FakeYouTubeProtocol.self]
        let old = YouTubeMeta.shared.session
        YouTubeMeta.shared.session = URLSession(configuration: cfg)
        YouTubeMeta.shared.clear()
        return old
    }

    // MARK: parsing
    @Test func parsesAllUrlForms() {
        let id = Self.id
        for u in ["https://youtu.be/\(id)", "https://www.youtube.com/watch?v=\(id)", "http://youtube.com/watch?v=\(id)&list=PLabc&index=2",
                  "https://m.youtube.com/watch?v=\(id)", "https://music.youtube.com/watch?v=\(id)", "https://www.youtube.com/shorts/\(id)",
                  "https://www.youtube.com/embed/\(id)", "https://www.youtube.com/live/\(id)", "<https://youtu.be/\(id)>", "youtu.be/\(id)",
                  "https://www.youtube-nocookie.com/embed/\(id)"] {
            #expect(YouTubeLink.parse(u)?.id == id, "\(u)")
        }
        for u in ["https://vimeo.com/\(id)", "https://youtube.com/watch?v=short", "https://example.com/watch?v=\(id)", "https://youtube.com/", "hello", "https://notyoutube.com/watch?v=\(id)", "https://youtube.com.evil.com/watch?v=\(id)"] {
            #expect(YouTubeLink.parse(u) == nil, "\(u)")
        }
    }

    @Test func parsesStartTimes() {
        let id = Self.id
        #expect(YouTubeLink.parse("https://youtu.be/\(id)?t=90")?.start == 90)
        #expect(YouTubeLink.parse("https://youtu.be/\(id)?t=1m30s")?.start == 90)
        #expect(YouTubeLink.parse("https://www.youtube.com/watch?v=\(id)&t=1h2m3s")?.start == 3723)
        #expect(YouTubeLink.parse("https://www.youtube.com/watch?v=\(id)&start=42")?.start == 42)
        #expect(YouTubeLink.parse("https://youtu.be/\(id)")?.start == nil || YouTubeLink.parse("https://youtu.be/\(id)")?.start == 0)
        #expect(YouTubeRef(id: id, start: 90).startLabel == "1:30")
        #expect(YouTubeRef(id: id, start: 3723).startLabel == "1:02:03")
        #expect(YouTubeRef(id: id, start: 90).embedURL.absoluteString.contains("start=90"))
        #expect(YouTubeRef(id: id, start: 90).embedURL.host == "www.youtube-nocookie.com")
    }

    @Test func playerHTMLAndErrors() {
        let ref = YouTubeRef(id: Self.id, start: 5)
        #expect(YouTubePlayerHTML.html(for: ref).contains(Self.id))
        #expect(YouTubePlayerHTML.message(forError: 150) == "This video can't be played here")
        #expect(YouTubePlayerHTML.message(forError: 153) == "This video can't be played here")
        #expect(YouTubePlayerHTML.message(forError: 100) == "This video is unavailable")
    }

    // MARK: round-trip / ขอบเขตการ์ด
    @Test func roundTripsExactly() {
        let id = Self.id
        for md in ["https://youtu.be/\(id)\n", "https://www.youtube.com/watch?v=\(id)\n", "https://www.youtube.com/watch?v=\(id)&list=PL1&t=1m30s\n",
                   "[ชื่อคลิป](https://youtu.be/\(id)?t=30)\n", "<https://youtu.be/\(id)>\n", "https://www.youtube.com/shorts/\(id)\n",
                   "ก\n\nhttps://youtu.be/\(id)\n\nข\n", "[a [b]](https://youtu.be/\(id))\n"] {
            #expect(rt(md) == md, "ได้ \(rt(md).debugDescription) จาก \(md.debugDescription)")
        }
    }

    @Test func singleLinkParagraphBecomesCard() {
        let id = Self.id
        for (md, title) in [("https://youtu.be/\(id)", nil), ("[My Clip](https://youtu.be/\(id))", "My Clip"), ("<https://youtu.be/\(id)>", nil)] as [(String, String?)] {
            let a = MarkdownParser.parse(md)
            #expect(a.string == imageCharacter, "\(md)")
            #expect(a.attribute(.attachment, at: 0, effectiveRange: nil) is VideoAttachment)
            let v = VideoRef(encoded: a.attribute(.jotVideo, at: 0, effectiveRange: nil) as! String)
            #expect(v?.title == title)
            #expect(v?.ref?.id == id)
        }
    }

    @Test func midSentenceAndNestedStayLinks() {
        let id = Self.id
        for md in ["ดูนี่ https://youtu.be/\(id) นะ\n", "ดู [คลิป](https://youtu.be/\(id)) ครับ\n", "- https://youtu.be/\(id)\n", "> https://youtu.be/\(id)\n",
                   "| a |\n| --- |\n| https://youtu.be/\(id) |\n", "1. [x](https://youtu.be/\(id))\n"] {
            let a = MarkdownParser.parse(md)
            var hasVideo = false
            a.enumerateAttribute(.jotVideo, in: NSRange(location: 0, length: a.length)) { v, _, _ in if v != nil { hasVideo = true } }
            #expect(!hasVideo, "ไม่ควรเป็นการ์ด: \(md.debugDescription)")
            if !md.hasPrefix("|") { #expect(rt(md) == md, "round-trip: \(md.debugDescription) -> \(rt(md).debugDescription)") }
        }
    }

    @Test func nonYouTubeLinkIsNotCard() {
        let md = "https://example.com/watch?v=\(Self.id)\n"
        let a = MarkdownParser.parse(md)
        #expect(!(a.attribute(.attachment, at: 0, effectiveRange: nil) is VideoAttachment))
        #expect(rt(md) == md)
    }

    // MARK: แทรก/ลบ/คัดลอก
    @Test func pasteIntoEmptyLineMakesCard() {
        let (doc, vc) = makeEditor("")
        let pb = NSPasteboard.withUniqueName(); pb.clearContents()
        pb.setString("https://youtu.be/\(Self.id)?t=30", forType: .string)
        vc.textView.pasteFrom(pb)
        #expect(doc.currentMarkdown.hasPrefix("https://youtu.be/\(Self.id)?t=30"))
        #expect(doc.textStorage.attribute(.attachment, at: 0, effectiveRange: nil) is VideoAttachment)
    }

    @Test func pasteMidSentenceStaysLink() {
        let (doc, vc) = makeEditor("ก ")
        let pb = NSPasteboard.withUniqueName(); pb.clearContents()
        pb.setString("https://youtu.be/\(Self.id)", forType: .string)
        vc.textView.pasteFrom(pb)
        #expect(!(doc.textStorage.attribute(.attachment, at: doc.textStorage.length - 1, effectiveRange: nil) is VideoAttachment))
        #expect(doc.currentMarkdown.contains("https://youtu.be/\(Self.id)"))
    }

    @Test func typeUrlThenEnterMakesCardAndNewParagraph() {
        let (doc, vc) = makeEditor("")
        vc.textView.type("https://youtu.be/\(Self.id)\n")
        #expect(doc.textStorage.attribute(.attachment, at: 0, effectiveRange: nil) is VideoAttachment)
        #expect(vc.textView.selectedRange().location == 2)
        vc.textView.type("ต่อ")
        #expect(doc.currentMarkdown == "https://youtu.be/\(Self.id)\n\nต่อ\n")
    }

    @Test func typeUrlInsideSentenceEnterDoesNotMakeCard() {
        let (doc, vc) = makeEditor("")
        vc.textView.type("ดู https://youtu.be/\(Self.id)\n")
        #expect(!(doc.textStorage.attribute(.attachment, at: 3, effectiveRange: nil) is VideoAttachment))
    }

    @Test func menuInsertValidatesAndInserts() {
        #expect(EditorTextView.makeVideo(from: "https://example.com") == nil)
        #expect(EditorTextView.makeVideo(from: "  youtu.be/\(Self.id) ")?.url == "https://youtu.be/\(Self.id)")
        let (doc, vc) = makeEditor("ก")
        let v = EditorTextView.makeVideo(from: "https://www.youtube.com/watch?v=\(Self.id)")!
        #expect(vc.textView.insertVideo(v))
        #expect(doc.currentMarkdown == "ก\n\nhttps://www.youtube.com/watch?v=\(Self.id)\n")
    }

    @Test func promptSheetValidatorBlocksBadInput() {
        let s = PromptSheet(title: "YouTube Video", message: "x", initial: "https://example.com", placeholder: "")
        s.validator = { EditorTextView.makeVideo(from: $0) == nil ? "Not a YouTube link" : nil }
        var done = false
        s.present(on: NSWindow()) { _ in done = true }
        s.submitForTesting()
        #expect(s.errorText == "Not a YouTube link")
        #expect(!done)
    }

    @Test func deleteUndoCopy() {
        let (doc, vc) = makeEditor("ก\n\nhttps://youtu.be/\(Self.id)\n\nข\n", explicitUndo: true)
        let tv = vc.textView!
        let idx = (doc.textStorage.string as NSString).range(of: imageCharacter).location
        tv.select(idx, 1)
        #expect(tv.selectedVideo() != nil)
        // คัดลอก = markdown ต้นฉบับ
        let pb = NSPasteboard.general; pb.clearContents()
        tv.copy(nil)
        #expect(pb.string(forType: .string)?.contains("https://youtu.be/\(Self.id)") == true)
        tv.select(idx, 1)
        tv.type("\u{8}")
        #expect(!doc.currentMarkdown.contains("youtu.be"))
        doc.undoManager?.undo()
        #expect(doc.currentMarkdown.contains("https://youtu.be/\(Self.id)"))
    }

    // MARK: เมตา / ออฟไลน์
    @Test func metaLoadsThumbnailAndTitleThenFailsGracefully() throws {
        let dir = try tempDir(); defer { try? FileManager.default.removeItem(at: dir) }
        let f = dir.appendingPathComponent("t.png"); try makePNG(f, 480, 360, color: .systemIndigo)
        let old = useFakeNetwork(thumb: try Data(contentsOf: f), title: "ชื่อคลิปทดสอบ")
        defer { YouTubeMeta.shared.session = old; YouTubeMeta.shared.clear() }
        let ref = YouTubeRef(id: Self.id, start: nil)
        #expect(YouTubeMeta.shared.info(for: ref).isLoading)
        waitFor { let i = YouTubeMeta.shared.info(for: ref); return i.thumbnail != nil && i.title != nil }
        let i = YouTubeMeta.shared.info(for: ref)
        #expect(i.thumbnail != nil); #expect(i.title == "ชื่อคลิปทดสอบ"); #expect(i.channel == "Sample Channel")
        #expect(FakeYouTubeProtocol.requested.contains { $0.host == "i.ytimg.com" })
        #expect(FakeYouTubeProtocol.requested.contains { $0.path == "/oembed" })

        _ = useFakeNetwork(thumb: nil, title: nil)
        let bad = YouTubeRef(id: "AAAAAAAAAAA", start: nil)
        _ = YouTubeMeta.shared.info(for: bad)
        waitFor { let i = YouTubeMeta.shared.info(for: bad); return i.thumbFailed && i.metaFailed }
        let b = YouTubeMeta.shared.info(for: bad)
        #expect(b.thumbFailed && b.metaFailed && b.thumbnail == nil)
    }

    // MARK: player overlay (ไม่โหลดเว็บในเทสต์)
    @Test func playerOverlayLifecycle() {
        VideoPlayerView.loadsContent = false
        let (doc, vc) = makeEditor("ก\n\nhttps://youtu.be/\(Self.id)\n\nข\n")
        let tv = vc.textView!
        tv.frame = NSRect(x: 0, y: 0, width: 800, height: 600)
        let idx = (doc.textStorage.string as NSString).range(of: imageCharacter).location
        #expect(tv.videoPlayers.isEmpty)           // ยังไม่สร้างจนกว่าจะกดเล่น
        tv.playVideo(at: idx)
        #expect(tv.videoPlayers.count == 1)
        tv.playVideo(at: idx)
        #expect(tv.videoPlayers.count == 1)
        // ลบการ์ด = ผู้เล่นหาย
        tv.select(idx, 1); tv.type("\u{8}")
        tv.updatePlayerFrames()
        #expect(tv.videoPlayers.isEmpty)
        tv.stopAllPlayers()
    }

    // MARK: snapshots
    func cardDoc() -> String { "# วิดีโอ\n\nhttps://www.youtube.com/watch?v=\(Self.id)&t=1m30s\n\nข้อความต่อจากวิดีโอ\n" }

    @Test func snapshots() throws {
        let dir = try tempDir(); defer { try? FileManager.default.removeItem(at: dir) }
        let f = dir.appendingPathComponent("t.png"); try makePNG(f, 480, 360, color: .systemIndigo)
        let png = try Data(contentsOf: f)
        for (name, thumb, title, md, select) in [
            ("youtube-with-title", png as Data?, "Sample video title" as String?, cardDoc(), false),
            ("youtube-no-title", png, nil, cardDoc(), false),
            ("youtube-failed", nil, nil, cardDoc(), false),
            ("youtube-selected", png, "Sample video title", cardDoc(), true),
        ] {
            for ap in [NSAppearance.Name.aqua, .darkAqua] {
                let old = useFakeNetwork(thumb: thumb, title: title)
                defer { YouTubeMeta.shared.session = old; YouTubeMeta.shared.clear() }
                let (doc, vc) = makeEditor(md)
                let shot = try snapshot(name, size: CGSize(width: 900, height: 700), appearance: ap, after: {
                    waitFor(2) { let i = YouTubeMeta.shared.info(for: YouTubeRef(id: Self.id, start: 90)); return thumb == nil ? i.thumbFailed : (i.thumbnail != nil && (title == nil || i.title != nil)) }
                    vc.textView.refreshImages()
                    if select, let r = (doc.textStorage.string as NSString).range(of: imageCharacter) as NSRange? { vc.textView.select(r.location, 1) }
                }, viewController: vc)
                #expect(FileManager.default.fileExists(atPath: shot.png.path))
            }
        }
    }
}
