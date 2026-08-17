import AppKit

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
