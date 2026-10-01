#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"
ROOT="$PWD"
SRC="$ROOT/source/main.swift"
DIST="$ROOT/dist"
APP="$DIST/NetToggle.app"
DMG="$DIST/NetToggle-1.3-macOS.dmg"
ICON_PNG="$ROOT/resources/AppIcon.png"

fail(){ echo; echo "ERROR: $*"; echo; read -r -p "Press Return to close..." _ || true; exit 1; }
command -v xcrun >/dev/null 2>&1 || { xcode-select --install >/dev/null 2>&1 || true; fail "Apple Command Line Tools are required. Finish their installer, then run this file again."; }
xcrun --find swiftc >/dev/null 2>&1 || fail "swiftc was not found in the active Apple developer tools."

rm -rf "$DIST"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

echo "Compiling NetToggle..."
xcrun swiftc -O -whole-module-optimization \
  -framework AppKit -framework Carbon -framework Foundation \
  "$SRC" -o "$APP/Contents/MacOS/NetToggle"

cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleExecutable</key><string>NetToggle</string>
<key>CFBundleIdentifier</key><string>local.nettoggle.app</string>
<key>CFBundleName</key><string>NetToggle</string>
<key>CFBundleDisplayName</key><string>NetToggle</string>
<key>CFBundleShortVersionString</key><string>1.3</string>
<key>CFBundleVersion</key><string>1.3.0</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>NSHighResolutionCapable</key><true/>
<key>LSMinimumSystemVersion</key><string>12.0</string>
<key>CFBundleIconFile</key><string>AppIcon</string>
</dict></plist>
PLIST

if [[ -f "$ICON_PNG" ]]; then
  ICONSET="$DIST/AppIcon.iconset"; mkdir -p "$ICONSET"
  for spec in "16 16x16" "32 16x16@2x" "32 32x32" "64 32x32@2x" "128 128x128" "256 128x128@2x" "256 256x256" "512 256x256@2x" "512 512x512" "1024 512x512@2x"; do
    read -r px name <<<"$spec"; /usr/bin/sips -z "$px" "$px" "$ICON_PNG" --out "$ICONSET/icon_${name}.png" >/dev/null
  done
  /usr/bin/iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/AppIcon.icns"
  rm -rf "$ICONSET"
fi

/usr/bin/codesign --force --deep --sign - "$APP"
mkdir -p "$DIST/dmg-root"
cp -R "$APP" "$DIST/dmg-root/"
ln -s /Applications "$DIST/dmg-root/Applications"
rm -f "$DMG"
/usr/bin/hdiutil create -volname "NetToggle 1.3" -srcfolder "$DIST/dmg-root" -ov -format UDZO "$DMG" >/dev/null
rm -rf "$DIST/dmg-root"

HASH=$(/usr/bin/shasum -a 256 "$DMG" | awk '{print $1}')
echo
echo "SUCCESS"
echo "App: $APP"
echo "DMG: $DMG"
echo "SHA256: $HASH"
echo
echo "Installing to /Applications..."
DEST="/Applications/NetToggle.app"
if [[ -w /Applications ]]; then
  rm -rf "$DEST"; cp -R "$APP" "$DEST"
else
  /usr/bin/osascript -e "do shell script \"rm -rf '$DEST' && cp -R '$APP' '$DEST'\" with administrator privileges" || fail "Could not copy to /Applications."
fi
/usr/bin/xattr -dr com.apple.quarantine "$DEST" 2>/dev/null || true
echo "Installed: $DEST"
/usr/bin/open "$DEST" || true
echo
read -r -p "Press Return to close..." _ || true
