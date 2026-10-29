#!/bin/bash
# รัน swift test ให้ใช้ได้กับ Command Line Tools อย่างเดียว (ไม่มี Xcode)
# CLT เก็บ Testing.framework ไว้ที่ path นี้ แต่ SwiftPM ไม่ส่งให้ compiler/linker เอง
# ทดสอบที่ต้องใช้เน็ต/API จริง: ปิดไว้หลัง env flag เช่น APP_RUN_INTEGRATION=1 APP_HOME=$(mktemp -d) ./test.sh
set -euo pipefail
export JOTDOWN_TESTING=1
cd "$(dirname "$0")"
CLT=/Library/Developer/CommandLineTools/Library/Developer
if [ -d /Applications/Xcode.app ] || [ ! -d "$CLT/Frameworks/Testing.framework" ]; then
  exec swift test "$@"
fi
exec swift test -Xswiftc -F -Xswiftc "$CLT/Frameworks" \
  -Xlinker -rpath -Xlinker "$CLT/Frameworks" -Xlinker -rpath -Xlinker "$CLT/usr/lib" "$@"
