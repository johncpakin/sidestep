#!/usr/bin/env bash
# Builds Sidestep.app (menu-bar only, no Dock icon) from the SwiftPM target.
set -euo pipefail
cd "$(dirname "$0")/.."
swift build -c release 2>&1 | tail -3; [ -x .build/release/Sidestep ] && [ .build/release/Sidestep -nt Package.swift ] || { echo "BUILD FAILED"; exit 1; }
APP=build/Sidestep.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp .build/release/Sidestep "$APP/Contents/MacOS/Sidestep"
cp -R Sources/Sidestep/Resources/Fonts "$APP/Contents/Resources/Fonts"
cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleName</key><string>Sidestep</string>
  <key>CFBundleDisplayName</key><string>Sidestep</string>
  <key>CFBundleIdentifier</key><string>io.mentatix.sidestep</string>
  <key>CFBundleVersion</key><string>1</string>
  <key>CFBundleShortVersionString</key><string>0.1</string>
  <key>CFBundleExecutable</key><string>Sidestep</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>LSMinimumSystemVersion</key><string>14.0</string>
  <key>LSUIElement</key><true/>
  <key>NSHighResolutionCapable</key><true/>
</dict></plist>
PLIST
codesign --force --sign - "$APP" >/dev/null 2>&1 || true
echo "built $APP"
if [[ "${1:-}" == "--install" ]]; then
  rm -rf /Applications/Sidestep.app
  cp -R "$APP" /Applications/Sidestep.app
  echo "installed /Applications/Sidestep.app"
fi
