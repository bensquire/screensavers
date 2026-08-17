import AppKit
import Metal

/// A view that can hand back what it just drew.
///
/// `Scripts/verify-saver.swift` loads a built `.saver` for real and asserts that
/// it draws something. For a Core Graphics saver it can read the view's backing
/// store, but a saver drawing through a `CAMetalLayer` or SceneKit renders on
/// the GPU, where that backing store stays empty — so the check was being turned
/// off per saver, and three of four ended up asserting nothing about their
/// pixels. Since a missing or stale shader library is the single most likely way
/// one of them breaks, that was exactly the wrong thing to stop checking.
///
/// `@objc` because the verifier `dlopen`s the bundle and has no way to import
/// this module; it finds conformers through the Objective-C runtime by selector.
/// The name is deliberately specific for the same reason — it has to be unique
/// enough that nothing else answers to it by accident.
@objc public protocol SaverFrameCapturing {

    /// The most recently drawn frame, rendered afresh if that is what it takes.
    @objc func captureSaverFrame() -> NSImage?
}

extension MTLDevice {

    /// True on a virtualised GPU, which is what CI runs on.
    ///
    /// SceneKit cannot render there at all: both `SCNView.snapshot()` and an
    /// offscreen `SCNRenderer` trip an assertion inside `AppleParavirtTexture`,
    /// and an assertion aborts the process rather than returning an error, so
    /// there is nothing to catch. Metal rendering into a texture allocated
    /// directly is fine on the same device — the two Metal savers capture there
    /// without trouble — so this is not a blanket "no GPU" check.
    public var isParavirtual: Bool {
        name.localizedCaseInsensitiveContains("paravirtual")
    }
}

extension NSView {

    /// Finds the first view in this subtree that can capture a frame.
    public func firstFrameCapturingView() -> SaverFrameCapturing? {
        if let capturing = self as? SaverFrameCapturing { return capturing }
        for subview in subviews {
            if let found = subview.firstFrameCapturingView() { return found }
        }
        return nil
    }
}

extension CGImage {

    /// Wraps a rendered frame for `captureSaverFrame`.
    public var asSaverFrame: NSImage {
        NSImage(cgImage: self, size: NSSize(width: width, height: height))
    }
}
