#!/bin/bash
# Builds ArchivePlayer.app next to this script. Needs the command line tools
# (xcode-select --install) and nothing else.
set -euo pipefail
cd "$(dirname "$0")"

APP="ArchivePlayer.app"
NAME="ArchivePlayer"

command -v swiftc >/dev/null || { echo "swiftc not found — run: xcode-select --install"; exit 1; }
[ -f Resources/archive-video-player.html ] || { echo "Resources/archive-video-player.html is missing"; exit 1; }

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

echo "compiling…"
swiftc -O -whole-module-optimization \
  -o "$APP/Contents/MacOS/$NAME" \
  Sources/main.swift \
  -framework AppKit -framework WebKit -framework Network

cp Info.plist "$APP/Contents/Info.plist"
cp Resources/archive-video-player.html "$APP/Contents/Resources/"
cp Resources/AppIcon.icns "$APP/Contents/Resources/"

# ad-hoc signature, so gatekeeper lets a locally built app run
codesign --force --sign - "$APP" >/dev/null 2>&1 || true
# tell the Finder the icon changed, in case an older copy is cached
touch "$APP"

echo "built $(pwd)/$APP"
echo "run it with:  open $APP"
