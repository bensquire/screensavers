import Foundation
import SaverKit
import SceneKit
import SolarSystemCore
import simd

/// A star field that scrolls past as the Sun travels, so the scene reads as motion.
///
/// The scene is rendered Sun-relative, which means the helix of trails is static in
/// that frame and the Sun never moves on screen. That is what you would actually see
/// flying alongside the Sun — so the *only* available cue of travel is the stars going
/// past. Real parallax cannot supply it: over the trail window the Sun covers a few
/// thousand AU while the nearest star sits 268,000 AU away — well under a degree. So star
/// motion
/// here is deliberately exaggerated by `parallax`, in the same spirit as the compressed
/// drift rate. See `driftFractionOfTrue` for the equivalent honesty knob on the drift.
///
/// Scrolling is seamless and runs indefinitely: the slab of stars is tiled three times
/// along the drift axis and the node is translated by the drift distance modulo the slab
/// length. Because the tiling is periodic with exactly that length, the wrap-around is
/// invisible, and the per-frame cost is one node translation rather than rewriting
/// thousands of vertices. That matters for something left running for hours.
final class StarField {

    let node: SCNNode
    private let slabLength: Double
    private let parallax: Double

    /// `sceneExtent` sizes the slab. A fixed slab works only for one scale: at true
    /// scale the scene is ~130× larger and the camera ends up outside the field, which
    /// renders it as a visible cube of dots rather than a sky.
    /// Tiles laid along the drift axis, for the seamless wrap.
    private static let tileCount = 3

    init(
        countPerTile: Int = 5_000,
        sceneExtent: Double,
        parallax: Double,
        seed: UInt64 = 0x5EED_5A1A_D000_1234
    ) {
        let slabLength = sceneExtent * 10
        // Half-width chosen so the tiled field is as deep across as it is along the
        // drift axis. Tiling makes the axial span `tileCount × slabLength`; if the
        // lateral span does not match, looking along the axis shows several times more
        // stars than looking across it, and the field visibly clumps to one side.
        let lateralExtent = slabLength * Double(Self.tileCount) / 2
        // A *fixed* count, not a fixed volumetric density. Every dimension is already
        // proportional to the scene, so holding the count constant is what keeps the
        // apparent density the same at any scale — tying it to volume instead makes the
        // large scenes dense and the small ones bare.
        self.slabLength = slabLength
        self.parallax = parallax

        // Generated in the galactic frame, whose +y is the Sun's direction of travel
        // (`GalacticFrame.solarApexDirection`) — the axis the slab is long along and
        // scrolls down.
        var rng = SplitMix64(seed: seed)
        var base: [SIMD3<Double>] = []
        var brightness: [Double] = []
        var warmth: [Double] = []
        base.reserveCapacity(countPerTile)

        for _ in 0..<countPerTile {
            base.append(
                SIMD3(
                    (rng.nextDouble() * 2 - 1) * lateralExtent,
                    (rng.nextDouble() - 0.5) * slabLength,
                    (rng.nextDouble() * 2 - 1) * lateralExtent
                ))
            // Power-law brightness: mostly faint, a few bright.
            brightness.append(pow(rng.nextDouble(), 2.6) * 0.78 + 0.10)
            warmth.append(rng.nextDouble())
        }

        node = SCNNode(
            geometry: StarField.geometry(
                base: base, brightness: brightness, warmth: warmth, slabLength: slabLength
            ))
        node.castsShadow = false
    }

    /// `driftDistance` is how far the Sun has travelled along its galactic orbit, in
    /// scene units. Stars slide the opposite way.
    func update(driftDistance: Double) {
        // Wrapped symmetrically about zero rather than into [0, slabLength). A one-sided
        // offset pushes the tiled field up to a whole slab off-centre, and the camera can
        // then see past its leading edge — which reads as the stars thinning out on one
        // side and bunching on the other.
        var wrapped = (driftDistance * parallax).truncatingRemainder(dividingBy: slabLength)
        if wrapped < -slabLength / 2 { wrapped += slabLength }
        if wrapped > slabLength / 2 { wrapped -= slabLength }
        // Taken from the frame rather than written as -y, so this cannot silently
        // disagree with the drift distance the renderer measures along the same axis.
        let back = -GalacticFrame.solarApexDirection * wrapped
        node.position = SCNVector3(back.x, back.y, back.z)
    }

    /// Three copies of the slab, offset by ±slabLength along the drift axis, so the
    /// scrolled field is always covered and the wrap is seamless.
    private static func geometry(
        base: [SIMD3<Double>], brightness: [Double], warmth: [Double], slabLength: Double
    ) -> SCNGeometry {
        // Derived from `tileCount`, which also sizes the lateral extent — written as a
        // literal the two silently disagree, which is the clumping this was built to fix.
        let mid = Double(Self.tileCount - 1) / 2
        let tiles = (0..<Self.tileCount).map { (Double($0) - mid) * slabLength }
        let total = base.count * tiles.count

        var vertices = [Float]()
        vertices.reserveCapacity(total * 3)
        var colors = [Float]()
        colors.reserveCapacity(total * 4)

        for tile in tiles {
            for (i, p) in base.enumerated() {
                vertices.append(Float(p.x))
                vertices.append(Float(p.y + tile))
                vertices.append(Float(p.z))

                let b = brightness[i], w = warmth[i]
                colors.append(Float(b * (0.85 + 0.25 * w)))
                colors.append(Float(b * 0.92))
                colors.append(Float(b * (1.10 - 0.25 * w)))
                colors.append(1.0)
            }
        }

        let indices = (0..<total).map { UInt32($0) }

        let element = Geometry.element(
            indices, primitiveType: .point, primitiveCount: total
        )
        // Screen-space radii are in pixels, so these need to be generous or the field
        // renders as invisible sub-pixel specks on a Retina panel.
        element.pointSize = 3.0
        element.minimumPointScreenSpaceRadius = 1.5
        element.maximumPointScreenSpaceRadius = 4.0

        let geometry = SCNGeometry(
            sources: [Geometry.vertexSource(vertices), Geometry.colorSource(colors)],
            elements: [element]
        )
        geometry.materials = [Geometry.unlit]
        return geometry
    }
}
