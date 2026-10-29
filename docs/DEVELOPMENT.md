# Jotdown — บันทึกสำหรับนักพัฒนา (ภาษาไทย)

โปรแกรมแก้ไข Markdown บน macOS ที่เบาและเร็ว แก้ไขแบบ Notion: ไม่เห็นเครื่องหมาย Markdown เลย อ่าน/เขียนไฟล์ `.md` ธรรมดา UI ภาษาไทย

## build / เทสต์
- `swift build` — build ปกติ
- `./test.sh` — รันเทสต์ (swift-testing) กรองได้ด้วย `./test.sh --filter <ชื่อ>` (บนเครื่องที่มีแต่ Command Line Tools ห้ามใช้ `swift test` ตรง ๆ)
- `./build-app.sh` — สร้าง `build/Jotdown.app` และ `build/Jotdown.zip` (`SKIP_ZIP=1` ข้าม zip) เซ็นแบบ ad-hoc จนกว่าจะรัน `./make-signing-cert.sh`
- snapshot ของ UI ไปที่ `build/snapshots/` (เปลี่ยนด้วย `APP_SNAPSHOT_DIR`)
- ฟอนต์: ค้นหาจาก `$JOTDOWN_FONTS_DIR` → `Jotdown.app/Contents/Resources/Fonts` → `Resources/Fonts` ของ repo (ไลเซนส์ OFL อยู่ใน `Resources/Fonts/OFL.txt`)
- ไอคอนแอป: `Jotdown.iconset/` (ออกแบบโดย Euw) → `scripts/fit-icon.swift` ปรับขนาดให้เท่าไอคอน Mac อื่นตอน build

## โครงโค้ด
- `Sources/Jotdown/App/` main, AppDelegate, เมนูภาษาไทย
- `Sources/Jotdown/Document/` `JotdownDocument` (NSDocument, autosave in place), `Debouncer`, `JotdownDocumentController`
- `Sources/Jotdown/Editor/` `EditorTextView` (TextKit 1), `EditorViewController`
- `Sources/Jotdown/Markdown/` `Attributes` (`BlockKind`, `.jotBlock`), `MarkdownParser`, `MarkdownSerializer` (ฟังก์ชันล้วน)
- `Sources/Jotdown/Style/` `Fonts`, `Theme`
- `Tests/JotdownTests/` เทสต์ + `Fixtures/`

## ฟีเจอร์

### ขั้น 1 — โครงแอป (2026-10-29)
- เปิด/บันทึกไฟล์ `.md` (UTF-8, อ่านได้ทั้งมี/ไม่มี BOM และ CRLF, เขียนเป็น LF) — `DocumentTests`
- บันทึกอัตโนมัติ: debounce 1 วินาทีหลังแก้ครั้งสุดท้าย + ทันทีเมื่อปิดหน้าต่าง/แอปเสียโฟกัส/ปิดแอป; ไฟล์ที่เนื้อหาไม่ต่างจากเดิมจะไม่ถูกเขียนใหม่ (ไฟล์ที่ไม่อยู่ในรูปแบบมาตรฐานจะไม่ถูกจัดรูปใหม่จนกว่าจะมีการแก้) — `DebouncerTests`, `DocumentTests`
- เอกสารไม่มีชื่อเก็บเป็นฉบับร่างโดยระบบ, หน้าต่างแท็บ, เวอร์ชัน, กู้คืนเมื่อเปิดแอปใหม่ (`autosavesInPlace`)
- ไฟล์ถูกแก้จากภายนอกและเราไม่มีการแก้ค้าง → โหลดใหม่เงียบ ๆ คงตำแหน่งเคอร์เซอร์/scroll
- ตัวแก้ไข: หัวข้อ H1–H6 + ย่อหน้า, คอลัมน์สูงสุด 720pt กลางหน้าต่าง, วางเป็นข้อความธรรมดา, Enter ท้ายหัวข้อ = ย่อหน้าใหม่ — `MarkdownTests`, `EditorTests`, `EditorSnapshotTests`, `FontsTests`
- บล็อก/inline ที่ยังไม่รองรับ (ลิสต์ โค้ด ตัวหนา ตาราง ฯลฯ) ถูกเก็บเป็นข้อความดิบในย่อหน้า ไม่เสียเนื้อหา (ขั้น 2 จะแปลงเป็นบล็อกจริง)
- soft break ในย่อหน้าเก็บเป็น U+2028 ใน text storage แล้วเขียนกลับเป็น `\n`

## ข้อจำกัดที่รู้
- รายการในเมนูรูปแบบเพิ่มแล้วในขั้น 2 ด้านล่าง

### ขั้น 2 — ตัวแก้ไขแบบ Notion เต็มรูปแบบ (2026-10-29)
- โมเดล: 1 ย่อหน้าใน text storage = 1 บล็อก ชนิดเก็บใน `.jotBlock` (`BlockKind`: ย่อหน้า, หัวข้อ 1–6, bullet/ตัวเลข/เช็กลิสต์ + ระดับ, quote, กล่องโค้ด+ภาษา, เส้นคั่น, `raw`) inline เก็บใน `.jotInline` (หนา/เอียง/ขีดฆ่า/โค้ด/ดิบ) และ `.jotLink` — ข้อความใน storage ไม่มีเครื่องหมาย markdown เลย; ฟอนต์/สีคำนวณจาก `Theme.attributes` ผ่าน `restyleParagraphs` (เฉพาะย่อหน้าที่แก้ ไม่ re-parse ทั้งเอกสาร)
- ตารางและรูปภาพ (ขั้น 3–4) ยังเก็บเป็นข้อความดิบ (`raw`) ไม่เสียเนื้อหา
- `InlineWriter`: escape อักขระพิเศษ, ย้ายช่องว่างออกนอก `**`, ซ้อน style แบบ interval — `InlineTests`
- วาดเอง (`EditorLayoutManager`): bullet/เลข/checkbox (คลิกได้), เส้น quote, พื้นกล่องโค้ด/ข้อความดิบ, เส้นคั่น, พื้นโค้ดในบรรทัด
- คีย์ลัด/เมนูรูปแบบ: ⌘B ⌘I ⇧⌘X ⌘E ⌘K ⌥⌘0–6 ⇧⌘8/7/9 ⌘Enter ⇧⌘. ⌥⌘C Tab/⇧Tab (⌘E ค้นหาจากส่วนที่เลือกย้ายเป็น ⌥⌘E) — `EditorTests` (blockMenuActions, toggleInline*, menuHasAllFormatItems, menuStateFollowsCaret)
- พิมพ์ลัด: `# ` `- ` `1. ` `[] ` `> ` ``` ``` `---` และ inline `**` `*` `_` `` ` `` `~~`; ⌘Z ครั้งเดียวคืนข้อความที่พิมพ์ — `blockShortcuts`, `inlineShortcuts`, `shortcut*Undo*`
- Enter/Backspace/Tab ในลิสต์ quote กล่องโค้ด — `enterInListsAndExit`, `nestedWithTabAndBacktab`, `backspaceAtStartBecomesParagraph`, `fencedCodeBlock`
- วาง: markdown → โครงสร้าง, HTML → หนา/เอียง/ลิงก์/หัวข้อ/ลิสต์ (`HTMLImporter`), URL ทับข้อความ = ลิงก์; คัดลอก = markdown + RTF — `pasteMarkdown`, `pasteHTML`, `pasteURLOverSelectionMakesLink`, `copyPutsMarkdownAndRTF`
- แท็บใหม่ (⌘T): `AppDelegate.newWindowForTab:`; ปิดหน้าต่างไม่ถาม/โหลดใหม่จากภายนอก — `FlowTests`
- ความเร็ว: `Jot --bench ไฟล์.md` (ไฟล์ 9,000 บรรทัด parse+build ~140ms ใน release); `largeDocumentIsFast`
- snapshot: `editor-all-*`, `editor-all-tall-*`, `link-sheet-aqua.png` ใน `build/snapshots/`

### ขั้น 3 — รูปภาพ (2026-10-29)
- `![alt](src "title")` ทั้งบล็อกและในบรรทัด แสดงเป็นรูปจริงด้วย `NSTextAttachment` (`ImageAttachment`/`ImageCell` ใน `Editor/ImageSupport.swift`) ใน storage เป็นอักขระ U+FFFC 1 ตัว + attribute `.jotImage` (src/alt/title) เขียนกลับเหมือนเดิม (src มีช่องว่างใช้ `<...>`) — `ImageTests.roundTrips`, `storageHoldsAttachment`
- โหลดเบื้องหลัง + cache ในหน่วยความจำ, ไฟล์ในเครื่อง downsample ด้วย ImageIO, URL เว็บผ่าน URLSession; ระหว่างโหลด/โหลดไม่ได้ = กล่องจางแสดงข้อความ ไม่ crash — `localImageIsDownsampledInBackground`, `remoteImageUsesSession`, `missingImageDoesNotCrashOrLoseContent`
- วาง/ลากรูป: ไฟล์ใต้โฟลเดอร์เอกสารใช้ path สัมพัทธ์เลย, นอกโฟลเดอร์ = คัดลอกไป `assets/` (ชื่อซ้ำต่อ -1, -2), screenshot = `assets/image-YYYYMMDD-HHmmss.png`, เอกสารไม่มีชื่อเก็บใน Application Support แล้วย้ายตอนบันทึกครั้งแรก — `importCopiesToAssetsWithUniqueNames`, `pasteImageDataCopiesToAssets`, `untitledImagesMoveOnFirstSave`
- คลิกเลือก, ดับเบิลคลิกเปิด Preview, คลิกขวา (แสดงใน Finder / คัดลอกรูป / แก้ alt), ลบรูปไม่ลบไฟล์ — `deletingImageKeepsFile`, `editAltKeepsOtherFields`, `copyImagePutsMarkdownAndImage`
- ระยะห่างหลังลิสต์/quote ตามบล็อกถัดไป (`Theme.gap`) — `listSpacingBetweenDifferentBlocks`
- sheet ลิงก์ใหม่ (`PromptSheet`), ไอคอนแอปจาก `Jotdown.iconset/` (PNG 1024 ที่ใช้จริงอยู่ `build/icon-1024.png`) — `promptSheetSnapshots`
- UI ทั้งแอปเป็นภาษาอังกฤษ (เมนูมาตรฐาน macOS, sheet ลิงก์ "Link / Remove Link / Cancel / OK", ข้อความรูป "Image not found: <path>", ชื่อเอกสาร "Untitled" จากระบบ; development region = en) — เนื้อหา/fixture ภาษาไทยยังใช้ทดสอบการแสดงผลตามเดิม; เมนูรูปแบบเป็น "Format" (Bold, Italic, Strikethrough, Inline Code, Link…, Paragraph, Heading 1–6, Bulleted/Numbered List, Checklist, Indent/Outdent, Quote, Code Block)

### ขั้น 4 — ตาราง GFM (2026-10-29)
- ตารางแสดงด้วย `NSTextTable`/`NSTextTableBlock` (TextKit 1) เซลล์ละย่อหน้า (`BlockKind.tableCell(row, col, align)`) ใน storage ไม่มี `|` หัวตารางตัวหนาพื้นจาง เส้นขอบบาง ตารางกว้างเท่าคอลัมน์ (เซลล์ wrap) alignment เก็บ/เขียนกลับตาม `:--` `:-:` `--:`
- serialize แบบ **จัดคอลัมน์ด้วยช่องว่าง** (ความกว้างนับเป็น grapheme cluster: สระ/วรรณยุกต์ไทยไม่กินคอลัมน์ CJK/emoji = 2); เซลล์ไม่เท่ากันเติมเซลล์ว่าง; `|` ในเซลล์ → `\|`; ขึ้นบรรทัดในเซลล์ → `<br>` (`TableModel`) — `TableTests`
- คีย์บอร์ด: Tab/⇧Tab เซลล์ถัดไป/ก่อน (เซลล์สุดท้าย = เพิ่มแถว), Enter = แถวถัดไป (แถวสุดท้าย = เพิ่มแถว), ⇧Enter = ขึ้นบรรทัดในเซลล์, ↑↓ ข้ามแถว, Backspace/Delete ไม่ลบโครงตาราง, ลบข้ามเซลล์ = ล้างเนื้อหาเซลล์
- สร้างตาราง: Format → Table → Insert Table (⌃⌘T, 3×3) หรือพิมพ์ `| a | b |` แล้ว Enter; เมนู Table: Insert Row Above/Below, Insert Column Left/Right, Delete Row/Column/Table, Align Column Left/Center/Right (+ เมนูคลิกขวา) ทุกคำสั่ง undo ได้ครั้งเดียว
- วาง markdown/HTML `<table>` เป็นตาราง, คัดลอกเซลล์ = markdown

### Toolbar จัดรูปแบบ (2026-10-29)
- `NSToolbar` (`Editor/FormatToolbar.swift`, `toolbarStyle = .unified`: เรียบกว่า compact เพราะปุ่มเป็นแคปซูลกลุ่มเดียวกับแถบหัวหน้าต่าง) Text style popup + inline + lists + blocks (รวม Table และ Image…) tooltip อังกฤษ + คีย์ลัด, สถานะกดตามเคอร์เซอร์จาก `validateMenuItem` ตัวเดียวกับเมนู, overflow (») ผ่าน `menuFormRepresentation`, ปรับแต่งได้, View → Hide/Show Toolbar (⌥⌘T), Format → Insert Image… (⇧⌘I) — `ToolbarTests`

### ธีมเหลืองอำพัน + ชื่อ Jotdown (2026-10-29)
- เปลี่ยนชื่อแอปเป็น **Jotdown** (target/โฟลเดอร์/bundle id `com.euw.jotdown`/`build/Jotdown.app`; env `JOTDOWN_FONTS_DIR`, `JOTDOWN_APPEARANCE`=dark|light สำหรับตรวจธีม, `JOTDOWN_TESTING` ใน test.sh)
- สีทั้งหมดอยู่ที่ `Palette` ใน `Style/Theme.swift` (dynamic NSColor สว่าง/มืด): พื้นครีม #FFFDF5 / น้ำตาลอุ่น #1F1C17, accent เหลืองอำพัน (เคอร์เซอร์ พื้นที่เลือก checkbox เส้น quote กรอบรูป ปุ่ม OK), ลิงก์เหลืองเข้ม (สว่าง #7A4F00 / มืด #F5C542) ขีดเส้นใต้เหลืองสด — contrast ข้อความ/ลิงก์ ≥ 4.5:1 ทดสอบใน `ThemeTests`
- ไอคอนแอปคงแบบเดิม (ครีม + J เข้ม + ขีดส้ม)
- snapshot sheet โหมดมืดที่เห็นเป็นพื้นขาวพังเฉพาะการถ่าย snapshot (พื้นหน้าต่างโปร่งใส) ไม่ใช่แอปจริง — แก้ใน `SnapshotSupport.snapshotWithWindowBackground`

### เลือก/ลบทั้งตาราง + สถานะปุ่ม toolbar สีเหลือง (2026-10-29)
- selection ที่ครอบทุกเซลล์ของตาราง (ทั้งตาราง, ลากข้ามจากข้อความก่อน/หลัง, ⌘A) + Backspace/Delete/⌘X/พิมพ์ทับ = ลบโครงตารางด้วย undo ครั้งเดียว; เลือกบางเซลล์ = ล้างเนื้อหา โครงคงอยู่; Format → Table → Select Table (และเมนูคลิกขวา); ไฮไลต์ทั้งตารางพื้นเหลือง — `TableTests` (`selectTableThenBackspace…`, `dragAcrossTable…`, `selectAllBackspace…`, `partialCellsKeepStructure`, …)
- ปุ่ม toolbar เป็น `NSButton` ของเราเอง (`ToolButton`/`ToolGroupView`): สถานะใช้งาน = พื้นเหลือง accent เต็มปุ่ม ไอคอนสีเข้ม; popup text style ไม่เปลี่ยนสี — `ToolbarTests.activeButtonFillsWholeButtonInAccent`

### Enter/Backspace/Tab ในลิสต์และ quote แบบ Notion (2026-10-29)
- สเปก 11 ข้อทดสอบทั้งเป็น unit test (`ListEnterTests`) และกดคีย์จริงในแอป (osascript `key code`, อ่านไฟล์ .md ที่บันทึกอัตโนมัติ): Enter ท้าย/กลาง/ต้นรายการ, รายการว่างซ้อน = ลดระดับ, รายการว่างบนสุด = ออกจากลิสต์, ⇧Enter = ขึ้นบรรทัดในรายการเดิม (ลิสต์/quote/เซลล์ตาราง; ในแอปจริง ⇧Enter มาทาง `insertNewline:` พร้อม modifier), Backspace ต้นรายการ (รายการซ้อน = ลดระดับก่อน เพราะ markdown เก็บระยะเยื้องของย่อหน้าไม่ได้), Tab/⇧Tab ที่ใดก็ได้ในรายการ, undo ทีละ Enter
- ปุ่ม active ใน toolbar: พื้นเหลืองอยู่ในแคปซูล (inset 3pt, มุมแบบแคปซูล) — ความสูงปุ่มเท่าแคปซูลที่ระบบวาดให้ (วัดจากกรอบ view ของกลุ่ม)

### เส้นขอบขวาของตาราง (2026-10-29)
- สาเหตุ: `NSTextTable.collapsesBorders = true` ทำให้เส้นขวานอกสุดหายเมื่อตารางกว้าง = text container พอดี แก้เป็น `collapsesBorders = false` แล้ววาดเส้นต่อเซลล์ให้บางเท่ากัน (ซ้าย/บนเฉพาะเซลล์ริม ขวา/ล่างทุกเซลล์) — `TableTests` ตรวจพิกเซลที่ขอบขวา (`rightBorderCoverage`) ที่ความกว้าง 480/700/900/1400 ทั้ง light/dark

### ลิงก์: แถบลอย / เปิดลิงก์ (2026-10-29)
- แถบลิงก์ลอย (`Editor/LinkBar.swift`, NSPanel ไม่ขโมยโฟกัส): ชี้ลิงก์ ~0.4 วิ หรือเคอร์เซอร์อยู่ในลิงก์ → ไอคอน + URL ย่อ + Open / Copy / Edit / Remove; หายเมื่อเมาส์ออก (หน่วง 0.3 วิ) / เคอร์เซอร์ออก / พิมพ์ / scroll / หน้าต่างไม่ active; แสดงเหนือลิงก์ถ้าใต้ไม่พอ; logic เวลาอยู่ใน `LinkBarState` (ทดสอบได้)
- ⌥↩ = Open Link, Format → Open Link / Copy Link Address, คลิกขวาบนลิงก์, ⌘-คลิก, cursor มือเมื่อกด ⌘
- ปลายทาง (`LinkResolver`): http(s)/mailto, โดเมนไม่มี scheme → https://, path สัมพัทธ์/ไฟล์ (.md เปิดใน Jotdown), `#หัวข้อ` (slug แบบ GitHub รองรับไทย), ไม่พบไฟล์ = "File not found" ในแถบ, เอกสารไม่มีชื่อ = "Save the document to open relative links"
- URL เปล่า + เว้นวรรค = ลิงก์อัตโนมัติ (เขียนกลับเป็น URL เปล่า, อ่านไฟล์แล้วกลับเป็นลิงก์) — `LinkTests`

### Obsidian (2026-10-29)
- รองรับ: `![[รูป.jpg]]`, `![[รูป.png|300]]`, `![[รูป.png|300x200]]` (รูปจริง ใช้ระบบรูปเดิม), `![[โน้ต]]`/`![[โน้ต#หัวข้อ]]` (การ์ดลิงก์ ไม่ดึงเนื้อหา), `[[โน้ต]]`, `[[โน้ต|ข้อความ]]`, `[[โน้ต#หัวข้อ]]`, `[[#หัวข้อ]]` (แสดงเป็นลิงก์ ไม่เห็น `[[ ]]` ใช้แถบลอย/⌥↩/⌘-คลิก/คลิกขวาเหมือนลิงก์ปกติ; Edit แก้ `โน้ต#หัวข้อ|ข้อความ`); โน้ตที่ไม่มี = ลิงก์สีจาง, Open = "Note not found" ไม่สร้างไฟล์ใหม่
- เก็บข้อความดิบใน attribute (`.jotWiki`, `ImageRef.raw`) → round-trip เหมือนเดิมทุกตัวอักษร รวมในตาราง `[[a\|b]]`; ไม่ parse ในโค้ด/กล่องโค้ด (`ObsidianSyntax`)
- หาไฟล์แบบ Obsidian (`ObsidianVault`): vault root = โฟลเดอร์แรกที่มี `.obsidian/` → path จาก root ก่อน → โฟลเดอร์เอกสาร → `attachmentFolderPath` ใน `.obsidian/app.json` (`./x` สัมพัทธ์เอกสาร) → ค้นทั้ง vault ตามชื่อ (ไม่สนตัวพิมพ์ ไม่ต้องมี .md เลือก path สั้นสุด) ด้วย index เบื้องหลัง (ข้าม `.obsidian/.git/node_modules/.trash`, รีเฟรชเมื่อหาไม่เจอ)
- รูปที่ลาก/วางในเอกสารที่อยู่ใน vault และมี `![[` อยู่แล้ว → `![[ชื่อไฟล์]]` ไม่งั้นใช้ `![](…)` เหมือนเดิม
- frontmatter `---` ต้นไฟล์ (ตรวจว่าเป็น YAML) เก็บเป็นบล็อก raw ไม่เสียเนื้อหา; callout `> [!note]`, tag `#tag`, checkbox ไม่ถูก escape ผิด (กฎ escape `[` แคบลง)
- **ยังไม่รองรับ:** callout แบบพับ/สไตล์ (แสดงเป็น quote ธรรมดา), tag เป็นลิงก์, `^block-id`, `![[…]]` ของ PDF/เสียง/วิดีโอ (แสดงเป็นการ์ดโน้ต), ฝังเนื้อหาโน้ตจริง, `%%comment%%`, math `$…$`, Dataview, ช่วงของ `[[note#^id]]` — `ObsidianTests`
