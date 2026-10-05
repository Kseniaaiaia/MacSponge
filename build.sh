#!/bin/bash
# Builds CleanMac.app into ./build
set -euo pipefail
cd "$(dirname "$0")"
swift build -c release
APP=build/CleanMac.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp .build/release/CleanMac "$APP/Contents/MacOS/CleanMac"
[ -f Resources/AppIcon.icns ] && cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleName</key><string>CleanMac</string>
  <key>CFBundleDisplayName</key><string>CleanMac</string>
  <key>CFBundleIdentifier</key><string>local.cleanmac.app</string>
  <key>CFBundleExecutable</key><string>CleanMac</string>
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>1.0</string>
  <key>CFBundleVersion</key><string>1</string>
  <key>LSMinimumSystemVersion</key><string>14.0</string>
  <key>NSHighResolutionCapable</key><true/>
</dict></plist>
PLIST
# A stable signing identity keeps macOS privacy grants (Full Disk Access) across rebuilds;
# ad-hoc signing ("-") changes the identity every build and the grant is lost.
IDENTITY="${SIGN_IDENTITY:-$(security find-identity -v -p codesigning | sed -n 's/.*"\(Apple Development:[^"]*\)".*/\1/p' | head -1)}"
codesign --force --sign "${IDENTITY:--}" "$APP"
echo "Built $APP"
