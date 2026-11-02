import AppKit
import Foundation
import Testing
@testable import Jotdown

/// URLSession ปลอม: คืนข้อมูลตาม URL ที่ลงทะเบียนไว้
final class StubURLProtocol: URLProtocol {
    nonisolated(unsafe) static var responses: [URL: (Int, Data)] = [:]
    nonisolated(unsafe) static var lastRequest: URLRequest?
    nonisolated(unsafe) static var lastBody: Data?

    static func session() -> URLSession {
        let c = URLSessionConfiguration.ephemeral
        c.protocolClasses = [StubURLProtocol.self]
        return URLSession(configuration: c)
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        Self.lastRequest = request
        if let s = request.httpBodyStream {
            s.open(); var d = Data(); var buf = [UInt8](repeating: 0, count: 4096)
            while s.hasBytesAvailable { let n = s.read(&buf, maxLength: buf.count); if n <= 0 { break }; d.append(buf, count: n) }
            s.close(); Self.lastBody = d
        } else { Self.lastBody = request.httpBody }
        let (code, data) = Self.responses[request.url!] ?? (404, Data())
        let resp = HTTPURLResponse(url: request.url!, statusCode: code, httpVersion: nil, headerFields: nil)!
        client?.urlProtocol(self, didReceive: resp, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: data)
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}

/// สองชุดนี้ใช้ StubURLProtocol ร่วมกัน จึงต้องรันทีละเทสต์
@Suite(.serialized) struct NetworkStubTests {}

extension NetworkStubTests { @Suite struct UpdaterTests {
    @Test func versionsCompareNumerically() {
        let v = { AppVersion($0)! }
        #expect(v("0.10.0") > v("0.9.9"))
        #expect(v("v0.3.0") > v("0.2.0"))
        #expect(v("1.0") == v("1.0.0"))
        #expect(!(v("0.2.0") > v("0.2.0")))
        #expect(v("0.3.0-beta") == v("0.3.0"))
        #expect(AppVersion("abc") == nil)
        #expect(AppVersion("1..2") == nil)
        #expect(v("v1.2.3").description == "1.2.3")
    }

    static let releaseJSON = """
    {"tag_name":"v0.3.0","name":"Jotdown 0.3.0","body":"**New**\\n- Updates","html_url":"https://github.com/euwnakrub/jotdown/releases/tag/v0.3.0",
     "assets":[{"name":"notes.txt","browser_download_url":"https://example.com/notes.txt"},
               {"name":"Jotdown.zip","browser_download_url":"https://example.com/Jotdown.zip","digest":"sha256:abc"}]}
    """

    @Test func decodesGitHubRelease() throws {
        let r = try ReleaseInfo.decode(Data(Self.releaseJSON.utf8))
        #expect(r.version == AppVersion("0.3.0"))
        #expect(r.zipAsset?.name == "Jotdown.zip")
        #expect(r.zipAsset?.digest == "sha256:abc")
        #expect(r.body?.contains("Updates") == true)
    }

    @Test @MainActor func fetchLatestUsesGitHubAPI() async throws {
        StubURLProtocol.responses = [Updater.latestAPI: (200, Data(Self.releaseJSON.utf8))]
        let u = Updater()
        u.session = StubURLProtocol.session()
        let r = try await u.fetchLatest()
        #expect(r.tagName == "v0.3.0")
        #expect(StubURLProtocol.lastRequest?.value(forHTTPHeaderField: "Accept") == "application/vnd.github+json")
        StubURLProtocol.responses = [Updater.latestAPI: (403, Data())]
        await #expect(throws: UpdateError.self) { try await u.fetchLatest() }
    }

    @Test @MainActor func autoCheckDefaultsOn() {
        let d = UserDefaults(suiteName: "jot-updater-test-\(UUID().uuidString)")!
        let u = Updater()
        u.defaults = d
        #expect(u.automaticallyChecks)
        u.automaticallyChecks = false
        #expect(!u.automaticallyChecks)
    }

    // MARK: - ติดตั้งจริงจาก zip ปลอม

    /// แอปปลอมที่เซ็น ad-hoc: Contents/MacOS/x (สำเนา /usr/bin/true) + Info.plist
    static func makeFakeApp(in dir: URL, id: String, version: String) throws -> URL {
        let app = dir.appendingPathComponent("Jotdown.app")
        let macos = app.appendingPathComponent("Contents/MacOS")
        try FileManager.default.createDirectory(at: macos, withIntermediateDirectories: true)
        try FileManager.default.copyItem(at: URL(fileURLWithPath: "/usr/bin/true"), to: macos.appendingPathComponent("x"))
        let plist: [String: Any] = ["CFBundleIdentifier": id, "CFBundleExecutable": "x", "CFBundlePackageType": "APPL",
                                    "CFBundleShortVersionString": version, "CFBundleVersion": version]
        try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
            .write(to: app.appendingPathComponent("Contents/Info.plist"))
        try run("/usr/bin/codesign", ["--force", "--sign", "-", "--identifier", id, app.path])
        return app
    }

    static func run(_ tool: String, _ args: [String]) throws {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: tool)
        p.arguments = args
        p.standardError = FileHandle.nullDevice
        try p.run(); p.waitUntilExit()
        if p.terminationStatus != 0 { throw UpdateError.unzipFailed }
    }

    static func zip(_ app: URL, to zip: URL) throws {
        try run("/usr/bin/ditto", ["-c", "-k", "--keepParent", app.path, zip.path])
    }

    struct Fixture {
        let root: URL, installed: URL, zip: URL, digest: String
    }

    /// แอปที่ "ติดตั้งอยู่" 0.2.0 + zip ของ 0.3.0
    static func fixture(newID: String = "com.euw.jotdown", newVersion: String = "0.3.0") throws -> Fixture {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("jot-update-\(UUID().uuidString)")
        let installedDir = root.appendingPathComponent("Applications")
        let buildDir = root.appendingPathComponent("build")
        let installed = try makeFakeApp(in: installedDir, id: "com.euw.jotdown", version: "0.2.0")
        let newApp = try makeFakeApp(in: buildDir, id: newID, version: newVersion)
        let zip = root.appendingPathComponent("Jotdown.zip")
        try Self.zip(newApp, to: zip)
        return Fixture(root: root, installed: installed, zip: zip, digest: "sha256:" + (try UpdateInstaller.sha256Hex(of: zip)))
    }

    static func asset(_ f: Fixture, digest: String?) throws -> ReleaseInfo.Asset {
        let url = URL(string: "https://example.com/dl/\(UUID().uuidString)/Jotdown.zip")!
        StubURLProtocol.responses[url] = (200, try Data(contentsOf: f.zip))
        return ReleaseInfo.Asset(name: "Jotdown.zip", browserDownloadUrl: url, digest: digest)
    }

    @Test func adHocAppRequiresOnlyBundleID() throws {
        let f = try Self.fixture()
        defer { try? FileManager.default.removeItem(at: f.root) }
        #expect(UpdateInstaller.requirement(for: f.installed, bundleID: "com.euw.jotdown") == "identifier \"com.euw.jotdown\"")
    }

    @Test func downloadsVerifiesAndReplacesApp() async throws {
        let f = try Self.fixture()
        defer { try? FileManager.default.removeItem(at: f.root) }
        let a = try Self.asset(f, digest: f.digest)
        let req = UpdateInstaller.requirement(for: f.installed, bundleID: "com.euw.jotdown")
        let (app, work) = try await UpdateInstaller.prepare(asset: a, version: AppVersion("0.3.0")!, replacing: f.installed,
                                                            bundleID: "com.euw.jotdown", requirement: req, session: StubURLProtocol.session())
        try UpdateInstaller.replace(f.installed, with: app)
        try? FileManager.default.removeItem(at: work)
        let info = NSDictionary(contentsOf: f.installed.appendingPathComponent("Contents/Info.plist"))
        #expect(info?["CFBundleShortVersionString"] as? String == "0.3.0")
        // แอปเดิมถูกแทนที่ ไม่มีสำเนาค้างข้าง ๆ
        let left = try FileManager.default.contentsOfDirectory(atPath: f.installed.deletingLastPathComponent().path)
        #expect(left == ["Jotdown.app"])
    }

    @Test func rejectsDamagedDownload() async throws {
        let f = try Self.fixture()
        defer { try? FileManager.default.removeItem(at: f.root) }
        let a = try Self.asset(f, digest: "sha256:" + String(repeating: "0", count: 64))
        await #expect(throws: UpdateError.self) {
            _ = try await UpdateInstaller.prepare(asset: a, version: AppVersion("0.3.0")!, replacing: f.installed,
                                                  bundleID: "com.euw.jotdown", requirement: "identifier \"com.euw.jotdown\"", session: StubURLProtocol.session())
        }
        let info = NSDictionary(contentsOf: f.installed.appendingPathComponent("Contents/Info.plist"))
        #expect(info?["CFBundleShortVersionString"] as? String == "0.2.0")
    }

    @Test func rejectsOtherAppOrWrongVersion() async throws {
        for (id, ver) in [("com.evil.app", "0.3.0"), ("com.euw.jotdown", "0.2.5")] {
            let f = try Self.fixture(newID: id, newVersion: ver)
            defer { try? FileManager.default.removeItem(at: f.root) }
            let a = try Self.asset(f, digest: f.digest)
            await #expect(throws: UpdateError.self) {
                _ = try await UpdateInstaller.prepare(asset: a, version: AppVersion("0.3.0")!, replacing: f.installed,
                                                      bundleID: "com.euw.jotdown", requirement: "identifier \"com.euw.jotdown\"", session: StubURLProtocol.session())
            }
        }
    }

    @Test func rejectsTamperedSignature() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("jot-tamper-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: dir) }
        let app = try Self.makeFakeApp(in: dir, id: "com.euw.jotdown", version: "0.3.0")
        let bin = app.appendingPathComponent("Contents/MacOS/x")
        let h = try FileHandle(forWritingTo: bin); h.seekToEndOfFile(); h.write(Data([0x00, 0x01])); try h.close()
        #expect(throws: UpdateError.self) {
            try UpdateInstaller.verifyApp(app, bundleID: "com.euw.jotdown", version: AppVersion("0.3.0")!, requirement: "identifier \"com.euw.jotdown\"")
        }
    }

    @Test @MainActor func appMenuHasCheckForUpdatesAndHelpHasFeedback() {
        _ = NSApplication.shared
        let menu = MainMenu.build()
        let appItems = menu.items.first?.submenu?.items.map(\.title) ?? []
        #expect(appItems.contains("Check for Updates…"))
        let help = menu.items.last?.submenu?.items.map(\.title) ?? []
        #expect(help.contains("Send Feedback…"))
        let delegate = AppDelegate()
        #expect(delegate.responds(to: NSSelectorFromString("jotCheckForUpdates:")))
        #expect(delegate.responds(to: NSSelectorFromString("jotSendFeedback:")))
    }
}
}

extension NetworkStubTests { @Suite struct FeedbackTests {
    @Test func validation() {
        #expect(Feedback.validate(message: "  \n ", email: "") != nil)
        #expect(Feedback.validate(message: "Great app", email: "") == nil)
        #expect(Feedback.validate(message: "Great app", email: "me@example.com") == nil)
        #expect(Feedback.validate(message: "Great app", email: "not-an-email") != nil)
        #expect(Feedback.validate(message: String(repeating: "a", count: Feedback.maxLength + 1), email: "") != nil)
    }

    @Test func payloadIncludesSystemInfo() {
        let p = Feedback.makePayload(message: "  สวัสดี  ", email: " a@b.co ")
        #expect(p.message == "สวัสดี")
        #expect(p.email == "a@b.co")
        #expect(p.osVersion.split(separator: ".").count == 3)
        #expect(!p.model.isEmpty)
    }

    @Test func requestIsJSONPost() throws {
        let p = FeedbackPayload(message: "hi", email: "", appVersion: "0.3.0", osVersion: "15.1.0", model: "Mac14,2")
        let r = try Feedback.request(for: p)
        #expect(r.httpMethod == "POST")
        #expect(r.url?.path == "/api/feedback")
        #expect(r.value(forHTTPHeaderField: "X-Jotdown-Client") == "mac")
        #expect(try JSONDecoder().decode(FeedbackPayload.self, from: r.httpBody!) == p)
    }

    @Test func sendReportsServerErrors() async throws {
        let p = FeedbackPayload(message: "hi", email: "", appVersion: "0.3.0", osVersion: "15.1.0", model: "Mac")
        StubURLProtocol.responses[Feedback.endpoint] = (200, Data("{\"ok\":true}".utf8))
        try await Feedback.send(p, session: StubURLProtocol.session())
        #expect(try JSONDecoder().decode(FeedbackPayload.self, from: StubURLProtocol.lastBody!) == p)
        StubURLProtocol.responses[Feedback.endpoint] = (503, Data())
        await #expect(throws: Feedback.SendError.self) { try await Feedback.send(p, session: StubURLProtocol.session()) }
    }

    @Test func mailtoFallbackEncodesEverything() {
        let p = FeedbackPayload(message: "a+b & c?\nบรรทัดสอง", email: "", appVersion: "0.3.0", osVersion: "15.1.0", model: "Mac14,2")
        let u = Feedback.mailtoURL(for: p)
        #expect(u.absoluteString.hasPrefix("mailto:euwnakrub@gmail.com?subject="))
        #expect(!u.absoluteString.contains("+"))
        let c = URLComponents(url: u, resolvingAgainstBaseURL: false)!
        #expect(c.queryItems?.first { $0.name == "body" }?.value?.hasPrefix("a+b & c?\nบรรทัดสอง") == true)
    }

    @Test @MainActor func windowShowsErrorForEmptyMessageAndSnapshots() throws {
        _ = NSApplication.shared
        let c = FeedbackWindowController()
        c.sendPressed()
        #expect(!c.errorLabel.isHidden)
        #expect(c.sendButton.isEnabled)
        c.showError(nil)
        c.textView.string = "The table editor is great, but I'd love keyboard shortcuts for moving rows."
        c.emailField.stringValue = "reader@example.com"
        for (tag, ap) in [("aqua", NSAppearance.Name.aqua), ("dark", .darkAqua)] {
            c.window!.appearance = NSAppearance(named: ap)
            let v = c.window!.contentView!
            v.layoutSubtreeIfNeeded()
            try snapshotWithWindowBackground(v, appearance: ap, to: SnapshotDir.url.appendingPathComponent("feedback-window-\(tag).png"))
            #expect(v.bounds.width >= 470 && v.bounds.height > 300)
        }
        c.close()
    }
}
}
