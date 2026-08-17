import Foundation
import GargantuaCore

/// The Swift halves of the structs `Gargantua.metal` declares.
///
/// These are handed to the GPU as raw memory, so field order and type must match
/// exactly. `UniformLayoutTests` asks the compiled shader for its own sizes and
/// offsets rather than trusting that they still do.
///
/// `SIMD3<Float>` is 16 bytes with 16-byte alignment in Swift, which is also
/// what MSL's `float3` is — so the two agree without any packing attributes.
struct MarchUniforms {
    var spots: (SIMD4<Float>, SIMD4<Float>, SIMD4<Float>)
    var spotShapes: (SIMD4<Float>, SIMD4<Float>, SIMD4<Float>)
    var camPos: SIMD3<Float>
    var camRight: SIMD3<Float>
    var camUp: SIMD3<Float>
    var camFwd: SIMD3<Float>
    var wind: SIMD3<Float>
    var resolution: SIMD2<Float>
    var jitter: SIMD2<Float>
    var scale: Float
    var rigid: Float
    var omegaRef: Float
    var noiseTexels: Float
    var steps: Float
    var diskIn: Float
    var diskOut: Float
    var innerEdge: Float
    var hA: Float
    var hB: Float
    var hMin: Float
    var diskStep: Float
    var stepScale: Float
    var photonStep: Float
    var photonR: Float
    var tempNorm: Float
    var diskTemp: Float
    var frameSeq: Float
    var diskEmis: Float
    var diskDens: Float
    var absorb: Float
    var turb: Float
    var warp: Float
    var noiseScale: Float
    var spiral: Float
    var redshift: Float
    var beaming: Float
    var dir: Float
    var lens: Float
    var spin: Float
    var horizon: Float
    var stars: Float
    var nebula: Float
    var flare: Float

    init(scene: GargantuaScene, resolution: SIMD2<Float>, noiseTexels: Int) {
        let p = scene.parameters
        let camera = scene.camera.current
        let half = p.diskHalfCoefficients
        let wind = scene.wind
        let spots = scene.events.spots
        let shapes = scene.events.spotShapes

        self.spots = (spots[0], spots[1], spots[2])
        self.spotShapes = (shapes[0], shapes[1], shapes[2])
        self.camPos = SIMD3(camera.position)
        self.camRight = SIMD3(camera.right)
        self.camUp = SIMD3(camera.up)
        self.camFwd = SIMD3(camera.forward)
        self.wind = wind.differential
        self.resolution = resolution
        self.jitter = scene.jitter
        self.scale = Float(camera.scale)
        self.rigid = Float(wind.rigid)
        self.omegaRef = Float(p.omegaReference)
        self.noiseTexels = Float(noiseTexels)
        self.steps = Float(p.steps)
        self.diskIn = Float(p.diskInnerRadius)
        self.diskOut = Float(p.diskOuterRadius)
        self.innerEdge = Float(p.innerEdge)
        self.hA = Float(half.a)
        self.hB = Float(half.b)
        self.hMin = Float(half.min)
        self.diskStep = Float(p.diskStep)
        self.stepScale = Float(p.stepScale)
        self.photonStep = Float(p.photonStep)
        self.photonR = Float(KerrGeometry.photonRadius(spin: p.signedSpin))
        self.tempNorm = Float(KerrGeometry.temperatureNormalisation(innerEdge: p.innerEdge))
        self.diskTemp = Float(p.diskTemp)
        self.frameSeq = scene.frameSequence
        self.diskEmis = Float(p.diskEmis)
        self.diskDens = Float(p.diskDens)
        self.absorb = Float(p.absorb)
        self.turb = Float(p.turb)
        self.warp = Float(p.warp)
        self.noiseScale = Float(p.noiseScale)
        self.spiral = Float(p.spiral)
        self.redshift = Float(p.redshift)
        self.beaming = Float(p.beaming)
        self.dir = Float(p.spinSign)
        self.lens = Float(p.lensing)
        self.spin = Float(p.signedSpin)
        self.horizon = Float(KerrGeometry.horizon(spin: p.signedSpin))
        self.stars = Float(p.stars)
        self.nebula = Float(p.nebula)
        self.flare = Float(scene.events.flare)
    }
}

struct AccumulateUniforms {
    var camPos: SIMD3<Float>
    var camRight: SIMD3<Float>
    var camUp: SIMD3<Float>
    var camFwd: SIMD3<Float>
    var prevPos: SIMD3<Float>
    var prevRight: SIMD3<Float>
    var prevUp: SIMD3<Float>
    var prevFwd: SIMD3<Float>
    var resolution: SIMD2<Float>
    var scale: Float
    var alpha: Float
    var clipK: Float
    var valid: Float
    var sharpen: Float

    init(scene: GargantuaScene, resolution: SIMD2<Float>, alpha: Float, historyValid: Bool) {
        let current = scene.camera.current
        let previous = scene.camera.previous
        self.camPos = SIMD3(current.position)
        self.camRight = SIMD3(current.right)
        self.camUp = SIMD3(current.up)
        self.camFwd = SIMD3(current.forward)
        self.prevPos = SIMD3(previous.position)
        self.prevRight = SIMD3(previous.right)
        self.prevUp = SIMD3(previous.up)
        self.prevFwd = SIMD3(previous.forward)
        self.resolution = resolution
        self.scale = Float(current.scale)
        self.alpha = alpha
        self.clipK = Float(scene.parameters.clipK)
        self.valid = historyValid ? 1 : 0
        self.sharpen = Float(scene.parameters.sharpen)
    }
}

struct BrightUniforms {
    var texel: SIMD2<Float>
    var threshold: Float
    var exposure: Float
}

struct BlurUniforms {
    var sourceTexel: SIMD2<Float>
    var destinationTexel: SIMD2<Float>
}

struct StreakUniforms {
    var texel: SIMD2<Float>
    var stride: Float
}

struct PostUniforms {
    var resolution: SIMD2<Float>
    var exposure: Float
    var bloom: Float
    var streak: Float
    var chromaticAberration: Float
    var vignette: Float
    var grain: Float
    var frame: Float

    init(scene: GargantuaScene, resolution: SIMD2<Float>) {
        let p = scene.parameters
        self.resolution = resolution
        self.exposure = Float(p.exposure)
        self.bloom = Float(p.bloom)
        self.streak = Float(p.streak)
        self.chromaticAberration = Float(p.chromaticAberration)
        self.vignette = Float(p.vignette)
        self.grain = Float(p.grain)
        self.frame = Float(scene.frameIndex % 1024)
    }
}

extension SIMD3 where Scalar == Float {
    init(_ v: SIMD3<Double>) {
        self.init(Float(v.x), Float(v.y), Float(v.z))
    }
}
