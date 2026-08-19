#!/bin/zsh
set -euo pipefail

PROJECT_DIR="${0:A:h:h}"
APP_NAME="Bose Control"
BUILD_DIR="$PROJECT_DIR/build"
APP_DIR="$BUILD_DIR/$APP_NAME.app"
DMG_STAGE="$BUILD_DIR/dmg-stage"

cd "$PROJECT_DIR"
"$PROJECT_DIR/scripts/build-icon.sh"
swift build -c release

rm -rf "$APP_DIR" "$DMG_STAGE"
mkdir -p "$APP_DIR/Contents/MacOS" "$APP_DIR/Contents/Resources"
cp "$PROJECT_DIR/.build/release/BoseControl" "$APP_DIR/Contents/MacOS/BoseControl"
cp "$PROJECT_DIR/Packaging/Info.plist" "$APP_DIR/Contents/Info.plist"
cp "$PROJECT_DIR/Assets/AppIcon/AppIcon.icns" "$APP_DIR/Contents/Resources/AppIcon.icns"
codesign --force --deep --sign - "$APP_DIR"

mkdir -p "$DMG_STAGE"
ditto "$APP_DIR" "$DMG_STAGE/$APP_NAME.app"
ln -sfn /Applications "$DMG_STAGE/Applications"

DMG_PATH="$BUILD_DIR/BoseControl-0.5.0-beta.1.dmg"
rm -f "$DMG_PATH"
hdiutil create -volname "$APP_NAME" -srcfolder "$DMG_STAGE" -ov -format UDZO "$DMG_PATH"

echo "$DMG_PATH"
