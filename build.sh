#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
APP_NAME="GitStatX"
APP_DIR="$ROOT_DIR/dist/${APP_NAME}.app"
CONTENTS_DIR="$APP_DIR/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
RESOURCES_DIR="$CONTENTS_DIR/Resources"

echo "▶️ Building ${APP_NAME} (release)..."
BIN_PATH=$(swift build -c release --show-bin-path)

echo "🧹 Cleaning dist..."
rm -rf "$APP_DIR"
mkdir -p "$MACOS_DIR" "$RESOURCES_DIR"

echo "📦 Copying executable..."
cp "$BIN_PATH/$APP_NAME" "$MACOS_DIR/"

echo "📄 Copying Info.plist..."
cp "$ROOT_DIR/Info.plist" "$CONTENTS_DIR/"

echo "🗂️ Copying resource bundles..."
shopt -s nullglob
for bundle in "$BIN_PATH"/*.bundle; do
    cp -R "$bundle" "$RESOURCES_DIR/"
done
shopt -u nullglob

echo "✅ App bundle ready at $APP_DIR"
