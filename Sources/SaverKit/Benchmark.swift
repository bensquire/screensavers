import Foundation
import Metal

/// What every saver's `--bench` mode shares, so the four report numbers measured
/// and summarised the same way.
public enum Benchmark {

    /// The integer after `name` on the command line, or `fallback`.
    public static func argument(_ name: String, default fallback: Int) -> Int {
        let args = CommandLine.arguments
        guard let i = args.firstIndex(of: name), i + 1 < args.count else { return fallback }
        return Int(args[i + 1]) ?? fallback
    }

    /// Median and 95th percentile. A median rather than a mean, because a frame's
    /// cost has a long tail — clock changes, the first use of a pipeline — that is
    /// not what a frame costs.
    public static func summary(_ samples: [Double]) -> (median: Double, p95: Double) {
        let sorted = samples.sorted()
        guard !sorted.isEmpty else { return (0, 0) }
        let p95 = min(sorted.count - 1, Int(Double(sorted.count) * 0.95))
        return (sorted[sorted.count / 2], sorted[p95])
    }

    /// Commits `buffer`, waits for it, and returns the milliseconds the GPU spent
    /// on it — its own clock, not the wall's, which would also count the wait.
    public static func gpuMilliseconds(committing buffer: MTLCommandBuffer) -> Double {
        buffer.commit()
        buffer.waitUntilCompleted()
        return (buffer.gpuEndTime - buffer.gpuStartTime) * 1000
    }

    /// A colour target only the GPU touches, like a drawable.
    public static func renderTarget(device: MTLDevice, width: Int, height: Int) -> MTLTexture? {
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .bgra8Unorm, width: width, height: height, mipmapped: false)
        descriptor.usage = [.renderTarget]
        descriptor.storageMode = .private
        return device.makeTexture(descriptor: descriptor)
    }
}
