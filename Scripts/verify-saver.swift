// End-to-end check that the built .saver is something ScreenSaverEngine can actually
// load: correct Mach-O type, principal class resolvable from Info.plist, the view
// instantiates, and its SceneKit scene renders. Run:
//
//   swift Scripts/verify-saver.swift "build/Solar System.saver" [out.png]

import Foundation
import AppKit
import SceneKit
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

// Both instances the engine creates: the full-screen one and the settings thumbnail.
for isPreview in [false, true] {
    let size = isPreview ? NSRect(x: 0, y: 0, width: 240, height: 150)
                         : NSRect(x: 0, y: 0, width: 1440, height: 900)
    guard let view = saverClass.init(frame: size, isPreview: isPreview) else {
        fail("init(frame:isPreview: \(isPreview)) returned nil")
    }

    let scnViews = view.subviews.compactMap { $0 as? SCNView }
    guard let scnView = scnViews.first else {
        fail("isPreview=\(isPreview): no SCNView subview")
    }
    guard let scene = scnView.scene else { fail("isPreview=\(isPreview): SCNView has no scene") }
    guard let pov = scnView.pointOfView else { fail("isPreview=\(isPreview): no pointOfView") }

    var nodeCount = 0
    scene.rootNode.enumerateHierarchy { _, _ in nodeCount += 1 }
    var withGeometry = 0
    scene.rootNode.enumerateHierarchy { n, _ in if n.geometry != nil { withGeometry += 1 } }

    print("instance:      isPreview=\(isPreview) nodes=\(nodeCount) geometry=\(withGeometry) "
        + "aa=\(scnView.antialiasingMode.rawValue)")

    guard withGeometry >= 9 else {
        fail("isPreview=\(isPreview): expected at least 9 geometry nodes "
           + "(sun + 8 planets), found \(withGeometry)")
    }

    view.startAnimation()
    view.animateOneFrame()
    view.stopAnimation()

    if !isPreview {
        guard view.hasConfigureSheet else { fail("no configure sheet — the toggle is unreachable") }
        guard let sheet = view.configureSheet else { fail("configureSheet returned nil") }
        let radios = (sheet.contentView?.subviews ?? []).compactMap { $0 as? NSButton }
            .filter { $0.title != "Done" }
        guard radios.count == 3 else { fail("expected three scale choices, got \(radios.count)") }
        let selected = radios.first { $0.state == .on }?.title ?? "none"
        print("options:       sheet ok — \(radios.map(\.title).joined(separator: ", ")); "
            + "selected: \(selected)")
    }

    // Render it, proving the scene is drawable and not just well-formed.
    if !isPreview, args.count > 1 {
        guard let device = MTLCreateSystemDefaultDevice() else { fail("no Metal device") }
        let renderer = SCNRenderer(device: device, options: nil)
        renderer.scene = scene
        renderer.pointOfView = pov
        let image = renderer.snapshot(
            atTime: 0, with: CGSize(width: 1440, height: 900), antialiasingMode: .multisampling4X
        )
        guard let tiff = image.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff),
              let png = rep.representation(using: .png, properties: [:]) else {
            fail("could not encode render")
        }
        try! png.write(to: URL(fileURLWithPath: args[1]))

        // A black frame would mean the scene loaded but drew nothing.
        let lit = (0..<rep.pixelsWide).reduce(into: 0) { acc, x in
            if let c = rep.colorAt(x: x, y: rep.pixelsHigh / 2), c.brightnessComponent > 0.05 {
                acc += 1
            }
        }
        print("render:        \(args[1]) — \(lit) lit pixels on centre scanline")
        guard lit > 0 else { fail("rendered frame is black") }
    }
}

print("\nPASS — bundle loads, both instances build a drawable scene.")
