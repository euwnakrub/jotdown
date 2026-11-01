(() => {
  "use strict";

  /* ---------- Copy (English / Thai) ---------- */
  const T = {
    en: {
      "meta.title": "Jotdown — Beautiful notes, simple files",
      "skip": "Skip to install guide",
      "nav.features": "Features", "nav.install": "How to install", "nav.faq": "FAQ", "nav.download": "Download",
      "hero.eyebrow": "Free note app for Mac",
      "hero.title": "Write beautiful notes.<br>Keep simple files.",
      "hero.lede": "Headings, checklists and tables look right the moment you type them. Every note is saved as a plain file that belongs to you.",
      "hero.download": "Download for Mac", "hero.howto": "How to install",
      "hero.free": "Free", "hero.req": "macOS 14+ · Apple silicon",
      "notmac": "Jotdown runs on Mac computers. Open this page on your Mac to download it.",
      "demo.saved": "Saved", "demo.rawcap": "The same note in any text editor",
      "cap.1": "Type <kbd>#</kbd> and a space to make a heading",
      "cap.2": "Put <kbd>**</kbd> around words to make them bold",
      "cap.3": "Type <kbd>[]</kbd> and a space for a checklist",
      "cap.4": "Click a box to tick it off",
      "cap.5": "Type <kbd>&gt;</kbd> and a space for a quote",
      "cap.6": "Saved automatically, as a plain <b>.md</b> file that opens anywhere",
      "feat.title": "Everything you need. Nothing in your way.",
      "f1.t": "No symbols in your way",
      "f1.d": "Headings look like headings and bold looks bold. You never see the # or ** behind them, just like Notion or Pages.",
      "f2.t": "Your files, your way",
      "f2.d": "Each note is a normal .md file in a folder you choose. Open it in Obsidian, VS Code or any text editor, today or in 20 years.",
      "f3.t": "Fast and light",
      "f3.d": "A true Mac app of about 4 MB. It opens instantly and stays smooth even with thousands of lines.",
      "f4.t": "Never lose a word",
      "f4.d": "Changes save about a second after you stop typing. There's no Save button to forget.",
      "f5.t": "Everything a note needs",
      "f5.d": "Checklists, tables, images, links, YouTube cards and colourful code blocks.",
      "f6.t": "Made for Thai, too",
      "f6.d": "Easy-to-read IBM Plex Sans Thai fonts, with light and dark mode that follow your Mac.",
      "shot.cap": "A real note in Jotdown, in light and dark mode.",
      "inst.title": "Install in 5 minutes",
      "inst.sub": "No technical skills needed. Follow these steps once and you're set.",
      "s1.t": "Check your Mac",
      "s1.d": "Click the <b>Apple logo</b> in the top-left corner of your screen, then choose <b>About This Mac</b>. Look at the two highlighted lines.",
      "s1.chip": "Chip", "s1.mem": "Memory",
      "s1.ok": "You're good to go if the chip is <b>Apple M1 or newer</b> (M2, M3, M4…) and macOS is <b>14 Sonoma or newer</b> (15 Sequoia, 26 Tahoe…).",
      "s2.t": "Download Jotdown",
      "s2.d": "Click the button below. A file called <b>Jotdown.zip</b> is saved to your <b>Downloads</b> folder.",
      "s2.btn": "Download Jotdown.zip",
      "s3.t": "Unzip it",
      "s3.d": "Open <b>Finder</b>, go to <b>Downloads</b> and double-click <b>Jotdown.zip</b>. The Jotdown app appears next to it.",
      "s3.safari": "Using Safari? It often unzips the file for you, so you may already see <b>Jotdown</b> in Downloads. That's fine, go straight to step 4.",
      "s4.t": "Move it to Applications",
      "s4.d": "Drag <b>Jotdown</b> onto <b>Applications</b> in the Finder sidebar. This keeps it with your other apps.",
      "s4.apps": "Applications", "s4.desk": "Desktop", "s4.down": "Downloads",
      "s5.t": "Open it the first time",
      "s5.d": "Jotdown is free and isn't sold through Apple, so your Mac asks you to confirm before opening it. <b>You only do this once.</b> Pick your macOS version:",
      "s5.tabNew": "macOS 15 or newer", "s5.tabOld": "macOS 14 Sonoma",
      "s5.n1": "Open <b>Applications</b> and double-click <b>Jotdown</b>. A message says it can't be opened. Click <b>Done</b>.",
      "s5.n2": "Open <b>System Settings</b> (Apple logo → System Settings) and click <b>Privacy &amp; Security</b> in the sidebar.",
      "s5.n3": "Scroll down to the message about Jotdown and click <b>Open Anyway</b>.",
      "s5.n4": "Enter your Mac password, then click <b>Open Anyway</b> once more. Jotdown opens.",
      "s5.ps": "Privacy &amp; Security", "s5.sec": "Security",
      "s5.blocked": "“Jotdown” was blocked to protect your Mac.",
      "s5.o1": "Open <b>Applications</b>, then <b>right-click</b> Jotdown (or hold <kbd>control</kbd> and click) and choose <b>Open</b>.",
      "s5.o2": "A message asks if you're sure. Click <b>Open</b>. Jotdown opens.",
      "s5.once": "From now on, Jotdown opens normally, like any other app.",
      "s6.t": "You're done!",
      "s6.d": "Press <kbd>⌘</kbd> <kbd>N</kbd> to start a new note. Your note saves itself while you type.",
      "s6.tip": "<b>Tip:</b> to open all your .md files in Jotdown, right-click one in Finder, choose <b>Get Info</b>, pick <b>Jotdown</b> under <b>Open with</b>, then click <b>Change All</b>.",
      "tech.sum": "Comfortable with Terminal?",
      "tech.d": "Instead of step 5, you can run this command once after moving Jotdown to Applications:",
      "faq.title": "Questions",
      "q1": "Is Jotdown free?",
      "a1": "Yes. It's free to download and use, with no account, ads or subscription. All of the source code is on GitHub.",
      "q2": "Why does my Mac warn me the first time?",
      "a2": "Apple charges developers a yearly fee to have their apps checked and remove this warning. Jotdown is a free personal project, so it skips that step. The warning only appears the first time you open it.",
      "q3": "What is a .md file?",
      "a3": "It's a Markdown file: plain text with a few simple marks, such as # for a heading. Almost every notes app can read it, so your notes never get locked into one app.",
      "q4": "Where are my notes saved?",
      "a4": "Wherever you choose, such as Documents or iCloud Drive. Each note is a .md file that you can see in Finder, back up, or open in other apps.",
      "q5": "Does it work on Windows, iPhone or iPad?",
      "a5": "No. Jotdown is made for Mac only.",
      "q6": "My Mac has an Intel chip. Can I use it?",
      "a6": "Not yet. Jotdown needs a Mac with Apple silicon (M1 or newer). You can check in About This Mac (step 1).",
      "q7": "How do I update or uninstall?",
      "a7": "To update, download the newest version from this page and replace the old app in Applications. To uninstall, drag Jotdown from Applications to the Trash. Your notes stay where you saved them.",
      "final.t": "Start writing in a minute.",
      "foot.rel": "All versions", "foot.font": "Fonts: IBM Plex Sans Thai (SIL Open Font License)",
      "aria.pause": "Pause", "aria.play": "Play", "aria.replay": "Replay",
    },
    th: {
      "meta.title": "Jotdown — จดโน้ตสวย เก็บไฟล์เรียบง่าย",
      "skip": "ข้ามไปวิธีติดตั้ง",
      "nav.features": "ความสามารถ", "nav.install": "วิธีติดตั้ง", "nav.faq": "คำถามที่พบบ่อย", "nav.download": "ดาวน์โหลด",
      "hero.eyebrow": "แอปจดโน้ตฟรีสำหรับ Mac",
      "hero.title": "จดโน้ตให้สวย<br>เก็บไฟล์ให้เรียบง่าย",
      "hero.lede": "หัวข้อ เช็กลิสต์ และตาราง แสดงผลสวยทันทีที่พิมพ์ ทุกโน้ตเก็บเป็นไฟล์ธรรมดาที่เป็นของคุณเอง",
      "hero.download": "ดาวน์โหลดสำหรับ Mac", "hero.howto": "วิธีติดตั้ง",
      "hero.free": "ฟรี", "hero.req": "macOS 14 ขึ้นไป · ชิป Apple",
      "notmac": "Jotdown ใช้ได้บนคอมพิวเตอร์ Mac เท่านั้น เปิดหน้านี้บน Mac เพื่อดาวน์โหลด",
      "demo.saved": "บันทึกแล้ว", "demo.rawcap": "โน้ตเดียวกัน เมื่อเปิดในโปรแกรมแก้ข้อความทั่วไป",
      "cap.1": "พิมพ์ <kbd>#</kbd> แล้วเว้นวรรค ได้หัวข้อทันที",
      "cap.2": "ครอบคำด้วย <kbd>**</kbd> เพื่อทำตัวหนา",
      "cap.3": "พิมพ์ <kbd>[]</kbd> แล้วเว้นวรรค ได้เช็กลิสต์",
      "cap.4": "คลิกที่ช่องเพื่อติ๊กว่าทำเสร็จแล้ว",
      "cap.5": "พิมพ์ <kbd>&gt;</kbd> แล้วเว้นวรรค ได้กล่องคำคม",
      "cap.6": "บันทึกให้อัตโนมัติ เป็นไฟล์ <b>.md</b> ธรรมดาที่เปิดได้ทุกที่",
      "feat.title": "ครบทุกอย่างที่ต้องใช้ ไม่มีอะไรมาเกะกะ",
      "f1.t": "ไม่ต้องเห็นสัญลักษณ์รกตา",
      "f1.d": "หัวข้อดูเป็นหัวข้อ ตัวหนาดูเป็นตัวหนา ไม่ต้องเห็น # หรือ ** ที่อยู่เบื้องหลัง เหมือนใช้ Notion หรือ Pages",
      "f2.t": "ไฟล์เป็นของคุณจริงๆ",
      "f2.d": "ทุกโน้ตเป็นไฟล์ .md ธรรมดาในโฟลเดอร์ที่คุณเลือกเอง เปิดด้วย Obsidian, VS Code หรือโปรแกรมแก้ข้อความอะไรก็ได้ วันนี้หรืออีก 20 ปีก็ยังเปิดได้",
      "f3.t": "เร็วและเบา",
      "f3.d": "แอป Mac แท้ๆ ขนาดราว 4 MB เปิดปุ๊บติดปั๊บ ลื่นแม้โน้ตยาวหลายพันบรรทัด",
      "f4.t": "งานไม่มีวันหาย",
      "f4.d": "บันทึกให้เองหลังหยุดพิมพ์ราวหนึ่งวินาที ไม่ต้องคอยกดเซฟ",
      "f5.t": "ครบทุกอย่างที่โน้ตต้องมี",
      "f5.d": "เช็กลิสต์ ตาราง รูปภาพ ลิงก์ การ์ด YouTube และกล่องโค้ดแบบมีสี",
      "f6.t": "อ่านภาษาไทยสบายตา",
      "f6.d": "ใช้ฟอนต์ IBM Plex Sans Thai อ่านง่าย มีโหมดสว่างและโหมดมืดตามการตั้งค่าของ Mac",
      "shot.cap": "หน้าตาโน้ตจริงใน Jotdown ทั้งโหมดสว่างและโหมดมืด",
      "inst.title": "ติดตั้งง่ายใน 5 นาที",
      "inst.sub": "ไม่ต้องมีความรู้ด้านเทคนิค ทำตามขั้นตอนนี้ครั้งเดียวก็ใช้ได้เลย",
      "s1.t": "เช็กว่า Mac ของคุณใช้ได้",
      "s1.d": "คลิก<b>โลโก้ Apple</b> ที่มุมซ้ายบนของจอ แล้วเลือก <b>About This Mac</b> (เกี่ยวกับ Mac เครื่องนี้) ดูสองบรรทัดที่ไฮไลต์ไว้",
      "s1.chip": "ชิป", "s1.mem": "หน่วยความจำ",
      "s1.ok": "ใช้ได้ถ้าชิปเป็น <b>Apple M1 ขึ้นไป</b> (M2, M3, M4…) และ macOS เป็น <b>14 Sonoma ขึ้นไป</b> (15 Sequoia, 26 Tahoe…)",
      "s2.t": "ดาวน์โหลด Jotdown",
      "s2.d": "กดปุ่มด้านล่าง ไฟล์ชื่อ <b>Jotdown.zip</b> จะไปอยู่ในโฟลเดอร์ <b>Downloads</b> (ดาวน์โหลด)",
      "s2.btn": "ดาวน์โหลด Jotdown.zip",
      "s3.t": "แตกไฟล์",
      "s3.d": "เปิด <b>Finder</b> ไปที่ <b>Downloads</b> แล้วดับเบิลคลิก <b>Jotdown.zip</b> แอป Jotdown จะโผล่ขึ้นมาข้างๆ",
      "s3.safari": "ถ้าใช้ Safari ส่วนใหญ่จะแตกไฟล์ให้เอง คุณอาจเห็น <b>Jotdown</b> อยู่ใน Downloads แล้ว แบบนั้นก็ได้ ข้ามไปขั้นที่ 4 ได้เลย",
      "s4.t": "ย้ายไปไว้ใน Applications",
      "s4.d": "ลาก <b>Jotdown</b> ไปวางที่ <b>Applications</b> (แอปพลิเคชัน) ในแถบด้านซ้ายของ Finder เพื่อเก็บไว้รวมกับแอปอื่นๆ",
      "s4.apps": "Applications", "s4.desk": "Desktop", "s4.down": "Downloads",
      "s5.t": "เปิดใช้ครั้งแรก",
      "s5.d": "Jotdown เป็นแอปฟรีที่ไม่ได้ขายผ่าน Apple ครั้งแรก Mac จึงจะถามยืนยันก่อนเปิด <b>ทำแค่ครั้งเดียวเท่านั้น</b> เลือกเวอร์ชัน macOS ของคุณ:",
      "s5.tabNew": "macOS 15 ขึ้นไป", "s5.tabOld": "macOS 14 Sonoma",
      "s5.n1": "เปิด <b>Applications</b> แล้วดับเบิลคลิก <b>Jotdown</b> จะมีข้อความบอกว่าเปิดไม่ได้ ให้กด <b>Done</b> (เสร็จสิ้น)",
      "s5.n2": "เปิด <b>System Settings</b> (การตั้งค่าระบบ) จากโลโก้ Apple แล้วคลิก <b>Privacy &amp; Security</b> (ความเป็นส่วนตัวและความปลอดภัย) ในแถบด้านซ้าย",
      "s5.n3": "เลื่อนลงไปหาข้อความที่พูดถึง Jotdown แล้วกดปุ่ม <b>Open Anyway</b>",
      "s5.n4": "ใส่รหัสผ่านเครื่อง Mac แล้วกด <b>Open Anyway</b> อีกครั้ง Jotdown ก็จะเปิดขึ้นมา",
      "s5.ps": "Privacy &amp; Security", "s5.sec": "Security",
      "s5.blocked": "“Jotdown” was blocked to protect your Mac.",
      "s5.o1": "เปิด <b>Applications</b> แล้ว<b>คลิกขวา</b>ที่ Jotdown (หรือกด <kbd>control</kbd> ค้างแล้วคลิก) แล้วเลือก <b>Open</b> (เปิด)",
      "s5.o2": "จะมีหน้าต่างถามว่าแน่ใจไหม ให้กด <b>Open</b> (เปิด) Jotdown ก็จะเปิดขึ้นมา",
      "s5.once": "ถ้า Mac ตั้งเป็นภาษาไทย ชื่อเมนูจะเป็นภาษาไทย แต่อยู่ตำแหน่งเดียวกัน หลังจากนี้ Jotdown จะเปิดได้ตามปกติเหมือนแอปอื่นๆ",
      "s6.t": "เสร็จแล้ว!",
      "s6.d": "กด <kbd>⌘</kbd> <kbd>N</kbd> เพื่อเริ่มโน้ตใหม่ โน้ตจะบันทึกให้เองระหว่างที่คุณพิมพ์",
      "s6.tip": "<b>เคล็ดลับ:</b> อยากให้ไฟล์ .md ทุกไฟล์เปิดด้วย Jotdown ให้คลิกขวาที่ไฟล์ใน Finder เลือก <b>Get Info</b> (รับข้อมูล) ตรง <b>Open with</b> (เปิดด้วย) เลือก Jotdown แล้วกด <b>Change All</b> (เปลี่ยนทั้งหมด)",
      "tech.sum": "ถนัดใช้ Terminal?",
      "tech.d": "แทนขั้นที่ 5 คุณรันคำสั่งนี้ครั้งเดียวหลังย้าย Jotdown ไปที่ Applications ได้เลย:",
      "faq.title": "คำถามที่พบบ่อย",
      "q1": "Jotdown ฟรีไหม?",
      "a1": "ฟรี ดาวน์โหลดและใช้ได้ฟรี ไม่ต้องสมัครบัญชี ไม่มีโฆษณา ไม่มีค่ารายเดือน และโค้ดทั้งหมดเปิดให้ดูบน GitHub",
      "q2": "ทำไมครั้งแรก Mac ถึงขึ้นคำเตือน?",
      "a2": "Apple เก็บค่าธรรมเนียมรายปีจากนักพัฒนาเพื่อตรวจแอปและเอาคำเตือนนี้ออก Jotdown เป็นโปรเจกต์ส่วนตัวที่แจกฟรี จึงไม่ได้ผ่านขั้นตอนนั้น คำเตือนจะขึ้นแค่ตอนเปิดครั้งแรกเท่านั้น",
      "q3": "ไฟล์ .md คืออะไร?",
      "a3": "คือไฟล์ Markdown เป็นข้อความธรรมดาที่มีเครื่องหมายง่ายๆ เช่น # แทนหัวข้อ แอปจดโน้ตแทบทุกตัวเปิดได้ โน้ตของคุณจึงไม่ถูกผูกติดกับแอปใดแอปหนึ่ง",
      "q4": "โน้ตถูกเก็บไว้ที่ไหน?",
      "a4": "ที่ไหนก็ได้ที่คุณเลือก เช่น Documents หรือ iCloud Drive ทุกโน้ตเป็นไฟล์ .md ที่มองเห็นใน Finder สำรองข้อมูลได้ และเปิดด้วยแอปอื่นได้",
      "q5": "ใช้บน Windows, iPhone หรือ iPad ได้ไหม?",
      "a5": "ไม่ได้ Jotdown ทำมาสำหรับ Mac เท่านั้น",
      "q6": "Mac เป็นชิป Intel ใช้ได้ไหม?",
      "a6": "ยังไม่ได้ Jotdown ต้องใช้ Mac ที่เป็นชิป Apple (M1 ขึ้นไป) เช็กได้ใน About This Mac (ขั้นที่ 1)",
      "q7": "อัปเดตหรือลบแอปยังไง?",
      "a7": "อัปเดต: ดาวน์โหลดเวอร์ชันล่าสุดจากหน้านี้ แล้ววางทับแอปเดิมใน Applications ลบแอป: ลาก Jotdown จาก Applications ไปที่ถังขยะ โน้ตของคุณยังอยู่ที่เดิมครบ",
      "final.t": "เริ่มเขียนได้ในไม่กี่นาที",
      "foot.rel": "ทุกเวอร์ชัน", "foot.font": "ฟอนต์: IBM Plex Sans Thai (SIL Open Font License)",
      "aria.pause": "หยุดชั่วคราว", "aria.play": "เล่น", "aria.replay": "เล่นใหม่",
    },
  };

  /* What the demo types, per language */
  const DEMO = {
    en: {
      file: "Kyoto Trip.md",
      h1: "Kyoto Trip",
      p: ["Five days in Kyoto, right in ", "cherry blossom season", "."],
      checks: ["Book flights", "Reserve the ryokan"],
      quote: "Leave one afternoon unplanned.",
    },
    th: {
      file: "ทริปเกียวโต.md",
      h1: "ทริปเกียวโต",
      p: ["ห้าวันในเกียวโต ตรงกับช่วง", "ซากุระบาน", "พอดี"],
      checks: ["จองตั๋วเครื่องบิน", "จองเรียวกัง"],
      quote: "เว้นว่างไว้สักบ่าย เผื่อเจอเรื่องดีๆ ที่ไม่ได้วางแผน",
    },
  };

  const $ = (s) => document.querySelector(s);
  const $$ = (s) => document.querySelectorAll(s);

  /* ---------- Language ---------- */
  function detectLang() {
    try {
      const saved = localStorage.getItem("jotdown-lang");
      if (saved === "th" || saved === "en") return saved;
    } catch (e) { /* storage blocked */ }
    const langs = navigator.languages && navigator.languages.length ? navigator.languages : [navigator.language || "en"];
    return langs.some((l) => /^th\b/i.test(l)) ? "th" : "en";
  }
  let lang = detectLang();

  function applyLang() {
    const t = T[lang];
    document.documentElement.lang = lang;
    document.title = t["meta.title"];
    $$("[data-i18n]").forEach((el) => {
      const v = t[el.dataset.i18n];
      if (v != null) el.innerHTML = v;
    });
    updatePlayLabel();
    $("#replayBtn").setAttribute("aria-label", t["aria.replay"]);
  }

  $("#lang").addEventListener("click", () => {
    lang = lang === "th" ? "en" : "th";
    try { localStorage.setItem("jotdown-lang", lang); } catch (e) { /* ignore */ }
    applyLang();
    restart();
  });

  /* ---------- Non-Mac visitors ---------- */
  const ua = navigator.userAgent;
  const isIpad = /Macintosh/.test(ua) && navigator.maxTouchPoints > 1;
  const isMac = /Macintosh|Mac OS X/.test(ua) && !isIpad;
  if (!isMac) $("#notmac").hidden = false;

  /* ---------- Latest version from GitHub (falls back to the static text) ---------- */
  fetch("https://api.github.com/repos/euwnakrub/jotdown/releases/latest")
    .then((r) => (r.ok ? r.json() : null))
    .then((j) => { if (j && j.tag_name) $$(".ver").forEach((el) => { el.textContent = j.tag_name; }); })
    .catch(() => {});

  /* ---------- Install tabs ---------- */
  $$(".tab").forEach((tab) => tab.addEventListener("click", () => {
    $$(".tab").forEach((b) => { const on = b === tab; b.classList.toggle("on", on); b.setAttribute("aria-selected", on); });
    $$(".tabpane").forEach((p) => { p.hidden = p.dataset.pane !== tab.dataset.tab; });
  }));

  /* ---------- Demo stage scaling ---------- */
  const stageIn = $("#stageIn");
  function fit() { stageIn.style.setProperty("--s", stageIn.clientWidth / 960); }
  new ResizeObserver(fit).observe(stageIn);
  fit();

  /* ---------- Demo animation ---------- */
  const docEl = $("#doc"), capEl = $("#caption"), barEl = $("#barFill"), rawEl = $("#raw");
  const pointer = $("#pointer"), savedEl = $("#saved"), playBtn = $("#playBtn");
  const tools = { head: $("#tHead"), bold: $("#tBold"), check: $("#tCheck"), quote: $("#tQuote") };
  const reduced = window.matchMedia("(prefers-reduced-motion: reduce)").matches;
  const STOP = Symbol("stop");
  let runId = 0, paused = false, visible = true;
  const caret = document.createElement("span");
  caret.className = "caret";
  let cur = null;

  function sleep(ms) {
    const id = runId;
    return new Promise((resolve, reject) => {
      let left = ms, last = performance.now();
      const tick = (now) => {
        if (id !== runId) return reject(STOP);
        if (!paused && visible) left -= now - last;
        last = now;
        if (left <= 0) resolve(); else requestAnimationFrame(tick);
      };
      requestAnimationFrame(tick);
    });
  }

  const graphemes = (s) => (window.Intl && Intl.Segmenter)
    ? Array.from(new Intl.Segmenter(lang, { granularity: "grapheme" }).segment(s), (x) => x.segment)
    : Array.from(s);

  function setTools({ head = "Body", bold = false, check = false, quote = false } = {}) {
    tools.head.firstChild.textContent = head + " ";
    tools.bold.classList.toggle("on", bold);
    tools.check.classList.toggle("on", check);
    tools.quote.classList.toggle("on", quote);
  }

  function newBlock(kind) {
    const el = document.createElement("div");
    el.className = "blk " + kind;
    if (kind === "check") el.appendChild(Object.assign(document.createElement("span"), { className: "box" }));
    const txt = document.createElement("span");
    txt.className = "txt";
    const node = document.createTextNode("");
    txt.append(node, caret);
    el.appendChild(txt);
    docEl.appendChild(el);
    cur = { el, txt, node };
    return el;
  }

  async function type(s, fast) {
    for (const ch of graphemes(s)) {
      cur.node.data += ch;
      await sleep(fast ? 22 : ch === " " ? 90 : 45 + Math.random() * 55);
    }
  }

  // The line started with a shortcut such as "# ": turn it into the real block.
  function morph(kind) {
    const { el } = cur;
    el.className = "blk " + kind + " morph";
    cur.node.data = "";
    if (kind === "check" && !el.querySelector(".box")) el.prepend(Object.assign(document.createElement("span"), { className: "box" }));
  }

  // The last `raw` characters were **word**: replace them with bold text.
  function boldify(word) {
    const raw = "**" + word + "**";
    cur.node.data = cur.node.data.slice(0, -raw.length);
    const strong = document.createElement("strong");
    strong.textContent = word;
    const after = document.createTextNode("");
    cur.txt.insertBefore(strong, caret);
    cur.txt.insertBefore(after, caret);
    cur.node = after;
  }

  function caption(key, step, total) {
    capEl.innerHTML = key ? `<span>${T[lang][key]}</span>` : "";
    barEl.style.transition = "width .6s ease";
    barEl.style.width = (step / total) * 100 + "%";
  }

  async function clickBox(block) {
    const box = block.querySelector(".box");
    const a = stageIn.getBoundingClientRect(), b = box.getBoundingClientRect();
    pointer.style.transition = "none";
    pointer.style.transform = `translate(${a.width * 0.72}px, ${a.height * 0.85}px)`;
    await sleep(30);
    pointer.classList.add("on");
    pointer.style.transition = "";
    pointer.style.transform = `translate(${b.left - a.left + b.width / 2 - 4}px, ${b.top - a.top + b.height / 2 - 3}px)`;
    await sleep(900);
    pointer.classList.add("click");
    block.classList.add("done");
    await sleep(350);
    pointer.classList.remove("click");
    await sleep(500);
    pointer.classList.remove("on");
  }

  function rawMarkdown(d) {
    const mk = (s) => `<span class="mk">${s}</span>`;
    const esc = (s) => s.replace(/&/g, "&amp;").replace(/</g, "&lt;");
    return [
      `${mk("#")} ${esc(d.h1)}`,
      "",
      `${esc(d.p[0])}${mk("**")}${esc(d.p[1])}${mk("**")}${esc(d.p[2])}`,
      "",
      `${mk("- [x]")} ${esc(d.checks[0])}`,
      `${mk("- [ ]")} ${esc(d.checks[1])}`,
      "",
      `${mk("&gt;")} ${esc(d.quote)}`,
    ].join("\n");
  }

  function reset() {
    const d = DEMO[lang];
    docEl.innerHTML = "";
    rawEl.classList.remove("on");
    $(".win").classList.remove("split");
    savedEl.classList.remove("on");
    pointer.classList.remove("on");
    $("#winTitle").textContent = d.file;
    $("#rawTitle").textContent = d.file;
    $("#rawText").innerHTML = rawMarkdown(d);
    barEl.style.transition = "none";
    barEl.style.width = "0";
    setTools();
    capEl.innerHTML = "";
  }

  async function play() {
    const d = DEMO[lang];
    const N = 6;
    reset();
    await sleep(700);

    caption("cap.1", 1, N);
    newBlock("p");
    await type("# ");
    await sleep(350);
    morph("h1");
    setTools({ head: "H1" });
    await type(d.h1);
    await sleep(900);

    caption("cap.2", 2, N);
    newBlock("p");
    setTools();
    await type(d.p[0]);
    await type("**" + d.p[1] + "**");
    await sleep(300);
    boldify(d.p[1]);
    setTools({ bold: true });
    await sleep(900);
    setTools();
    await type(d.p[2]);
    await sleep(800);

    caption("cap.3", 3, N);
    newBlock("p");
    await type("[] ");
    await sleep(350);
    morph("check");
    setTools({ check: true });
    const first = cur.el;
    await type(d.checks[0]);
    await sleep(400);
    newBlock("check");
    await type(d.checks[1]);
    await sleep(700);

    caption("cap.4", 4, N);
    await clickBox(first);
    await sleep(600);

    caption("cap.5", 5, N);
    newBlock("p");
    setTools();
    await type("> ");
    await sleep(350);
    morph("quote");
    setTools({ quote: true });
    await type(d.quote);
    await sleep(900);

    caption("cap.6", 6, N);
    caret.remove();
    savedEl.classList.add("on");
    await sleep(700);
    $(".win").classList.add("split");
    await sleep(300);
    rawEl.classList.add("on");
    await sleep(6000);
    docEl.style.transition = "opacity .5s";
    docEl.style.opacity = "0";
    rawEl.classList.remove("on");
    await sleep(600);
    $(".win").classList.remove("split");
    docEl.style.opacity = "";
  }

  // Static final frame for visitors who prefer less motion.
  function renderFinal() {
    const d = DEMO[lang];
    reset();
    newBlock("h1"); cur.node.data = d.h1;
    newBlock("p");
    cur.txt.replaceChildren(d.p[0], Object.assign(document.createElement("strong"), { textContent: d.p[1] }), d.p[2]);
    newBlock("check"); cur.node.data = d.checks[0]; cur.el.classList.add("done");
    newBlock("check"); cur.node.data = d.checks[1];
    newBlock("quote"); cur.node.data = d.quote;
    caret.remove();
    savedEl.classList.add("on");
    capEl.innerHTML = `<span>${T[lang]["cap.6"]}</span>`;
    barEl.style.width = "100%";
  }

  async function loop(id) {
    while (id === runId) {
      try { await play(); } catch (e) { if (e === STOP) return; throw e; }
    }
  }

  function restart() {
    runId++;
    if (reduced) { renderFinal(); return; }
    paused = false;
    updatePlayLabel();
    loop(runId);
  }

  function updatePlayLabel() {
    playBtn.classList.toggle("paused", paused);
    playBtn.setAttribute("aria-label", T[lang][paused ? "aria.play" : "aria.pause"]);
  }

  playBtn.addEventListener("click", () => {
    if (reduced) { reducedPlayOnce(); return; }
    paused = !paused;
    updatePlayLabel();
  });
  $("#replayBtn").addEventListener("click", () => { if (reduced) reducedPlayOnce(); else restart(); });

  // With reduced motion, the player buttons still let a visitor watch it on request.
  function reducedPlayOnce() {
    runId++;
    const id = runId;
    play().catch(() => {}).then(() => { if (id === runId) renderFinal(); });
  }

  // Pause the animation while the demo is off screen.
  new IntersectionObserver((entries) => { visible = entries[0].isIntersecting; }, { threshold: 0.1 }).observe($("#stage"));

  applyLang();
  restart();
})();
