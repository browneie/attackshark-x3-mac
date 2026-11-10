#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
swift build -c release
APP="dist/X3 Config.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
swift scripts/make-icon.swift dist/AppIcon.icns
iconutil -c icns dist/AppIcon.iconset -o "$APP/Contents/Resources/AppIcon.icns"
rm -rf dist/AppIcon.iconset
cp .build/release/X3Config "$APP/Contents/MacOS/X3Config"
cp .build/release/x3ctl dist/x3ctl
cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key><string>X3 Config</string>
  <key>CFBundleIdentifier</key><string>local.attackshark.x3config</string>
  <key>CFBundleExecutable</key><string>X3Config</string>
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>0.1</string>
  <key>LSMinimumSystemVersion</key><string>14.0</string>
  <key>NSHighResolutionCapable</key><true/>
</dict>
</plist>
PLIST
codesign --force --sign - "$APP" dist/x3ctl
echo "built $APP and dist/x3ctl"
