#!/bin/bash
# Build and install into ~/Library/Screen Savers.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

SAVER="build/Three-Body Problem.saver"
DEST="$HOME/Library/Screen Savers/Three-Body Problem.saver"

Scripts/build-saver.sh

# Kill every process that might have the old bundle mmap'd. If any of these are still
# alive, the kernel holds the old signed pages and rejects the new binary with
# "Invalid Page" -> SIGKILL.
killall legacyScreenSaver 2>/dev/null || true
killall WallpaperAgent 2>/dev/null || true
killall ScreenSaverEngine 2>/dev/null || true
killall "System Settings" 2>/dev/null || true
# Give the kernel a moment to release the mappings.
sleep 1

mkdir -p "$HOME/Library/Screen Savers"
rm -rf "$DEST"
cp -R "$SAVER" "$DEST"

# Re-sign after the copy so the on-disk mtime matches the signed code directory.
codesign --force --sign - --timestamp=none "$DEST/Contents/MacOS/ThreeBodySaver"
codesign --force --sign - --timestamp=none "$DEST"

echo "Installed to: $DEST"
codesign -dv "$DEST" 2>&1 | head -4
