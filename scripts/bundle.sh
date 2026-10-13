#!/usr/bin/env bash
# Builds SidebarHover.app into ~/Applications. Replaces only that app bundle.
set -euo pipefail
cd "$(dirname "$0")/.."

swift build -c release
app="$HOME/Applications/SidebarHover.app"
rm -rf "$app"
mkdir -p "$app/Contents/MacOS"
cp .build/release/SidebarHover "$app/Contents/MacOS/SidebarHover"
cp Resources/Info.plist "$app/Contents/Info.plist"
codesign --force --sign - "$app"
echo "Built $app"
