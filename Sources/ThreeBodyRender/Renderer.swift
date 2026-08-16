import AppKit
import CoreGraphics
import ThreeBodyCore

/// Draws the simulation with Core Graphics.
///
/// Everything luminous is composited with `.plusLighter` so overlapping trails
/// and glows add up the way light does, which is what makes a close encounter
/// flare without any per-pixel work.
public final class Renderer {

    /// One hue per body, chosen to stay distinct against black and against
    /// each other when their trails overlap.
    public static let palette: [(r: Double, g: Double, b: Double)] = [
        (1.00, 0.76, 0.34),  // amber
        (0.40, 0.82, 1.00),  // cyan
        (1.00, 0.47, 0.66),  // rose
        (0.60, 1.00, 0.66),  // green, for the odd extra body
    ]

    public static func color(at index: Int) -> (r: Double, g: Double, b: Double) {
        palette[index % palette.count]
    }

    /// Everything the cached backdrop depends on. Compared field by field each
    /// frame, so the check costs nothing.
    private struct BackgroundKey: Equatable {
        var width: Double
        var height: Double
        var scale: Double
    }

    private var starField = StarField()
    private var backgroundGradient: CGGradient?
    private var backgroundImage: CGImage?
    private var backgroundKey: BackgroundKey?
    private var glowGradients: [Int: CGGradient] = [:]
    private let colorSpace = CGColorSpaceCreateDeviceRGB()

    /// Shrinks text and line weights for the System Settings preview thumbnail.
    /// Fonts depend on it, so changing it drops the cached ones.
    public var uiScale: Double = 1.0 {
        didSet {
            guard uiScale != oldValue else { return }
            titleFont = nil
            bodyFont = nil
        }
    }

    public init() {}

    private var titleFont: NSFont?
    private var bodyFont: NSFont?

    /// `time` is a monotonic clock in seconds, used only for the star drift.
    public func draw(
        engine: SimulationEngine,
        in ctx: CGContext,
        size: CGSize,
        time: Double,
        showHUD: Bool
    ) {

        let visibility = engine.visibility

        // Repainting the background gradient every frame was the single largest
        // cost in the renderer — several million pixels of it — so it is drawn
        // once into an image and blitted. (A `CGLayer` is the obvious tool and
        // measures ~45× slower than a plain `CGImage`; it never reaches an
        // accelerated blit path.)
        //
        // The stars are *not* baked in with it, because they drift. Drawing
        // them live costs about a tenth of a millisecond: it was never the
        // stars that were expensive.
        if let image = cachedBackground(for: ctx, size: size) {
            ctx.draw(image, in: CGRect(origin: .zero, size: size))
        } else {
            drawBackground(in: ctx, size: size)
        }

        if engine.settings.showStars {
            starField.regenerateIfNeeded(size: size, density: engine.settings.starDensity)
            starField.draw(
                in: ctx, size: size, time: time, alpha: 1.0,
                pixelScale: Renderer.pixelScale(of: ctx))
        }

        let viewSize = (width: Double(size.width), height: Double(size.height))

        ctx.saveGState()
        ctx.setBlendMode(.plusLighter)
        ctx.setLineCap(.round)
        ctx.setLineJoin(.round)

        for view in engine.bodyViews {
            drawTrail(
                view.trail,
                colorIndex: view.colorIndex,
                camera: engine.camera,
                viewSize: viewSize,
                alpha: visibility,
                in: ctx)
        }

        let masses = engine.system.bodies.map { $0.mass }
        let referenceMass = masses.max() ?? 1
        for (index, body) in engine.system.bodies.enumerated() {
            drawBody(
                body,
                colorIndex: engine.colorIndex(at: index),
                referenceMass: referenceMass,
                camera: engine.camera,
                viewSize: viewSize,
                alpha: visibility,
                glow: engine.settings.showGlow,
                in: ctx)
        }

        if let ending = engine.ending {
            drawEnding(
                ending,
                camera: engine.camera,
                viewSize: viewSize,
                in: ctx)
        }

        ctx.restoreGState()

        if showHUD {
            drawHUD(engine: engine, size: size, alpha: visibility)
        }
    }

    // MARK: - Scene endings

    /// The send-off for a scene that resolved itself.
    ///
    /// Both effects are drawn in screen-space radii anchored to a world-space
    /// point, so they keep their weight while the camera continues to drift and
    /// zoom underneath them. Neither is scaled by `visibility`: they are at
    /// their brightest exactly as the scene begins to fade, which is what makes
    /// the fade read as a consequence rather than a cut.
    private func drawEnding(
        _ ending: SceneEnding,
        camera: Camera,
        viewSize: (width: Double, height: Double),
        in ctx: CGContext
    ) {
        let p = camera.project(ending.position, viewSize: viewSize)
        let center = CGPoint(x: p.x, y: p.y)
        let age = ending.age

        switch ending.kind {
        case .collision:
            // A hard, fast flash, then a shockwave that outruns it.
            let flash = falloff(age, over: 0.35)
            if flash > 0 {
                ctx.setFillColor(red: 1, green: 1, blue: 1, alpha: CGFloat(0.85 * flash))
                let r = CGFloat((10.0 + 26.0 * (1 - flash)) * uiScale)
                ctx.fillEllipse(
                    in: CGRect(
                        x: center.x - r, y: center.y - r,
                        width: r * 2, height: r * 2))
            }
            // Two rings at different speeds give the blast some depth.
            let color = blend(ending.colorIndices)
            ring(
                at: center, age: age, duration: 1.5, maxRadius: 230,
                width: 3.0, peakAlpha: 0.55, color: color, in: ctx)
            ring(
                at: center, age: age - 0.12, duration: 2.1, maxRadius: 330,
                width: 1.4, peakAlpha: 0.22, color: color, in: ctx)

        case .escape:
            // Quieter: one slow ring marking where the system let go.
            let color = blend(ending.colorIndices)
            ring(
                at: center, age: age, duration: 2.4, maxRadius: 150,
                width: 1.6, peakAlpha: 0.40, color: color, in: ctx)
        }
    }

    /// Expanding ring: radius eases out while the stroke thins and fades, so it
    /// reads as energy dissipating rather than a circle being scaled up.
    private func ring(
        at center: CGPoint,
        age: Double,
        duration: Double,
        maxRadius: Double,
        width: Double,
        peakAlpha: Double,
        color: (r: Double, g: Double, b: Double),
        in ctx: CGContext
    ) {
        guard age > 0, age < duration else { return }
        let t = age / duration
        // Cubic ease-out: fast expansion that decelerates.
        let eased = 1 - pow(1 - t, 3)
        let radius = maxRadius * eased * uiScale
        guard radius > 0.5 else { return }

        let alpha = peakAlpha * pow(1 - t, 1.6)
        ctx.setLineWidth(CGFloat(width * (1 - t * 0.75) * uiScale))
        ctx.setStrokeColor(
            red: CGFloat(color.r), green: CGFloat(color.g),
            blue: CGFloat(color.b), alpha: CGFloat(alpha))
        ctx.strokeEllipse(
            in: CGRect(
                x: center.x - CGFloat(radius),
                y: center.y - CGFloat(radius),
                width: CGFloat(radius * 2),
                height: CGFloat(radius * 2)))
    }

    /// 0 at `duration`, 1 at age 0 — a quick decay for the impact flash.
    private func falloff(_ age: Double, over duration: Double) -> Double {
        guard age >= 0, age < duration else { return 0 }
        return pow(1 - age / duration, 2.0)
    }

    /// Average of the palette colours involved, so a merge flashes in the
    /// mixture of the two bodies that made it.
    private func blend(_ indices: [Int]) -> (r: Double, g: Double, b: Double) {
        guard !indices.isEmpty else { return (1, 1, 1) }
        var sum = (r: 0.0, g: 0.0, b: 0.0)
        for index in indices {
            let c = Renderer.color(at: index)
            sum.r += c.r
            sum.g += c.g
            sum.b += c.b
        }
        let n = Double(indices.count)
        return (sum.r / n, sum.g / n, sum.b / n)
    }

    // MARK: - Background

    /// Rebuilt only when the view size or backing scale changes.
    private func cachedBackground(for ctx: CGContext, size: CGSize) -> CGImage? {
        // Render the cache at the destination's real pixel density, so a
        // Retina display gets a crisp gradient rather than an upscaled blur.
        let scale = CGFloat(Renderer.pixelScale(of: ctx))

        let key = BackgroundKey(
            width: Double(size.width),
            height: Double(size.height),
            scale: Double(scale))
        if key == backgroundKey, let image = backgroundImage { return image }

        let width = Int(size.width * scale)
        let height = Int(size.height * scale)
        guard width > 0, height > 0,
            let bitmap = CGContext(
                data: nil,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: 0,
                space: colorSpace,
                bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue)
        else { return nil }

        bitmap.scaleBy(x: scale, y: scale)
        drawBackground(in: bitmap, size: size)
        backgroundImage = bitmap.makeImage()
        backgroundKey = key
        return backgroundImage
    }

    /// Backing-store pixels per point for whatever this context draws into.
    public static func pixelScale(of ctx: CGContext) -> Double {
        let transform = ctx.userSpaceToDeviceSpaceTransform
        let determinant = abs(transform.a * transform.d - transform.b * transform.c)
        return min(max(Double(determinant.squareRoot()), 1.0), 3.0)
    }

    private func drawBackground(in ctx: CGContext, size: CGSize) {
        if backgroundGradient == nil {
            // Not pure black: a faint cool-to-warm shift gives the void depth.
            let colors = [
                CGColor(colorSpace: colorSpace, components: [0.016, 0.020, 0.035, 1])!,
                CGColor(colorSpace: colorSpace, components: [0.008, 0.009, 0.016, 1])!,
                CGColor(colorSpace: colorSpace, components: [0.020, 0.014, 0.020, 1])!,
            ]
            backgroundGradient = CGGradient(
                colorsSpace: colorSpace,
                colors: colors as CFArray,
                locations: [0.0, 0.55, 1.0])
        }
        ctx.setFillColor(gray: 0, alpha: 1)
        ctx.fill(CGRect(origin: .zero, size: size))
        if let gradient = backgroundGradient {
            ctx.drawLinearGradient(
                gradient,
                start: CGPoint(x: 0, y: size.height),
                end: CGPoint(x: size.width, y: 0),
                options: [])
        }
    }

    // MARK: - Trails

    /// Drawn as a series of constant-alpha bands rather than per-segment
    /// gradients: a smooth ramp at a fraction of the cost.
    private func drawTrail(
        _ trail: Trail,
        colorIndex: Int,
        camera: Camera,
        viewSize: (width: Double, height: Double),
        alpha: Double,
        in ctx: CGContext
    ) {
        let color = Renderer.color(at: colorIndex)
        let samples = trail.samples
        guard samples.count >= 2, alpha > 0.01 else { return }

        // Project once and reuse for both the banded pass and the bloom pass;
        // projection was showing up as pure duplicated work.
        var points = [CGPoint]()
        points.reserveCapacity(samples.count)
        for sample in samples {
            let p = camera.project(sample.position, viewSize: viewSize)
            points.append(CGPoint(x: p.x, y: p.y))
        }

        let bandCount = min(20, max(4, points.count / 3))
        for band in 0..<bandCount {
            let start = points.count * band / bandCount
            // Overlap by one sample so the bands join without gaps.
            let end = min(points.count, points.count * (band + 1) / bandCount + 1)
            guard end - start >= 2 else { continue }

            // 0 at the tail's far end, 1 at the body.
            let t = Double(band) / Double(bandCount - 1)
            let fade = t * t

            ctx.setLineWidth(CGFloat((0.5 + 1.9 * t) * uiScale))
            ctx.setStrokeColor(
                red: CGFloat(color.r), green: CGFloat(color.g),
                blue: CGFloat(color.b), alpha: CGFloat(0.80 * fade * alpha))
            ctx.beginPath()
            ctx.addLines(between: Array(points[start..<end]))
            ctx.strokePath()
        }

        // One wide, dim pass over the freshest third of the tail reads as bloom
        // around the fast-moving body — cheaper and smoother than blooming
        // every band separately.
        // Antialiasing is switched off for it: on a wide, soft, 5%-alpha stroke
        // the difference is invisible, and it is by far the most expensive
        // thing the renderer does with antialiasing on.
        let bloomStart = points.count * 2 / 3
        if points.count - bloomStart >= 2 {
            ctx.setShouldAntialias(false)
            ctx.setLineWidth(CGFloat(6.0 * uiScale))
            ctx.setStrokeColor(
                red: CGFloat(color.r), green: CGFloat(color.g),
                blue: CGFloat(color.b), alpha: CGFloat(0.05 * alpha))
            ctx.beginPath()
            ctx.addLines(between: Array(points[bloomStart...]))
            ctx.strokePath()
            ctx.setShouldAntialias(true)
        }
    }

    // MARK: - Bodies

    /// One radial gradient per palette colour, built once. Scene fades are
    /// applied with the context's global alpha instead of rebuilding it.
    private func glowGradient(for index: Int) -> CGGradient? {
        if let cached = glowGradients[index] { return cached }
        let color = Renderer.color(at: index)
        let inner = CGColor(
            colorSpace: colorSpace,
            components: [
                CGFloat(color.r), CGFloat(color.g),
                CGFloat(color.b), 0.55,
            ])!
        let outer = CGColor(
            colorSpace: colorSpace,
            components: [
                CGFloat(color.r), CGFloat(color.g),
                CGFloat(color.b), 0,
            ])!
        let gradient = CGGradient(
            colorsSpace: colorSpace,
            colors: [inner, outer] as CFArray,
            locations: [0.0, 1.0])
        glowGradients[index] = gradient
        return gradient
    }

    private func drawBody(
        _ body: Body,
        colorIndex: Int,
        referenceMass: Double,
        camera: Camera,
        viewSize: (width: Double, height: Double),
        alpha: Double,
        glow: Bool,
        in ctx: CGContext
    ) {
        guard alpha > 0.01 else { return }
        let color = Renderer.color(at: colorIndex)
        let p = camera.project(body.position, viewSize: viewSize)
        let center = CGPoint(x: p.x, y: p.y)

        // Point masses have no physical radius, so size encodes mass instead:
        // the cube root keeps a 5:1 mass ratio from looking like a 5:1 disc.
        let massFactor = pow(max(body.mass, 1e-6) / max(referenceMass, 1e-6), 1.0 / 3.0)
        let core = (2.0 + 2.1 * massFactor) * uiScale

        if glow, let gradient = glowGradient(for: colorIndex) {
            ctx.saveGState()
            ctx.setAlpha(CGFloat(alpha))
            ctx.drawRadialGradient(
                gradient,
                startCenter: center, startRadius: 0,
                endCenter: center, endRadius: CGFloat(core * 7.0),
                options: [])
            ctx.restoreGState()
        }

        // Tinted halo, then a white-hot core, so the body always reads as a
        // light source rather than a coloured dot.
        ctx.setFillColor(
            red: CGFloat(color.r), green: CGFloat(color.g),
            blue: CGFloat(color.b), alpha: CGFloat(0.95 * alpha))
        ctx.fillEllipse(
            in: CGRect(
                x: center.x - CGFloat(core),
                y: center.y - CGFloat(core),
                width: CGFloat(core * 2),
                height: CGFloat(core * 2)))

        let hot = core * 0.45
        ctx.setFillColor(red: 1, green: 1, blue: 1, alpha: CGFloat(0.9 * alpha))
        ctx.fillEllipse(
            in: CGRect(
                x: center.x - CGFloat(hot),
                y: center.y - CGFloat(hot),
                width: CGFloat(hot * 2),
                height: CGFloat(hot * 2)))
    }

    // MARK: - HUD

    private func drawHUD(engine: SimulationEngine, size: CGSize, alpha: Double) {
        guard alpha > 0.02, size.width > 260 else { return }

        let scale = uiScale
        let titleFont = cachedTitleFont()
        let bodyFont = cachedBodyFont()

        let stats = engine.stats
        let scenario = engine.scenario

        var lines: [(String, NSFont, Double)] = []
        lines.append((scenario.name, titleFont, 0.92))
        lines.append((scenario.credit, bodyFont, 0.45))
        lines.append(("", bodyFont, 0))

        // Elapsed time and separations in units a person can picture, rather
        // than the dimensionless numbers the integrator works in.
        var timeLine = String(
            format: "t = %@   step = %@",
            Units.formatTime(stats.simulatedTime),
            Units.formatShortDuration(stats.lastStepSize))
        let rate = engine.playbackRate
        if abs(rate - 1) > 0.08 {
            timeLine +=
                rate < 1
                ? String(format: "   ×%.2f speed", rate)
                : String(format: "   ×%.1f speed", rate)
        }
        lines.append((timeLine, bodyFont, 0.42))

        lines.append(
            (
                String(
                    format: "%@ · %.0f evals/s   ΔE/E = %@   ΔL = %@   closest %@",
                    engine.settings.accuracy.order.displayName,
                    stats.forceEvaluationsPerSecond,
                    scientific(stats.relativeEnergyError),
                    scientific(stats.angularMomentumError),
                    Units.formatDistance(stats.minimumSeparation)),
                bodyFont, 0.42
            ))

        if let ending = engine.ending {
            // Say what resolved the system, and brighten it — this is the one
            // line in the readout worth actually reading.
            switch ending.kind {
            case .escape:
                lines.append(("body ejected — the triple has broken up", bodyFont, 0.75))
            case .collision:
                lines.append(
                    (
                        String(
                            format: "collision — bodies merged, shedding %@ × |E| as heat",
                            scientific(ending.energyLostRelative)),
                        bodyFont, 0.75
                    ))
            }
        } else if stats.stepBudgetExhausted {
            lines.append(("close encounter — running in slow motion", bodyFont, 0.55))
        }

        let padding = 26.0 * scale
        let lineHeight = 15.0 * scale
        var y = padding + Double(lines.count - 1) * lineHeight

        for (text, font, opacity) in lines where !text.isEmpty {
            let attributes: [NSAttributedString.Key: Any] = [
                .font: font,
                .foregroundColor: NSColor(white: 1, alpha: CGFloat(opacity * alpha)),
            ]
            (text as NSString).draw(at: NSPoint(x: padding, y: y), withAttributes: attributes)
            y -= lineHeight
        }

        drawMassLegend(engine: engine, size: size, alpha: alpha, scale: scale, font: bodyFont)
    }

    /// Built once and reused: `uiScale` is fixed for the life of the view, so
    /// rebuilding these at 60 fps was pure churn.
    private func cachedTitleFont() -> NSFont {
        if let font = titleFont { return font }
        let font = NSFont.systemFont(ofSize: 15 * uiScale, weight: .medium)
        titleFont = font
        return font
    }

    private func cachedBodyFont() -> NSFont {
        if let font = bodyFont { return font }
        let font = NSFont.monospacedSystemFont(ofSize: 10.5 * uiScale, weight: .regular)
        bodyFont = font
        return font
    }

    /// A colour key in the corner: which dot is which mass.
    private func drawMassLegend(
        engine: SimulationEngine,
        size: CGSize,
        alpha: Double,
        scale: Double,
        font: NSFont
    ) {
        guard size.width > 520 else { return }
        let padding = 26.0 * scale
        let lineHeight = 15.0 * scale
        var y = padding + Double(engine.system.bodies.count - 1) * lineHeight

        for (index, body) in engine.system.bodies.enumerated() {
            let color = Renderer.color(at: engine.colorIndex(at: index))
            let text = Units.formatMass(body.mass)
            let attributes: [NSAttributedString.Key: Any] = [
                .font: font,
                .foregroundColor: NSColor(
                    calibratedRed: CGFloat(color.r),
                    green: CGFloat(color.g),
                    blue: CGFloat(color.b),
                    alpha: CGFloat(0.6 * alpha)),
            ]
            let width = (text as NSString).size(withAttributes: attributes).width
            (text as NSString).draw(
                at: NSPoint(x: Double(size.width) - padding - Double(width), y: y),
                withAttributes: attributes)
            y -= lineHeight
        }
    }

    private func scientific(_ value: Double) -> String {
        guard value.isFinite else { return "—" }
        if value == 0 { return "0" }
        return String(format: "%.2e", value)
    }
}
