import Metal
import XCTest

@testable import GargantuaCore
@testable import GargantuaRender

/// The parts only the GPU can answer for: that the shaders compile, that Swift
/// and Metal agree on the buffers passed between them, and that the black hole
/// actually appears.
final class RenderTests: XCTestCase {

    private func makeDevice() throws -> MTLDevice {
        guard let device = MTLCreateSystemDefaultDevice() else {
            throw XCTSkip("no Metal device on this machine")
        }
        return device
    }

    func testSwiftAndMetalAgreeOnBufferLayout() throws {
        let device = try makeDevice()
        let library = try ShaderLibrary.compileFromSource(device: device)
        guard let probe = library.makeFunction(name: "uniform_layout_probe") else {
            return XCTFail("the layout probe is missing from the shader library")
        }
        let pipeline = try device.makeComputePipelineState(function: probe)

        let slots = 8
        guard
            let out = device.makeBuffer(
                length: MemoryLayout<UInt32>.stride * slots, options: .storageModeShared),
            let marchRef = device.makeBuffer(
                length: MemoryLayout<MarchUniforms>.stride, options: .storageModeShared),
            let accumulateRef = device.makeBuffer(
                length: MemoryLayout<AccumulateUniforms>.stride, options: .storageModeShared),
            let queue = device.makeCommandQueue(),
            let commandBuffer = queue.makeCommandBuffer(),
            let encoder = commandBuffer.makeComputeCommandEncoder()
        else { return XCTFail("could not set up the probe") }

        encoder.setComputePipelineState(pipeline)
        encoder.setBuffer(out, offset: 0, index: 0)
        encoder.setBuffer(marchRef, offset: 0, index: 1)
        encoder.setBuffer(accumulateRef, offset: 0, index: 2)
        encoder.dispatchThreads(
            MTLSize(width: 1, height: 1, depth: 1),
            threadsPerThreadgroup: MTLSize(width: 1, height: 1, depth: 1))
        encoder.endEncoding()
        commandBuffer.commit()
        commandBuffer.waitUntilCompleted()

        let reported = out.contents().bindMemory(to: UInt32.self, capacity: slots)
        XCTAssertEqual(
            Int(reported[0]), MemoryLayout<MarchUniforms>.stride,
            "MarchUniforms is a different size in Swift and Metal")
        XCTAssertEqual(
            Int(reported[1]), MemoryLayout<AccumulateUniforms>.stride,
            "AccumulateUniforms is a different size in Swift and Metal")
        XCTAssertEqual(
            Int(reported[2]), MemoryLayout<MarchUniforms>.offset(of: \.camPos),
            "MarchUniforms.camPos is at a different offset")
        XCTAssertEqual(
            Int(reported[3]), MemoryLayout<MarchUniforms>.offset(of: \.resolution),
            "MarchUniforms.resolution is at a different offset")
        XCTAssertEqual(
            Int(reported[4]), MemoryLayout<MarchUniforms>.offset(of: \.flare),
            "MarchUniforms.flare is at a different offset — the tail has shifted")
        XCTAssertEqual(
            Int(reported[5]), MemoryLayout<AccumulateUniforms>.offset(of: \.resolution))
        XCTAssertEqual(
            Int(reported[6]), MemoryLayout<AccumulateUniforms>.offset(of: \.sharpen))
        XCTAssertEqual(Int(reported[7]), MemoryLayout<PostUniforms>.stride)
    }

    // MARK: - Drawing

    private struct Frame {
        let width: Int
        let height: Int
        /// BGRA bytes.
        let pixels: [UInt8]

        /// Relative luminance in LINEAR light, 0...1.
        ///
        /// The composite writes gamma-encoded pixels, which compress the
        /// disk-to-shadow contrast from about 200:1 down to 10:1 — so measuring
        /// the encoded bytes would make a correct render look washed out and a
        /// broken one look plausible. Undo the encoding first.
        func luminance(x: Int, y: Int) -> Double {
            let i = (y * width + x) * 4
            let b = pow(Double(pixels[i]) / 255, 2.2)
            let g = pow(Double(pixels[i + 1]) / 255, 2.2)
            let r = pow(Double(pixels[i + 2]) / 255, 2.2)
            return 0.2126 * r + 0.7152 * g + 0.0722 * b
        }
    }

    private func render(
        settleSeconds: Double = 6,
        settings: GargantuaSettings = .default,
        width: Int = 240,
        height: Int = 150
    ) throws -> Frame {
        let device = try makeDevice()
        let library = try ShaderLibrary.compileFromSource(device: device)
        let scene = GargantuaScene(settings: settings, seed: 9)
        let renderer = try GargantuaRenderer(device: device, library: library)
        renderer.fixRenderScale(at: 1.0)

        let step = 1.0 / GargantuaRenderer.framesPerSecond
        var t = 0.0
        while t < max(0, settleSeconds - 0.25) {
            scene.update(deltaTime: step)
            t += step
        }
        var image: CGImage?
        // Draw the last quarter second so the accumulation buffer converges —
        // a single frame is one jittered sample per pixel.
        while t < settleSeconds {
            scene.update(deltaTime: step)
            image = renderer.renderToImage(
                scene: scene, deltaTime: step, width: width, height: height)
            t += step
        }
        guard let image else { throw XCTSkip("the GPU did not return a frame") }

        let bytesPerRow = width * 4
        var pixels = [UInt8](repeating: 0, count: bytesPerRow * height)
        pixels.withUnsafeMutableBytes { buffer in
            guard
                let context = CGContext(
                    data: buffer.baseAddress, width: width, height: height,
                    bitsPerComponent: 8, bytesPerRow: bytesPerRow,
                    space: CGColorSpaceCreateDeviceRGB(),
                    bitmapInfo: CGImageAlphaInfo.noneSkipFirst.rawValue
                        | CGBitmapInfo.byteOrder32Little.rawValue)
            else { return }
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        }
        return Frame(width: width, height: height, pixels: pixels)
    }

    func testTheShadowIsDarkAndTheDiskIsNot() throws {
        let frame = try render()

        // The hole sits at the centre of frame — aimDrift is zero, so the
        // camera looks straight at it — and the shadow is several degrees
        // across at this distance.
        let shadow = frame.luminance(x: frame.width / 2, y: frame.height / 2)
        var diskPeak = 0.0
        for y in 0..<frame.height {
            for x in 0..<frame.width {
                diskPeak = max(diskPeak, frame.luminance(x: x, y: y))
            }
        }

        // Not perfectly black: bloom from the disk bleeds across the whole
        // frame, which is real and wanted. It should still be a fraction of a
        // percent of the brightest gas.
        XCTAssertLessThan(shadow, 0.02, "the middle of the frame is not the shadow")
        XCTAssertGreaterThan(diskPeak, 0.3, "the disk is not plainly lit")
        XCTAssertGreaterThan(
            diskPeak, shadow * 20, "no real contrast between the disk and the shadow")
    }

    func testTheDiskIsLensedAboveAndBelowTheShadow() throws {
        // The signature of the thing: light from the far side of the disk is
        // bent over and under the hole, so there is disk above and below the
        // shadow as well as either side of it. Without lensing there would be a
        // flat bar and nothing else.
        let frame = try render()
        let cx = frame.width / 2

        func brightest(column x: Int, rows: Range<Int>) -> Double {
            rows.reduce(0.0) { max($0, frame.luminance(x: x, y: $1)) }
        }
        let above = brightest(column: cx, rows: 0..<(frame.height * 2 / 5))
        let below = brightest(column: cx, rows: (frame.height * 3 / 5)..<frame.height)
        let shadow = frame.luminance(x: cx, y: frame.height / 2)

        XCTAssertGreaterThan(above, max(0.01, shadow * 3), "no lensed disk above the shadow")
        XCTAssertGreaterThan(below, max(0.01, shadow * 3), "no lensed disk below the shadow")
    }

    func testBeamingMakesTheDiskLopsided() throws {
        // With beaming off the disk is left-right symmetric in brightness; with
        // it on, the limb rotating toward the camera is far brighter. That
        // asymmetry is the one piece of physics Interstellar dropped, so it is
        // worth pinning that the switch really does something.
        func asymmetry(beaming: Double) throws -> Double {
            let frame = try render(
                settings: GargantuaSettings(
                    pace: 1, beaming: beaming, stars: 0,
                    adaptiveResolution: false, renderScale: 1))
            let row = frame.height / 2
            var left = 0.0, right = 0.0
            for x in 0..<(frame.width / 3) { left += frame.luminance(x: x, y: row) }
            for x in (frame.width * 2 / 3)..<frame.width { right += frame.luminance(x: x, y: row) }
            return abs(left - right) / max(left + right, 1)
        }

        let symmetric = try asymmetry(beaming: 0)
        let beamed = try asymmetry(beaming: 1)
        XCTAssertGreaterThan(beamed, symmetric + 0.05, "beaming did not brighten one limb")
    }

    func testStarsCanBeTurnedOff() throws {
        // The sky of the shipped look is otherwise black, so with the stars off
        // the corners should be genuinely empty.
        let frame = try render(
            settings: GargantuaSettings(
                pace: 1, beaming: 0, stars: 0, adaptiveResolution: false, renderScale: 1))
        for (x, y) in [(2, 2), (frame.width - 3, 2), (2, frame.height - 3)] {
            XCTAssertLessThan(
                frame.luminance(x: x, y: y), 0.001, "corner (\(x),\(y)) is not black")
        }
    }

    // MARK: - Adaptive resolution

    func testAdaptiveResolutionMovesTowardTheBudget() {
        var adaptive = AdaptiveResolution(renderScale: 0.55)
        adaptive.budget = 1.0 / 60

        // Comfortably inside budget: it should climb, but only after enough
        // agreeing frames, because a change reallocates every target.
        for _ in 0..<400 { _ = adaptive.note(gpuSeconds: 0.002) }
        XCTAssertGreaterThan(adaptive.renderScale, 0.55)

        // Now far too slow: it should fall back.
        let climbed = adaptive.renderScale
        for _ in 0..<400 { _ = adaptive.note(gpuSeconds: 0.060) }
        XCTAssertLessThan(adaptive.renderScale, climbed)
        XCTAssertGreaterThanOrEqual(adaptive.renderScale, AdaptiveResolution.minimumScale)
    }

    func testAdaptiveResolutionStaysWithinItsBounds() {
        var adaptive = AdaptiveResolution(renderScale: 0.55)
        adaptive.budget = 1.0 / 60
        for _ in 0..<5000 { _ = adaptive.note(gpuSeconds: 0.0001) }
        XCTAssertEqual(adaptive.renderScale, AdaptiveResolution.maximumScale, accuracy: 1e-9)
        for _ in 0..<5000 { _ = adaptive.note(gpuSeconds: 5.0) }
        XCTAssertEqual(adaptive.renderScale, AdaptiveResolution.minimumScale, accuracy: 1e-9)
    }

    func testFixingTheScaleStopsItMoving() {
        var adaptive = AdaptiveResolution()
        adaptive.fix(at: 0.42)
        for _ in 0..<2000 { XCTAssertFalse(adaptive.note(gpuSeconds: 1.0)) }
        XCTAssertEqual(adaptive.renderScale, 0.42, accuracy: 1e-9)
    }

    // MARK: - Noise

    func testNoiseVolumeIsBuiltWithMips() throws {
        let device = try makeDevice()
        guard let queue = device.makeCommandQueue(),
            let texture = NoiseVolume.make(device: device, queue: queue)
        else { return XCTFail("could not build the noise volume") }
        XCTAssertEqual(texture.textureType, MTLTextureType.type3D)
        XCTAssertEqual(texture.width, NoiseVolume.size)
        XCTAssertEqual(texture.depth, NoiseVolume.size)
        // The marcher selects a mip explicitly to prefilter the field to its
        // sample spacing, so the chain has to be there.
        XCTAssertGreaterThan(texture.mipmapLevelCount, 5)

        // Second call returns the cached volume rather than spending another
        // ~11ms rebuilding an identical million voxels.
        XCTAssertTrue(
            NoiseVolume.shared(device: device, queue: queue)
                === NoiseVolume.shared(device: device, queue: queue),
            "the noise volume is not being cached")
    }
}
