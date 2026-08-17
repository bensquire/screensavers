import AppKit
import Foundation
import SpriteKit

/// A very faint simulated-date readout in the bottom-right corner.
///
/// Drawn as a SpriteKit overlay rather than an `NSView` on top, so it is part of what the
/// renderer produces — which means it appears in the offscreen `--render` path too, not
/// just in a live window.
final class DateOverlay {

    let scene: SKScene
    private let label: SKLabelNode
    private let formatter: DateFormatter
    /// The font and the string's advance width are pure functions of the point size, so
    /// they are cached against it. The *text* is not cached: at the default speed the date
    /// changes every single frame, so guarding on it never hits — and the guard was
    /// wrapped around the cheap half while the CoreText measurement ran regardless.
    private var cached: (fontSize: CGFloat, font: NSFont, advance: CGFloat)?

    /// Fraction of the view's height used for the type size, so it reads the same on a
    /// laptop panel and a 5K display.
    private static let relativeFontSize: CGFloat = 0.016
    /// Inset from the corner, again as a fraction of height.
    private static let relativeMargin: CGFloat = 0.022

    /// Explicit sizing, for the offscreen renderer where nothing else will set it.
    func setSize(_ size: CGSize) {
        guard size.width > 1, size.height > 1, scene.size != size else { return }
        scene.size = size
    }

    init() {
        formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_GB")
        // Fixed character count so the string never changes width: a zero-padded day and
        // a three-letter month. Combined with a monospaced face and right alignment, the
        // readout is completely static even though it advances every frame.
        formatter.dateFormat = "dd MMM yyyy"
        formatter.timeZone = TimeZone(identifier: "UTC")

        label = SKLabelNode()
        // Positioned off the font's own metrics, not off the rendered glyphs.
        //
        // SKLabelNode's alignment modes work on the node's frame, which is the *ink* of
        // the text — and ink varies with the characters even in a monospaced face: a
        // month with a descender ("Sep") is 2.6px taller than one without ("Feb"), and
        // ink widths differ by ~0.6px. Aligning `.bottom`/`.right` therefore shifts the
        // whole string whenever the date changes. The baseline is glyph-independent, and
        // every date here starts with a digit so the left ink edge is stable too.
        label.horizontalAlignmentMode = .left
        label.verticalAlignmentMode = .baseline

        scene = SKScene(size: CGSize(width: 100, height: 100))
        scene.scaleMode = .resizeFill
        scene.backgroundColor = .clear
        scene.addChild(label)
    }

    /// Positions against the scene's *own* size rather than a size passed in.
    ///
    /// `scaleMode = .resizeFill` means SpriteKit resizes the scene to match whatever is
    /// hosting it. Assigning `scene.size` as well means two owners writing the same
    /// property, and the label — whose position is in scene coordinates — lands somewhere
    /// different depending on which write happened last. That is the wobble. Reading the
    /// value instead of setting it leaves exactly one owner.
    func update(date: Date) {
        let size = scene.size
        guard size.width > 1, size.height > 1 else { return }

        let fontSize = max(9, size.height * Self.relativeFontSize)
        let text = formatter.string(from: date)

        // Advance width is identical for every date in this format, so the right edge
        // lands in the same place each time.
        let metrics: (fontSize: CGFloat, font: NSFont, advance: CGFloat)
        if let cached, cached.fontSize == fontSize {
            metrics = cached
        } else {
            let font = NSFont.monospacedSystemFont(ofSize: fontSize, weight: .regular)
            metrics = (fontSize, font, (text as NSString).size(withAttributes: [.font: font]).width)
            cached = metrics
        }

        let margin = size.height * Self.relativeMargin
        label.position = CGPoint(x: size.width - margin - metrics.advance, y: margin)

        // Set through an attributed string rather than `fontNamed:`, which silently falls
        // back to a proportional face when the name does not resolve — and "SFMono-Regular"
        // does not, so the digits jittered. `monospacedSystemFont` is guaranteed to exist
        // and to be fixed-pitch.
        label.attributedText = NSAttributedString(
            string: text,
            attributes: [
                .font: metrics.font,
                // Faint enough to be missed unless looked for, which is the point.
                .foregroundColor: NSColor(white: 1, alpha: 0.28),
            ]
        )
    }
}
