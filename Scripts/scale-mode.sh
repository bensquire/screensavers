#!/bin/bash
# Choose the screensaver's scale preset without going through the Options sheet, which
# is presented from a sandboxed host and does not reliably persist there.
#
#   ./Scripts/scale-mode.sh balanced        distances and sizes compressed (default)
#   ./Scripts/scale-mode.sh true-distances  real relative orbit sizes, drift compressed
#   ./Scripts/scale-mode.sh birds-eye       fixed top-down orrery, no galactic drift
#   ./Scripts/scale-mode.sh                 report the current setting

set -euo pipefail
# These must match ScalePreset.Preference in Sources/SolarSystemRender/ScalePreset.swift.
# ScalePresetTests asserts that they do.
DOMAIN="com.solarsystem.screensaver"
KEY="scaleMode"
FALLBACK="$DOMAIN.$KEY"

# The host that actually runs the saver is sandboxed, so it reads its preferences from
# its own container, not from ~/Library/Preferences. Writing only the latter — which
# this once did — reported success and changed nothing: the choice the Options sheet
# had saved in the container went on winning. Both places are written, so this works
# for a sandboxed host and an unsandboxed one alike.
#
# The container's files are edited directly: cfprefsd will not open another app's
# container on our behalf (`defaults read` answers "Domain … does not exist" with the
# file right there). PlistBuddy rather than plutil, whose key paths split on the dots
# in the mirrored key.
HOST_PREFS="$HOME/Library/Containers/com.apple.ScreenSaver.Engine.legacyScreenSaver/Data/Library/Preferences"
HOST_UUID=$(ioreg -rd1 -c IOPlatformExpertDevice | awk -F'"' '/IOPlatformUUID/ { print $4 }')
HOST_BYHOST="$HOST_PREFS/ByHost/$DOMAIN.$HOST_UUID.plist"
HOST_STANDARD="$HOST_PREFS/com.apple.ScreenSaver.Engine.legacyScreenSaver.plist"
BUDDY=/usr/libexec/PlistBuddy

plist_read() { "$BUDDY" -c "Print :$2" "$1" 2>/dev/null || echo "unset"; }
plist_write() {
  "$BUDDY" -c "Set :$2 $3" "$1" 2>/dev/null || "$BUDDY" -c "Add :$2 string $3" "$1" >/dev/null
}

report() {
  if [ -d "$HOST_PREFS" ]; then
    echo "  host ByHost   $KEY = $(plist_read "$HOST_BYHOST" "$KEY")"
    echo "  host standard $FALLBACK = $(plist_read "$HOST_STANDARD" "$FALLBACK")"
  fi
  echo "  ByHost        $KEY = $(defaults -currentHost read "$DOMAIN" "$KEY" 2>/dev/null || echo unset)"
  echo "  global        $FALLBACK = $(defaults read -g "$FALLBACK" 2>/dev/null || echo unset)"
}

case "${1:-}" in
  balanced|stylised|default) VALUE=stylised ;;
  true-distances|distances)  VALUE=trueDistances ;;
  birds-eye|birdseye|orrery) VALUE=birdsEye ;;
  "") echo "current setting:"; report; exit 0 ;;
  *)  echo "usage: $0 [balanced|true-distances|birds-eye]" >&2; exit 2 ;;
esac

defaults -currentHost write "$DOMAIN" "$KEY" -string "$VALUE"
defaults write -g "$FALLBACK" -string "$VALUE"
# The host is stopped before its files are edited, and cfprefsd after: it caches
# them, and would otherwise hand the old value straight back — or write it over ours.
killall legacyScreenSaver 2>/dev/null || true
killall WallpaperAgent 2>/dev/null || true
if [ -d "$HOST_PREFS" ]; then
  plist_write "$HOST_BYHOST" "$KEY" "$VALUE"
  plist_write "$HOST_STANDARD" "$FALLBACK" "$VALUE"
  killall cfprefsd 2>/dev/null || true
fi
echo "scale mode: $VALUE"
report
echo "screensaver host restarted — the next start uses the new setting"
