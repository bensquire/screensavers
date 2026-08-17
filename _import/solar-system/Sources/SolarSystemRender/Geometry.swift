import Foundation
import SceneKit
import simd

enum Geometry {

    // MARK: - Buffer plumbing

    private static let floatStride = MemoryLayout<Float>.stride
    private static let indexStride = MemoryLayout<UInt32>.stride

    /// Packed xyz positions.
    static func vertexSource(_ floats: [Float]) -> SCNGeometrySource {
        SCNGeometrySource(
            data: Data(bytes: floats, count: floats.count * floatStride),
            semantic: .vertex, vectorCount: floats.count / 3,
            usesFloatComponents: true, componentsPerVector: 3,
            bytesPerComponent: floatStride, dataOffset: 0, dataStride: floatStride * 3
        )
    }

    /// Packed rgba colours.
    static func colorSource(_ floats: [Float]) -> SCNGeometrySource {
        SCNGeometrySource(
            data: Data(bytes: floats, count: floats.count * floatStride),
            semantic: .color, vectorCount: floats.count / 4,
            usesFloatComponents: true, componentsPerVector: 4,
            bytesPerComponent: floatStride, dataOffset: 0, dataStride: floatStride * 4
        )
    }

    static func element(
        _ indices: [UInt32], primitiveType: SCNGeometryPrimitiveType, primitiveCount: Int
    ) -> SCNGeometryElement {
        SCNGeometryElement(
            data: Data(bytes: indices, count: indices.count * indexStride),
            primitiveType: primitiveType,
            primitiveCount: primitiveCount,
            bytesPerIndex: indexStride
        )
    }

    // MARK: - Materials

    /// Unlit and depth-transparent. Trails and stars should glow through each other
    /// rather than occlude — that layered look is most of the reference image.
    ///
    /// Both variants are stateless, so one shared instance serves every geometry;
    /// SceneKit is happy for a material to be referenced from many.
    static let additive: SCNMaterial = unlitMaterial(blend: .add, doubleSided: true)
    static let unlit: SCNMaterial = unlitMaterial(blend: .alpha, doubleSided: false)

    private static func unlitMaterial(blend: SCNBlendMode, doubleSided: Bool) -> SCNMaterial {
        let m = SCNMaterial()
        m.lightingModel = .constant
        m.diffuse.contents = NSColor.white
        m.blendMode = blend
        m.writesToDepthBuffer = false
        m.readsFromDepthBuffer = false
        m.isDoubleSided = doubleSided
        return m
    }

    /// A glowing body: an unlit sphere, left to HDR bloom for its halo.
    static func bodyNode(
        radius: Double, color: (r: Double, g: Double, b: Double), boost: Double = 1.0
    ) -> SCNNode {
        let sphere = SCNSphere(radius: CGFloat(radius))
        sphere.segmentCount = 24
        let m = SCNMaterial()
        m.lightingModel = .constant
        m.diffuse.contents = NSColor(
            srgbRed: CGFloat(min(1, color.r * boost)),
            green: CGFloat(min(1, color.g * boost)),
            blue: CGFloat(min(1, color.b * boost)),
            alpha: 1
        )
        m.writesToDepthBuffer = true
        m.readsFromDepthBuffer = false
        sphere.materials = [m]
        return SCNNode(geometry: sphere)
    }
}

/// A camera-facing trail ribbon.
///
/// SceneKit has no line-width control — `.line` primitives always rasterise one pixel
/// wide, which is why trails drawn that way read as hairlines. Building the trail as
/// actual triangles is the only way to get luminous ribbons, and it has to be re-oriented
/// against the view direction every frame so it never turns edge-on and vanishes.
///
/// Only the vertex positions actually change between frames: the brightness ramp is a
/// pure function of the sample index, and the triangle indices of the sample count. Both
/// are built once here. Rebuilding all three every frame cost ~0.22 ms and ~130 KB of
/// transient allocation per frame, and handed SceneKit three new buffers to upload when
/// two of them were byte-identical to the last.
final class Ribbon {

    private let sampleCount: Int
    private let taperFrom: Double
    private let cachedColors: SCNGeometrySource
    private let cachedElement: SCNGeometryElement
    /// Reused between frames so the per-frame path allocates nothing.
    private var vertices: [Float]

    init(
        sampleCount n: Int,
        color: (r: Double, g: Double, b: Double),
        gamma: Double,
        intensity: Double,
        taperFrom: Double = 0.18
    ) {
        precondition(n >= 2, "a ribbon needs at least two samples")
        self.sampleCount = n
        self.taperFrom = taperFrom
        self.vertices = [Float](repeating: 0, count: n * 6)

        var colors = [Float]()
        colors.reserveCapacity(n * 8)
        for i in 0..<n {
            let brightness = pow(Double(i) / Double(n - 1), gamma) * intensity
            let c: [Float] = [
                Float(color.r * brightness), Float(color.g * brightness),
                Float(color.b * brightness), 1.0,
            ]
            colors.append(contentsOf: c)
            colors.append(contentsOf: c)  // both edge vertices share the ramp value
        }
        self.cachedColors = Geometry.colorSource(colors)

        var indices = [UInt32]()
        indices.reserveCapacity((n - 1) * 6)
        for i in 0..<(n - 1) {
            let a = UInt32(i * 2), b = a + 1, c = a + 2, d = a + 3
            indices.append(contentsOf: [a, b, c])
            indices.append(contentsOf: [b, d, c])
        }
        self.cachedElement = Geometry.element(
            indices, primitiveType: .triangles, primitiveCount: (n - 1) * 2
        )
    }

    /// Rebuilds the ribbon for one frame. `points` must hold `sampleCount` entries;
    /// `origin` is subtracted as we go, so the caller need not allocate a shifted copy.
    func geometry(
        points: [SIMD3<Double>],
        origin: SIMD3<Double>,
        toCamera: SIMD3<Double>,
        halfWidth: Double
    ) -> SCNGeometry? {
        guard points.count == sampleCount else { return nil }
        let n = sampleCount
        let view = simd_normalize(toCamera)

        for i in 0..<n {
            // Central difference for a smooth tangent; one-sided at the ends.
            let prev = points[max(0, i - 1)]
            let next = points[min(n - 1, i + 1)]
            var tangent = next - prev
            let tl = simd_length(tangent)
            tangent = tl > 1e-12 ? tangent / tl : SIMD3(1, 0, 0)

            var side = simd_cross(tangent, view)
            let sl = simd_length(side)
            // Tangent parallel to the view axis: any perpendicular will do, the ribbon
            // is edge-on to the camera there anyway.
            side = sl > 1e-9 ? side / sl : simd_normalize(simd_cross(tangent, SIMD3(0, 0, 1)))

            let f = Double(i) / Double(n - 1)
            let w = halfWidth * (taperFrom + (1 - taperFrom) * f)
            let centre = points[i] - origin
            let a = centre - side * w
            let b = centre + side * w

            let o = i * 6
            vertices[o + 0] = Float(a.x)
            vertices[o + 1] = Float(a.y)
            vertices[o + 2] = Float(a.z)
            vertices[o + 3] = Float(b.x)
            vertices[o + 4] = Float(b.y)
            vertices[o + 5] = Float(b.z)
        }

        let geometry = SCNGeometry(
            sources: [Geometry.vertexSource(vertices), cachedColors],
            elements: [cachedElement]
        )
        geometry.materials = [Geometry.additive]
        return geometry
    }
}

/// Small deterministic PRNG — Foundation's RandomNumberGenerator isn't reproducible
/// across processes, and reproducible starfields make render diffs meaningful.
struct SplitMix64 {
    private var state: UInt64
    init(seed: UInt64) { state = seed }

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }

    mutating func nextDouble() -> Double {
        Double(next() >> 11) * (1.0 / 9_007_199_254_740_992.0)
    }
}
