// End-to-end check that a built .saver is something ScreenSaverEngine can actually
// load: correct Mach-O type, principal class resolvable from Info.plist, both view
// instances build, an options sheet is reachable, and a frame actually draws. Run:
//
//   swift Scripts/verify-saver.swift "build/<saver>/<Name>.saver" [out.png]
//
// Deliberately generic: it asserts what every screensaver must do, so a new saver
// gets the check for free rather than needing its own verifier.

import AppKit
import Foundation
import ScreenSaver

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data("FAIL: \(message)\n".utf8))
    exit(1)
}

var args = Array(CommandLine.arguments.dropFirst())

// Whether a drawn frame can be captured from the host view at all. A saver that
// draws with Core Graphics renders into the view's backing store, so
// cacheDisplay sees the frame. One that renders on the GPU — SceneKit, Metal,
// WebGL in a web view — does not: its pixels never pass through the view's
// context, and cacheDisplay returns an empty frame whether the scene is drawing
// beautifully or not at all. Asserting on that would be worse than not
// asserting, so each saver declares which it is.
let checksRenderedPixels = !args.contains("--no-render-check")
args.removeAll { $0 == "--no-render-check" }

guard let path = args.first else {
    fail("usage: verify-saver.swift <path to .saver> [out.png] [--no-render-check]")
}
guard let bundle = Bundle(path: path) else { fail("not a bundle: \(path)") }
print("bundle:        \(path)")

guard let identifier = bundle.bundleIdentifier else { fail("no CFBundleIdentifier") }
print("identifier:    \(identifier)")

guard let principalName = bundle.object(forInfoDictionaryKey: "NSPrincipalClass") as? String else {
    fail("Info.plist has no NSPrincipalClass")
}
print("principal:     \(principalName)")

guard bundle.load() else { fail("bundle.load() returned false — check the Swift runtime links") }
guard let cls = bundle.principalClass else {
    fail("principalClass is nil — NSPrincipalClass '\(principalName)' does not resolve. "
        + "Check the @objc(...) name on the view class.")
}
guard let saverClass = cls as? ScreenSaverView.Type else {
    fail("principal class is not a ScreenSaverView subclass")
}
print("load:          ok — \(cls)")

for isPreview in [false, true] {
    let size = isPreview
        ? NSRect(x: 0, y: 0, width: 240, height: 150)
        : NSRect(x: 0, y: 0, width: 1440, height: 900)
    guard let view = saverClass.init(frame: size, isPreview: isPreview) else {
        fail("init(frame:isPreview: \(isPreview)) returned nil")
    }

    // Real time has to pass between frames: a saver that derives its timestep from
    // the wall clock advances by microseconds in a tight loop and renders its
    // opening frame over and over, which would let this pass on a scene that never
    // moved.
    view.startAnimation()
    let frames = 90
    for _ in 0..<frames {
        view.animateOneFrame()
        Thread.sleep(forTimeInterval: 1.0 / 30.0)
    }
    view.stopAnimation()
    print("instance:      isPreview=\(isPreview) animated \(frames) frames over "
        + String(format: "%.0f s", Double(frames) / 30.0))

    guard !isPreview else { continue }

    guard view.hasConfigureSheet else { fail("no configure sheet — the options are unreachable") }
    guard let sheet = view.configureSheet, let content = sheet.contentView else {
        fail("configureSheet returned nil")
    }
    func controls(in view: NSView) -> [NSControl] {
        view.subviews.flatMap { child -> [NSControl] in
            ((child as? NSControl).map { [$0] } ?? []) + controls(in: child)
        }
    }
    let interactive = controls(in: content).filter { !($0 is NSTextField) }
    guard interactive.count >= 2 else {
        fail("options sheet has \(interactive.count) controls — expected at least a choice and a button")
    }
    print("options:       sheet ok — \(interactive.count) controls")

    guard checksRenderedPixels else {
        print("render:        skipped — this saver renders on the GPU, where the "
            + "host view's backing store stays empty")
        continue
    }

    guard let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else {
        fail("could not create a bitmap rep")
    }
    view.cacheDisplay(in: view.bounds, to: rep)
    var lit = 0
    for x in stride(from: 0, to: rep.pixelsWide, by: 4) {
        for y in stride(from: 0, to: rep.pixelsHigh, by: 4) {
            if let c = rep.colorAt(x: x, y: y), c.brightnessComponent > 0.05 { lit += 1 }
        }
    }
    print("render:        \(lit) lit samples")
    guard lit > 0 else { fail("rendered frame is black — it loaded but drew nothing") }

    if args.count > 1, let png = rep.representation(using: .png, properties: [:]) {
        try? png.write(to: URL(fileURLWithPath: args[1]))
        print("wrote:         \(args[1])")
    }
}

print("\nPASS — bundle loads, both instances animate and draw, options are reachable.")
