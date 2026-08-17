# One saver at a time, chosen with SAVER=<name>; the all-* targets do every one.
# Adding a screensaver means adding savers/<name>/, not editing this.
SAVERS := $(notdir $(wildcard savers/*))
SAVER  ?= three-body

.PHONY: build install verify release thumbnails bench test lint format clean \
        all-build all-verify list

list:
	@echo "savers: $(SAVERS)"
	@echo "usage:  make <target> SAVER=<name>"

build:
	Scripts/build-saver.sh $(SAVER)

install:
	Scripts/install.sh $(SAVER)

release:
	Scripts/release.sh $(SAVER)

# Loads the built bundle for real: resolves the principal class, instantiates both the
# full-screen and preview views, animates them in real time, and renders a frame.
verify: build
	@BUNDLE=$$(sed -n 's/^BUNDLE_NAME="\(.*\)"$$/\1/p' savers/$(SAVER)/saver.conf); \
	swift Scripts/verify-saver.swift "build/$(SAVER)/$$BUNDLE.saver" "build/$(SAVER)/check.png"


# The System Settings tiles, committed rather than built in CI so a release stays a
# pure compile-and-link. Regenerate after any change to how a scene looks.
thumbnails:
	@APP=$$(sed -n 's/^APP_PRODUCT="\(.*\)"$$/\1/p' savers/$(SAVER)/saver.conf); \
	swift build -c release --product $$APP; \
	.build/release/$$APP --render savers/$(SAVER)/Resources/thumbnail.png    --width 90  --height 58  --at 40; \
	.build/release/$$APP --render savers/$(SAVER)/Resources/thumbnail@2x.png --width 180 --height 116 --at 40

# Times the renderer. Release-mode is not optional: the three-body numerics are
# an order of magnitude slower unoptimised, so a debug build reports physics
# costs that are simply wrong. Extra flags pass through, e.g.
#   make bench SAVER=gargantua ARGS="--width 3840 --height 2160"
bench:
	@APP=$$(sed -n 's/^APP_PRODUCT="\(.*\)"$$/\1/p' savers/$(SAVER)/saver.conf); \
	swift build -c release --product $$APP; \
	.build/release/$$APP --bench $(ARGS)


# Release-mode: the three-body tests are numerical — million-step integrations and
# convergence-slope measurements — and unoptimised they take tens of minutes.
test:
	swift test -c release

lint:
	swift format lint --strict --recursive Sources Tests Package.swift

format:
	swift format --in-place --recursive Sources Tests Package.swift

all-build:
	@for s in $(SAVERS); do $(MAKE) build SAVER=$$s || exit 1; done

all-verify:
	@for s in $(SAVERS); do $(MAKE) verify SAVER=$$s || exit 1; done

clean:
	swift package clean && rm -rf .build build dist
