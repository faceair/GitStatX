#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
APP_NAME="GitStatX"
APP_DIR="$ROOT_DIR/dist/${APP_NAME}.app"
CONTENTS_DIR="$APP_DIR/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
RESOURCES_DIR="$CONTENTS_DIR/Resources"
ICON_ICNS="$ROOT_DIR/Sources/GitStatX/Resources/AppIcon.icns"
SVG_ICON="$ROOT_DIR/Sources/GitStatX/Resources/AppIcon.svg"

echo "▶️ Building ${APP_NAME} (release)..."
BIN_PATH=$(swift build -c release --show-bin-path)

if [[ ! -x "$BIN_PATH/$APP_NAME" ]]; then
  echo "ℹ️ Executable not found at $BIN_PATH/$APP_NAME, rebuilding..."
  swift build -c release
  BIN_PATH=$(swift build -c release --show-bin-path)
fi

echo "🧹 Cleaning dist..."
rm -rf "$APP_DIR"
mkdir -p "$MACOS_DIR" "$RESOURCES_DIR"
rm -rf "$ROOT_DIR/.iconbuild"

echo "📦 Copying executable..."
cp "$BIN_PATH/$APP_NAME" "$MACOS_DIR/"

echo "📄 Copying Info.plist..."
cp "$ROOT_DIR/Info.plist" "$CONTENTS_DIR/"

echo "🎨 Copying app icon..."
if [[ -f "$ICON_ICNS" ]]; then
  cp "$ICON_ICNS" "$RESOURCES_DIR/AppIcon.icns"
else
  echo "⚠️ AppIcon.icns missing, attempting on-the-fly generation from SVG..."
  ICON_BUILD_DIR="$ROOT_DIR/.iconbuild"
  ICONSET_DIR="$ICON_BUILD_DIR/icon.iconset"
  mkdir -p "$ICONSET_DIR"
  BASEPNG="$ICON_BUILD_DIR/icon.png"

  if [[ -f "$SVG_ICON" ]]; then
    if command -v rsvg-convert >/dev/null 2>&1; then
      rsvg-convert -w 1024 -h 1024 "$SVG_ICON" -o "$BASEPNG"
    else
      sips -s format png "$SVG_ICON" --out "$BASEPNG" >/dev/null
      sips -z 1024 1024 "$BASEPNG" --out "$BASEPNG" >/dev/null
    fi

    sizes=(16 32 128 256 512)
    for sz in "${sizes[@]}"; do
      sips -z "$sz" "$sz" "$BASEPNG" --out "$ICONSET_DIR/icon_${sz}x${sz}.png" >/dev/null
      dbl=$((sz * 2))
      if [[ $dbl -le 1024 ]]; then
        sips -z "$dbl" "$dbl" "$BASEPNG" --out "$ICONSET_DIR/icon_${sz}x${sz}@2x.png" >/dev/null
      fi
    done
    iconutil -c icns "$ICONSET_DIR" -o "$RESOURCES_DIR/AppIcon.icns"
  else
    echo "❌ Neither AppIcon.icns nor SVG icon found. Build will proceed without custom icon."
  fi
fi

echo "🗂️ Copying resource bundles..."
shopt -s nullglob
for bundle in "$BIN_PATH"/*.bundle; do
    cp -R "$bundle" "$RESOURCES_DIR/"
done
shopt -u nullglob

echo "✅ App bundle ready at $APP_DIR"
