import CoreGraphics
import Foundation
import Metal
import SaverKit
import VortexCore

/// Draws the tunnel.
///
/// Five passes: the first four accumulate additively into an offscreen texture,
/// and the fifth resolves that to the target with chromatic aberration and a
/// vignette. Nothing here walks the particle field — it lives in two immutable
/// buffers uploaded once, and the shaders evaluate each particle's position from
/// the clock. The only per-frame upload is a few dozen bytes of uniforms, plus
/// lightning geometry on the rare frames a bolt is alive.
public final class VortexRenderer {

    /// Fraction of the target's resolution the scene is rendered at.
    ///
    /// The post pass smears colour channels apart anyway, so the softening this
    /// introduces is invisible while it removes about a third of the pixel work.
    public static let sceneScale = 0.85

    /// Frames per second — `FrameClock`'s, which is the whole fleet's.
    public static var framesPerSecond: Double { FrameClock.framesPerSecond }

    /// `setVertexBytes` takes at most 4KB. A bolt subdivides to 145 points — 290
    /// vertices, 2320 bytes — so lightning goes through the same path as the
    /// uniforms and needs no buffer of its own. `BoltTests` pins the bound.
    static let maxInlineBytes = 4096

    public let device: MTLDevice
    private let commandQueue: MTLCommandQueue

    private let backgroundPipeline: MTLRenderPipelineState
    private let streakPipeline: MTLRenderPipelineState
    private let spritePipeline: MTLRenderPipelineState
    private let boltPipeline: MTLRenderPipelineState
    private let postPipeline: MTLRenderPipelineState
    private let sceneSampler: MTLSamplerState

    /// One optional per set, so "there is a buffer" and "there is something in
    /// it" cannot disagree.
    private let streaks: (buffer: MTLBuffer, count: Int)?
    private let sprites: (buffer: MTLBuffer, count: Int)?
    /// Two triangles over four corners, shared by every streak instance.
    private let streakIndices: MTLBuffer

    private var sceneTexture: MTLTexture?

    public enum Failure: Error, CustomStringConvertible {
        case noDevice
        case noCommandQueue
        case missingFunction(String)

        public var description: String {
            switch self {
            case .noDevice: return "no Metal device"
            case .noCommandQueue: return "could not create a Metal command queue"
            case .missingFunction(let name): return "shader '\(name)' is missing"
            }
        }
    }

    public init(
        device: MTLDevice? = nil,
        library providedLibrary: MTLLibrary? = nil,
        particles: ParticleSet
    ) throws {
        guard let device = device ?? MTLCreateSystemDefaultDevice() else { throw Failure.noDevice }
        self.device = device
        guard let queue = device.makeCommandQueue() else { throw Failure.noCommandQueue }
        self.commandQueue = queue

        let library = try providedLibrary ?? ShaderLibrary.load(device: device)
        func function(_ name: String) throws -> MTLFunction {
            guard let f = library.makeFunction(name: name) else {
                throw Failure.missingFunction(name)
            }
            return f
        }

        let colorFormat = MTLPixelFormat.bgra8Unorm

        // The background fills every pixel, so it is the one scene pass that does
        // not blend. Everything after it adds light to what is already there.
        backgroundPipeline = try VortexRenderer.pipeline(
            device: device, label: "background",
            vertex: function("quad_vertex"), fragment: function("background_fragment"),
            format: colorFormat, additive: false)
        streakPipeline = try VortexRenderer.pipeline(
            device: device, label: "streak",
            vertex: function("streak_vertex"), fragment: function("streak_fragment"),
            format: colorFormat, additive: true)
        spritePipeline = try VortexRenderer.pipeline(
            device: device, label: "sprite",
            vertex: function("sprite_vertex"), fragment: function("sprite_fragment"),
            format: colorFormat, additive: true)
        boltPipeline = try VortexRenderer.pipeline(
            device: device, label: "bolt",
            vertex: function("bolt_vertex"), fragment: function("bolt_fragment"),
            format: colorFormat, additive: true)
        postPipeline = try VortexRenderer.pipeline(
            device: device, label: "post",
            vertex: function("quad_vertex"), fragment: function("post_fragment"),
            format: colorFormat, additive: false)

        let sampler = MTLSamplerDescriptor()
        sampler.minFilter = .linear
        sampler.magFilter = .linear
        // Clamped, so the aberration's offset samples do not wrap a red fringe
        // from one edge of the screen onto the other.
        sampler.sAddressMode = .clampToEdge
        sampler.tAddressMode = .clampToEdge
        guard let samplerState = device.makeSamplerState(descriptor: sampler) else {
            throw Failure.noDevice
        }
        self.sceneSampler = samplerState

        // The particle field never changes, so both buffers are written once and
        // then only ever read by the GPU.
        streaks = VortexRenderer.buffer(device: device, particles.streaks, label: "streaks")
        sprites = VortexRenderer.buffer(device: device, particles.sprites, label: "sprites")

        // Corners are (along, side) = (0,-1) (0,+1) (1,-1) (1,+1); the two
        // triangles share the tail-right and head-left corners.
        let indices: [UInt16] = [0, 1, 2, 1, 3, 2]
        guard
            let indexBuffer = device.makeBuffer(
                bytes: indices, length: MemoryLayout<UInt16>.stride * indices.count,
                options: .storageModeShared)
        else { throw Failure.noDevice }
        indexBuffer.label = "streak indices"
        self.streakIndices = indexBuffer
    }

    private static func buffer(
        device: MTLDevice, _ particles: [Particle], label: String
    ) -> (buffer: MTLBuffer, count: Int)? {
        guard !particles.isEmpty else { return nil }
        let buffer = particles.withUnsafeBytes {
            device.makeBuffer(bytes: $0.baseAddress!, length: $0.count, options: .storageModeShared)
        }
        guard let buffer else { return nil }
        buffer.label = label
        return (buffer, particles.count)
    }

    private static func pipeline(
        device: MTLDevice,
        label: String,
        vertex: MTLFunction,
        fragment: MTLFunction,
        format: MTLPixelFormat,
        additive: Bool
    ) throws -> MTLRenderPipelineState {
        let descriptor = MTLRenderPipelineDescriptor()
        descriptor.label = label
        descriptor.vertexFunction = vertex
        descriptor.fragmentFunction = fragment
        let attachment = descriptor.colorAttachments[0]!
        attachment.pixelFormat = format
        if additive {
            // The fragment shaders emit premultiplied colour, so adding both the
            // colour and the alpha is all "more light here" means.
            attachment.isBlendingEnabled = true
            attachment.rgbBlendOperation = .add
            attachment.alphaBlendOperation = .add
            attachment.sourceRGBBlendFactor = .one
            attachment.sourceAlphaBlendFactor = .one
            attachment.destinationRGBBlendFactor = .one
            attachment.destinationAlphaBlendFactor = .one
        }
        return try device.makeRenderPipelineState(descriptor: descriptor)
    }

    // MARK: - Drawing

    /// Renders one frame of `scene` into `target`.
    ///
    /// The caller owns the command buffer so the on-screen path can present a
    /// drawable on the same submission, while tests can simply wait for it.
    public func render(scene: VortexScene, to target: MTLTexture, in commandBuffer: MTLCommandBuffer) {
        var uniforms = SceneUniforms(scene: scene, sceneScale: VortexRenderer.sceneScale)

        let sceneTexture = offscreenTexture(matching: target)
        drawScene(scene, uniforms: &uniforms, to: sceneTexture, in: commandBuffer)
        drawPost(from: sceneTexture, uniforms: &uniforms, to: target, in: commandBuffer)
    }

    private func offscreenTexture(matching target: MTLTexture) -> MTLTexture {
        let width = max(1, Int(Double(target.width) * VortexRenderer.sceneScale))
        let height = max(1, Int(Double(target.height) * VortexRenderer.sceneScale))
        if let existing = sceneTexture, existing.width == width, existing.height == height {
            return existing
        }
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .bgra8Unorm, width: width, height: height, mipmapped: false)
        descriptor.usage = [.renderTarget, .shaderRead]
        descriptor.storageMode = .private
        let texture = device.makeTexture(descriptor: descriptor)!
        texture.label = "scene"
        sceneTexture = texture
        return texture
    }

    private func drawScene(
        _ scene: VortexScene,
        uniforms: inout SceneUniforms,
        to texture: MTLTexture,
        in commandBuffer: MTLCommandBuffer
    ) {
        let pass = MTLRenderPassDescriptor()
        pass.colorAttachments[0].texture = texture
        // The background covers every pixel, so nothing needs loading — but
        // clearing is free on a tile GPU and means a failed background pass shows
        // as black rather than as whatever was in memory.
        pass.colorAttachments[0].loadAction = .clear
        pass.colorAttachments[0].clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 1)
        pass.colorAttachments[0].storeAction = .store

        guard let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: pass) else { return }
        encoder.label = "scene"
        let size = MemoryLayout<SceneUniforms>.stride

        encoder.setRenderPipelineState(backgroundPipeline)
        encoder.setFragmentBytes(&uniforms, length: size, index: 0)
        encoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)

        if let streaks {
            encoder.setRenderPipelineState(streakPipeline)
            encoder.setVertexBuffer(streaks.buffer, offset: 0, index: 0)
            encoder.setVertexBytes(&uniforms, length: size, index: 1)
            encoder.drawIndexedPrimitives(
                type: .triangle, indexCount: 6, indexType: .uint16,
                indexBuffer: streakIndices, indexBufferOffset: 0,
                instanceCount: streaks.count)
        }

        if let sprites {
            encoder.setRenderPipelineState(spritePipeline)
            encoder.setVertexBuffer(sprites.buffer, offset: 0, index: 0)
            encoder.setVertexBytes(&uniforms, length: size, index: 1)
            encoder.drawPrimitives(type: .point, vertexStart: 0, vertexCount: sprites.count)
        }

        if !scene.bolts.isEmpty {
            encoder.setRenderPipelineState(boltPipeline)
            encoder.setVertexBytes(&uniforms, length: size, index: 1)
            for bolt in scene.bolts {
                let bytes = MemoryLayout<SIMD2<Float>>.stride * bolt.vertices.count
                guard bytes > 0, bytes <= VortexRenderer.maxInlineBytes else { continue }
                var boltUniforms = BoltUniforms(
                    color: SIMD4(bolt.color.x, bolt.color.y, bolt.color.z, bolt.intensity))
                encoder.setVertexBytes(bolt.vertices, length: bytes, index: 0)
                encoder.setFragmentBytes(
                    &boltUniforms, length: MemoryLayout<BoltUniforms>.stride, index: 0)
                encoder.drawPrimitives(
                    type: .triangleStrip, vertexStart: 0, vertexCount: bolt.vertices.count)
            }
        }

        encoder.endEncoding()
    }

    private func drawPost(
        from sceneTexture: MTLTexture,
        uniforms: inout SceneUniforms,
        to target: MTLTexture,
        in commandBuffer: MTLCommandBuffer
    ) {
        let pass = MTLRenderPassDescriptor()
        pass.colorAttachments[0].texture = target
        // Every pixel is written, so there is nothing worth loading first.
        pass.colorAttachments[0].loadAction = .dontCare
        pass.colorAttachments[0].storeAction = .store

        guard let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: pass) else { return }
        encoder.label = "post"
        encoder.setRenderPipelineState(postPipeline)
        encoder.setFragmentTexture(sceneTexture, index: 0)
        encoder.setFragmentSamplerState(sceneSampler, index: 0)
        encoder.setFragmentBytes(&uniforms, length: MemoryLayout<SceneUniforms>.stride, index: 0)
        encoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)
        encoder.endEncoding()
    }

    /// Renders one frame and waits for it, for tests and thumbnails.
    public func renderSynchronously(scene: VortexScene, to target: MTLTexture) {
        guard let commandBuffer = commandQueue.makeCommandBuffer() else { return }
        render(scene: scene, to: target, in: commandBuffer)
        commandBuffer.commit()
        commandBuffer.waitUntilCompleted()
    }

    public func makeCommandBuffer() -> MTLCommandBuffer? {
        commandQueue.makeCommandBuffer()
    }

    /// Copies a rendered texture back to the CPU. The texture must have been
    /// created with readable storage.
    public func readBack(texture: MTLTexture) -> CGImage? {
        texture.readBack(using: commandQueue)
    }
}
