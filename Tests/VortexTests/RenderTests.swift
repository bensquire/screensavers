import Metal
import SaverKit
import XCTest

@testable import VortexCore
@testable import VortexRender

/// Checks the parts of the port that only the GPU can answer for: that the
/// shaders compile, that Swift and Metal agree on the shape of the buffers
/// handed between them, and that a frame comes back with something in it.
final class RenderTests: XCTestCase {

    private func makeDevice() throws -> MTLDevice {
        guard let device = MTLCreateSystemDefaultDevice() else {
            throw XCTSkip("no Metal device on this machine")
        }
        return device
    }

    // MARK: - Struct layout
    //
    // The uniform and particle buffers are handed to the GPU as raw memory, so a
    // field reordered on one side and not the other would not fail to compile —
    // it would silently render nonsense. Ask the shader what it thinks the
    // structs look like and compare.

    func testSwiftAndMetalAgreeOnBufferLayout() throws {
        let device = try makeDevice()
        let library = try ShaderLibrary.compileFromSource(device: device)
        guard let probe = library.makeFunction(name: "uniform_layout_probe") else {
            return XCTFail("the layout probe is missing from the shader library")
        }
        let pipeline = try device.makeComputePipelineState(function: probe)

        let slots = 5
        guard
            let out = device.makeBuffer(
                length: MemoryLayout<UInt32>.stride * slots, options: .storageModeShared),
            let reference = device.makeBuffer(
                length: MemoryLayout<SceneUniforms>.stride, options: .storageModeShared),
            let queue = device.makeCommandQueue(),
            let commandBuffer = queue.makeCommandBuffer(),
            let encoder = commandBuffer.makeComputeCommandEncoder()
        else { return XCTFail("could not set up the probe") }

        encoder.setComputePipelineState(pipeline)
        encoder.setBuffer(out, offset: 0, index: 0)
        encoder.setBuffer(reference, offset: 0, index: 1)
        encoder.dispatchThreads(
            MTLSize(width: 1, height: 1, depth: 1),
            threadsPerThreadgroup: MTLSize(width: 1, height: 1, depth: 1))
        encoder.endEncoding()
        commandBuffer.commit()
        commandBuffer.waitUntilCompleted()

        let reported = out.contents().bindMemory(to: UInt32.self, capacity: slots)
        XCTAssertEqual(
            Int(reported[0]), MemoryLayout<SceneUniforms>.stride,
            "SceneUniforms is a different size in Swift and Metal")
        XCTAssertEqual(
            Int(reported[1]), MemoryLayout<Particle>.stride,
            "Particle is a different size in Swift and Metal")
        XCTAssertEqual(
            Int(reported[2]), MemoryLayout<SceneUniforms>.offset(of: \.resolution),
            "SceneUniforms.resolution is at a different offset")
        XCTAssertEqual(
            Int(reported[3]), MemoryLayout<SceneUniforms>.offset(of: \.focal),
            "SceneUniforms.focal is at a different offset")
        XCTAssertEqual(
            Int(reported[4]), MemoryLayout<SceneUniforms>.offset(of: \.chromaticAberration),
            "SceneUniforms.chromaticAberration is at a different offset")
    }

    // MARK: - Drawing

    private func renderFrame(
        settleSeconds: Double = 4,
        settings: VortexSettings = .default,
        width: Int = 320,
        height: Int = 200
    ) throws -> (image: CGImage, pixels: [UInt8]) {
        let device = try makeDevice()
        let library = try ShaderLibrary.compileFromSource(device: device)
        let layout = Layout(
            pointWidth: Double(width), pointHeight: Double(height), backingScale: 1)
        let scene = VortexScene(layout: layout, settings: settings, seed: 11)
        let renderer = try VortexRenderer(
            device: device, library: library, particles: scene.particles)

        let step = FrameClock.frameInterval
        var t = 0.0
        while t < settleSeconds {
            scene.update(deltaTime: step, layout: layout)
            t += step
        }
        guard let image = renderer.renderToImage(scene: scene, width: width, height: height) else {
            throw XCTSkip("the GPU did not return a frame")
        }
        return (image, RenderTests.samples(image))
    }

    /// The rendered pixels as BGRA bytes.
    private static func samples(_ image: CGImage) -> [UInt8] {
        let bytesPerRow = image.width * 4
        var pixels = [UInt8](repeating: 0, count: bytesPerRow * image.height)
        pixels.withUnsafeMutableBytes { buffer in
            guard
                let context = CGContext(
                    data: buffer.baseAddress, width: image.width, height: image.height,
                    bitsPerComponent: 8, bytesPerRow: bytesPerRow,
                    space: CGColorSpaceCreateDeviceRGB(),
                    bitmapInfo: CGImageAlphaInfo.noneSkipFirst.rawValue
                        | CGBitmapInfo.byteOrder32Little.rawValue)
            else { return }
            context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        }
        return pixels
    }

    func testAFrameHasSomethingInIt() throws {
        let (image, pixels) = try renderFrame()
        XCTAssertEqual(image.width, 320)

        var lit = 0
        var brightest = 0
        for i in stride(from: 0, to: pixels.count, by: 4) {
            let value = Int(max(pixels[i], max(pixels[i + 1], pixels[i + 2])))
            if value > 24 { lit += 1 }
            brightest = max(brightest, value)
        }
        let total = image.width * image.height
        // The background alone lights most of the frame; the streaks put the
        // highlights well above it.
        XCTAssertGreaterThan(lit, total / 10, "the frame is essentially black")
        XCTAssertGreaterThan(brightest, 140, "nothing bright was drawn")
    }

    func testTheSceneActuallyMoves() throws {
        // A renderer that draws the opening frame forever would pass every check
        // above. Two frames four seconds apart must differ.
        let early = try renderFrame(settleSeconds: 1).pixels
        let later = try renderFrame(settleSeconds: 9).pixels
        XCTAssertEqual(early.count, later.count)

        var changed = 0
        for i in stride(from: 0, to: early.count, by: 4)
        where
            abs(Int(early[i]) - Int(later[i])) > 8
        {
            changed += 1
        }
        XCTAssertGreaterThan(
            changed, early.count / 4 / 50, "the tunnel looks identical eight seconds later")
    }

    func testDensityChangesWhatIsDrawn() throws {
        let sparse = try renderFrame(
            settings: VortexSettings(flowSpeed: 1, lightning: false, density: 0.25)
        ).pixels
        let dense = try renderFrame(
            settings: VortexSettings(flowSpeed: 1, lightning: false, density: 1.5)
        ).pixels

        func totalLight(_ pixels: [UInt8]) -> Int {
            stride(from: 0, to: pixels.count, by: 4).reduce(0) { $0 + Int(pixels[$1 + 1]) }
        }
        XCTAssertGreaterThan(
            totalLight(dense), totalLight(sparse), "density did not add any particles")
    }
}
