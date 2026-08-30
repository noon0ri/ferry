#!/bin/bash
set -euo pipefail

APP_NAME="Ferry"
BUNDLE_ID="dev.noon0ri.ferry"
VERSION="0.1.1"

cd "$(dirname "$0")/.."

# Intel과 Apple Silicon 모두에서 돌도록 유니버설로 빌드한다.
# 다른 Mac에 그냥 복사해서 쓰는 것이 이 앱의 주된 배포 방식이라, 아키텍처를 가리면
# 받는 쪽에서 "손상되었다"는 모호한 오류만 보게 된다.
swift build -c release --arch arm64 --arch x86_64
BUILD_DIR=".build/apple/Products/Release"

APP="build/${APP_NAME}.app"
rm -rf "$APP"
mkdir -p "${APP}/Contents/MacOS" "${APP}/Contents/Resources"

cp "${BUILD_DIR}/FerryApp" "${APP}/Contents/MacOS/${APP_NAME}"

# SwiftPM이 만든 리소스 번들(로컬라이즈 문자열)을 함께 넣는다.
# 이게 빠지면 Bundle.module이 문자열을 찾지 못해 UI에 키가 그대로 노출된다.
for res in "${BUILD_DIR}"/*.bundle; do
    [ -e "$res" ] || continue
    cp -R "$res" "${APP}/Contents/Resources/"
done

# Icon Composer로 만든 icon.icon을 컴파일한다.
# actool은 두 가지를 내놓는다 — macOS 26의 레이어드 렌더링용 Assets.car와,
# 그 이전 버전이 읽는 고전 icon.icns. 둘 다 넣어야 macOS 14~26을 모두 커버한다.
ICON_KEYS=""
if [ -d "icon.icon" ]; then
    ICON_TMP="$(mktemp -d)"
    xcrun actool icon.icon \
        --compile "${ICON_TMP}" \
        --platform macosx \
        --minimum-deployment-target 14.0 \
        --app-icon icon \
        --output-partial-info-plist "${ICON_TMP}/partial.plist" >/dev/null

    cp "${ICON_TMP}/Assets.car" "${APP}/Contents/Resources/" 2>/dev/null || true
    cp "${ICON_TMP}/icon.icns" "${APP}/Contents/Resources/" 2>/dev/null || true
    rm -rf "${ICON_TMP}"

    ICON_KEYS="    <key>CFBundleIconFile</key>          <string>icon</string>
    <key>CFBundleIconName</key>          <string>icon</string>"
else
    echo "경고: icon.icon 이 없어 기본 아이콘으로 빌드합니다."
fi

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
${ICON_KEYS}
    <key>CFBundleDevelopmentRegion</key>  <string>en</string>
    <key>CFBundleLocalizations</key>
    <array>
        <string>en</string>
        <string>ko</string>
    </array>
    <key>NSAppleEventsUsageDescription</key>
    <string>세션을 재개할 때 Terminal.app에 명령을 전달하기 위해 필요합니다.</string>
</dict>
</plist>
PLIST

codesign --force --deep --sign - "$APP" 2>/dev/null || \
    echo "경고: 코드 서명 실패. 자동화 권한이 매번 초기화될 수 있습니다."

echo "완료: ${APP}"
