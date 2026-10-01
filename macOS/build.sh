#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"
DIST="$PWD/dist"
APP="$DIST/ihatemeetings.app"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
for arch in arm64 x86_64; do
  xcrun swiftc -swift-version 5 -O -whole-module-optimization -target "${arch}-apple-macos12.0" -framework AppKit -framework Carbon -framework Foundation source/main.swift source/Timing.swift -o "$DIST/ihatemeetings-$arch"
done
lipo -create "$DIST/ihatemeetings-arm64" "$DIST/ihatemeetings-x86_64" -output "$APP/Contents/MacOS/ihatemeetings"
cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleExecutable</key><string>ihatemeetings</string>
<key>CFBundleIdentifier</key><string>local.ihatemeetings.app</string>
<key>CFBundleName</key><string>ihatemeetings</string>
<key>CFBundleDisplayName</key><string>ihatemeetings</string>
<key>CFBundleShortVersionString</key><string>1.4</string>
<key>CFBundleVersion</key><string>1.4.0</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>NSHighResolutionCapable</key><true/>
<key>LSMinimumSystemVersion</key><string>12.0</string>
<key>CFBundleIconFile</key><string>AppIcon</string>
</dict></plist>
PLIST
ICONSET="$DIST/AppIcon.iconset"
mkdir -p "$ICONSET"
for spec in "16 16x16" "32 16x16@2x" "32 32x32" "64 32x32@2x" "128 128x128" "256 128x128@2x" "256 256x256" "512 256x256@2x" "512 512x512" "1024 512x512@2x"; do
 read -r px name <<< "$spec"
 sips -z "$px" "$px" resources/AppIcon.png --out "$ICONSET/icon_${name}.png" >/dev/null
done
iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/AppIcon.icns"
codesign --force --deep --sign - "$APP"
codesign --verify --deep --strict "$APP"
STAGE=$(mktemp -d "$DIST/dmg-stage.XXXXXX")
trap 'rm -rf "$STAGE"' EXIT
cp -R "$APP" "$STAGE/"
cp README.txt "$STAGE/READ-ME.txt"
ln -s /Applications "$STAGE/Applications"
hdiutil create -volname "ihatemeetings 1.4" -srcfolder "$STAGE" -ov -format UDZO "$DIST/ihatemeetings-1.4-macOS-universal.dmg"
hdiutil verify "$DIST/ihatemeetings-1.4-macOS-universal.dmg"
ditto -c -k --keepParent "$APP" "$DIST/ihatemeetings-1.4-macOS-app.zip"
