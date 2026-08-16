.PHONY: build thumbnails test lint format verify install release run clean

build:
	Scripts/build-saver.sh

# The System Settings tiles. Committed rather than built in CI, so a release is a
# pure compile-and-link. Regenerate here after any change to how the scene looks,
# and commit the result.
thumbnails:
	swift build -c release --product ThreeBodyApp
	.build/release/ThreeBodyApp --render Resources/thumbnail.png    --width 90  --height 58  --at 40
	.build/release/ThreeBodyApp --render Resources/thumbnail@2x.png --width 180 --height 116 --at 40

# Release, not debug: these are numerical tests — million-step integrations and
# convergence-slope measurements — and unoptimised they take tens of minutes.
test:
	swift test -c release

lint:
	swift format lint --strict --recursive Sources Tests Package.swift

format:
	swift format --in-place --recursive Sources Tests Package.swift

# Loads the built bundle for real: resolves the principal class, instantiates both the
# full-screen and preview views, animates them, checks the mode picker, and draws.
verify: build
	swift Scripts/verify-saver.swift "build/Three-Body Problem.saver" build/check.png

install:
	Scripts/install.sh

# Watch a scene without locking the screen. MODE=known|random|both
run:
	swift build -c release --product ThreeBodyApp
	.build/release/ThreeBodyApp --mode $(or $(MODE),both)

release:
	Scripts/release.sh

clean:
	swift package clean && rm -rf .build build dist
