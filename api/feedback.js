// POST /api/feedback — รับ feedback จากแอป Jotdown แล้วส่งอีเมลถึงผู้พัฒนาผ่าน Resend (resend.com)
// ตั้งค่าใน Vercel (Project → Settings → Environment Variables):
//   RESEND_API_KEY  จำเป็น
//   FEEDBACK_TO     ไม่บังคับ (ค่าเริ่มต้นด้านล่าง)
//   FEEDBACK_FROM   ไม่บังคับ ใช้ได้เมื่อยืนยันโดเมนใน Resend แล้ว
const TO = process.env.FEEDBACK_TO || 'euwnakrub@gmail.com';
const FROM = process.env.FEEDBACK_FROM || 'Jotdown Feedback <onboarding@resend.dev>';
const EMAIL_RE = /^[^@\s]+@[^@\s]+\.[^@\s]+$/;

// กันยิงรัว ๆ แบบง่าย (ต่อ instance): 5 ข้อความต่อ IP ต่อ 10 นาที
const hits = new Map();
function limited(ip) {
  const now = Date.now();
  const recent = (hits.get(ip) || []).filter((t) => now - t < 10 * 60 * 1000);
  recent.push(now);
  hits.set(ip, recent);
  return recent.length > 5;
}

const short = (v, n) => String(v ?? '').replace(/[\r\n]+/g, ' ').trim().slice(0, n);

module.exports = async function handler(req, res) {
  if (req.method !== 'POST') return res.status(405).json({ error: 'method' });
  if (req.headers['x-jotdown-client'] !== 'mac') return res.status(400).json({ error: 'client' });

  let body = req.body;
  if (typeof body === 'string') { try { body = JSON.parse(body); } catch { body = null; } }
  if (!body || typeof body !== 'object') return res.status(400).json({ error: 'body' });

  const message = String(body.message ?? '').trim();
  const email = short(body.email, 200);
  if (!message || message.length > 10000) return res.status(400).json({ error: 'message' });
  if (email && !EMAIL_RE.test(email)) return res.status(400).json({ error: 'email' });

  const ip = String(req.headers['x-forwarded-for'] || '').split(',')[0].trim() || 'unknown';
  if (limited(ip)) return res.status(429).json({ error: 'rate' });

  const key = process.env.RESEND_API_KEY;
  if (!key) return res.status(503).json({ error: 'not configured' });

  const appVersion = short(body.appVersion, 40) || '?';
  const osVersion = short(body.osVersion, 40) || '?';
  const model = short(body.model, 60) || '?';
  const text = [
    message,
    '',
    '—',
    `From: ${email || '(no email given)'}`,
    `Jotdown ${appVersion} · macOS ${osVersion} · ${model}`,
  ].join('\n');

  const r = await fetch('https://api.resend.com/emails', {
    method: 'POST',
    headers: { Authorization: `Bearer ${key}`, 'Content-Type': 'application/json' },
    body: JSON.stringify({
      from: FROM,
      to: [TO],
      subject: `Jotdown feedback (${appVersion}): ${short(message, 60)}`,
      text,
      ...(email ? { reply_to: email } : {}),
    }),
  });
  if (!r.ok) {
    console.error('resend failed', r.status, await r.text().catch(() => ''));
    return res.status(502).json({ error: 'send' });
  }
  return res.status(200).json({ ok: true });
};
