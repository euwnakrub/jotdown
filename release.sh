#!/bin/bash
# ออก release ใหม่บน GitHub (แอปที่ติดตั้งแล้วจะเห็นและอัปเดตเองภายใน 1 วัน หรือกด Check for Updates…)
#   ./release.sh                 ใช้เลขใน VERSION
#   ./release.sh 0.3.1           ตั้ง VERSION ใหม่ก่อน (ต้องมากกว่า release ล่าสุด)
#   NOTES="แก้บั๊ก…" ./release.sh   ข้อความที่ผู้ใช้เห็นในหน้าต่างอัปเดต (ไม่ใส่ = ใช้รายการ commit จาก GitHub)
set -euo pipefail
cd "$(dirname "$0")"
[ $# -ge 1 ] && echo "$1" > VERSION
V="$(tr -d '[:space:]' < VERSION)"
TAG="v$V"
if gh release view "$TAG" >/dev/null 2>&1; then echo "มี release $TAG แล้ว: เปลี่ยนเลขใน VERSION"; exit 1; fi
if [ -n "$(git status --porcelain)" ]; then echo "มีไฟล์ที่ยังไม่ commit: commit ก่อน (รวม VERSION)"; exit 1; fi
./test.sh
./build-app.sh
git push origin HEAD
if [ -n "${NOTES:-}" ]; then
  gh release create "$TAG" build/Jotdown.zip --title "Jotdown $V" --notes "$NOTES"
else
  gh release create "$TAG" build/Jotdown.zip --title "Jotdown $V" --generate-notes
fi
echo "== ออก $TAG แล้ว"
