#!/bin/bash
# แม่แบบ: สร้าง build/<App>.app (เซ็นด้วยตัวตนคงที่ถ้ามี ไม่งั้น ad-hoc) + build/<App>.zip สำหรับแจกทีม รันซ้ำได้
# ค่า: Jotdown (ชื่อที่ผู้ใช้เห็น + executable target), com.euw.jotdown, __DOC_EXT__ (ถ้ามีไฟล์เอกสารของแอป)
#   ./build-app.sh            ทั้งหมด
#   SKIP_ZIP=1 ./build-app.sh ข้าม zip
set -euo pipefail
cd "$(dirname "$0")"
ROOT="$PWD"
APP_NAME="Jotdown"
EXEC="Jotdown"
BUNDLE_ID="com.euw.jotdown"
APP="$ROOT/build/$APP_NAME.app"
VERSION="${APP_VERSION:-0.1.0}"

echo "== swift build -c release"
swift build -c release
BIN="$(swift build -c release --show-bin-path)/$EXEC"

echo "== assemble $APP"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/$EXEC"
# ของที่ต้องฝังในแอป (ไบนารีช่วย, สคริปต์, asset) คัดลอกไป Contents/Resources ที่นี่
# ไฟล์ที่โหลดจากเน็ต: ปักเวอร์ชัน + ตรวจ sha256 กับค่าที่ปักไว้ในสคริปต์ และเก็บใน .cache/

# ฟอนต์ที่ฝังในแอป (ลงทะเบียนตอนเปิดแอป + ATSApplicationFontsPath)
mkdir -p "$APP/Contents/Resources/Fonts"
cp "$ROOT"/Resources/Fonts/* "$APP/Contents/Resources/Fonts/"

# ไอคอน: Jotdown.iconset/ ที่ Euw ออกแบบเอง (ที่ราก repo)
#   ปรับขนาดให้เท่าไอคอน Mac อื่น (รูปทรง 824/1024 วางกลาง) ด้วย scripts/fit-icon.swift ไม่แก้ไฟล์ต้นฉบับ
ICONSET="$ROOT/build/app.iconset"
rm -rf "$ICONSET"
swift "$ROOT/scripts/fit-icon.swift" "$ROOT/Jotdown.iconset/icon_512x512@2x.png" "$ICONSET"
iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/AppIcon.icns"
cp "$ICONSET/icon_512x512@2x.png" "$ROOT/build/icon-1024.png"

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleIdentifier</key><string>$BUNDLE_ID</string>
  <key>CFBundleName</key><string>$APP_NAME</string>
  <key>CFBundleDisplayName</key><string>$APP_NAME</string>
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>CFBundleIconName</key><string>AppIcon</string>
  <key>CFBundleExecutable</key><string>$EXEC</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>$VERSION</string>
  <key>CFBundleVersion</key><string>$VERSION</string>
  <key>LSMinimumSystemVersion</key><string>14.0</string>
  <key>NSHighResolutionCapable</key><true/>
  <key>NSPrincipalClass</key><string>NSApplication</string>
  <key>CFBundleDevelopmentRegion</key><string>en</string>
  <key>CFBundleLocalizations</key><array><string>en</string></array>
  <key>ATSApplicationFontsPath</key><string>Fonts</string>
  <key>NSSupportsAutomaticTermination</key><false/>
  <key>NSSupportsSuddenTermination</key><false/>
  <key>CFBundleDocumentTypes</key>
  <array>
    <dict>
      <key>CFBundleTypeName</key><string>Markdown</string>
      <key>CFBundleTypeRole</key><string>Editor</string>
      <key>LSHandlerRank</key><string>Alternate</string>
      <key>LSItemContentTypes</key><array><string>net.daringfireball.markdown</string></array>
      <key>CFBundleTypeExtensions</key><array><string>md</string><string>markdown</string></array>
      <key>NSDocumentClass</key><string>JotdownDocument</string>
    </dict>
  </array>
  <key>UTImportedTypeDeclarations</key>
  <array>
    <dict>
      <key>UTTypeIdentifier</key><string>net.daringfireball.markdown</string>
      <key>UTTypeDescription</key><string>Markdown</string>
      <key>UTTypeConformsTo</key><array><string>public.plain-text</string></array>
      <key>UTTypeTagSpecification</key>
      <dict>
        <key>public.filename-extension</key><array><string>md</string><string>markdown</string></array>
        <key>public.mime-type</key><array><string>text/markdown</string></array>
      </dict>
    </dict>
  </array>
</dict>
</plist>
PLIST

# เซ็นด้วยตัวตนคงที่ (./make-signing-cert.sh) เพื่อให้ Keychain ไม่ถามซ้ำทุก build
SIGN_CN="${SIGNING_CN:-$APP_NAME Local Signing}"
SIGN_HASH="$(security find-identity -p codesigning ${KEYCHAIN:+"$KEYCHAIN"} 2>/dev/null | awk -v cn="\"$SIGN_CN\"" 'index($0, cn) {print $2; exit}')"
sign_stable() {
  # self-signed ไม่อยู่ใน chain ที่ trust -> designated requirement ปกติเป็น cdhash (เปลี่ยนทุก build)
  # จึงกำหนดเองให้อิง identifier + SHA-1 ของใบรับรอง ซึ่งคงที่ข้าม build
  # ไบนารีช่วยใน Resources ต้องเซ็นแยกก่อน (identifier ของตัวเอง) แล้วค่อยเซ็นแอป
  codesign --force ${KEYCHAIN:+--keychain "$KEYCHAIN"} --sign "$SIGN_HASH" --identifier "$BUNDLE_ID" \
    -r="designated => identifier \"$BUNDLE_ID\" and certificate leaf = H\"$SIGN_HASH\"" "$APP"
}
SIGNED=0
if [ -n "$SIGN_HASH" ]; then
  echo "== codesign ($SIGN_CN)"
  if sign_stable; then SIGNED=1; else echo "   เซ็นด้วยตัวตนคงที่ไม่สำเร็จ ใช้ ad-hoc แทน"; fi
fi
if [ $SIGNED = 0 ]; then
  echo "== codesign (ad-hoc)"
  [ -n "$SIGN_HASH" ] || echo "   คำใบ้: รัน ./make-signing-cert.sh ครั้งเดียว เพื่อให้ Keychain ไม่ถามรหัสผ่านซ้ำทุกครั้งที่ build"
  codesign --force --deep --sign - "$APP"
fi
codesign --verify --deep --strict "$APP"

if [ "${SKIP_ZIP:-0}" != 1 ]; then
  echo "== zip"
  ZIP="$ROOT/build/${APP_NAME// /-}.zip"
  rm -f "$ZIP"
  ditto -c -k --keepParent "$APP" "$ZIP"
  ls -lh "$ZIP"
fi
echo "== เสร็จ: $APP"
