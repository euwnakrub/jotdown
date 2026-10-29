import AppKit

// ทดสอบความเร็ว: Jot --bench <ไฟล์.md>  (parse + สร้าง text storage + serialize)
if let i = CommandLine.arguments.firstIndex(of: "--bench"), i + 1 < CommandLine.arguments.count,
   let text = try? String(contentsOfFile: CommandLine.arguments[i + 1], encoding: .utf8) {
    Fonts.registerAll()
    let t0 = Date()
    let a = MarkdownParser.parse(text)
    let t1 = Date()
    let out = MarkdownSerializer.serialize(a)
    let t2 = Date()
    print(String(format: "parse+build %.0f ms, serialize %.0f ms, %d chars -> %d", t1.timeIntervalSince(t0) * 1000, t2.timeIntervalSince(t1) * 1000, text.count, out.count))
    exit(0)
}

let app = NSApplication.shared
_ = JotdownDocumentController()      // ต้องสร้างก่อนใคร เพื่อให้เป็น NSDocumentController.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.regular)
app.run()
