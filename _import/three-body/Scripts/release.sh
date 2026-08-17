#!/bin/bash
# Build and package the screensaver as a distributable zip.
#   VERSION=1.1.0 Scripts/release.sh
#
# Locally the bundle is ad-hoc signed and therefore not notarized: macOS quarantines it
# on download and the recipient has to clear that flag by hand. The signed + notarized
# artifact people should actually download comes from release.yml, on a pushed tag.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

export VERSION="${VERSION:-}"
Scripts/build-saver.sh

ZIP="dist/ThreeBodyProblem${VERSION:+-$VERSION}.zip"
Scripts/make-zip.sh "build/Three-Body Problem.saver" "$ZIP"
