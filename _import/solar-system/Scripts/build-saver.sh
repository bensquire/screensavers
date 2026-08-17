#!/bin/bash
# Builds "Solar System.saver", a loadable macOS screensaver bundle.
#
# SwiftPM cannot emit an MH_BUNDLE, which is what ScreenSaverEngine dlopens, so this
# drives swiftc directly: compile each module in dependency order, then link the
# objects with `-bundle`. Universal (arm64 + x86_64) by default because the
# legacyScreenSaver host process picks its architecture independently of the app that
# built the saver.
#
# Env overrides (used by CI):
#   VERSION            marketing version written into Info.plist
#                      (default: whatever Scripts/Info.plist already says)
#   CODESIGN_IDENTITY  signing identity (default "-", ad-hoc self-signing)
#   ARCHS / CONFIG     architecture list and swiftc optimisation level

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUILD="$ROOT/build"
BUNDLE="$BUILD/Solar System.saver"
DEPLOY_TARGET="14.0"
ARCHS="${ARCHS:-arm64 x86_64}"
CONFIG="${CONFIG:-release}"

if [ "$CONFIG" = "release" ]; then
  SWIFT_OPT="-O -wmo"
  C_OPT="-O2"
else
  SWIFT_OPT="-Onone"
  C_OPT="-O0 -g"
fi

SDK="$(xcrun --sdk macosx --show-sdk-path)"
MODULES=(SolarSystemCore SolarSystemRender SolarSystemSaver)

rm -rf "$BUILD"
mkdir -p "$BUNDLE/Contents/MacOS" "$BUNDLE/Contents/Resources"

thin_binaries=()

for arch in $ARCHS; do
  echo "==> building $arch"
  obj="$BUILD/obj-$arch"
  mkdir -p "$obj"
  target="$arch-apple-macos$DEPLOY_TARGET"

  # 1. astronomy-engine (C)
  xcrun clang -c $C_OPT -arch "$arch" -isysroot "$SDK" \
    -mmacosx-version-min="$DEPLOY_TARGET" \
    -I "$ROOT/Sources/CAstronomy/include" \
    "$ROOT/Sources/CAstronomy/astronomy.c" \
    -o "$obj/astronomy.o"

  # 2. Swift modules, in dependency order. Each emits both a .swiftmodule (for the
  #    next module to import) and a single object file.
  for module in "${MODULES[@]}"; do
    # shellcheck disable=SC2086
    xcrun swiftc $SWIFT_OPT \
      -target "$target" \
      -sdk "$SDK" \
      -module-name "$module" \
      -parse-as-library \
      -emit-module -emit-module-path "$obj/$module.swiftmodule" \
      -I "$obj" \
      -Xcc -I -Xcc "$ROOT/Sources/CAstronomy/include" \
      -c "$ROOT/Sources/$module"/*.swift \
      -o "$obj/$module.o"
  done

  # 3. Link an MH_BUNDLE. swiftc drives the link so the Swift runtime and its
  #    rpaths are wired up correctly; -bundle is passed through to ld.
  xcrun swiftc \
    -target "$target" \
    -sdk "$SDK" \
    -emit-library \
    -Xlinker -bundle \
    -module-name SolarSystemSaver \
    -framework ScreenSaver -framework SceneKit -framework AppKit \
    "$obj"/*.o \
    -o "$BUILD/SolarSystemSaver-$arch"

  thin_binaries+=("$BUILD/SolarSystemSaver-$arch")
done

echo "==> assembling bundle"
if [ ${#thin_binaries[@]} -gt 1 ]; then
  xcrun lipo -create "${thin_binaries[@]}" -output "$BUNDLE/Contents/MacOS/SolarSystemSaver"
else
  cp "${thin_binaries[0]}" "$BUNDLE/Contents/MacOS/SolarSystemSaver"
fi

PLIST="$BUNDLE/Contents/Info.plist"
cp "$ROOT/Scripts/Info.plist" "$PLIST"
cp "$ROOT/LICENSES/astronomy-engine-MIT.txt" "$BUNDLE/Contents/Resources/"

# A release stamps the tag's version in; a local build keeps whatever the plist says.
VERSION="${VERSION:-}"
if [ -n "$VERSION" ]; then
  /usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $VERSION" "$PLIST"
  /usr/libexec/PlistBuddy -c "Set :CFBundleVersion $VERSION" "$PLIST"
fi

# System Settings shows these in the screensaver grid; a saver without them renders as an
# easy-to-miss blank tile. They are real frames of the real scene, but they are committed
# rather than rendered here: SCNRenderer's offscreen snapshot traps on a paravirtualised
# GPU, so a CI runner cannot produce them at all. `make thumbnails` regenerates them on a
# machine with a GPU.
echo "==> copying thumbnails"
for thumb in thumbnail.png thumbnail@2x.png; do
  if [ ! -f "$ROOT/Resources/$thumb" ]; then
    echo "error: Resources/$thumb is missing — run 'make thumbnails'" >&2
    exit 1
  fi
  cp "$ROOT/Resources/$thumb" "$BUNDLE/Contents/Resources/$thumb"
done

# Ad-hoc ("-") by default, which is enough for the saver to load locally. A real
# Developer ID additionally gets the hardened runtime and a trusted timestamp, both of
# which notarisation requires and neither of which an ad-hoc signature can carry.
# Sign the executable before the bundle: signing the bundle seals its contents, so the
# other order invalidates the wrapper the moment the inner binary is re-signed.
IDENTITY="${CODESIGN_IDENTITY:--}"
SIGN_FLAGS=(--force --sign "$IDENTITY")
if [ "$IDENTITY" = "-" ]; then
  SIGN_FLAGS+=(--timestamp=none)
else
  SIGN_FLAGS+=(--options runtime --timestamp)
fi
codesign "${SIGN_FLAGS[@]}" "$BUNDLE/Contents/MacOS/SolarSystemSaver"
codesign "${SIGN_FLAGS[@]}" "$BUNDLE"

echo
echo "built: $BUNDLE"
xcrun lipo -info "$BUNDLE/Contents/MacOS/SolarSystemSaver"
echo
echo "install with:  cp -R '$BUNDLE' ~/Library/Screen\\ Savers/"
