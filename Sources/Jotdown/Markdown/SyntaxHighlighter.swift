import Foundation

/// ชนิดของ token ที่ระบายสีในกล่องโค้ด (เป็นแค่ข้อมูลการแสดงผล ไม่เกี่ยวกับ markdown ที่บันทึก)
enum TokenKind: Int, CaseIterable {
    case keyword, string, number, comment, type, function, attribute
}

struct SyntaxToken: Equatable {
    var range: NSRange          // ช่วง UTF-16 ในข้อความที่ส่งเข้ามา
    var kind: TokenKind
}

/// tokenizer แบบเบา (ฟังก์ชันล้วน ไม่มี dependency) สำหรับระบายสีโค้ดตามภาษาจาก info string ของ fence
/// สแกนครั้งเดียวแบบ O(n) บน UTF-16; ตัวคั่นบรรทัดในกล่องโค้ดของเราคือ U+2028 (soft break) หรือ "\n"
enum SyntaxHighlighter {
    // MARK: - ภาษา
    /// ภาษาที่เลือกได้ในเมนู: (ชื่อที่แสดง, ค่า info string)
    static let menuLanguages: [(title: String, id: String)] = [
        ("Swift", "swift"), ("Python", "python"), ("JavaScript", "javascript"), ("TypeScript", "typescript"),
        ("JSON", "json"), ("Bash", "bash"), ("HTML", "html"), ("XML", "xml"), ("CSS", "css"), ("SQL", "sql"),
        ("Go", "go"), ("Rust", "rust"), ("C", "c"), ("C++", "cpp"), ("Java", "java"), ("Kotlin", "kotlin"),
        ("C#", "csharp"), ("YAML", "yaml"), ("Markdown", "markdown"),
    ]

    private static let aliases: [String: String] = [
        "py": "python", "python3": "python", "py3": "python",
        "js": "javascript", "jsx": "javascript", "mjs": "javascript", "cjs": "javascript", "node": "javascript",
        "ts": "typescript", "tsx": "typescript",
        "jsonc": "json", "json5": "json",
        "sh": "bash", "zsh": "bash", "shell": "bash", "shellscript": "bash", "console": "bash", "fish": "bash",
        "htm": "html", "xhtml": "html", "vue": "html",
        "svg": "xml", "plist": "xml", "xsd": "xml", "xsl": "xml", "rss": "xml",
        "golang": "go", "rs": "rust",
        "h": "c", "cc": "cpp", "cxx": "cpp", "hpp": "cpp", "c++": "cpp", "hh": "cpp",
        "kt": "kotlin", "kts": "kotlin", "cs": "csharp", "c#": "csharp",
        "yml": "yaml", "md": "markdown", "mdx": "markdown",
        "postgres": "sql", "postgresql": "sql", "mysql": "sql", "sqlite": "sql",
        "scss": "css", "less": "css",
    ]
    private static let plain: Set<String> = ["", "text", "txt", "plain", "plaintext", "none", "output", "log"]

    /// ชื่อภาษามาตรฐานจาก info string (nil = ข้อความธรรมดา ไม่ระบายสี); ภาษาที่ไม่รู้จักแต่มีชื่อ = "generic"
    static func canonical(_ info: String) -> String? {
        // info string อาจมี attribute ต่อท้าย เช่น "swift {1,3}" / "python title=x"
        let first = info.split(whereSeparator: { $0 == " " || $0 == "\t" || $0 == "{" }).first.map(String.init) ?? ""
        let l = first.lowercased()
        if plain.contains(l) { return nil }
        if let a = aliases[l] { return a }
        if known.contains(l) { return l }
        return "generic"
    }
    private static let known: Set<String> = ["swift", "python", "javascript", "typescript", "json", "bash", "html", "xml", "css", "sql", "go", "rust", "c", "cpp", "java", "kotlin", "csharp", "yaml", "markdown"]

    // MARK: - ตัวเข้าใช้
    static func tokens(for text: String, language: String) -> [SyntaxToken] {
        guard let lang = canonical(language), !text.isEmpty else { return [] }
        let u = Array(text.utf16)
        var out: [SyntaxToken] = []
        switch lang {
        case "html", "xml": scanMarkup(u, &out)
        case "css": scanCSS(u, &out)
        case "markdown": scanMarkdown(u, &out)
        case "bash": scanBash(u, &out)
        default: scanGeneric(u, config(lang), &out)
        }
        return out
    }

    /// ตัด token เป็นช่วงต่อเนื่องครอบคลุมข้อความทั้งหมด (kind = nil คือข้อความปกติ) ใช้ตอนใส่สี
    static func runs(for text: String, language: String) -> [(range: NSRange, kind: TokenKind?)] {
        let len = (text as NSString).length
        var out: [(NSRange, TokenKind?)] = []
        var pos = 0
        for t in tokens(for: text, language: language).sorted(by: { $0.range.location < $1.range.location }) {
            guard t.range.location >= pos, t.range.length > 0 else { continue }
            if t.range.location > pos { out.append((NSRange(location: pos, length: t.range.location - pos), nil)) }
            out.append((t.range, t.kind))
            pos = NSMaxRange(t.range)
        }
        if pos < len { out.append((NSRange(location: pos, length: len - pos), nil)) }
        return out
    }

    // MARK: - ตัวช่วยอักขระ
    @inline(__always) private static func isNewline(_ c: UInt16) -> Bool { c == 0x0A || c == 0x2028 || c == 0x0D }
    @inline(__always) private static func isSpace(_ c: UInt16) -> Bool { c == 0x20 || c == 0x09 || isNewline(c) }
    @inline(__always) private static func isDigit(_ c: UInt16) -> Bool { c >= 0x30 && c <= 0x39 }
    @inline(__always) private static func isUpper(_ c: UInt16) -> Bool { c >= 0x41 && c <= 0x5A }
    @inline(__always) private static func isLower(_ c: UInt16) -> Bool { c >= 0x61 && c <= 0x7A }
    @inline(__always) private static func isIdentStart(_ c: UInt16) -> Bool { isUpper(c) || isLower(c) || c == 0x5F || (c >= 0x80 && c != 0x2028 && c != 0x2029 && c != 0xA0) }
    @inline(__always) private static func isIdentChar(_ c: UInt16) -> Bool { isIdentStart(c) || isDigit(c) }
    @inline(__always) private static func isHex(_ c: UInt16) -> Bool { isDigit(c) || (c >= 0x41 && c <= 0x46) || (c >= 0x61 && c <= 0x66) }
    private static func str(_ u: [UInt16], _ a: Int, _ b: Int) -> String { String(decoding: u[a..<b], as: UTF16.self) }
    private static func matches(_ u: [UInt16], _ i: Int, _ p: [UInt16]) -> Bool {
        guard !p.isEmpty, i + p.count <= u.count else { return false }
        for k in 0..<p.count where u[i + k] != p[k] { return false }
        return true
    }
    private static func a(_ s: String) -> [UInt16] { Array(s.utf16) }

    /// จบ token ตัวเลข: รองรับ 0x1F, 1_000, 3.14, 1e-5, 10px (ต่อท้ายตัวอักษร = หน่วย/ชนิด)
    private static func scanNumber(_ u: [UInt16], _ start: Int) -> Int {
        var i = start
        if u[i] == 0x30, i + 1 < u.count, [0x78, 0x58, 0x62, 0x42, 0x6F, 0x4F].contains(u[i + 1]) {
            i += 2
            while i < u.count, isHex(u[i]) || u[i] == 0x5F { i += 1 }
            return i
        }
        while i < u.count, isDigit(u[i]) || u[i] == 0x5F { i += 1 }
        if i + 1 < u.count, u[i] == 0x2E, isDigit(u[i + 1]) {
            i += 1
            while i < u.count, isDigit(u[i]) || u[i] == 0x5F { i += 1 }
        }
        if i < u.count, u[i] == 0x65 || u[i] == 0x45 {
            var j = i + 1
            if j < u.count, u[j] == 0x2B || u[j] == 0x2D { j += 1 }
            if j < u.count, isDigit(u[j]) { while j < u.count, isDigit(u[j]) { j += 1 }; i = j }
        }
        while i < u.count, isIdentChar(u[i]) && u[i] != 0x5F || u[i] == 0x25 { i += 1 }    // หน่วย/ตัวต่อท้าย (f, u32, px, %)
        return i
    }

    /// อ่านสตริงที่เริ่ม ณ `start` (เครื่องหมายคำพูด `q`) ถึงตัวปิด; escape ด้วย `\`; ไม่ข้ามบรรทัดเว้นแต่ `multiline`
    private static func scanString(_ u: [UInt16], _ start: Int, quote q: UInt16, multiline: Bool, escapes: Bool = true) -> Int {
        var i = start + 1
        while i < u.count {
            let c = u[i]
            if escapes, c == 0x5C { i += 2; continue }
            if c == q { return i + 1 }
            if !multiline, isNewline(c) { return i }
            i += 1
        }
        return u.count
    }

    // MARK: - ตั้งค่าของภาษาแบบ C/Python/JS ฯลฯ
    struct Config {
        var keywords: Set<String>
        var types: Set<String> = []
        var specials: Set<String> = []          // self / this / super: แสดงเป็นตัวแปรพิเศษ
        var lineComments: [[UInt16]] = []
        var blockComments: [([UInt16], [UInt16])] = []
        var quotes: [UInt16] = [0x22, 0x27]
        var charLiterals = false                // ' เป็นตัวอักษรเดี่ยว (C/Java/Rust ...) ไม่ใช่สตริง
        var tripleQuotes = false                // """ ... """ / ''' ... '''
        var backtickStrings = false
        var stringPrefixes = false              // f"..." r'...' b"..." (Python)
        var caseInsensitive = false
        var capitalIsType = true
        var atAttributes = false                // @name
        var dollarIdents = false                // $name เป็นส่วนของ identifier (JS) หรือ attribute (shell/PHP)
        var hashDirectives = false              // #include / #if (C, Swift)
        var rustMacros = false                  // name!( ...
        var jsonKeys = false                    // "key": ...
        var yaml = false
        var capitalCallIsFunction = false       // Go: Run( = เมธอด ไม่ใช่ชนิด
    }

    private static func words(_ s: String) -> Set<String> { Set(s.split(whereSeparator: { $0 == " " || $0 == "\n" }).map(String.init)) }

    private static var configs: [String: Config] = [:]
    private static let configLock = NSLock()

    static func config(_ lang: String) -> Config {
        configLock.lock(); defer { configLock.unlock() }
        if let c = configs[lang] { return c }
        let c = makeConfig(lang)
        configs[lang] = c
        return c
    }

    private static let cLike: (line: [[UInt16]], block: [([UInt16], [UInt16])]) = ([a("//")], [(a("/*"), a("*/"))])

    private static func makeConfig(_ lang: String) -> Config {
        switch lang {
        case "swift":
            var c = Config(keywords: words("""
                actor any as associatedtype async await break case catch class continue convenience default defer deinit do dynamic else enum extension fallthrough
                false fileprivate final for func get guard if import in indirect infix init inout internal is lazy let mutating nil nonisolated nonmutating open operator
                optional override postfix precedencegroup prefix private protocol public repeat required rethrows return set some static struct subscript super switch
                throw throws true try typealias unowned var weak where while willSet didSet
                """), specials: words("self Self super"))
            (c.lineComments, c.blockComments) = ([a("//")], [(a("/*"), a("*/"))])
            c.quotes = [0x22]; c.charLiterals = false; c.tripleQuotes = true; c.atAttributes = true; c.hashDirectives = true
            return c
        case "python":
            var c = Config(keywords: words("""
                and as assert async await break class continue def del elif else except finally for from global if import in is lambda nonlocal not or pass raise return try
                while with yield None True False match case
                """), types: words("int str float bool list dict set tuple bytes object type"), specials: words("self cls"))
            c.lineComments = [a("#")]; c.tripleQuotes = true; c.stringPrefixes = true; c.atAttributes = true
            return c
        case "javascript", "typescript":
            var kw = """
                async await break case catch class const continue debugger default delete do else export extends false finally for from function if import in instanceof let new
                null of return static super switch throw true try typeof undefined var void while with yield get set
                """
            if lang == "typescript" { kw += " abstract as declare enum implements interface keyof namespace private protected public readonly type is satisfies override" }
            var c = Config(keywords: words(kw), types: lang == "typescript" ? words("string number boolean any void never unknown object symbol bigint") : [], specials: words("this super"))
            (c.lineComments, c.blockComments) = ([a("//")], [(a("/*"), a("*/"))])
            c.backtickStrings = true; c.dollarIdents = true; c.atAttributes = lang == "typescript"
            return c
        case "json":
            var c = Config(keywords: words("true false null"))
            c.quotes = [0x22]; c.jsonKeys = true; c.capitalIsType = false
            (c.lineComments, c.blockComments) = ([a("//")], [(a("/*"), a("*/"))])
            return c
        case "yaml":
            var c = Config(keywords: words("true false null yes no on off True False Null ~"))
            c.lineComments = [a("#")]; c.yaml = true; c.capitalIsType = false
            return c
        case "sql":
            var c = Config(keywords: words("""
                select from where and or not in is null like between exists insert into values update set delete create alter drop table view index database schema
                join inner left right full outer cross on using group by order having limit offset union all distinct as case when then else end primary key foreign
                references default unique constraint check add column cascade if begin commit rollback transaction with recursive returning asc desc true false
                grant revoke to truncate explain analyze over partition fetch next rows only
                """), types: words("int integer bigint smallint tinyint serial bigserial varchar char text boolean bool date time timestamp timestamptz datetime decimal numeric float double real uuid json jsonb blob bytea"))
            c.lineComments = [a("--")]; c.blockComments = [(a("/*"), a("*/"))]; c.quotes = [0x27, 0x22]
            c.caseInsensitive = true; c.capitalIsType = false
            return c
        case "go":
            var c = Config(keywords: words("""
                break case chan const continue default defer else fallthrough for func go goto if import interface map package range return select struct switch type var
                true false nil iota
                """), types: words("int int8 int16 int32 int64 uint uint8 uint16 uint32 uint64 uintptr float32 float64 string bool byte rune error any complex128 complex64"))
            (c.lineComments, c.blockComments) = ([a("//")], [(a("/*"), a("*/"))])
            c.backtickStrings = true; c.charLiterals = true; c.quotes = [0x22]; c.capitalCallIsFunction = true
            return c
        case "rust":
            var c = Config(keywords: words("""
                as async await break const continue crate dyn else enum extern false fn for if impl in let loop match mod move mut pub ref return static struct super trait
                true type unsafe use where while union
                """), types: words("i8 i16 i32 i64 i128 isize u8 u16 u32 u64 u128 usize f32 f64 bool char str String Vec Option Result Box Self"), specials: words("self"))
            (c.lineComments, c.blockComments) = ([a("//")], [(a("/*"), a("*/"))])
            c.charLiterals = true; c.quotes = [0x22]; c.rustMacros = true; c.atAttributes = false; c.hashDirectives = true
            return c
        case "c", "cpp":
            var kw = "auto break case const continue default do else enum extern for goto if inline register return sizeof static struct switch typedef union volatile while NULL true false"
            if lang == "cpp" { kw += " alignas catch class constexpr const_cast decltype delete dynamic_cast explicit export final friend mutable namespace new noexcept nullptr operator override private protected public reinterpret_cast static_assert static_cast template this throw try typeid typename using virtual" }
            var c = Config(keywords: words(kw), types: words("int char short long float double void unsigned signed bool size_t int8_t int16_t int32_t int64_t uint8_t uint16_t uint32_t uint64_t string vector map"), specials: lang == "cpp" ? words("this") : [])
            (c.lineComments, c.blockComments) = ([a("//")], [(a("/*"), a("*/"))])
            c.charLiterals = true; c.quotes = [0x22]; c.hashDirectives = true
            return c
        case "java", "kotlin", "csharp":
            var kw: String
            switch lang {
            case "java": kw = "abstract assert break case catch class continue default do else enum extends final finally for if implements import instanceof interface native new package private protected public return static strictfp super switch synchronized this throw throws transient try volatile while true false null var record sealed permits"
            case "kotlin": kw = "as break class continue do else false for fun if in interface is null object package return super this throw true try typealias typeof val var when while by catch constructor delegate dynamic field file finally get import init param property receiver set setparam value where abstract actual annotation companion const crossinline data enum expect external final infix inline inner internal lateinit noinline open operator out override private protected public reified sealed suspend tailrec vararg"
            default: kw = "abstract as base bool break byte case catch char checked class const continue decimal default delegate do double else enum event explicit extern false finally fixed float for foreach goto if implicit in int interface internal is lock long namespace new null object operator out override params private protected public readonly ref return sbyte sealed short sizeof stackalloc static string struct switch this throw true try typeof uint ulong unchecked unsafe ushort using virtual void volatile while var async await record init get set yield"
            }
            var c = Config(keywords: words(kw), types: words("int long short byte char float double boolean void String Int Long Double Float Boolean Unit Any Nothing"), specials: words("this super"))
            (c.lineComments, c.blockComments) = ([a("//")], [(a("/*"), a("*/"))])
            c.charLiterals = true; c.quotes = [0x22]; c.atAttributes = true; c.tripleQuotes = lang == "kotlin"; c.hashDirectives = lang == "csharp"
            return c
        default:   // generic: ไม่รู้จักภาษา ระบายแค่ comment / string / number
            var c = Config(keywords: [])
            c.lineComments = [a("//"), a("#")]; c.blockComments = [(a("/*"), a("*/"))]; c.capitalIsType = false
            return c
        }
    }

    // MARK: - scanner กลาง
    private static func scanGeneric(_ u: [UInt16], _ cfg: Config, _ out: inout [SyntaxToken]) {
        let n = u.count
        var i = 0
        var lineStart = true          // ยังไม่เจออะไรที่ไม่ใช่ช่องว่างในบรรทัดนี้
        var prevWord = ""           // คำก่อนหน้า (ใช้แยก `def Foo(` ออกจาก `Foo(` ที่เป็น constructor)
        let defKeywords: Set<String> = ["func", "fn", "def", "fun", "function"]
        func add(_ s: Int, _ e: Int, _ k: TokenKind) { if e > s { out.append(SyntaxToken(range: NSRange(location: s, length: e - s), kind: k)) } }
        outer: while i < n {
            let c = u[i]
            if isNewline(c) { lineStart = true; i += 1; continue }
            if c == 0x20 || c == 0x09 { i += 1; continue }
            let wasLineStart = lineStart
            lineStart = false

            // YAML: คีย์ต้นบรรทัด  `key:` / `- key:`
            if cfg.yaml, wasLineStart || (i >= 2 && u[i - 1] == 0x20 && u[i - 2] == 0x2D) {
                var j = i
                if u[j] == 0x2D, j + 1 < n, u[j + 1] == 0x20 { j += 2; while j < n, u[j] == 0x20 { j += 1 } }
                let ks = j
                if j < n, u[j] != 0x23, u[j] != 0x22, u[j] != 0x27, !isNewline(u[j]) {
                    while j < n, !isNewline(u[j]), !(u[j] == 0x3A && (j + 1 >= n || u[j + 1] == 0x20 || isNewline(u[j + 1]))) { j += 1 }
                    if j < n, u[j] == 0x3A, j > ks {
                        var e = j; while e > ks, u[e - 1] == 0x20 { e -= 1 }
                        add(ks, e, .attribute)
                        i = j + 1; lineStart = false
                        continue
                    }
                }
            }
            // comment
            for p in cfg.lineComments where matches(u, i, p) {
                // `#` และ `--` ใน yaml/sql: ต้องอยู่ต้นบรรทัดหรือหลังช่องว่าง (ไม่ใช่ที่กลางคำ)
                if p.first == 0x23, i > 0, !isSpace(u[i - 1]), cfg.yaml { break }
                if p.first == 0x23, cfg.hashDirectives, wasLineStart { break }       // #include / #if ไม่ใช่ comment
                var e = i; while e < n, !isNewline(u[e]) { e += 1 }
                add(i, e, .comment); i = e; continue outer
            }
            for (open, close) in cfg.blockComments where matches(u, i, open) {
                var e = i + open.count
                while e < n, !matches(u, e, close) { e += 1 }
                e = min(n, e + close.count)
                add(i, e, .comment); i = e; continue outer
            }
            // directive
            if cfg.hashDirectives, c == 0x23, wasLineStart {
                var e = i + 1; while e < n, isIdentChar(u[e]) { e += 1 }
                if e > i + 1 { add(i, e, .attribute); i = e; continue }
            }
            // string
            if cfg.stringPrefixes, isIdentStart(c), i + 2 < n {
                // r"..." f'...' rb"..." : ตัวนำหน้า 1-2 ตัวติดเครื่องหมายคำพูด
                var j = i; while j < n, j - i < 3, isLower(u[j]) || isUpper(u[j]) { j += 1 }
                if j < n, j - i <= 2, u[j] == 0x22 || u[j] == 0x27, "rRbBfFuU".utf16.contains(u[i]) {
                    let e = scanQuoted(u, j, cfg)
                    add(i, e, .string); i = e; continue
                }
            }
            if c == 0x22 || c == 0x27 || (c == 0x60 && cfg.backtickStrings) {
                if c == 0x27, cfg.charLiterals {
                    if let e = charLiteralEnd(u, i) { add(i, e, .string); i = e; continue }
                    if cfg.rustMacros, i + 1 < n, isIdentStart(u[i + 1]) {          // lifetime 'a
                        var e = i + 1; while e < n, isIdentChar(u[e]) { e += 1 }
                        add(i, e, .attribute); i = e; continue
                    }
                    i += 1; continue
                }
                if cfg.quotes.contains(c) || c == 0x60 {
                    let e = scanQuoted(u, i, cfg)
                    var kind = TokenKind.string
                    if cfg.jsonKeys {
                        var j = e; while j < n, u[j] == 0x20 || u[j] == 0x09 { j += 1 }
                        if j < n, u[j] == 0x3A { kind = .attribute }
                    }
                    add(i, e, kind); i = e; continue
                }
            }
            // number
            if isDigit(c) || (c == 0x2E && i + 1 < n && isDigit(u[i + 1]) && (i == 0 || !isIdentChar(u[i - 1]))) {
                let e = scanNumber(u, c == 0x2E ? i + 1 : i)
                add(i, e, .number); i = e; continue
            }
            // @attribute
            if cfg.atAttributes, c == 0x40, i + 1 < n, isIdentStart(u[i + 1]) {
                var e = i + 1; while e < n, isIdentChar(u[e]) || u[e] == 0x2E { e += 1 }
                add(i, e, .attribute); i = e; continue
            }
            // identifier
            if isIdentStart(c) || (cfg.dollarIdents && c == 0x24) {
                var e = i + 1
                while e < n, isIdentChar(u[e]) || (cfg.dollarIdents && u[e] == 0x24) { e += 1 }
                var w = str(u, i, e)
                if cfg.caseInsensitive { w = w.lowercased() }
                var kind: TokenKind?
                if cfg.keywords.contains(w) { kind = .keyword }
                else if cfg.specials.contains(w) { kind = .attribute }
                else if cfg.types.contains(w) { kind = .type }
                else if cfg.capitalIsType, isUpper(u[i]), u[i..<e].contains(where: isLower),
                        !(e < n && u[e] == 0x28 && (cfg.capitalCallIsFunction || defKeywords.contains(prevWord))) { kind = .type }     // Foo / Foo(...) = ชนิด/constructor
                else if e < n, u[e] == 0x28 { kind = .function }
                else if cfg.rustMacros, e + 1 < n, u[e] == 0x21, u[e + 1] == 0x28 || u[e + 1] == 0x5B || u[e + 1] == 0x7B { kind = .function; e += 1 }
                if let kind { add(i, e, kind) }
                prevWord = w
                i = e; continue
            }
            // swift $0 / shorthand และสัญลักษณ์อื่น: ข้าม
            i += 1
        }
    }

    /// สตริงที่เริ่มด้วย `"`/`'`/`` ` `` พร้อมรองรับ triple quotes
    private static func scanQuoted(_ u: [UInt16], _ i: Int, _ cfg: Config) -> Int {
        let q = u[i]
        if cfg.tripleQuotes, i + 2 < u.count, u[i + 1] == q, u[i + 2] == q {
            var e = i + 3
            while e < u.count {
                if u[e] == 0x5C { e += 2; continue }
                if matches(u, e, [q, q, q]) { return e + 3 }
                e += 1
            }
            return u.count
        }
        return scanString(u, i, quote: q, multiline: q == 0x60)
    }

    /// 'x' หรือ '\n' หรือ '\u{1F600}' ที่ปิดภายในไม่กี่ตัวและไม่ข้ามบรรทัด (nil = ไม่ใช่ char literal)
    private static func charLiteralEnd(_ u: [UInt16], _ i: Int) -> Int? {
        var j = i + 1
        guard j < u.count else { return nil }
        if u[j] == 0x5C {                    // escape: '\n' '\u{1F600}' ถึง ' ภายใน 10 ตัว
            var steps = 0
            j += 2
            while j < u.count, steps < 10, !isNewline(u[j]) { if u[j] == 0x27 { return j + 1 }; j += 1; steps += 1 }
            return nil
        }
        guard !isNewline(u[j]), u[j] != 0x27 else { return nil }
        j += (0xD800...0xDBFF).contains(u[j]) ? 2 : 1       // ตัวอักษรเดียว (รวม surrogate pair)
        return j < u.count && u[j] == 0x27 ? j + 1 : nil
    }

    // MARK: - HTML / XML
    private static func scanMarkup(_ u: [UInt16], _ out: inout [SyntaxToken]) {
        let n = u.count
        var i = 0
        func add(_ s: Int, _ e: Int, _ k: TokenKind) { if e > s { out.append(SyntaxToken(range: NSRange(location: s, length: e - s), kind: k)) } }
        let open = a("<!--"), close = a("-->")
        while i < n {
            if matches(u, i, open) {
                var e = i + 4; while e < n, !matches(u, e, close) { e += 1 }
                e = min(n, e + 3); add(i, e, .comment); i = e; continue
            }
            guard u[i] == 0x3C, i + 1 < n else { i += 1; continue }
            var j = i + 1
            if u[j] == 0x2F || u[j] == 0x21 || u[j] == 0x3F { j += 1 }
            guard j < n, isIdentStart(u[j]) || (u[j] == 0x44 || u[j] == 0x64) else { i += 1; continue }
            // ชื่อแท็ก
            let ns = j
            while j < n, isIdentChar(u[j]) || u[j] == 0x2D || u[j] == 0x3A || u[j] == 0x2E { j += 1 }
            add(ns, j, .keyword)
            // attribute จนถึง >
            while j < n, u[j] != 0x3E {
                let c = u[j]
                if c == 0x22 || c == 0x27 { let e = scanString(u, j, quote: c, multiline: true, escapes: false); add(j, e, .string); j = e; continue }
                if isIdentStart(c) {
                    let s = j
                    while j < n, isIdentChar(u[j]) || u[j] == 0x2D || u[j] == 0x3A || u[j] == 0x40 || u[j] == 0x2E { j += 1 }
                    add(s, j, .attribute); continue
                }
                j += 1
            }
            i = j
        }
    }

    // MARK: - CSS
    private static func scanCSS(_ u: [UInt16], _ out: inout [SyntaxToken]) {
        let n = u.count
        var i = 0
        var depth = 0
        var inValue = false
        func add(_ s: Int, _ e: Int, _ k: TokenKind) { if e > s { out.append(SyntaxToken(range: NSRange(location: s, length: e - s), kind: k)) } }
        while i < n {
            let c = u[i]
            if matches(u, i, a("/*")) {
                var e = i + 2; while e < n, !matches(u, e, a("*/")) { e += 1 }
                e = min(n, e + 2); add(i, e, .comment); i = e; continue
            }
            if c == 0x22 || c == 0x27 { let e = scanString(u, i, quote: c, multiline: false); add(i, e, .string); i = e; continue }
            if c == 0x7B { depth += 1; inValue = false; i += 1; continue }
            if c == 0x7D { depth = max(0, depth - 1); inValue = false; i += 1; continue }
            if c == 0x3B { inValue = false; i += 1; continue }
            if c == 0x40, i + 1 < n, isIdentStart(u[i + 1]) {                // @media
                var e = i + 1; while e < n, isIdentChar(u[e]) || u[e] == 0x2D { e += 1 }
                add(i, e, .keyword); i = e; continue
            }
            if isDigit(c) || (c == 0x2E && i + 1 < n && isDigit(u[i + 1]) && inValue) {
                let e = scanNumber(u, c == 0x2E ? i + 1 : i); add(i, e, .number); i = e; continue
            }
            if c == 0x23 {
                var e = i + 1; while e < n, isHex(u[e]) { e += 1 }
                let len = e - i - 1
                if inValue, [3, 4, 6, 8].contains(len), !(e < n && isIdentChar(u[e])) { add(i, e, .number); i = e; continue }
                e = i + 1; while e < n, isIdentChar(u[e]) || u[e] == 0x2D { e += 1 }
                if !inValue { add(i, e, .type) }
                i = max(e, i + 1); continue
            }
            if c == 0x2E, !inValue, i + 1 < n, isIdentStart(u[i + 1]) {      // .class
                var e = i + 1; while e < n, isIdentChar(u[e]) || u[e] == 0x2D { e += 1 }
                add(i, e, .type); i = e; continue
            }
            if isIdentStart(c) || (c == 0x2D && i + 1 < n && (isIdentStart(u[i + 1]) || u[i + 1] == 0x2D)) {
                var e = i + 1; while e < n, isIdentChar(u[e]) || u[e] == 0x2D { e += 1 }
                var j = e; while j < n, u[j] == 0x20 || u[j] == 0x09 { j += 1 }
                if e < n, u[e] == 0x28 { add(i, e, .function); i = e; continue }
                if !inValue, depth > 0, j < n, u[j] == 0x3A, !(j + 1 < n && u[j + 1] == 0x3A) {
                    // ภายใน {} ตามด้วย ':' = ชื่อ property (selector แบบ a:hover ซ้อนไม่ได้ในเงื่อนไขนี้ที่ depth 1; ยอมรับข้อจำกัด)
                    add(i, e, .attribute); i = j + 1; inValue = true; continue
                }
                i = e; continue
            }
            i += 1
        }
    }

    // MARK: - Markdown
    private static func scanMarkdown(_ u: [UInt16], _ out: inout [SyntaxToken]) {
        let n = u.count
        var i = 0
        func add(_ s: Int, _ e: Int, _ k: TokenKind) { if e > s { out.append(SyntaxToken(range: NSRange(location: s, length: e - s), kind: k)) } }
        var inFence = false
        while i < n {
            var e = i; while e < n, !isNewline(u[e]) { e += 1 }      // บรรทัด [i, e)
            var s = i; while s < e, u[s] == 0x20 { s += 1 }
            if s + 2 < e, matches(u, s, a("```")) || matches(u, s, a("~~~")) { inFence.toggle(); add(s, e, .comment) }
            else if inFence { add(i, e, .string) }
            else if s < e, u[s] == 0x23 { var h = s; while h < e, u[h] == 0x23 { h += 1 }; if h < e, u[h] == 0x20 { add(s, e, .keyword) } }
            else if s < e, u[s] == 0x3E { add(s, e, .comment) }
            else {
                var m = s
                if m < e, u[m] == 0x2D || u[m] == 0x2A || u[m] == 0x2B, m + 1 < e, u[m + 1] == 0x20 { add(m, m + 1, .attribute); m += 2 }
                else { var d = m; while d < e, isDigit(u[d]) { d += 1 }; if d > m, d < e, u[d] == 0x2E || u[d] == 0x29, d + 1 < e, u[d + 1] == 0x20 { add(m, d + 1, .attribute); m = d + 2 } }
                scanMarkdownInline(u, m, e, &out)
            }
            i = e + 1
        }
    }

    private static func scanMarkdownInline(_ u: [UInt16], _ from: Int, _ to: Int, _ out: inout [SyntaxToken]) {
        var i = from
        func add(_ s: Int, _ e: Int, _ k: TokenKind) { if e > s { out.append(SyntaxToken(range: NSRange(location: s, length: e - s), kind: k)) } }
        while i < to {
            let c = u[i]
            if c == 0x60 {                                           // `code`
                var e = i + 1; while e < to, u[e] != 0x60 { e += 1 }
                if e < to { add(i, e + 1, .string); i = e + 1; continue }
            } else if c == 0x5B {                                    // [text](url)
                var e = i + 1; while e < to, u[e] != 0x5D { e += 1 }
                if e + 1 < to, u[e + 1] == 0x28 {
                    var f = e + 2; while f < to, u[f] != 0x29 { f += 1 }
                    if f < to { add(i, e + 1, .function); add(e + 1, f + 1, .type); i = f + 1; continue }
                }
            } else if c == 0x2A || c == 0x5F {                       // **bold** / *italic*
                var m = i; while m < to, u[m] == c { m += 1 }
                let marks = m - i
                if marks <= 3, m < to, u[m] != 0x20 {
                    var e = m
                    while e < to {
                        if u[e] == c { var k = e; while k < to, u[k] == c { k += 1 }; if k - e >= marks { add(i, k, .attribute); i = k; break } else { e = k; continue } }
                        e += 1
                    }
                    if e < to { continue }
                }
                i = m; continue
            }
            i += 1
        }
    }

    // MARK: - Bash
    private static let bashKeywords = words("if then else elif fi for while until do done case esac in function select time return exit break continue local export readonly declare unset source alias set shift trap true false")

    private static func scanBash(_ u: [UInt16], _ out: inout [SyntaxToken]) {
        let n = u.count
        var i = 0
        var cmdStart = true
        func add(_ s: Int, _ e: Int, _ k: TokenKind) { if e > s { out.append(SyntaxToken(range: NSRange(location: s, length: e - s), kind: k)) } }
        let lead = words("if then else elif while until do for case select time")   // ตามด้วยคำสั่งอีกที
        while i < n {
            let c = u[i]
            if isNewline(c) { cmdStart = true; i += 1; continue }
            if c == 0x20 || c == 0x09 { i += 1; continue }
            if c == 0x23, i == 0 || isSpace(u[i - 1]) || u[i - 1] == 0x3B || u[i - 1] == 0x28 {       // # comment
                var e = i; while e < n, !isNewline(u[e]) { e += 1 }
                add(i, e, .comment); i = e; continue
            }
            if c == 0x3B || c == 0x7C || c == 0x26 || c == 0x28 || c == 0x7B || c == 0x60 { cmdStart = true; i += 1; continue }
            if c == 0x22 { let e = scanString(u, i, quote: c, multiline: true); add(i, e, .string); cmdStart = false; i = e; continue }
            if c == 0x27 { let e = scanString(u, i, quote: c, multiline: true, escapes: false); add(i, e, .string); cmdStart = false; i = e; continue }
            if c == 0x24 {                                                          // $VAR ${VAR} $(…) $1 $@
                var e = i + 1
                if e < n, u[e] == 0x7B { while e < n, u[e] != 0x7D, !isNewline(u[e]) { e += 1 }; e = min(n, e + 1) }
                else if e < n, isIdentStart(u[e]) { while e < n, isIdentChar(u[e]) { e += 1 } }
                else if e < n, isDigit(u[e]) || [0x40, 0x2A, 0x3F, 0x23, 0x21, 0x24].contains(u[e]) { e += 1 }
                add(i, e, .attribute); cmdStart = false; i = max(e, i + 1); continue
            }
            if isDigit(c), !cmdStart { let e = scanNumber(u, i); add(i, e, .number); i = e; continue }
            // คำ: อ่านจนถึงช่องว่างหรือตัวคั่น
            var e = i
            while e < n, !isSpace(u[e]), ![0x3B, 0x7C, 0x26, 0x28, 0x29, 0x3C, 0x3E, 0x22, 0x27, 0x24, 0x60, 0x7D].contains(u[e]) { e += 1 }
            if e == i { i += 1; continue }
            let w = str(u, i, e)
            if bashKeywords.contains(w) { add(i, e, .keyword); cmdStart = lead.contains(w); i = e; continue }
            if cmdStart {
                if let eq = w.firstIndex(of: "="), eq != w.startIndex {                 // VAR=value
                    let l = w.utf16.distance(from: w.utf16.startIndex, to: eq.samePosition(in: w.utf16) ?? w.utf16.startIndex)
                    add(i, i + l, .attribute); i += l + 1
                    if i < n, ![0x22, 0x27, 0x24].contains(u[i]) { while i < n, !isSpace(u[i]), ![0x3B, 0x7C, 0x26, 0x29].contains(u[i]) { i += 1 } }
                    continue
                }
                add(i, e, .function); cmdStart = false
            } else if w.hasPrefix("-"), w.count > 1 {
                add(i, e, .type)                                                         // --flag / -f
            }
            i = e
        }
    }
}
