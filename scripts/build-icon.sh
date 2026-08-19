#!/bin/zsh
set -euo pipefail

PROJECT_DIR="${0:A:h:h}"
MASTER="$PROJECT_DIR/Assets/AppIcon/AppIcon-master.png"
ICONSET="$PROJECT_DIR/Assets/AppIcon/AppIcon.iconset"
OUTPUT="$PROJECT_DIR/Assets/AppIcon/AppIcon.icns"

rm -rf "$ICONSET"
mkdir -p "$ICONSET"

sips -z 16 16 "$MASTER" --out "$ICONSET/icon_16x16.png" >/dev/null
sips -z 32 32 "$MASTER" --out "$ICONSET/icon_16x16@2x.png" >/dev/null
sips -z 32 32 "$MASTER" --out "$ICONSET/icon_32x32.png" >/dev/null
sips -z 64 64 "$MASTER" --out "$ICONSET/icon_32x32@2x.png" >/dev/null
sips -z 128 128 "$MASTER" --out "$ICONSET/icon_128x128.png" >/dev/null
sips -z 256 256 "$MASTER" --out "$ICONSET/icon_128x128@2x.png" >/dev/null
sips -z 256 256 "$MASTER" --out "$ICONSET/icon_256x256.png" >/dev/null
sips -z 512 512 "$MASTER" --out "$ICONSET/icon_256x256@2x.png" >/dev/null
sips -z 512 512 "$MASTER" --out "$ICONSET/icon_512x512.png" >/dev/null
sips -z 1024 1024 "$MASTER" --out "$ICONSET/icon_512x512@2x.png" >/dev/null

# Downloaded or generated PNGs may carry provenance metadata that makes
# iconutil reject an otherwise valid iconset.
xattr -dr com.apple.provenance "$ICONSET" 2>/dev/null || true
iconutil -c icns "$ICONSET" -o "$OUTPUT"
