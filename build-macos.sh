#!/bin/bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")" && pwd)"
APP_DIR="$ROOT_DIR/dist/小小信.app"

cd "$ROOT_DIR"
mkdir -p "$ROOT_DIR/Sources/XiaoXiaoXin/Resources/Web/assets/pets/default"
cp "$ROOT_DIR/index.html" "$ROOT_DIR/Sources/XiaoXiaoXin/Resources/Web/index.html"
cp "$ROOT_DIR/styles.css" "$ROOT_DIR/Sources/XiaoXiaoXin/Resources/Web/styles.css"
cp "$ROOT_DIR/app.js" "$ROOT_DIR/Sources/XiaoXiaoXin/Resources/Web/app.js"
cp "$ROOT_DIR/assets/pets/default/"* "$ROOT_DIR/Sources/XiaoXiaoXin/Resources/Web/assets/pets/default/"
swift build -c release

rm -rf "$APP_DIR"
mkdir -p "$APP_DIR/Contents/MacOS" "$APP_DIR/Contents/Resources"
cp "$ROOT_DIR/.build/release/XiaoXiaoXin" "$APP_DIR/Contents/MacOS/小小信"
cp "$ROOT_DIR/Info.plist" "$APP_DIR/Contents/Info.plist"
cp -R "$ROOT_DIR/Sources/XiaoXiaoXin/Resources/Web" "$APP_DIR/Contents/Resources/Web"

codesign --force --deep --sign - "$APP_DIR"
echo "Built: $APP_DIR"
