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
/// motion here is deliberately exaggerated by `parallax`, in the same spirit as the
/// compressed drift rate. See `driftFractionOfTrue` for the equivalent honesty knob on
/// the drift.
///
/// The stars fill a cube around the Sun and stream along the drift axis through it
/// indefinitely. Each one wraps on its own, in the vertex shader: leaving the trailing
/// face it reappears at the leading one, fading out over the last stretch before the
/// face and back in after it, so no star ever pops and the field never resets.
///
/// It used to be three copies of one slab moved as a whole and snapped back by a slab
/// length every couple of minutes. Inside the field that snap was invisible, but at
/// its ends a whole slab's worth of stars appeared and vanished at once — visible
/// along the drift axis as the sky resetting. Wrapping per star also means every star
/// is a different star rather than one of three copies, for the same vertex count.
///
/// The per-frame cost is one shader uniform: the CPU never touches a vertex.
final class StarField {

    let node: SCNNode
    /// Edge of the cube along the drift axis, which is the period stars wrap with.
    private let length: Double
    private let parallax: Double
    private let material: SCNMaterial

    /// Fraction of each half of the cube, at either end, over which a star fades
    /// out before it wraps and back in after.
    private static let fadeFraction = 0.2

    /// `sceneExtent` sizes the field. A fixed size works only for one scale: at true
    /// scale the scene is ~130× larger and the camera would end up outside the field,
    /// which renders it as a visible cube of dots rather than a sky.
    init(
        count: Int = 15_000,
        sceneExtent: Double,
        parallax: Double,
        seed: UInt64 = 0x5EED_5A1A_D000_1234
    ) {
        // As deep as it is wide, so looking along the drift axis shows no more stars
        // than looking across it — the clumping an elongated field produced.
        let length = sceneExtent * 30
        self.length = length
        self.parallax = parallax

        // Generated in the galactic frame, whose +y is the Sun's direction of travel
        // (`GalacticFrame.solarApexDirection`) — the axis the stars stream along.
        var rng = SplitMix64(seed: seed)
        var vertices = [Float]()
        vertices.reserveCapacity(count * 3)
        var colors = [Float]()
        colors.reserveCapacity(count * 4)
        for _ in 0..<count {
            vertices.append(Float((rng.nextDouble() - 0.5) * length))
            vertices.append(Float((rng.nextDouble() - 0.5) * length))
            vertices.append(Float((rng.nextDouble() - 0.5) * length))
            // Power-law brightness: mostly faint, a few bright.
            let b = pow(rng.nextDouble(), 2.6) * 0.78 + 0.10
            let w = rng.nextDouble()
            colors.append(Float(b * (0.85 + 0.25 * w)))
            colors.append(Float(b * 0.92))
            colors.append(Float(b * (1.10 - 0.25 * w)))
            colors.append(1.0)
        }

        let element = Geometry.element(
            (0..<count).map { UInt32($0) }, primitiveType: .point, primitiveCount: count)
        // Screen-space radii are in pixels, so these need to be generous or the field
        // renders as invisible sub-pixel specks on a Retina panel.
        element.pointSize = 3.0
        element.minimumPointScreenSpaceRadius = 1.5
        element.maximumPointScreenSpaceRadius = 4.0

        // Its own material, not a shared one: the scroll offset is set on it every
        // frame, and the screensaver's two live instances must not share one.
        material = Geometry.unlitMaterial(blend: .alpha, doubleSided: false)
        material.shaderModifiers = [.geometry: Self.wrap]
        material.setValue(Float(length), forKey: "starPeriod")
        material.setValue(Float(Self.fadeFraction), forKey: "starFade")
        material.setValue(Float(0), forKey: "starScroll")

        let geometry = SCNGeometry(
            sources: [Geometry.vertexSource(vertices), Geometry.colorSource(colors)],
            elements: [element])
        geometry.materials = [material]
        node = SCNNode(geometry: geometry)
        node.castsShadow = false
    }

    /// Slides every star back along the drift axis by its scroll offset, wrapped into
    /// the cube, and fades it near the faces it wraps between.
    private static let wrap = """
        uniform float starPeriod;
        uniform float starFade;
        uniform float starScroll;

        #pragma body
        float y = _geometry.position.y - starScroll;
        y -= starPeriod * floor(y / starPeriod + 0.5);
        _geometry.position.y = y;
        float edge = 0.5 * starPeriod;
        _geometry.color.rgb *= 1.0 - smoothstep(edge * (1.0 - starFade), edge, abs(y));
        """

    /// `driftDistance` is how far the Sun has travelled along its galactic orbit, in
    /// scene units. Stars slide the opposite way.
    ///
    /// Reduced modulo the field's length here, in double precision, before it goes to
    /// the GPU as a float: the shader wraps with that same period, so the reduction
    /// changes nothing on screen, and the float it is handed stays small however long
    /// the screensaver has been running.
    func update(driftDistance: Double) {
        material.setValue(
            Float((driftDistance * parallax).wrapped(modulo: length)), forKey: "starScroll")
    }
}
