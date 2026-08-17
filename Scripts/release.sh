#!/bin/bash
# Build and package one saver as a distributable zip.
#   VERSION=1.1.0 Scripts/release.sh <saver>
#
# Locally the bundle is ad-hoc signed and therefore not notarized: macOS quarantines it
# on download and the recipient has to clear that flag by hand. The signed + notarized
# artifact people should actually download comes from release.yml, on a pushed tag.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SAVER="${1:-}"
[ -f "$ROOT/savers/$SAVER/saver.conf" ] || { echo "usage: release.sh <saver>" >&2; exit 1; }
# shellcheck source=/dev/null
source "$ROOT/savers/$SAVER/saver.conf"
cd "$ROOT"
export VERSION="${VERSION:-}"
Scripts/build-saver.sh "$SAVER"
Scripts/make-zip.sh "build/$SAVER/$BUNDLE_NAME.saver" "dist/${ZIP_PREFIX}${VERSION:+-$VERSION}.zip"
