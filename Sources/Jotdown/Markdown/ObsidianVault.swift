import Foundation

/// vault ของ Obsidian: root = โฟลเดอร์แรกที่มี `.obsidian/` ไล่ขึ้นจากโฟลเดอร์ของเอกสาร (ไม่เจอ = โฟลเดอร์ของเอกสาร)
/// หาไฟล์ตามลำดับแบบ Obsidian และมี index ชื่อไฟล์ของทั้ง vault สร้างเบื้องหลังครั้งเดียวต่อ vault
final class ObsidianVault {
    enum Resolution: Equatable {
        case found(URL)
        case notFound
        case pending            // กำลังสร้าง index ยังตอบไม่ได้
    }

    let root: URL
    let hasObsidianFolder: Bool
    private(set) var attachmentFolder: String?

    private let lock = NSLock()
    private var index: [String: [URL]] = [:]       // ชื่อไฟล์ตัวพิมพ์เล็ก -> path ทั้งหมด
    private var building = false
    private var builtAt: Date?
    private(set) var isReady = false
    /// หาไม่เจอแล้ว index เก่ากว่านี้ (วินาที) = สร้างใหม่เบื้องหลัง
    var rebuildInterval: TimeInterval = 3
    static let skipped: Set<String> = [".obsidian", ".git", "node_modules", ".trash"]

    private static var cache: [String: ObsidianVault] = [:]
    private static let cacheLock = NSLock()

    static func rootDirectory(for docDir: URL) -> (URL, Bool) {
        var d = docDir.standardizedFileURL
        while true {
            if FileManager.default.fileExists(atPath: d.appendingPathComponent(".obsidian").path) { return (d, true) }
            let parent = d.deletingLastPathComponent()
            if parent.path == d.path || d.path == "/" { break }
            d = parent
        }
        return (docDir.standardizedFileURL, false)
    }

    static func vault(for docDir: URL) -> ObsidianVault {
        let (root, has) = rootDirectory(for: docDir)
        cacheLock.lock(); defer { cacheLock.unlock() }
        if let v = cache[root.path] { return v }
        let v = ObsidianVault(root: root, hasObsidianFolder: has)
        cache[root.path] = v
        return v
    }

    static func resetCache() { cacheLock.lock(); cache = [:]; cacheLock.unlock() }

    init(root: URL, hasObsidianFolder: Bool) {
        self.root = root
        self.hasObsidianFolder = hasObsidianFolder
        if hasObsidianFolder,
           let data = try? Data(contentsOf: root.appendingPathComponent(".obsidian/app.json")),
           let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let p = obj["attachmentFolderPath"] as? String, !p.isEmpty, p != "/" {
            attachmentFolder = p
        }
    }

    // MARK: - ค้นหา
    /// `name` อาจมี path (`folder/x.png`) ไม่ต้องมี `.md` สำหรับโน้ต
    func resolve(_ name: String, docDir: URL?, isNote: Bool, rebuildIfMissing: Bool = true) -> Resolution {
        let fm = FileManager.default
        func candidates(_ n: String) -> [String] {
            let ext = (n as NSString).pathExtension
            return isNote && ext.isEmpty ? [n + ".md", n] : (isNote && ext.lowercased() != "md" && ext.lowercased() != "markdown" ? [n + ".md", n] : [n])
        }
        func exists(_ u: URL) -> Bool { var d: ObjCBool = false; return fm.fileExists(atPath: u.path, isDirectory: &d) && !d.boolValue }
        let clean = name.trimmingCharacters(in: .whitespaces)
        guard !clean.isEmpty else { return .notFound }
        // 1) มี path: จาก vault root ก่อน แล้วจากโฟลเดอร์เอกสาร
        if clean.contains("/") {
            for base in [root, docDir].compactMap({ $0 }) { for c in candidates(clean) where exists(base.appendingPathComponent(c)) { return .found(base.appendingPathComponent(c).standardizedFileURL) } }
        } else {
            // 2) ชื่ออย่างเดียว: โฟลเดอร์เอกสาร → โฟลเดอร์ attachment → ทั้ง vault
            if let docDir { for c in candidates(clean) where exists(docDir.appendingPathComponent(c)) { return .found(docDir.appendingPathComponent(c).standardizedFileURL) } }
            if let af = attachmentFolder {
                let dir: URL? = af.hasPrefix("./") ? docDir?.appendingPathComponent(String(af.dropFirst(2))) : root.appendingPathComponent(af)
                if let dir { for c in candidates(clean) where exists(dir.appendingPathComponent(c)) { return .found(dir.appendingPathComponent(c).standardizedFileURL) } }
            }
        }
        // 3) index ทั้ง vault (ชื่อไฟล์ไม่สนตัวพิมพ์) เจอหลายไฟล์ = path สั้นสุด
        startIndexIfNeeded()
        lock.lock()
        let ready = isReady
        var hits: [URL] = []
        for c in candidates(clean) { hits += index[(c as NSString).lastPathComponent.lowercased()] ?? [] }
        if clean.contains("/") { let tail = "/" + clean.lowercased(); hits = hits.filter { $0.path.lowercased().hasSuffix(tail) || $0.path.lowercased().hasSuffix(tail + ".md") } }
        let stale = builtAt.map { Date().timeIntervalSince($0) > rebuildInterval } ?? true
        lock.unlock()
        if let best = hits.min(by: { $0.path.count < $1.path.count }) { return .found(best) }
        if !ready { return .pending }
        if rebuildIfMissing, stale { rebuild() }
        return .notFound
    }

    // MARK: - index เบื้องหลัง
    func startIndexIfNeeded() {
        lock.lock()
        let need = !isReady && !building
        if need { building = true }
        lock.unlock()
        if need { build() }
    }

    private func rebuild() {
        lock.lock(); let ok = !building; if ok { building = true }; lock.unlock()
        if ok { build() }
    }

    private func build() {
        DispatchQueue.global(qos: .utility).async { [self] in
            var map: [String: [URL]] = [:]
            let fm = FileManager.default
            if let e = fm.enumerator(at: root, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsPackageDescendants]) {
                for case let u as URL in e {
                    let n = u.lastPathComponent
                    if Self.skipped.contains(n) { e.skipDescendants(); continue }
                    if (try? u.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true { continue }
                    map[n.lowercased(), default: []].append(u.standardizedFileURL)
                }
            }
            lock.lock(); index = map; isReady = true; building = false; builtAt = Date(); lock.unlock()
            DispatchQueue.main.async { NotificationCenter.default.post(name: .jotImageLoaded, object: nil) }
        }
    }

    var indexedFileCount: Int { lock.lock(); defer { lock.unlock() }; return index.values.reduce(0) { $0 + $1.count } }
}
