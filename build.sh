#!/bin/bash
# Builds MacSponge.app into ./build
set -euo pipefail
cd "$(dirname "$0")"
swift build -c release
APP=build/MacSponge.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp .build/release/MacSponge "$APP/Contents/MacOS/MacSponge"
[ -f Resources/AppIcon.icns ] && cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
[ -f Resources/mascot.png ] && cp Resources/mascot.png "$APP/Contents/Resources/mascot.png"
# Rive animation(s): any Resources/*.riv is bundled and played by MascotView
for f in Resources/*.riv; do [ -f "$f" ] && cp "$f" "$APP/Contents/Resources/"; done
# RiveRuntime is a dynamic framework: embed it and let the executable find it
mkdir -p "$APP/Contents/Frameworks"
cp -R .build/artifacts/rive-ios/RiveRuntime/RiveRuntime.xcframework/macos-arm64_x86_64/RiveRuntime.framework "$APP/Contents/Frameworks/"
install_name_tool -add_rpath "@executable_path/../Frameworks" "$APP/Contents/MacOS/MacSponge" 2>/dev/null || true
cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleName</key><string>MacSponge</string>
  <key>CFBundleDisplayName</key><string>MacSponge</string>
  <key>CFBundleIdentifier</key><string>local.macsponge.app</string>
  <key>CFBundleExecutable</key><string>MacSponge</string>
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>1.0</string>
  <key>CFBundleVersion</key><string>1</string>
  <key>LSMinimumSystemVersion</key><string>14.0</string>
  <key>NSHighResolutionCapable</key><true/>
  <key>NSAppleEventsUsageDescription</key><string>MacSponge asks Finder to move protected apps to the Trash.</string>
</dict></plist>
PLIST
# A stable signing identity keeps macOS privacy grants (Full Disk Access) across rebuilds;
# ad-hoc signing ("-") changes the identity every build and the grant is lost.
IDENTITY="${SIGN_IDENTITY:-$(security find-identity -v -p codesigning | sed -n 's/.*"\(Apple Development:[^"]*\)".*/\1/p' | head -1)}"
codesign --force --sign "${IDENTITY:--}" "$APP/Contents/Frameworks/RiveRuntime.framework"
codesign --force --sign "${IDENTITY:--}" "$APP"
echo "Built $APP"
