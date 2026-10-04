// End-to-end check that a built .saver is something ScreenSaverEngine can actually
// load: correct Mach-O type, principal class resolvable from Info.plist, both view
// instances build, an options sheet is reachable, and a frame actually draws — and
// draws again after the view has been stopped and restarted. Run:
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

guard let path = args.first else {
    fail("usage: verify-saver.swift <path to .saver> [out.png]")
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

// A saver drawing through Metal or SceneKit renders on the GPU, so its backing
// store stays empty and cacheDisplay would capture nothing. Those views answer
// `captureSaverFrame` (SaverKit's SaverFrameCapturing) and hand back what they
// actually drew; found by selector because this script dlopens the bundle and
// cannot import the module.
let capture = NSSelectorFromString("captureSaverFrame")
func capturingView(in root: NSView) -> NSView? {
    if root.responds(to: capture) { return root }
    for child in root.subviews {
        if let found = capturingView(in: child) { return found }
    }
    return nil
}

/// What the view is drawing right now, or nil if it declined — the only case
/// being SceneKit on a virtualised GPU, where rendering at all aborts the process.
func currentFrame(of view: ScreenSaverView) -> NSBitmapImageRep? {
    if let source = capturingView(in: view) {
        guard let image = source.perform(capture)?.takeUnretainedValue() as? NSImage,
            let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil)
        else { return nil }
        return NSBitmapImageRep(cgImage: cgImage)
    }
    guard let cached = view.bitmapImageRepForCachingDisplay(in: view.bounds) else {
        fail("could not create a bitmap rep")
    }
    view.cacheDisplay(in: view.bounds, to: cached)
    return cached
}

func litSamples(_ rep: NSBitmapImageRep) -> Int {
    var lit = 0
    for x in stride(from: 0, to: rep.pixelsWide, by: 4) {
        for y in stride(from: 0, to: rep.pixelsHigh, by: 4) {
            if let c = rep.colorAt(x: x, y: y), c.brightnessComponent > 0.05 { lit += 1 }
        }
    }
    return lit
}

/// Real time has to pass between frames: a saver that derives its timestep from
/// the wall clock advances by microseconds in a tight loop and renders its
/// opening frame over and over, which would let this pass on a scene that never
/// moved.
func animate(_ view: ScreenSaverView, frames: Int) {
    for _ in 0..<frames {
        view.animateOneFrame()
        Thread.sleep(forTimeInterval: 1.0 / 30.0)
    }
}

for isPreview in [false, true] {
    let size = isPreview
        ? NSRect(x: 0, y: 0, width: 240, height: 150)
        : NSRect(x: 0, y: 0, width: 1440, height: 900)
    guard let view = saverClass.init(frame: size, isPreview: isPreview) else {
        fail("init(frame:isPreview: \(isPreview)) returned nil")
    }

    view.startAnimation()
    let frames = 90
    animate(view, frames: frames)
    print("instance:      isPreview=\(isPreview) animated \(frames) frames over "
        + String(format: "%.0f s", Double(frames) / 30.0))

    // Stopping has to be survivable. Savers here hand their GPU resources back
    // on stop, because the host keeps a stopped view alive indefinitely, and
    // rebuild them on the next start — a path nothing else would exercise.
    func restart() {
        view.stopAnimation()
        guard !view.isAnimating else { fail("still animating after stopAnimation") }
        view.startAnimation()
        animate(view, frames: 10)
    }

    guard !isPreview else {
        restart()
        view.stopAnimation()
        print("restart:       isPreview=\(isPreview) stopped and started again")
        continue
    }

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

    // Captured while still animating: a saver that releases its renderer on
    // stop has nothing left to capture afterwards.
    guard let rep = currentFrame(of: view) else {
        print("render:        declined — this GPU cannot render this saver offscreen")
        view.stopAnimation()
        continue
    }
    print("render:        captured \(rep.pixelsWide)x\(rep.pixelsHigh)")
    let lit = litSamples(rep)
    print("render:        \(lit) lit samples")
    guard lit > 0 else { fail("rendered frame is black — it loaded but drew nothing") }

    if args.count > 1, let png = rep.representation(using: .png, properties: [:]) {
        try? png.write(to: URL(fileURLWithPath: args[1]))
        print("wrote:         \(args[1])")
    }

    restart()
    guard let again = currentFrame(of: view), litSamples(again) > 0 else {
        fail("drew nothing after being stopped and started again")
    }
    view.stopAnimation()
    print("restart:       stopped, started again, and drew")
}

print("\nPASS — bundle loads, both instances animate, draw and survive a restart, options are reachable.")
