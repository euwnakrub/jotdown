import AppKit
import CryptoKit
import Security

/// เลขเวอร์ชันแบบ 1.2.3 (ตัด v นำหน้าและ -beta ท้ายออก) เทียบทีละหลัก ขาดหลัก = 0
struct AppVersion: Comparable, CustomStringConvertible {
    let parts: [Int]

    init?(_ string: String) {
        var s = string.trimmingCharacters(in: .whitespaces)
        if s.first == "v" || s.first == "V" { s.removeFirst() }
        let core = s.split(separator: "-", maxSplits: 1).first.map(String.init) ?? s
        let nums = core.split(separator: ".", omittingEmptySubsequences: false).map { Int($0) }
        guard !nums.isEmpty, nums.allSatisfy({ $0 != nil }) else { return nil }
        parts = nums.map { $0! }
    }

    private static func padded(_ a: AppVersion, _ b: AppVersion) -> ([Int], [Int]) {
        let n = max(a.parts.count, b.parts.count)
        return (a.parts + Array(repeating: 0, count: n - a.parts.count), b.parts + Array(repeating: 0, count: n - b.parts.count))
    }
    static func == (a: AppVersion, b: AppVersion) -> Bool { let (x, y) = padded(a, b); return x == y }
    static func < (a: AppVersion, b: AppVersion) -> Bool { let (x, y) = padded(a, b); return x.lexicographicallyPrecedes(y) }
    var description: String { parts.map(String.init).joined(separator: ".") }
}

/// ข้อมูลจาก GitHub API /releases/latest (เฉพาะช่องที่ใช้)
struct ReleaseInfo: Decodable {
    struct Asset: Decodable {
        let name: String
        let browserDownloadUrl: URL
        /// "sha256:<hex>" (GitHub ใส่ให้เองทุก asset)
        let digest: String?
    }
    let tagName: String
    let name: String?
    let body: String?
    let htmlUrl: URL
    let assets: [Asset]

    var version: AppVersion? { AppVersion(tagName) }
    var zipAsset: Asset? { assets.first { $0.name == "Jotdown.zip" } ?? assets.first { $0.name.hasSuffix(".zip") } }

    static func decode(_ data: Data) throws -> ReleaseInfo {
        let d = JSONDecoder()
        d.keyDecodingStrategy = .convertFromSnakeCase
        return try d.decode(ReleaseInfo.self, from: data)
    }
}

enum UpdateError: LocalizedError {
    case server(Int)
    case digestMismatch
    case noAppInArchive
    case badSignature(String)
    case wrongApp
    case unzipFailed

    var errorDescription: String? {
        switch self {
        case .server(let code): return "The update server returned an error (\(code))."
        case .digestMismatch: return "The downloaded update was damaged. Please try again."
        case .noAppInArchive: return "The downloaded update doesn't contain Jotdown."
        case .badSignature(let why): return "The downloaded update failed its security check (\(why))."
        case .wrongApp: return "The downloaded update isn't the expected version of Jotdown."
        case .unzipFailed: return "The downloaded update couldn't be unpacked."
        }
    }
}

/// ขั้นตอนติดตั้งที่ไม่แตะ UI (เทสต์ได้): ดาวน์โหลด → ตรวจ sha256 → แตก zip → ตรวจลายเซ็น/bundle id/เวอร์ชัน → สลับแอป
enum UpdateInstaller {
    static func sha256Hex(of file: URL) throws -> String {
        let data = try Data(contentsOf: file, options: .mappedIfSafe)
        return SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    /// digest ว่าง = ข้าม (release เก่าบางอันไม่มี) ไม่งั้นต้องตรง
    static func verifyDigest(_ file: URL, digest: String?) throws {
        guard let digest, digest.hasPrefix("sha256:") else { return }
        let want = digest.dropFirst("sha256:".count).lowercased()
        guard try sha256Hex(of: file) == want else { throw UpdateError.digestMismatch }
    }

    static func unzip(_ zip: URL, to dir: URL) throws {
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        p.arguments = ["-x", "-k", zip.path, dir.path]
        try p.run()
        p.waitUntilExit()
        guard p.terminationStatus == 0 else { throw UpdateError.unzipFailed }
    }

    static func findApp(in dir: URL) -> URL? {
        (try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil))?
            .first { $0.pathExtension == "app" }
    }

    /// requirement ที่แอปใหม่ต้องผ่าน: ถ้าแอปปัจจุบันเซ็นด้วยใบรับรองคงที่ ใช้ designated requirement ของมัน (ต้องเป็นใบเดียวกัน)
    /// ถ้าเป็น ad-hoc (requirement อิง cdhash ซึ่งเปลี่ยนทุก build) ใช้แค่ bundle id + ลายเซ็นต้องสมบูรณ์
    static func requirement(for app: URL, bundleID: String) -> String {
        let fallback = "identifier \"\(bundleID)\""
        var code: SecStaticCode?
        guard SecStaticCodeCreateWithPath(app as CFURL, [], &code) == errSecSuccess, let code else { return fallback }
        var req: SecRequirement?
        guard SecCodeCopyDesignatedRequirement(code, [], &req) == errSecSuccess, let req else { return fallback }
        var text: CFString?
        guard SecRequirementCopyString(req, [], &text) == errSecSuccess, let s = text as String? else { return fallback }
        return s.contains("cdhash") ? fallback : s
    }

    static func verifyApp(_ app: URL, bundleID: String, version: AppVersion, requirement: String) throws {
        let info = NSDictionary(contentsOf: app.appendingPathComponent("Contents/Info.plist"))
        guard info?["CFBundleIdentifier"] as? String == bundleID,
              let v = (info?["CFBundleShortVersionString"] as? String).flatMap(AppVersion.init), v == version
        else { throw UpdateError.wrongApp }
        var code: SecStaticCode?
        guard SecStaticCodeCreateWithPath(app as CFURL, [], &code) == errSecSuccess, let code else {
            throw UpdateError.badSignature("unreadable")
        }
        var req: SecRequirement?
        guard SecRequirementCreateWithString(requirement as CFString, [], &req) == errSecSuccess, let req else {
            throw UpdateError.badSignature("bad requirement")
        }
        let flags = SecCSFlags(rawValue: kSecCSCheckAllArchitectures | kSecCSCheckNestedCode | kSecCSStrictValidate)
        let status = SecStaticCodeCheckValidity(code, flags, req)
        guard status == errSecSuccess else { throw UpdateError.badSignature("code \(status)") }
    }

    /// ดาวน์โหลดและตรวจ คืน (แอปใหม่ที่พร้อมสลับ, โฟลเดอร์ชั่วคราวที่ต้องลบทีหลัง)
    /// โฟลเดอร์ชั่วคราวอยู่ volume เดียวกับแอปเดิม เพื่อให้สลับด้วย rename ได้
    static func prepare(asset: ReleaseInfo.Asset, version: AppVersion, replacing appURL: URL, bundleID: String,
                        requirement: String, session: URLSession) async throws -> (app: URL, work: URL) {
        let fm = FileManager.default
        let work = try fm.url(for: .itemReplacementDirectory, in: .userDomainMask, appropriateFor: appURL, create: true)
        do {
            let (tmp, resp) = try await session.download(from: asset.browserDownloadUrl)
            if let code = (resp as? HTTPURLResponse)?.statusCode, code != 200 { throw UpdateError.server(code) }
            let zip = work.appendingPathComponent("update.zip")
            try fm.moveItem(at: tmp, to: zip)
            try verifyDigest(zip, digest: asset.digest)
            let out = work.appendingPathComponent("extracted", isDirectory: true)
            try unzip(zip, to: out)
            guard let app = findApp(in: out) else { throw UpdateError.noAppInArchive }
            try verifyApp(app, bundleID: bundleID, version: version, requirement: requirement)
            return (app, work)
        } catch {
            try? fm.removeItem(at: work)
            throw error
        }
    }

    static func replace(_ appURL: URL, with newApp: URL) throws {
        _ = try FileManager.default.replaceItemAt(appURL, withItemAt: newApp)
    }

    /// เปิดแอปใหม่หลังตัวนี้ปิดสนิท (process ลูกอยู่ต่อได้หลังแอปปิด)
    static func relaunch(_ appURL: URL) {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/sh")
        p.arguments = ["-c", "while /bin/kill -0 \"$1\" 2>/dev/null; do /bin/sleep 0.2; done; /usr/bin/open \"$2\"",
                       "sh", "\(getpid())", appURL.path]
        try? p.run()
    }
}

/// อัปเดตอัตโนมัติจาก GitHub Releases: เช็ควันละครั้งตอนเปิดแอป + เมนู Jotdown → Check for Updates…
@MainActor
final class Updater: NSObject {
    static let shared = Updater()

    static let latestAPI = URL(string: "https://api.github.com/repos/euwnakrub/jotdown/releases/latest")!
    static let releasesPage = URL(string: "https://github.com/euwnakrub/jotdown/releases/latest")!
    static let checkInterval: TimeInterval = 24 * 60 * 60

    enum Key {
        static let auto = "JotUpdateAutoCheck"
        static let lastCheck = "JotUpdateLastCheck"
        static let skipped = "JotUpdateSkippedVersion"
    }

    var session: URLSession = .shared
    var defaults: UserDefaults = .standard
    private var busy = false
    private var timer: Timer?
    private var progressWindow: NSWindow?

    var automaticallyChecks: Bool {
        get { defaults.object(forKey: Key.auto) as? Bool ?? true }
        set { defaults.set(newValue, forKey: Key.auto) }
    }

    var currentVersion: AppVersion? {
        (Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String).flatMap(AppVersion.init)
    }

    /// เรียกตอนเปิดแอป: เช็คหลังเปิด 5 วินาที แล้วทุก 6 ชั่วโมง (แต่จะถามจริงไม่เกินวันละครั้ง)
    func start() {
        guard ProcessInfo.processInfo.environment["JOTDOWN_TESTING"] == nil,
              Bundle.main.bundleURL.pathExtension == "app" else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 5) { [weak self] in self?.checkIfDue() }
        timer = Timer.scheduledTimer(withTimeInterval: 6 * 60 * 60, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.checkIfDue() }
        }
    }

    private func checkIfDue() {
        guard automaticallyChecks, !busy else { return }
        let last = defaults.double(forKey: Key.lastCheck)
        guard Date().timeIntervalSince1970 - last >= Self.checkInterval else { return }
        Task { await check(userInitiated: false) }
    }

    func checkNow() {
        if busy { progressWindow?.makeKeyAndOrderFront(nil); return }
        Task { await check(userInitiated: true) }
    }

    func fetchLatest() async throws -> ReleaseInfo {
        var r = URLRequest(url: Self.latestAPI, timeoutInterval: 20)
        r.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        r.setValue("Jotdown/\(currentVersion?.description ?? "0")", forHTTPHeaderField: "User-Agent")
        let (data, resp) = try await session.data(for: r)
        let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
        guard code == 200 else { throw UpdateError.server(code) }
        return try ReleaseInfo.decode(data)
    }

    private func check(userInitiated: Bool) async {
        guard !busy else { return }
        busy = true
        defer { busy = false }
        let release: ReleaseInfo
        do {
            release = try await fetchLatest()
        } catch {
            if userInitiated { alert("Couldn't check for updates", error.localizedDescription) }
            return
        }
        defaults.set(Date().timeIntervalSince1970, forKey: Key.lastCheck)
        guard let new = release.version, let current = currentVersion, new > current, let asset = release.zipAsset else {
            if userInitiated {
                alert("You're up to date", "Jotdown \(currentVersion?.description ?? "") is the newest version.")
            }
            return
        }
        if !userInitiated, defaults.string(forKey: Key.skipped) == new.description { return }

        switch ask(release: release, new: new, current: current, userInitiated: userInitiated) {
        case .install: await install(asset: asset, version: new, release: release)
        case .skip: defaults.set(new.description, forKey: Key.skipped)
        case .later: break
        }
    }

    private enum Choice { case install, later, skip }

    private func ask(release: ReleaseInfo, new: AppVersion, current: AppVersion, userInitiated: Bool) -> Choice {
        let a = NSAlert()
        a.messageText = "A new version of Jotdown is available"
        a.informativeText = "Jotdown \(new) is available. You have \(current). Your notes are saved before Jotdown restarts."
        a.addButton(withTitle: "Install and Relaunch")
        a.addButton(withTitle: "Later")
        if !userInitiated { a.addButton(withTitle: "Skip This Version") }
        if let notes = release.body?.trimmingCharacters(in: .whitespacesAndNewlines), !notes.isEmpty {
            a.accessoryView = Self.notesView(notes)
        }
        a.showsSuppressionButton = true
        a.suppressionButton?.title = "Automatically check for updates"
        a.suppressionButton?.state = automaticallyChecks ? .on : .off
        NSApp.activate(ignoringOtherApps: true)
        let r = a.runModal()
        automaticallyChecks = a.suppressionButton?.state == .on
        switch r {
        case .alertFirstButtonReturn: return .install
        case .alertThirdButtonReturn: return .skip
        default: return .later
        }
    }

    /// บันทึกการเปลี่ยนแปลงของ release ในกล่องเลื่อนได้
    static func notesView(_ notes: String) -> NSView {
        let scroll = NSScrollView(frame: NSRect(x: 0, y: 0, width: 360, height: 140))
        scroll.hasVerticalScroller = true
        scroll.borderType = .bezelBorder
        let tv = NSTextView(frame: scroll.bounds)
        tv.isEditable = false
        tv.drawsBackground = false
        tv.textContainerInset = NSSize(width: 6, height: 6)
        tv.font = Fonts.body(.regular, size: 12)
        tv.string = notes
        tv.autoresizingMask = [.width]
        scroll.documentView = tv
        return scroll
    }

    private func install(asset: ReleaseInfo.Asset, version: AppVersion, release: ReleaseInfo) async {
        let appURL = Bundle.main.bundleURL
        let folder = appURL.deletingLastPathComponent()
        let fm = FileManager.default
        if appURL.path.contains("/AppTranslocation/") {
            manualDownload("Move Jotdown to your Applications folder first",
                           "macOS is running Jotdown from a temporary location, so it can't update itself. Quit Jotdown, drag it into Applications, open it from there and try again.",
                           release.htmlUrl)
            return
        }
        guard fm.isWritableFile(atPath: folder.path), fm.isWritableFile(atPath: appURL.path) else {
            manualDownload("Jotdown can't update itself",
                           "Your account can't change apps in “\(folder.path)”. Download the new version and replace Jotdown yourself.",
                           release.htmlUrl)
            return
        }
        showProgress("Downloading Jotdown \(version)…")
        let bundleID = Bundle.main.bundleIdentifier ?? "com.euw.jotdown"
        let requirement = UpdateInstaller.requirement(for: appURL, bundleID: bundleID)
        do {
            let (newApp, work) = try await UpdateInstaller.prepare(asset: asset, version: version, replacing: appURL,
                                                                   bundleID: bundleID, requirement: requirement, session: session)
            try UpdateInstaller.replace(appURL, with: newApp)
            try? fm.removeItem(at: work)
            hideProgress()
            defaults.removeObject(forKey: Key.skipped)
            UpdateInstaller.relaunch(appURL)
            NSApp.terminate(nil)     // applicationShouldTerminate บันทึกเอกสารทุกฉบับก่อนปิด
        } catch {
            hideProgress()
            manualDownload("Couldn't install the update", error.localizedDescription, release.htmlUrl)
        }
    }

    // MARK: - UI

    private func alert(_ title: String, _ text: String) {
        let a = NSAlert()
        a.messageText = title
        a.informativeText = text
        NSApp.activate(ignoringOtherApps: true)
        a.runModal()
    }

    private func manualDownload(_ title: String, _ text: String, _ page: URL) {
        let a = NSAlert()
        a.messageText = title
        a.informativeText = text
        a.addButton(withTitle: "Open Download Page")
        a.addButton(withTitle: "Cancel")
        NSApp.activate(ignoringOtherApps: true)
        if a.runModal() == .alertFirstButtonReturn { NSWorkspace.shared.open(page) }
    }

    private func showProgress(_ text: String) {
        let w = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 320, height: 90), styleMask: [.titled], backing: .buffered, defer: false)
        w.title = "Updating Jotdown"
        w.isReleasedWhenClosed = false
        let label = NSTextField(labelWithString: text)
        label.font = Fonts.body(.regular, size: 13)
        let bar = NSProgressIndicator()
        bar.style = .bar
        bar.isIndeterminate = true
        bar.startAnimation(nil)
        let stack = NSStackView(views: [label, bar])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 10
        stack.edgeInsets = NSEdgeInsets(top: 16, left: 20, bottom: 18, right: 20)
        bar.translatesAutoresizingMaskIntoConstraints = false
        bar.widthAnchor.constraint(equalToConstant: 280).isActive = true
        w.contentView = stack
        w.center()
        w.makeKeyAndOrderFront(nil)
        progressWindow = w
    }

    private func hideProgress() {
        progressWindow?.orderOut(nil)
        progressWindow = nil
    }
}
