.PHONY: build thumbnails test lint format verify install release clean

build:
	Scripts/build-saver.sh

# The System Settings tiles. Committed rather than built, because the offscreen
# renderer they need traps on a paravirtualised GPU and so can't run in CI.
# Regenerate here after any change to how the scene looks, and commit the result.
thumbnails:
	swift build -c release --product SolarSystemApp
	.build/release/SolarSystemApp --render Resources/thumbnail.png    --width 90  --height 58  --at 40
	.build/release/SolarSystemApp --render Resources/thumbnail@2x.png --width 180 --height 116 --at 40

test:
	swift test

lint:
	swift format lint --strict --recursive Sources Tests Package.swift

format:
	swift format --in-place --recursive Sources Tests Package.swift

# Loads the built bundle for real: resolves the principal class, instantiates both the
# full-screen and preview views, and renders a frame.
verify: build
	swift Scripts/verify-saver.swift "build/Solar System.saver" build/check.png

install:
	Scripts/install.sh

release:
	Scripts/release.sh

clean:
	swift package clean && rm -rf .build build dist
