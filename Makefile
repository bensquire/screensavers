.PHONY: build test lint format verify install release clean

build:
	Scripts/build-saver.sh

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
