#!/bin/bash
# Build one saver and install it into ~/Library/Screen Savers.
#   Scripts/install.sh <saver>
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SAVER="${1:-}"
[ -f "$ROOT/savers/$SAVER/saver.conf" ] || { echo "usage: install.sh <saver>" >&2; exit 1; }
# shellcheck source=/dev/null
source "$ROOT/savers/$SAVER/saver.conf"
cd "$ROOT"
Scripts/build-saver.sh "$SAVER"

SRC="build/$SAVER/$BUNDLE_NAME.saver"
DEST="$HOME/Library/Screen Savers/$BUNDLE_NAME.saver"

# Kill every process that might have the old bundle mmap'd. If any of these are still
# alive, the kernel holds the old signed pages and rejects the new binary with
# "Invalid Page" -> SIGKILL.
killall legacyScreenSaver 2>/dev/null || true
killall WallpaperAgent 2>/dev/null || true
killall ScreenSaverEngine 2>/dev/null || true
killall "System Settings" 2>/dev/null || true
sleep 1

mkdir -p "$HOME/Library/Screen Savers"
rm -rf "$DEST"
cp -R "$SRC" "$DEST"
# Re-sign after the copy so the on-disk mtime matches the signed code directory.
codesign --force --sign - --timestamp=none "$DEST/Contents/MacOS/$EXECUTABLE"
codesign --force --sign - --timestamp=none "$DEST"
echo "Installed: $DEST"
