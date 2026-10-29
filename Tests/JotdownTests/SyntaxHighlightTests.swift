import Testing
import AppKit
@testable import Jotdown

/// ตัวอย่างโค้ดทั้งหมดเป็นข้อความสังเคราะห์ที่เขียนขึ้นเพื่อเทสต์
@Suite struct SyntaxTokenizerTests {
    /// (ข้อความของ token, ชนิด) ตามลำดับ
    func toks(_ code: String, _ lang: String) -> [(String, TokenKind)] {
        let ns = code as NSString
        return SyntaxHighlighter.tokens(for: code, language: lang).map { (ns.substring(with: $0.range), $0.kind) }
    }
    func has(_ code: String, _ lang: String, _ text: String, _ kind: TokenKind, sourceLocation: SourceLocation = #_sourceLocation) {
        let t = toks(code, lang)
        #expect(t.contains { $0.0 == text && $0.1 == kind }, Comment(rawValue: "\(lang): ไม่พบ \(kind) '\(text)' ใน \(t)"), sourceLocation: sourceLocation)
    }

    @Test func swift() {
        let c = "import Foundation\n@MainActor struct Box<T> { // note\n  let n = 42\n  func run() -> String { \"hi\" } }"
        has(c, "swift", "import", .keyword); has(c, "swift", "struct", .keyword); has(c, "swift", "let", .keyword)
        has(c, "swift", "@MainActor", .attribute); has(c, "swift", "Foundation", .type); has(c, "swift", "String", .type)
        has(c, "swift", "// note", .comment); has(c, "swift", "42", .number); has(c, "swift", "\"hi\"", .string); has(c, "swift", "run", .function)
    }

    @Test func swiftMultilineStringAndBlockComment() {
        let c = "let s = \"\"\"\nline \"quoted\"\n\"\"\"\n/* a\nb */ let x = 1"
        has(c, "swift", "\"\"\"\nline \"quoted\"\n\"\"\"", .string)
        has(c, "swift", "/* a\nb */", .comment)
        has(c, "swift", "1", .number)
    }

    @Test func python() {
        let c = "@decorator\nclass Foo(Base):\n    def run(self, n=10):\n        # comment\n        return f\"x{n}\" if n else None\n"
        has(c, "python", "@decorator", .attribute); has(c, "python", "class", .keyword); has(c, "python", "def", .keyword)
        has(c, "python", "Foo", .type); has(c, "python", "run", .function); has(c, "python", "self", .attribute)
        has(c, "python", "# comment", .comment); has(c, "python", "10", .number); has(c, "python", "f\"x{n}\"", .string); has(c, "python", "None", .keyword)
        has("s = '''a\nb'''", "py", "'''a\nb'''", .string)
    }

    @Test func javascriptAndTypescript() {
        let c = "const total = items.map((x) => x * 2.5); // sum\nclass App extends Base { async load() { return `t${1}`; } }"
        has(c, "js", "const", .keyword); has(c, "js", "map", .function); has(c, "js", "2.5", .number); has(c, "js", "// sum", .comment)
        has(c, "javascript", "class", .keyword); has(c, "js", "App", .type); has(c, "js", "`t${1}`", .string); has(c, "jsx", "async", .keyword)
        has("interface User { id: number; name: string }", "ts", "interface", .keyword)
        has("interface User { id: number; name: string }", "ts", "number", .type)
        has("let x: Map<string, Foo> = new Map()", "tsx", "Foo", .type)
    }

    @Test func json() {
        let c = "{\n  \"name\": \"jot\",\n  \"count\": 3,\n  \"ok\": true,\n  \"none\": null\n}"
        has(c, "json", "\"name\"", .attribute); has(c, "json", "\"jot\"", .string); has(c, "json", "3", .number)
        has(c, "json", "true", .keyword); has(c, "json", "null", .keyword)
    }

    @Test func bash() {
        let c = "#!/bin/bash\nNAME=world\nif [ -f \"$FILE\" ]; then\n  echo \"hi $NAME\" | grep -n hi # tail\nx=$HOME\nfi\nls --all ./src"
        has(c, "bash", "#!/bin/bash", .comment); has(c, "sh", "NAME", .attribute); has(c, "zsh", "if", .keyword); has(c, "shell", "fi", .keyword)
        has(c, "bash", "echo", .function); has(c, "bash", "grep", .function); has(c, "bash", "\"hi $NAME\"", .string)
        has(c, "bash", "$HOME", .attribute); has(c, "bash", "# tail", .comment); has(c, "bash", "ls", .function); has(c, "bash", "--all", .type)
    }

    @Test func html() {
        let c = "<!-- c --><div class=\"box\" id='a'><a href=\"x\">hi</a></div>"
        has(c, "html", "<!-- c -->", .comment); has(c, "html", "div", .keyword); has(c, "xml", "class", .attribute)
        has(c, "html", "\"box\"", .string); has(c, "html", "'a'", .string); has(c, "html", "href", .attribute)
        #expect(!toks(c, "html").contains { $0.0 == "hi" })
    }

    @Test func css() {
        let c = "/* x */\n@media (max-width: 600px) { .box, #id { color: #fff; margin: 0 auto 12px; background: rgb(1, 2, 3); } }"
        has(c, "css", "/* x */", .comment); has(c, "css", "@media", .keyword); has(c, "css", ".box", .type); has(c, "css", "#id", .type)
        has(c, "css", "color", .attribute); has(c, "css", "#fff", .number); has(c, "css", "12px", .number); has(c, "css", "rgb", .function)
    }

    @Test func sql() {
        let c = "-- all\nSELECT id, COUNT(*) FROM users WHERE name = 'bob' AND age > 30 GROUP BY id;\ncreate table t (id int primary key, n varchar(20));"
        has(c, "sql", "-- all", .comment); has(c, "sql", "SELECT", .keyword); has(c, "sql", "FROM", .keyword); has(c, "sql", "COUNT", .function)
        has(c, "sql", "'bob'", .string); has(c, "sql", "30", .number); has(c, "sql", "create", .keyword); has(c, "sql", "int", .type); has(c, "sql", "varchar", .type)
    }

    @Test func goRust() {
        let g = "package main\n// hi\nfunc (s *Server) Run(n int) error { s := \"x\"; return nil }"
        has(g, "go", "package", .keyword); has(g, "golang", "// hi", .comment); has(g, "go", "int", .type); has(g, "go", "Server", .type); has(g, "go", "Run", .function); has(g, "go", "nil", .keyword)
        let r = "fn main<'a>(x: &'a str) { let c = 'z'; println!(\"hi {}\", 1_000u32); }"
        has(r, "rust", "fn", .keyword); has(r, "rs", "'a", .attribute); has(r, "rust", "'z'", .string); has(r, "rust", "println!", .function)
        has(r, "rust", "\"hi {}\"", .string); has(r, "rust", "1_000u32", .number); has(r, "rust", "str", .type)
    }

    @Test func cFamily() {
        let c = "#include <stdio.h>\nint main(void) { char c = 'x'; /* z */ printf(\"%d\", 0x1F); return 0; }"
        has(c, "c", "#include", .attribute); has(c, "c", "int", .type); has(c, "h", "main", .function); has(c, "c", "'x'", .string)
        has(c, "cpp", "/* z */", .comment); has(c, "c++", "0x1F", .number); has(c, "c", "return", .keyword)
        let j = "@Override\npublic class Foo extends Bar { private final String s = \"a\"; }"
        has(j, "java", "@Override", .attribute); has(j, "java", "public", .keyword); has(j, "java", "Foo", .type); has(j, "java", "\"a\"", .string)
        has("val x = listOf(1)\nfun go() = Unit", "kotlin", "fun", .keyword)
        has("public async Task Run() { var n = 5; }", "csharp", "async", .keyword)
        has("public async Task Run() { var n = 5; }", "cs", "Task", .type)
    }

    @Test func yaml() {
        let c = "# conf\nname: jot\nitems:\n  - key: \"v\"\n  - 12\nflag: true\nurl: http://x.y # c"
        has(c, "yaml", "# conf", .comment); has(c, "yml", "name", .attribute); has(c, "yaml", "items", .attribute); has(c, "yaml", "key", .attribute)
        has(c, "yaml", "\"v\"", .string); has(c, "yaml", "12", .number); has(c, "yaml", "true", .keyword); has(c, "yaml", "# c", .comment)
        #expect(!toks(c, "yaml").contains { $0.0.hasPrefix("//") })     // URL ไม่ถูกจับเป็น comment
    }

    @Test func markdownLang() {
        let c = "# Title\n> quote\n- item with `code` and [link](http://x.y)\n```\nraw\n```\n**bold** text"
        has(c, "markdown", "# Title", .keyword); has(c, "md", "> quote", .comment); has(c, "md", "`code`", .string); has(c, "md", "[link]", .function)
        has(c, "md", "**bold**", .attribute)
    }

    @Test func unknownAndPlainLanguages() {
        // ไม่ระบุ/ข้อความธรรมดา = ไม่ระบายสีเลย
        for l in ["", "text", "txt", "plain", "plaintext"] { #expect(SyntaxHighlighter.tokens(for: "if x // 'no'", language: l).isEmpty, Comment(rawValue: l)) }
        // ภาษาที่ไม่รู้จัก: ระบายแค่ string/number/comment
        let c = "local x = \"s\" -- no\n// yes\nprint(42)"
        let t = toks(c, "lua")
        #expect(t.contains { $0.0 == "\"s\"" && $0.1 == .string })
        #expect(t.contains { $0.0 == "42" && $0.1 == .number })
        #expect(t.contains { $0.0 == "// yes" && $0.1 == .comment })
        #expect(!t.contains { $0.1 == .keyword })
    }

    @Test func infoStringExtrasAndCase() {
        #expect(SyntaxHighlighter.canonical("Swift") == "swift")
        #expect(SyntaxHighlighter.canonical("python title=a.py") == "python")
        #expect(SyntaxHighlighter.canonical("js {1,3}") == "javascript")
        #expect(SyntaxHighlighter.canonical("PY") == "python")
        #expect(SyntaxHighlighter.canonical("zzz") == "generic")
    }

    @Test func runsCoverTextExactlyWithoutOverlap() {
        for (lang, code) in [("swift", "let a = \"ก ข\" // ไทย\nfunc f() {}"), ("html", "<p class=\"a\">ไทย 😀</p>"), ("bash", "echo \"😀\" # x"), ("css", "a { color: red }")] {
            let runs = SyntaxHighlighter.runs(for: code, language: lang)
            var pos = 0
            for r in runs { #expect(r.range.location == pos, Comment(rawValue: lang)); pos = NSMaxRange(r.range) }
            #expect(pos == (code as NSString).length)
        }
    }

    @Test func softBreakSeparatesLines() {
        // กล่องโค้ดใน storage ใช้ U+2028 เป็นตัวคั่นบรรทัด: comment บรรทัดเดียวต้องจบที่ตัวคั่น
        let code = "// a\u{2028}let x = 1"
        let t = toks(code, "swift")
        #expect(t.contains { $0.0 == "// a" && $0.1 == .comment })
        #expect(t.contains { $0.0 == "let" && $0.1 == .keyword })
    }

    @Test func thousandLinesIsFast() {
        let block = "import Foundation\nstruct Item: Codable { let id: Int; var name = \"x\" } // c\nfunc load(_ n: Int) -> [Item] { return (0..<n).map { Item(id: $0) } }\n"
        let code = String(repeating: block, count: 340)           // ~1000 บรรทัด
        let start = Date()
        let t = SyntaxHighlighter.tokens(for: code, language: "swift")
        let dt = Date().timeIntervalSince(start)
        #expect(t.count > 5000)
        #expect(dt < 1.0, Comment(rawValue: "\(dt)s"))          // build แบบ debug; release เร็วกว่ามาก
    }

    @Test func paletteContrastOnCodeBackground() {
        for k in TokenKind.allCases {
            let h = Palette.syntaxHex(k)
            let need = k == .comment ? 3.8 : 4.5
            #expect(Palette.contrast(h.light, Palette.codeBackgroundHex.light) >= need, Comment(rawValue: "light \(k)"))
            #expect(Palette.contrast(h.dark, Palette.codeBackgroundHex.dark) >= need, Comment(rawValue: "dark \(k)"))
        }
        // สีโค้ดต่างจากพื้นกระดาษพอเห็นชัด และเป็นเทาอมเหลือง (R >= G >= B)
        let c = Palette.codeBackgroundHex
        #expect(c.light != Palette.paperHex.light && c.dark != Palette.paperHex.dark)
        #expect(Palette.contrast(c.dark, Palette.paperHex.dark) >= 1.1)
        let r = (c.light >> 16) & 0xFF, g = (c.light >> 8) & 0xFF, b = c.light & 0xFF
        #expect(r >= g && g > b && r - b < 40)
    }

    @Test func tokenColorsAreDistinct() {
        let all = TokenKind.allCases.map { Palette.syntaxHex($0).light }
        #expect(Set(all).count == all.count)
        let dark = TokenKind.allCases.map { Palette.syntaxHex($0).dark }
        #expect(Set(dark).count == dark.count)
    }
}
