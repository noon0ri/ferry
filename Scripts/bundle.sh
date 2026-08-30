#!/bin/bash
set -euo pipefail

APP_NAME="Ferry"
BUNDLE_ID="dev.seongbin.ferry"
VERSION="0.1.0"

cd "$(dirname "$0")/.."
swift build -c release

APP="build/${APP_NAME}.app"
rm -rf "$APP"
mkdir -p "${APP}/Contents/MacOS" "${APP}/Contents/Resources"

cp ".build/release/FerryApp" "${APP}/Contents/MacOS/${APP_NAME}"

cat > "${APP}/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key>              <string>${APP_NAME}</string>
    <key>CFBundleDisplayName</key>       <string>${APP_NAME}</string>
    <key>CFBundleIdentifier</key>        <string>${BUNDLE_ID}</string>
    <key>CFBundleExecutable</key>        <string>${APP_NAME}</string>
    <key>CFBundlePackageType</key>       <string>APPL</string>
    <key>CFBundleShortVersionString</key><string>${VERSION}</string>
    <key>CFBundleVersion</key>           <string>${VERSION}</string>
    <key>LSMinimumSystemVersion</key>    <string>14.0</string>
    <key>LSUIElement</key>               <true/>
    <key>NSAppleEventsUsageDescription</key>
    <string>세션을 재개할 때 Terminal.app에 명령을 전달하기 위해 필요합니다.</string>
</dict>
</plist>
PLIST

codesign --force --deep --sign - "$APP" 2>/dev/null || \
    echo "경고: 코드 서명 실패. 자동화 권한이 매번 초기화될 수 있습니다."

echo "완료: ${APP}"
