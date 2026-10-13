#!/usr/bin/env bash
# Builds Herdr-Glow.app into ~/Applications. Replaces only that app bundle.
set -euo pipefail
cd "$(dirname "$0")/.."

swift build -c release
app="$HOME/Applications/Herdr-Glow.app"
rm -rf "$app"
mkdir -p "$app/Contents/MacOS"
cp .build/release/HerdrGlow "$app/Contents/MacOS/HerdrGlow"
cp Resources/Info.plist "$app/Contents/Info.plist"
codesign --force --sign - "$app"
echo "Built $app"
