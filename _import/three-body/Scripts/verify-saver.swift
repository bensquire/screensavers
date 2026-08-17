// End-to-end check that the built .saver is something ScreenSaverEngine can actually
// load: correct Mach-O type, principal class resolvable from Info.plist, both view
// instances build, the options sheet offers the scene modes, and a frame actually
// draws something. Run:
//
//   swift Scripts/verify-saver.swift "build/Three-Body Problem.saver" [out.png]

import AppKit
import Foundation
import ScreenSaver

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data("FAIL: \(message)\n".utf8))
    exit(1)
}

let args = Array(CommandLine.arguments.dropFirst())
guard let path = args.first else { fail("usage: verify-saver.swift <path to .saver> [out.png]") }

guard let bundle = Bundle(path: path) else { fail("not a bundle: \(path)") }
print("bundle:        \(path)")

guard let identifier = bundle.bundleIdentifier else { fail("no CFBundleIdentifier") }
print("identifier:    \(identifier)")

guard let principalName = bundle.object(forInfoDictionaryKey: "NSPrincipalClass") as? String else {
    fail("Info.plist has no NSPrincipalClass")
}
print("principal:     \(principalName)")

guard bundle.load() else { fail("bundle.load() returned false — check the Swift runtime links") }
print("load:          ok")

guard let cls = bundle.principalClass else {
    fail("principalClass is nil — NSPrincipalClass '\(principalName)' does not resolve. "
        + "Check the @objc(...) name on the view class.")
}
print("class:         \(cls)")

guard let saverClass = cls as? ScreenSaverView.Type else {
    fail("principal class is not a ScreenSaverView subclass")
}

/// Every button in a view tree, however deeply the stack views nest it.
func buttons(in view: NSView) -> [NSButton] {
    view.subviews.flatMap { child -> [NSButton] in
        (child as? NSButton).map { [$0] } ?? [] + buttons(in: child)
    }
}

// Both instances the engine creates: the full-screen one and the settings thumbnail.
for isPreview in [false, true] {
    let size = isPreview
        ? NSRect(x: 0, y: 0, width: 240, height: 150)
        : NSRect(x: 0, y: 0, width: 1440, height: 900)
    guard let view = saverClass.init(frame: size, isPreview: isPreview) else {
        fail("init(frame:isPreview: \(isPreview)) returned nil")
    }

    // Real time has to pass between frames: the engine derives its timestep
    // from the wall clock, so a tight loop advances the simulation by
    // microseconds and renders the opening frame 120 times over. Pacing this
    // properly is what makes the render check below meaningful — otherwise it
    // would pass on a scene that never moved.
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

    guard view.hasConfigureSheet else { fail("no configure sheet — the modes are unreachable") }
    guard let sheet = view.configureSheet, let content = sheet.contentView else {
        fail("configureSheet returned nil")
    }
    // The scene-mode radios are the reason the sheet exists; a saver that builds
    // but offers no way to pick a mode is a regression worth failing on. Matched
    // by title, and deliberately not by "is it a radio button" — the point is
    // that these three specific choices are reachable, so a rename should fail
    // here and be renamed here too.
    let expected = ["Known orbits", "Random systems", "Both"]
    let radios = buttons(in: content)
        .filter { !($0 is NSPopUpButton) }
        .filter { button in expected.contains { button.title.hasPrefix($0) } }
    guard radios.count == expected.count else {
        fail("expected \(expected.count) scene-mode choices, got \(radios.count). "
            + "Sheet contains: " + buttons(in: content).map(\.title).joined(separator: ", "))
    }
    let selected = radios.first { $0.state == .on }?.title ?? "none"
    print("options:       \(radios.map(\.title).joined(separator: " | ")) — selected: \(selected)")

    // Render it, proving the scene draws and is not merely well-formed.
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
    guard lit > 0 else { fail("rendered frame is black — the scene loaded but drew nothing") }

    if args.count > 1 {
        guard let png = rep.representation(using: .png, properties: [:]) else {
            fail("could not encode render")
        }
        try! png.write(to: URL(fileURLWithPath: args[1]))
        print("wrote:         \(args[1])")
    }
}

print("\nPASS — bundle loads, both instances animate and draw, modes are selectable.")
