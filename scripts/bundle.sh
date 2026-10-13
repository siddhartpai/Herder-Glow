#!/usr/bin/env bash
# Builds Herder-Glow.app into ~/Applications. Replaces only that app bundle.
set -euo pipefail
cd "$(dirname "$0")/.."

swift build -c release
app="$HOME/Applications/Herder-Glow.app"
rm -rf "$app"
mkdir -p "$app/Contents/MacOS"
cp .build/release/HerderGlow "$app/Contents/MacOS/HerderGlow"
cp Resources/Info.plist "$app/Contents/Info.plist"
codesign --force --sign - "$app"
echo "Built $app"
