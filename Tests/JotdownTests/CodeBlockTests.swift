import Testing
import AppKit
@testable import Jotdown

@MainActor @Suite(.serialized) struct CodeBlockTests {
    static let md = """
    Intro

    ```swift
    // comment
    let n = 42
    print("hi")
    ```

    Middle text

    ```python
    def run(self):
        return None
    ```

    Tail text

    ```
    plain let n = 1
    ```

    """

    func color(_ s: NSTextStorage, _ needle: String, in block: String? = nil) -> NSColor? {
        let ns = s.string as NSString
        let base = block.map { ns.range(of: $0).location } ?? 0
        let r = ns.range(of: needle, options: [], range: NSRange(location: base, length: ns.length - base))
        guard r.location != NSNotFound else { return nil }
        return s.attribute(.foregroundColor, at: r.location, effectiveRange: nil) as? NSColor
    }

    @Test func roundTripByteExactWithHighlighting() {
        let (doc, _) = makeEditor(Self.md)
        #expect(doc.currentMarkdown == Self.md)
        // และบล็อกที่ไม่รู้จักภาษา / ภาษาแปลก ๆ ก็ไม่เสียเนื้อหา
        let odd = "```lua\nlocal x = \"a\" -- c\n```\n\n````md\n```inner\n```\n````\n"
        let (d2, _) = makeEditor(odd)
        #expect(d2.currentMarkdown == odd)
    }

    @Test func colorsAreAppliedOnLoad() {
        let (doc, _) = makeEditor(Self.md)
        let s = doc.textStorage
        #expect(color(s, "let", in: "// comment") === Palette.syntax(.keyword))
        #expect(color(s, "42") === Palette.syntax(.number))
        #expect(color(s, "\"hi\"") === Palette.syntax(.string))
        #expect(color(s, "// comment") === Palette.syntax(.comment))
        #expect(color(s, "print") === Palette.syntax(.function))
        #expect(color(s, "def") === Palette.syntax(.keyword))
        #expect(color(s, "self") === Palette.syntax(.attribute))
        #expect(color(s, "None") === Palette.syntax(.keyword))
        // ไม่มีภาษา = สีข้อความปกติ
        #expect(color(s, "let", in: "plain") === Palette.text)
        // ข้อความนอกกล่องโค้ดไม่ถูกแตะ
        #expect(color(s, "Middle") === Palette.text)
    }

    @Test func typingRehighlightsOnlyTheEditedBlock() {
        let (doc, vc) = makeEditor(Self.md)
        let tv = vc.textView!
        let s = doc.textStorage
        // ทำเครื่องหมายสีผิดในบล็อก python (อยู่ไกลจากบล็อกที่จะแก้เกิน 1 ย่อหน้า) ถ้า restyle แตะมัน สีนี้จะถูกเขียนทับ
        let py = (s.string as NSString).range(of: "def")
        s.addAttribute(.foregroundColor, value: NSColor.red, range: py)
        #expect(s.attribute(.foregroundColor, at: py.location, effectiveRange: nil) as? NSColor == NSColor.red)
        // พิมพ์ต่อท้ายบรรทัด `let n = 42` ในบล็อก swift: "let n = 42" -> เติม " // x"
        let at = (s.string as NSString).range(of: "42")
        tv.select(NSMaxRange(at))
        tv.type(" // x")
        #expect(color(s, "// x") === Palette.syntax(.comment))
        #expect(color(s, "let", in: "// comment") === Palette.syntax(.keyword))
        #expect(s.attribute(.foregroundColor, at: py.location + 5, effectiveRange: nil) as? NSColor == NSColor.red)      // ตำแหน่งขยับตามตัวอักษรที่พิมพ์เพิ่ม 5 ตัว
        #expect(doc.currentMarkdown.contains("let n = 42 // x\n"))
        // เริ่มสตริงใหม่: ตัวอักษรหลังเครื่องหมายคำพูดกลายเป็นสีสตริงทันที และปิดแล้วกลับเป็นปกติ
        tv.select((s.string as NSString).range(of: "print").location)
        tv.type("\"abc")
        // (สตริงยังไม่ปิดจบที่ท้ายบรรทัด: เป็นสีสตริง)
        #expect(color(s, "\"abc") === Palette.syntax(.string))
    }

    @Test func changingLanguageRecolorsAndRewritesFence() {
        let (doc, vc) = makeEditor("```\nlet n = 1 // c\n```\n")
        let tv = vc.textView!
        let s = doc.textStorage
        #expect(color(s, "let") === Palette.text)
        #expect(tv.setCodeLanguage("swift", at: 0))
        #expect(doc.currentMarkdown == "```swift\nlet n = 1 // c\n```\n")
        #expect(color(s, "let") === Palette.syntax(.keyword))
        #expect(color(s, "// c") === Palette.syntax(.comment))
        // เปลี่ยนเป็นภาษาอื่น/ข้อความธรรมดา
        #expect(tv.setCodeLanguage("python", at: 0))
        #expect(doc.currentMarkdown.hasPrefix("```python\n"))
        #expect(color(s, "let") === Palette.text)             // let ไม่ใช่ keyword ใน python
        #expect(color(s, "// c") === Palette.text)
        #expect(tv.setCodeLanguage("", at: 0))
        #expect(doc.currentMarkdown == "```\nlet n = 1 // c\n```\n")
        // ไม่เปลี่ยนถ้าเหมือนเดิม / ชื่อไม่ถูกต้อง / ไม่ใช่กล่องโค้ด
        #expect(!tv.setCodeLanguage("", at: 0))
        #expect(!tv.setCodeLanguage("a b", at: 0))
        #expect(!tv.setCodeLanguage("a`b", at: 0))
    }

    @Test func languageChangeIsUndoable() {
        let (doc, vc) = makeEditor("```swift\nlet n = 1\n```\n", explicitUndo: true)
        let tv = vc.textView!
        tv.event { tv.setCodeLanguage("go", at: 0) }
        #expect(doc.currentMarkdown.hasPrefix("```go\n"))
        doc.undoManager?.undo()
        #expect(doc.currentMarkdown.hasPrefix("```swift\n"))
        #expect(color(doc.textStorage, "let") === Palette.syntax(.keyword))
    }

    @Test func languageMenuListsLanguagesAndMarksCurrent() {
        let (_, vc) = makeEditor("```swift\nlet n = 1\n```\n")
        let m = vc.textView.languageMenu(forBlockAt: 0)
        let titles = m.items.map(\.title)
        for t in ["Plain Text", "Swift", "Python", "JavaScript", "TypeScript", "JSON", "Bash", "HTML", "CSS", "SQL", "Go", "Rust", "C", "C++", "Java", "Kotlin", "YAML", "Markdown", "Other…"] {
            #expect(titles.contains(t), Comment(rawValue: t))
        }
        #expect(m.items.first { $0.title == "Swift" }?.state == .on)
        #expect(m.items.first { $0.title == "Python" }?.state == .off)
        let other = (vc.textView.languageMenu(forBlockAt: 0))
        #expect(other.items.filter { $0.state == .on }.count == 1)
    }

    @Test func labelRectIsInsideBlockAndOnlyForCodeBlocks() {
        let (_, vc) = makeEditor(Self.md)
        let tv = vc.textView!
        let lm = tv.layoutManager as! EditorLayoutManager
        let ns = tv.nsString
        let w = tv.textContainer!.size.width
        let code = lm.languageLabelRect(forParagraphAt: ns.range(of: "let n").location)
        #expect(code != nil)
        if let r = code {
            #expect(r.maxX <= w + 1 && r.minX > w / 2)       // ชิดขวา อยู่ในกล่อง
            let first = lm.lineFragmentUsedRect(forGlyphAt: lm.glyphIndexForCharacter(at: ns.range(of: "// comment").location), effectiveRange: nil)
            #expect(r.maxY <= first.minY + 1, Comment(rawValue: "ป้ายต้องอยู่เหนือบรรทัดแรก \(r) \(first)"))
        }
        #expect(lm.languageLabelRect(forParagraphAt: ns.range(of: "Middle").location) == nil)
        #expect(EditorLayoutManager.languageTitle("swift") == "Swift")
        #expect(EditorLayoutManager.languageTitle("") == "Plain Text")
        #expect(EditorLayoutManager.languageTitle("lua") == "lua")
        #expect(EditorLayoutManager.languageTitle("js") == "JavaScript")
    }

    @Test func inlineCodeAndBlockShareBackground() {
        #expect(Palette.codeBackgroundHex.light == 0xEFEBDF)
    }

    // MARK: - snapshot
    static let showcase = """
    # Code blocks

    ```swift
    import Foundation

    // Greets someone
    @MainActor
    struct Greeter {
        let name: String
        func greet(times: Int = 3) -> String {
            return String(repeating: "Hello, \\(name)! ", count: times)
        }
    }
    ```

    ```python
    @dataclass
    class Point:
        x: float = 0.0

        def dist(self, other):
            # euclidean
            return ((self.x - other.x) ** 2) ** 0.5 if other else None
    ```

    ```javascript
    const items = [1, 2, 3].map((n) => n * 2.5); // double
    class App extends Base { async load() { return `ok ${items.length}`; } }
    ```

    ```json
    { "name": "jotdown", "version": 1, "private": true, "tags": ["a", null] }
    ```

    ```bash
    #!/bin/bash
    NAME=world
    if [ -f "$FILE" ]; then echo "hi $NAME" | grep -n hi; fi
    ```

    ```html
    <!-- page --><div class="box" id="a"><a href="/x">link</a></div>
    ```

    ```css
    .box > a { color: #b45309; margin: 0 auto 12px; background: rgb(1, 2, 3); }
    ```

    ```sql
    -- users
    SELECT id, COUNT(*) FROM users WHERE name = 'bob' AND age > 30 GROUP BY id;
    ```

    ```go
    func (s *Server) Run(n int) error { return fmt.Errorf("bad %d", n) }
    ```

    ```rust
    fn main<'a>(x: &'a str) { let c = 'z'; println!("hi {}", 1_000u32); }
    ```

    ```yaml
    name: jotdown   # app
    items:
      - key: "v"
      - 12
    ```

    ```text
    plain text, no colors: let if "x" 42
    ```

    Inline `code` sits on the same warm gray as blocks.

    """

    func snap(_ ap: NSAppearance.Name, size: CGSize = CGSize(width: 900, height: 1900)) throws {
        _ = NSApplication.shared
        Fonts.registerAll()
        let doc = JotdownDocument(); doc.load(markdown: Self.showcase)
        let vc = EditorViewController(document: doc); _ = vc.view
        let shot = try snapshot("code-blocks", size: size, appearance: ap, viewController: vc)
        #expect(FileManager.default.fileExists(atPath: shot.png.path))
        let tv = vc.textView!
        #expect(tv.frame.width <= size.width + 0.5)
        let used = tv.layoutManager!.usedRect(for: tv.textContainer!)
        #expect(used.width <= Theme.columnMaxWidth + 0.5)
        #expect(doc.currentMarkdown == Self.showcase)
    }
    @Test func snapshotLight() throws { try snap(.aqua) }
    @Test func snapshotDark() throws { try snap(.darkAqua) }
    @Test func snapshotNarrow() throws { try snap(.aqua, size: CGSize(width: 480, height: 2400)) }
}
