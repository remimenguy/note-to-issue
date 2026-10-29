#!/usr/bin/env bash
set -euo pipefail

MODE="${1:-run}"
APP_NAME="NoteToIssue"
BUNDLE_ID="com.remimenguy.NoteToIssue"
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUILD_DIR="$HOME/Library/Caches/NoteToIssue/Build"
APP_BUNDLE="$ROOT_DIR/dist/$APP_NAME.app"

case "$MODE" in
  run|--build-only|--debug|--logs|--telemetry|--verify) ;;
  *) echo "usage: $0 [--build-only|--debug|--logs|--telemetry|--verify]" >&2; exit 2 ;;
esac

if [[ "$MODE" != "--build-only" ]]; then pkill -x "$APP_NAME" >/dev/null 2>&1 || true; fi
cd "$ROOT_DIR"
swift build --scratch-path "$BUILD_DIR" -j 4
BIN_DIR="$(swift build --scratch-path "$BUILD_DIR" --show-bin-path)"
mkdir -p "$APP_BUNDLE/Contents/MacOS" "$APP_BUNDLE/Contents/Resources"
cp "$BIN_DIR/$APP_NAME" "$APP_BUNDLE/Contents/MacOS/$APP_NAME"
chmod +x "$APP_BUNDLE/Contents/MacOS/$APP_NAME"
# Stage the script in the native app resource directory (SwiftPM handles tests).
mkdir -p "$APP_BUNDLE/Contents/Resources/Notes"
cp "$ROOT_DIR/Sources/NoteToIssueCore/Resources/ReadNotes.js" "$APP_BUNDLE/Contents/Resources/Notes/ReadNotes.js"
cp "$ROOT_DIR/assets/AppIcon.icns" "$APP_BUNDLE/Contents/Resources/AppIcon.icns"
cat > "$APP_BUNDLE/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleExecutable</key><string>NoteToIssue</string>
<key>CFBundleIdentifier</key><string>com.remimenguy.NoteToIssue</string>
<key>CFBundleName</key><string>NoteToIssue</string>
<key>CFBundleDisplayName</key><string>Note to Issue</string>
<key>CFBundleIconFile</key><string>AppIcon</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>0.1.0</string>
<key>CFBundleVersion</key><string>1</string>
<key>LSMinimumSystemVersion</key><string>14.0</string>
<key>NSPrincipalClass</key><string>NSApplication</string>
<key>LSUIElement</key><true/>
<key>NSAppleEventsUsageDescription</key><string>Note to Issue lit les notes du compte choisi pour préparer des issues GitHub.</string>
</dict></plist>
PLIST
/usr/bin/codesign --force --sign - --identifier "$BUNDLE_ID" "$APP_BUNDLE"

case "$MODE" in
  --build-only) echo "App construite : $APP_BUNDLE" ;;
  run) /usr/bin/open "$APP_BUNDLE" ;;
  --debug) lldb -- "$APP_BUNDLE/Contents/MacOS/$APP_NAME" ;;
  --logs|--telemetry)
    /usr/bin/open "$APP_BUNDLE"
    /usr/bin/log stream --info --style compact --predicate "process == \"$APP_NAME\""
    ;;
  --verify)
    /usr/bin/open "$APP_BUNDLE"
    sleep 2
    pgrep -x "$APP_NAME" >/dev/null
    swift "$ROOT_DIR/script/verify_background.swift" "$APP_BUNDLE"
    echo "Note to Issue est démarrée."
    ;;
esac
