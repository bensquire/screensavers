import Foundation
import Metal
import SaverKit

/// The 3D noise the disk's turbulence and the nebula are made of.
///
/// Built once at startup rather than shipped as an asset: it is 1MB of
/// incompressible noise, and generating it costs a few milliseconds.
public enum NoiseVolume {

    /// Edge length. Must be a power of two, and must match what the shader is
    /// told, since it uses the texel count to pick a mip level.
    public static let size = 64

    /// Cache, keyed by device. The content is a fixed seed, so every renderer
    /// would otherwise spend ~11ms of the main thread rebuilding exactly the
    /// same million voxels — once per launch, and again on every options commit.
    private static let cache = NSMapTable<AnyObject, MTLTexture>.weakToStrongObjects()
    private static let cacheLock = NSLock()

    /// Returns the volume for this device, building it the first time.
    public static func shared(device: MTLDevice, queue: MTLCommandQueue) -> MTLTexture? {
        cacheLock.lock()
        defer { cacheLock.unlock() }
        if let existing = cache.object(forKey: device) { return existing }
        guard let built = make(device: device, queue: queue) else { return nil }
        cache.setObject(built, forKey: device)
        return built
    }

    /// Builds the volume and uploads it with a full mip chain.
    ///
    /// White noise is smoothed by two separable [1,2,1] passes per axis,
    /// wrapping at the edges, so trilinear interpolation lands on something
    /// smooth rather than a lattice of creases. Each channel is then stretched
    /// back over the full range, because blurring collapses it toward the mean.
    public static func make(
        device: MTLDevice, queue: MTLCommandQueue, seed: UInt64 = 0x51E7_D0C5
    ) -> MTLTexture? {
        let n = size
        let channels = 4
        let count = n * n * n * channels

        var rng = SplitMix64(seed: seed)
        var values = [Float](repeating: 0, count: count)
        for i in 0..<count { values[i] = Float(rng.nextDouble()) }

        var scratch = [Float](repeating: 0, count: count)
        func index(_ x: Int, _ y: Int, _ z: Int) -> Int { ((z * n + y) * n + x) * channels }
        func blur(axis: Int) {
            for z in 0..<n {
                for y in 0..<n {
                    for x in 0..<n {
                        var (mx, my, mz) = (x, y, z)
                        var (px, py, pz) = (x, y, z)
                        switch axis {
                        case 0:
                            mx = (x + n - 1) % n
                            px = (x + 1) % n
                        case 1:
                            my = (y + n - 1) % n
                            py = (y + 1) % n
                        default:
                            mz = (z + n - 1) % n
                            pz = (z + 1) % n
                        }
                        let o = index(x, y, z)
                        let a = index(mx, my, mz)
                        let b = index(px, py, pz)
                        for c in 0..<channels {
                            scratch[o + c] = (values[a + c] + 2 * values[o + c] + values[b + c]) * 0.25
                        }
                    }
                }
            }
            values = scratch
        }
        for _ in 0..<2 {
            blur(axis: 0)
            blur(axis: 1)
            blur(axis: 2)
        }

        for c in 0..<channels {
            var lo = Float.greatestFiniteMagnitude
            var hi = -Float.greatestFiniteMagnitude
            for i in stride(from: c, to: count, by: channels) {
                lo = min(lo, values[i])
                hi = max(hi, values[i])
            }
            let scale = hi > lo ? 1 / (hi - lo) : 1
            for i in stride(from: c, to: count, by: channels) {
                values[i] = (values[i] - lo) * scale
            }
        }

        var bytes = [UInt8](repeating: 0, count: count)
        for i in 0..<count {
            bytes[i] = UInt8(min(max(values[i] * 255, 0), 255))
        }

        let descriptor = MTLTextureDescriptor()
        descriptor.textureType = .type3D
        descriptor.pixelFormat = .rgba8Unorm
        descriptor.width = n
        descriptor.height = n
        descriptor.depth = n
        // The marcher selects a mip explicitly to prefilter the field to its own
        // sample spacing, so the chain has to exist.
        descriptor.mipmapLevelCount = Int(log2(Double(n))) + 1
        descriptor.usage = .shaderRead
        descriptor.storageMode = .managed

        guard let texture = device.makeTexture(descriptor: descriptor) else { return nil }
        texture.label = "disk noise"
        bytes.withUnsafeBytes { buffer in
            texture.replace(
                region: MTLRegionMake3D(0, 0, 0, n, n, n),
                mipmapLevel: 0,
                slice: 0,
                withBytes: buffer.baseAddress!,
                bytesPerRow: n * channels,
                bytesPerImage: n * n * channels)
        }

        guard let commandBuffer = queue.makeCommandBuffer(),
            let blit = commandBuffer.makeBlitCommandEncoder()
        else { return nil }
        blit.generateMipmaps(for: texture)
        blit.endEncoding()
        commandBuffer.commit()
        commandBuffer.waitUntilCompleted()
        return texture
    }
}
