#!/usr/bin/env bash
#
# Build Claude Reset Tracker as a macOS .app bundle.
# Usage:
#   ./build.sh              -> builds ./build/Claude Reset Tracker.app
#   ./build.sh --install    -> also copies the .app into /Applications

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
APP_NAME="Claude Reset Tracker"
EXE_NAME="ClaudeResetTracker"
BUNDLE_ID="com.mustaphography.ClaudeResetTracker"
VERSION="1.0.0"
BUILD_DIR="$ROOT/build"
APP_DIR="$BUILD_DIR/$APP_NAME.app"

echo "==> Compiling release binary"
cd "$ROOT"
swift build -c release

echo "==> Assembling app bundle at $APP_DIR"
rm -rf "$APP_DIR"
mkdir -p "$APP_DIR/Contents/MacOS"
mkdir -p "$APP_DIR/Contents/Resources"

BIN_PATH="$(swift build -c release --show-bin-path)"
cp "$BIN_PATH/$EXE_NAME" "$APP_DIR/Contents/MacOS/$EXE_NAME"
chmod +x "$APP_DIR/Contents/MacOS/$EXE_NAME"

cat > "$APP_DIR/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDevelopmentRegion</key>
    <string>en</string>
    <key>CFBundleExecutable</key>
    <string>$EXE_NAME</string>
    <key>CFBundleIdentifier</key>
    <string>$BUNDLE_ID</string>
    <key>CFBundleInfoDictionaryVersion</key>
    <string>6.0</string>
    <key>CFBundleName</key>
    <string>$APP_NAME</string>
    <key>CFBundleDisplayName</key>
    <string>$APP_NAME</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>$VERSION</string>
    <key>CFBundleVersion</key>
    <string>$VERSION</string>
    <key>LSMinimumSystemVersion</key>
    <string>13.0</string>
    <key>LSUIElement</key>
    <true/>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>NSSupportsAutomaticTermination</key>
    <true/>
    <key>NSSupportsSuddenTermination</key>
    <true/>
</dict>
</plist>
PLIST

# Ad-hoc sign so Gatekeeper lets it run without "damaged app" errors.
codesign --force --deep --sign - "$APP_DIR" >/dev/null 2>&1 || true

echo "==> Built: $APP_DIR"

if [[ "${1:-}" == "--install" ]]; then
    DEST="/Applications/$APP_NAME.app"
    echo "==> Installing to $DEST"
    rm -rf "$DEST"
    cp -R "$APP_DIR" "/Applications/"
    echo "==> Installed. Launching."
    open "$DEST"
else
    echo ""
    echo "Run it now:"
    echo "  open \"$APP_DIR\""
    echo ""
    echo "Or install to /Applications:"
    echo "  ./build.sh --install"
fi
