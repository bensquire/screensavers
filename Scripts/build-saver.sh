#!/bin/bash
# Builds one screensaver into a loadable macOS bundle.
#
#   Scripts/build-saver.sh <saver>          # e.g. three-body, solar-system
#
# SwiftPM cannot emit an MH_BUNDLE, which is what ScreenSaverEngine dlopens, so this
# drives swiftc directly: compile each module in dependency order, then link the
# objects with `-bundle`. Universal (arm64 + x86_64) by default because the
# legacyScreenSaver host process picks its architecture independently of the app that
# built the saver.
#
# Everything saver-specific is declared in savers/<name>/saver.conf, so adding another
# screensaver means adding a directory, not editing this.
#
# Env overrides (used by CI):
#   VERSION            marketing version written into Info.plist
#   CODESIGN_IDENTITY  signing identity (default "-", ad-hoc self-signing)
#   ARCHS / CONFIG     architecture list and swiftc optimisation level

set -euo pipefail

SAVER="${1:-}"
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

if [ -z "$SAVER" ] || [ ! -f "$ROOT/savers/$SAVER/saver.conf" ]; then
  echo "usage: build-saver.sh <saver>" >&2
  echo "available:" >&2
  ls "$ROOT/savers" | sed 's/^/  /' >&2
  exit 1
fi

# shellcheck source=/dev/null
source "$ROOT/savers/$SAVER/saver.conf"

BUILD="$ROOT/build/$SAVER"
BUNDLE="$BUILD/$BUNDLE_NAME.saver"
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

rm -rf "$BUILD"
mkdir -p "$BUNDLE/Contents/MacOS" "$BUNDLE/Contents/Resources"

# Metal shaders, if the saver has any. A metallib is architecture-independent,
# so unlike the Swift it is built once rather than per slice.
if [ -n "${METAL_SOURCES:-}" ]; then
  echo "==> $SAVER: compiling shaders"
  air_files=()
  for source in $METAL_SOURCES; do
    air="$BUILD/$(basename "${source%.metal}").air"
    xcrun -sdk macosx metal -c \
      -mmacosx-version-min="$DEPLOYMENT_TARGET" \
      "$ROOT/$source" -o "$air"
    air_files+=("$air")
  done
  xcrun -sdk macosx metallib "${air_files[@]}" \
    -o "$BUNDLE/Contents/Resources/$METAL_LIBRARY.metallib"
  rm -f "${air_files[@]}"
fi

thin_binaries=()

for arch in $ARCHS; do
  echo "==> $SAVER: building $arch"
  obj="$BUILD/obj-$arch"
  mkdir -p "$obj"
  target="$arch-apple-macos$DEPLOYMENT_TARGET"

  # Optional C dependency (solar-system vendors astronomy-engine).
  swift_cc_flags=()
  if [ -n "$C_SOURCES" ]; then
    xcrun clang -c $C_OPT -arch "$arch" -isysroot "$SDK" \
      -mmacosx-version-min="$DEPLOYMENT_TARGET" \
      -I "$ROOT/$C_INCLUDE" \
      "$ROOT/$C_SOURCES" \
      -o "$obj/c-dependency.o"
    swift_cc_flags=(-Xcc -I -Xcc "$ROOT/$C_INCLUDE")
  fi

  # Swift modules in dependency order. Each emits a .swiftmodule for the next to
  # import, and one object file.
  for module in $MODULES; do
    # shellcheck disable=SC2086
    xcrun swiftc $SWIFT_OPT \
      -swift-version 5 \
      -target "$target" \
      -sdk "$SDK" \
      -module-name "$module" \
      -parse-as-library \
      -emit-module -emit-module-path "$obj/$module.swiftmodule" \
      -I "$obj" \
      "${swift_cc_flags[@]+"${swift_cc_flags[@]}"}" \
      -c "$ROOT/Sources/$module"/*.swift \
      -o "$obj/$module.o"
  done

  framework_flags=()
  for framework in $FRAMEWORKS; do framework_flags+=(-framework "$framework"); done

  # Link an MH_BUNDLE. swiftc drives the link so the Swift runtime and its rpaths
  # are wired up correctly; -bundle is passed through to ld.
  xcrun swiftc \
    -target "$target" \
    -sdk "$SDK" \
    -emit-library \
    -Xlinker -bundle \
    -module-name "$EXECUTABLE" \
    "${framework_flags[@]}" \
    "$obj"/*.o \
    -o "$BUILD/$EXECUTABLE-$arch"

  thin_binaries+=("$BUILD/$EXECUTABLE-$arch")
done

echo "==> $SAVER: assembling bundle"
if [ ${#thin_binaries[@]} -gt 1 ]; then
  xcrun lipo -create "${thin_binaries[@]}" -output "$BUNDLE/Contents/MacOS/$EXECUTABLE"
else
  cp "${thin_binaries[0]}" "$BUNDLE/Contents/MacOS/$EXECUTABLE"
fi

PLIST="$BUNDLE/Contents/Info.plist"
cp "$ROOT/savers/$SAVER/Info.plist" "$PLIST"

# A release stamps the tag's version in; a local build keeps whatever the plist says.
VERSION="${VERSION:-}"
if [ -n "$VERSION" ]; then
  /usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $VERSION" "$PLIST"
  /usr/libexec/PlistBuddy -c "Set :CFBundleVersion $VERSION" "$PLIST"
fi

for resource in $EXTRA_RESOURCES; do
  cp "$ROOT/$resource" "$BUNDLE/Contents/Resources/"
done

# System Settings shows these in the screensaver grid; a saver without them renders as
# an easy-to-miss blank tile. Committed rather than rendered here, so a release stays a
# pure compile-and-link — `make thumbnails SAVER=<name>` regenerates them.
echo "==> $SAVER: copying thumbnails"
for thumb in thumbnail.png thumbnail@2x.png; do
  src="$ROOT/savers/$SAVER/Resources/$thumb"
  if [ ! -f "$src" ]; then
    echo "error: savers/$SAVER/Resources/$thumb is missing — run 'make thumbnails SAVER=$SAVER'" >&2
    exit 1
  fi
  cp "$src" "$BUNDLE/Contents/Resources/$thumb"
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
codesign "${SIGN_FLAGS[@]}" "$BUNDLE/Contents/MacOS/$EXECUTABLE"
codesign "${SIGN_FLAGS[@]}" "$BUNDLE"

echo
echo "built: $BUNDLE"
xcrun lipo -info "$BUNDLE/Contents/MacOS/$EXECUTABLE"
