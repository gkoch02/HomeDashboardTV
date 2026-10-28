#!/bin/bash
# Builds the Mac screensaver in Release and installs it for this user, replacing any
# earlier copy. System Settings caches a loaded saver in the legacy screensaver host; if
# the preview keeps showing the old build, quit System Settings and `killall legacyScreenSaver`.
set -euo pipefail
cd "$(dirname "$0")/.."

build="build/saver"
xcodebuild -scheme HomeDashboardSaver -configuration Release -derivedDataPath "$build" build | tail -3
product="$build/Build/Products/Release/Home Dashboard.saver"
[ -d "$product" ] || { echo "❌ no product at $product"; exit 1; }

dest="$HOME/Library/Screen Savers"
mkdir -p "$dest"
rm -rf "$dest/Home Dashboard.saver"
cp -R "$product" "$dest/"
killall legacyScreenSaver 2> /dev/null || true
echo "✅ installed $dest/Home Dashboard.saver — pick Home Dashboard under Screen Saver in System Settings."
