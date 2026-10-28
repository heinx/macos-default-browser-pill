#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p .scratch/cache .scratch/tmp
export CLANG_MODULE_CACHE_PATH="$PWD/.scratch/cache"
export TMPDIR="$PWD/.scratch/tmp"
swift build -c release --build-system native --disable-sandbox --cache-path "$PWD/.scratch/cache"
mkdir -p "build/Browser Pill.app/Contents/MacOS"
cp .build/release/BrowserPill "build/Browser Pill.app/Contents/MacOS/BrowserPill"
cp Resources/Info.plist "build/Browser Pill.app/Contents/Info.plist"
codesign --force --deep --sign - "build/Browser Pill.app"
echo "Built build/Browser Pill.app"
