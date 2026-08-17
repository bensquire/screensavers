#!/bin/bash
# Package the .saver for distribution — the single home for the release archive
# layout, shared by Scripts/release.sh (local) and release.yml (CI).
#   Scripts/make-zip.sh <saver-path> <zip-path>
#
# ditto --keepParent (not `zip`) because it preserves the bundle directory, its code
# signature, and extended attributes — including a stapled notarisation ticket. Plain
# zip mangles all three.
set -euo pipefail

SAVER=${1:-}
ZIP=${2:-}
[[ -d "$SAVER" && -n "$ZIP" ]] || {
    echo "usage: make-zip.sh <saver> <zip>" >&2
    exit 1
}

rm -f "$ZIP"
mkdir -p "$(dirname "$ZIP")"
ditto -c -k --keepParent "$SAVER" "$ZIP"
echo "built $ZIP ($(du -h "$ZIP" | cut -f1 | tr -d ' '))"
