#!/bin/bash
# สร้างใบรับรอง code-signing แบบ self-signed ครั้งเดียว เพื่อให้ build-app.sh เซ็นแอปด้วยตัวตนเดิมทุกครั้ง
# ผลคือ Keychain ไม่ถามรหัสผ่านซ้ำทุกครั้งที่ build ใหม่ (ไม่ต้องกด Always Allow ซ้ำ)
#   ./make-signing-cert.sh              ใส่ใน login keychain ของเครื่องนี้
#   KEYCHAIN=/path/x.keychain-db ./make-signing-cert.sh   (ใช้ทดสอบกับ keychain ชั่วคราว)
# รันซ้ำได้ ถ้ามีตัวตนอยู่แล้วจะบอกแล้วจบ
set -euo pipefail

CN="${SIGNING_CN:-Jotdown Local Signing}"
KC="${KEYCHAIN:-$HOME/Library/Keychains/login.keychain-db}"

if security find-identity -p codesigning "$KC" 2>/dev/null | grep -q "\"$CN\""; then
  echo "มีตัวตน \"$CN\" ใน keychain แล้ว ไม่ต้องทำอะไร"
  exit 0
fi

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
cat > "$TMP/openssl.cnf" <<CNF
[req]
distinguished_name = dn
x509_extensions = ext
prompt = no
[dn]
CN = $CN
[ext]
basicConstraints = critical,CA:false
keyUsage = critical,digitalSignature
extendedKeyUsage = critical,codeSigning
CNF

openssl req -x509 -newkey rsa:2048 -nodes -days 3650 -config "$TMP/openssl.cnf" \
  -keyout "$TMP/priv.pem" -out "$TMP/cert.pem" 2>/dev/null
P12PASS="$(openssl rand -hex 12)"
# -legacy: security ของ macOS อ่าน PKCS12 แบบ OpenSSL 3 ใหม่ไม่ได้ (openssl รุ่นที่ไม่มี flag นี้ใช้แบบปกติ)
if ! openssl pkcs12 -export -legacy -inkey "$TMP/priv.pem" -in "$TMP/cert.pem" -name "$CN" \
     -passout "pass:$P12PASS" -out "$TMP/id.p12" 2>/dev/null; then
  openssl pkcs12 -export -inkey "$TMP/priv.pem" -in "$TMP/cert.pem" -name "$CN" \
     -passout "pass:$P12PASS" -out "$TMP/id.p12"
fi

security import "$TMP/id.p12" -k "$KC" -P "$P12PASS" -T /usr/bin/codesign >/dev/null

# codesign ใช้ตัวตน self-signed ได้ก็ต่อเมื่อเชื่อถือใบรับรองสำหรับ code signing (macOS จะขอรหัสผ่านเครื่อง 1 ครั้ง)
echo "macOS จะขอรหัสผ่านเครื่องเพื่อตั้งค่าให้เชื่อถือใบรับรองนี้เฉพาะงาน code signing (เฉพาะผู้ใช้นี้)"
if ! security add-trusted-cert -r trustRoot -p codeSign -k "$KC" "$TMP/cert.pem"; then
  echo "ตั้งค่าเชื่อถือใบรับรองไม่สำเร็จ: ลองใหม่ด้วยมือ เปิด Keychain Access > ใบรับรอง \"$CN\" > Trust > Code Signing = Always Trust"
fi

cat <<MSG

สร้างตัวตน "$CN" แล้ว (อายุ 10 ปี) ใน keychain: $KC

ขั้นต่อไป
  1. รัน ./build-app.sh ตามปกติ มันจะเซ็นแอปด้วยตัวตนนี้เอง
  2. ถ้า macOS ถามว่า codesign ขอใช้กุญแจ ให้ใส่รหัสผ่านแล้วกด Always Allow
  3. build และเปิดแอปครั้งแรกหลังจากนี้ Keychain จะถามรหัสผ่านอีกครั้งสุดท้าย (กด Always Allow)
     หลังจากนั้น build ใหม่กี่ครั้งก็ไม่ถามซ้ำ ตราบใดที่ใช้ตัวตนเดิม
  4. ใบรับรองนี้ระบบไม่ได้ "เชื่อถือ" (ไม่จำเป็น) ใช้เพื่อให้ลายเซ็นคงที่เท่านั้น ไม่ใช่สำหรับแจกจ่ายสาธารณะ
MSG
