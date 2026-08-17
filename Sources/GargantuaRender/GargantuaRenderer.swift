import CoreGraphics
import Foundation
import GargantuaCore
import Metal
import SaverKit

/// Draws the black hole.
///
/// Six passes, all full-screen, in one command buffer:
///
///   march     the geodesic integration, at render scale, into an HDR buffer
///   accumulate  reproject the previous frame and blend into it
///   bright    threshold for bloom
///   down/up   the bloom pyramid
///   streak    optional anamorphic smear, skipped entirely when it is off
///   post      tone map and composite to the drawable
///
/// The march is by far the most expensive: every pixel integrates a null
/// geodesic through curved spacetime with RK4, up to several hundred steps. That
/// is why it runs at a fraction of the output resolution and why the resolution
/// is driven rather than chosen — see `AdaptiveResolution`.
public final class GargantuaRenderer {

    /// Frames per second. GPU-bound work, and the accumulation window is fixed
    /// in seconds, so a higher rate genuinely converges the image faster.
    public static let framesPerSecond: Double = 60

    /// Levels in the bloom pyramid.
    static let bloomLevels = 5

    /// HDR throughout: the disk's dynamic range is enormous, the bloom threshold
    /// sits above 1, and tone mapping does not happen until the composite.
    static let hdrFormat = MTLPixelFormat.rgba16Float

    public let device: MTLDevice
    private let commandQueue: MTLCommandQueue

    private let marchPipeline: MTLRenderPipelineState
    private let accumulatePipeline: MTLRenderPipelineState
    private let brightPipeline: MTLRenderPipelineState
    private let downsamplePipeline: MTLRenderPipelineState
    private let upsamplePipeline: MTLRenderPipelineState
    private let streakPipeline: MTLRenderPipelineState
    private let postPipeline: MTLRenderPipelineState

    private let linearSampler: MTLSamplerState
    private let noiseSampler: MTLSamplerState
    private let noise: MTLTexture

    private var targets: RenderTargets?
    private var historyValid = false
    private var usingHistoryA = true

    private var adaptive = AdaptiveResolution()

    public enum Failure: Error, CustomStringConvertible {
        case noDevice
        case noCommandQueue
        case missingLibrary
        case missingFunction(String)
        case noNoiseVolume

        public var description: String {
            switch self {
            case .noDevice: return "no Metal device"
            case .noCommandQueue: return "could not create a Metal command queue"
            case .missingLibrary: return "Gargantua.metallib is missing from the bundle"
            case .missingFunction(let name): return "shader '\(name)' is missing"
            case .noNoiseVolume: return "could not build the noise volume"
            }
        }
    }

    public init(device: MTLDevice? = nil, library providedLibrary: MTLLibrary? = nil) throws {
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
        let vertex = try function("fullscreen_vertex")

        func pipeline(
            _ label: String, _ fragment: String, format: MTLPixelFormat, additive: Bool = false
        ) throws -> MTLRenderPipelineState {
            let descriptor = MTLRenderPipelineDescriptor()
            descriptor.label = label
            descriptor.vertexFunction = vertex
            descriptor.fragmentFunction = try function(fragment)
            let attachment = descriptor.colorAttachments[0]!
            attachment.pixelFormat = format
            if additive {
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

        marchPipeline = try pipeline("march", "march_fragment", format: Self.hdrFormat)
        accumulatePipeline = try pipeline("accumulate", "accumulate_fragment", format: Self.hdrFormat)
        brightPipeline = try pipeline("bright", "bright_fragment", format: Self.hdrFormat)
        downsamplePipeline = try pipeline("downsample", "downsample_fragment", format: Self.hdrFormat)
        // The pyramid is walked back up additively, so each level gains the one
        // below it without needing a second set of targets.
        upsamplePipeline = try pipeline(
            "upsample", "upsample_fragment", format: Self.hdrFormat, additive: true)
        streakPipeline = try pipeline("streak", "streak_fragment", format: Self.hdrFormat)
        postPipeline = try pipeline("post", "post_fragment", format: .bgra8Unorm)

        let linear = MTLSamplerDescriptor()
        linear.minFilter = .linear
        linear.magFilter = .linear
        linear.sAddressMode = .clampToEdge
        linear.tAddressMode = .clampToEdge
        guard let linearState = device.makeSamplerState(descriptor: linear) else {
            throw Failure.noDevice
        }
        self.linearSampler = linearState

        let noiseDescriptor = MTLSamplerDescriptor()
        noiseDescriptor.minFilter = .linear
        noiseDescriptor.magFilter = .linear
        // Trilinear across mips, because the marcher picks its level explicitly
        // to prefilter the field to its own sample spacing.
        noiseDescriptor.mipFilter = .linear
        // The volume tiles: the disk pattern is sampled over an unbounded domain.
        noiseDescriptor.sAddressMode = .repeat
        noiseDescriptor.tAddressMode = .repeat
        noiseDescriptor.rAddressMode = .repeat
        guard let noiseState = device.makeSamplerState(descriptor: noiseDescriptor) else {
            throw Failure.noDevice
        }
        self.noiseSampler = noiseState

        guard let volume = NoiseVolume.make(device: device) else { throw Failure.noNoiseVolume }
        self.noise = volume
    }

    // MARK: - Targets

    /// Everything the frame is assembled in. Reallocated when the output size or
    /// the render scale changes, which is also when the accumulation history
    /// stops being meaningful.
    private struct RenderTargets {
        let outputWidth: Int
        let outputHeight: Int
        let renderWidth: Int
        let renderHeight: Int

        let scene: MTLTexture
        let historyA: MTLTexture
        let historyB: MTLTexture
        /// Sized from the march resolution, not the output: their only input is
        /// the scene buffer, they are pure low-frequency energy, and the
        /// composite upsamples them bilinearly. Sizing them off the output would
        /// leave the post chain at full cost exactly when the adaptive
        /// controller drops render scale to shed load.
        let bloom: [MTLTexture]
        let streakA: MTLTexture
        let streakB: MTLTexture
    }

    private func makeTarget(_ width: Int, _ height: Int, label: String) -> MTLTexture {
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: Self.hdrFormat, width: max(1, width), height: max(1, height),
            mipmapped: false)
        descriptor.usage = [.renderTarget, .shaderRead]
        descriptor.storageMode = .private
        let texture = device.makeTexture(descriptor: descriptor)!
        texture.label = label
        return texture
    }

    private func targets(outputWidth: Int, outputHeight: Int, renderScale: Double) -> RenderTargets {
        let renderWidth = max(2, Int((Double(outputWidth) * renderScale).rounded()))
        let renderHeight = max(2, Int((Double(outputHeight) * renderScale).rounded()))
        if let existing = targets,
            existing.outputWidth == outputWidth, existing.outputHeight == outputHeight,
            existing.renderWidth == renderWidth, existing.renderHeight == renderHeight
        {
            return existing
        }

        var bloom: [MTLTexture] = []
        var w = max(2, renderWidth), h = max(2, renderHeight)
        for level in 0..<Self.bloomLevels {
            guard w > 4 && h > 4 || level == 0 else { break }
            bloom.append(makeTarget(w, h, label: "bloom \(level)"))
            w = max(2, w >> 1)
            h = max(2, h >> 1)
        }

        let streakWidth = max(4, renderWidth >> 2)
        let streakHeight = max(4, renderHeight >> 2)
        let fresh = RenderTargets(
            outputWidth: outputWidth, outputHeight: outputHeight,
            renderWidth: renderWidth, renderHeight: renderHeight,
            scene: makeTarget(renderWidth, renderHeight, label: "scene"),
            historyA: makeTarget(renderWidth, renderHeight, label: "history A"),
            historyB: makeTarget(renderWidth, renderHeight, label: "history B"),
            bloom: bloom,
            streakA: makeTarget(streakWidth, streakHeight, label: "streak A"),
            streakB: makeTarget(streakWidth, streakHeight, label: "streak B"))
        targets = fresh
        // The new buffers hold nothing, and the old history is the wrong size.
        historyValid = false
        return fresh
    }

    /// Fraction of the output the march is currently running at.
    public var renderScale: Double { adaptive.renderScale }

    /// Pins the render scale, turning the adaptive controller off. For the fixed
    /// resolution setting, and for thumbnails, where sixty frames of settling is
    /// longer than the view exists for.
    public func fixRenderScale(at scale: Double) {
        adaptive.fix(at: scale)
    }

    /// Throws the accumulation history away. Needed after anything that makes
    /// the previous frame a lie — a resize, a settings change, a long pause.
    public func invalidateHistory() {
        historyValid = false
    }

    // MARK: - Drawing

    /// Renders one frame of `scene` into `target`.
    public func render(
        scene: GargantuaScene,
        deltaTime: Double,
        to target: MTLTexture,
        in commandBuffer: MTLCommandBuffer
    ) {
        let rt = targets(
            outputWidth: target.width, outputHeight: target.height,
            renderScale: adaptive.renderScale)
        let renderResolution = SIMD2<Float>(Float(rt.renderWidth), Float(rt.renderHeight))

        // 1. Geodesic march, at render scale.
        var march = MarchUniforms(
            scene: scene, resolution: renderResolution, noiseTexels: NoiseVolume.size)
        encode(pass: rt.scene, label: "march", in: commandBuffer) { encoder in
            encoder.setRenderPipelineState(self.marchPipeline)
            encoder.setFragmentBytes(&march, length: MemoryLayout<MarchUniforms>.stride, index: 0)
            encoder.setFragmentTexture(self.noise, index: 0)
            encoder.setFragmentSamplerState(self.noiseSampler, index: 0)
        }

        // 2. Reproject and accumulate. Ping-pong, so the frame just written
        //    becomes next frame's history.
        let historySource = usingHistoryA ? rt.historyA : rt.historyB
        let historyDestination = usingHistoryA ? rt.historyB : rt.historyA
        var accumulate = AccumulateUniforms(
            scene: scene, resolution: renderResolution,
            alpha: scene.accumulationAlpha(deltaTime: deltaTime),
            historyValid: historyValid)
        encode(pass: historyDestination, label: "accumulate", in: commandBuffer) { encoder in
            encoder.setRenderPipelineState(self.accumulatePipeline)
            encoder.setFragmentBytes(
                &accumulate, length: MemoryLayout<AccumulateUniforms>.stride, index: 0)
            encoder.setFragmentTexture(rt.scene, index: 0)
            encoder.setFragmentTexture(historySource, index: 1)
            encoder.setFragmentSamplerState(self.linearSampler, index: 0)
        }
        usingHistoryA.toggle()
        historyValid = true
        let resolved = historyDestination

        // 3. Bloom: threshold, downsample chain, additive walk back up.
        let p = scene.parameters
        var bright = BrightUniforms(
            texel: texel(rt.bloom[0]),
            threshold: Float(p.bloomThresh),
            exposure: Float(p.exposure))
        encode(pass: rt.bloom[0], label: "bright", in: commandBuffer) { encoder in
            encoder.setRenderPipelineState(self.brightPipeline)
            encoder.setFragmentBytes(&bright, length: MemoryLayout<BrightUniforms>.stride, index: 0)
            encoder.setFragmentTexture(resolved, index: 0)
            encoder.setFragmentSamplerState(self.linearSampler, index: 0)
        }

        for level in 1..<rt.bloom.count {
            var blur = BlurUniforms(
                sourceTexel: texel(rt.bloom[level - 1]),
                destinationTexel: texel(rt.bloom[level]))
            encode(pass: rt.bloom[level], label: "downsample \(level)", in: commandBuffer) {
                encoder in
                encoder.setRenderPipelineState(self.downsamplePipeline)
                encoder.setFragmentBytes(&blur, length: MemoryLayout<BlurUniforms>.stride, index: 0)
                encoder.setFragmentTexture(rt.bloom[level - 1], index: 0)
                encoder.setFragmentSamplerState(self.linearSampler, index: 0)
            }
        }

        for level in stride(from: rt.bloom.count - 2, through: 0, by: -1) {
            var blur = BlurUniforms(
                sourceTexel: texel(rt.bloom[level + 1]),
                destinationTexel: texel(rt.bloom[level]))
            // Loads what is already there: this pass adds the coarser level on
            // top rather than replacing it.
            encode(pass: rt.bloom[level], label: "upsample \(level)", load: .load, in: commandBuffer) {
                encoder in
                encoder.setRenderPipelineState(self.upsamplePipeline)
                encoder.setFragmentBytes(&blur, length: MemoryLayout<BlurUniforms>.stride, index: 0)
                encoder.setFragmentTexture(rt.bloom[level + 1], index: 0)
                encoder.setFragmentSamplerState(self.linearSampler, index: 0)
            }
        }

        // 4. Anamorphic streaks. Three widening horizontal blurs, and skipped
        //    outright when the look does not use them — the shipped one does not.
        var streakSource = rt.bloom[min(1, rt.bloom.count - 1)]
        if p.streak > 0 {
            var destination = rt.streakA
            var spare = rt.streakB
            for (pass, stride) in [Float(1.0), 4.0, 14.0].enumerated() {
                var uniforms = StreakUniforms(texel: texel(destination), stride: stride)
                let source = streakSource
                let output = destination
                encode(pass: output, label: "streak \(pass)", in: commandBuffer) { encoder in
                    encoder.setRenderPipelineState(self.streakPipeline)
                    encoder.setFragmentBytes(
                        &uniforms, length: MemoryLayout<StreakUniforms>.stride, index: 0)
                    encoder.setFragmentTexture(source, index: 0)
                    encoder.setFragmentSamplerState(self.linearSampler, index: 0)
                }
                streakSource = output
                swap(&destination, &spare)
            }
        }

        // 5. Composite to the drawable.
        var post = PostUniforms(
            scene: scene, resolution: SIMD2(Float(target.width), Float(target.height)))
        encode(pass: target, label: "post", in: commandBuffer) { encoder in
            encoder.setRenderPipelineState(self.postPipeline)
            encoder.setFragmentBytes(&post, length: MemoryLayout<PostUniforms>.stride, index: 0)
            encoder.setFragmentTexture(resolved, index: 0)
            encoder.setFragmentTexture(rt.bloom[0], index: 1)
            encoder.setFragmentTexture(streakSource, index: 2)
            encoder.setFragmentSamplerState(self.linearSampler, index: 0)
        }
    }

    private func texel(_ texture: MTLTexture) -> SIMD2<Float> {
        SIMD2(1 / Float(texture.width), 1 / Float(texture.height))
    }

    /// One full-screen pass. Every pass here is a single triangle, so the
    /// boilerplate is identical apart from what gets bound.
    private func encode(
        pass texture: MTLTexture,
        label: String,
        load: MTLLoadAction = .dontCare,
        in commandBuffer: MTLCommandBuffer,
        _ configure: (MTLRenderCommandEncoder) -> Void
    ) {
        let descriptor = MTLRenderPassDescriptor()
        descriptor.colorAttachments[0].texture = texture
        descriptor.colorAttachments[0].loadAction = load
        descriptor.colorAttachments[0].storeAction = .store
        guard let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: descriptor) else {
            return
        }
        encoder.label = label
        configure(encoder)
        encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
        encoder.endEncoding()
    }

    public func makeCommandBuffer() -> MTLCommandBuffer? {
        commandQueue.makeCommandBuffer()
    }

    /// Renders one frame and waits for it, for tests and thumbnails.
    public func renderSynchronously(
        scene: GargantuaScene, deltaTime: Double, to target: MTLTexture
    ) {
        guard let commandBuffer = commandQueue.makeCommandBuffer() else { return }
        render(scene: scene, deltaTime: deltaTime, to: target, in: commandBuffer)
        commandBuffer.commit()
        commandBuffer.waitUntilCompleted()
    }

    /// Copies a rendered texture back to the CPU. The texture must have been
    /// created with readable storage.
    public func readBack(texture: MTLTexture) -> CGImage? {
        texture.readBack(using: commandQueue)
    }

    /// Renders one frame into a fresh readable texture, for tests and thumbnails.
    public func renderToImage(
        scene: GargantuaScene, deltaTime: Double, width: Int, height: Int
    ) -> CGImage? {
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .bgra8Unorm, width: width, height: height, mipmapped: false)
        descriptor.usage = [.renderTarget, .shaderRead]
        // Managed rather than shared: it is the one storage mode that reads back
        // on both Apple Silicon and Intel.
        descriptor.storageMode = .managed
        guard let target = device.makeTexture(descriptor: descriptor) else { return nil }
        renderSynchronously(scene: scene, deltaTime: deltaTime, to: target)
        return readBack(texture: target)
    }

    /// Feeds a finished frame's measured GPU time to the adaptive controller.
    public func noteFrameCost(gpuSeconds: Double) {
        if adaptive.note(gpuSeconds: gpuSeconds) {
            // A scale change reallocates the targets on the next frame, which
            // throws the history away with them.
            invalidateHistory()
        }
    }
}
