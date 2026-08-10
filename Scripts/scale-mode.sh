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

report() {
  local byhost std
  byhost=$(defaults -currentHost read "$DOMAIN" "$KEY" 2>/dev/null || echo "unset")
  std=$(defaults read -g "$FALLBACK" 2>/dev/null || echo "unset")
  echo "  ByHost   $KEY = $byhost"
  echo "  standard $FALLBACK = $std"
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
echo "scale mode: $VALUE"
report
# The saver reads the setting when it starts, so restart the host to pick it up.
killall legacyScreenSaver 2>/dev/null || true
killall WallpaperAgent 2>/dev/null || true
echo "screensaver host restarted — the next start uses the new setting"
