import XCTest
import simd

@testable import SolarSystemCore
@testable import SolarSystemRender

/// `TrailSampler` replaces 2,320 ephemeris evaluations a frame with a handful and
/// an interpolation. That is only a saving if the picture is the same, so it is
/// held to the direct computation here — across every preset the screensaver
/// offers, the cheap preview tier, and the jumps a live view can make.
final class TrailSamplerTests: XCTestCase {

    private let epoch = parseISODate("2026-10-03")!

    /// Worst sample error over `frames` frames of animation, relative to the radius
    /// of the orbit the sample belongs to.
    private func worstRelativeError(
        _ config: SceneConfig, frames: Int, startOffset: TimeInterval = 0,
        file: StaticString = #filePath, line: UInt = #line
    ) throws -> Double {
        let model = DisplayModel(config: config, epoch: epoch)
        let sampler = TrailSampler(model: model)
        let step = config.yearsPerSecond * Constants.secondsPerJulianYear / 30
        var worst = 0.0
        for frame in 0..<frames {
            let date = epoch.addingTimeInterval(startOffset + Double(frame) * step)
            worst = max(worst, try relativeError(sampler, model, at: date, file: file, line: line))
        }
        return worst
    }

    private func relativeError(
        _ sampler: TrailSampler, _ model: DisplayModel, at date: Date,
        file: StaticString = #filePath, line: UInt = #line
    ) throws -> Double {
        let fast = try sampler.snapshot(at: date)
        let exact = try model.snapshot(at: date)
        let sunError = simd_distance(fast.sunPosition, exact.sunPosition)
        XCTAssertEqual(
            sunError, 0, accuracy: 1e-9, "at \(date) the sampled Sun is \(sunError) out",
            file: file, line: line)
        XCTAssertEqual(
            fast.bodies.map(\.planet), exact.bodies.map(\.planet),
            "at \(date) the sampler lists different planets", file: file, line: line)
        var worst = 0.0
        for (a, b) in zip(fast.bodies, exact.bodies) {
            XCTAssertEqual(
                a.trail.count, b.trail.count,
                "at \(date) \(a.planet.name)'s trail has \(a.trail.count) samples, not \(b.trail.count)",
                file: file, line: line)
            // Sun-relative, at each sample's own time, so the drift — which is
            // added back exactly and is far larger than any orbit — does not
            // flatter the comparison.
            for (i, (p, q)) in zip(a.trail, b.trail).enumerated() {
                let sun = model.sunOffset(
                    at: model.sampleDate(i, of: b.trail.count, for: b.planet, at: date))
                let radius = max(simd_length(q - sun), 1e-6)
                worst = max(worst, simd_distance(p, q) / radius)
            }
        }
        return worst
    }

    /// Each preset the options offer samples and interpolates differently; the
    /// cheap path has to match the direct computation for every one of them.
    func testMatchesTheEphemerisForEveryOfferedPreset() throws {
        for preset in ScalePreset.selectable {
            let error = try worstRelativeError(preset.config(), frames: 90)
            // Measured at 3.4e-5. A ten-thousandth of an orbit's radius is a
            // tenth of a pixel even with that orbit filling a 5K display, and a
            // tenth of the sag of the straight segments the trail is drawn with.
            XCTAssertLessThan(error, 1e-4, "\(preset.title): worst relative error \(error)")
        }
    }

    /// System Settings' thumbnail draws a quarter of the samples, so its grid is
    /// four times coarser. Still invisible: the bound is the straight segments it
    /// already draws between those samples, whose sag is far larger.
    func testMatchesTheEphemerisAtPreviewDensity() throws {
        var config = SceneConfig()
        config.trailSamples = RenderQuality.preview.trailSamples
        // Measured at 1.4e-3, against a segment sag of 8.6e-3 at this density.
        let error = try worstRelativeError(config, frames: 60)
        XCTAssertLessThan(error, 3e-3, "worst relative error at preview density \(error)")
    }

    /// Far from J2000 the date has the least precision to spare, which is where
    /// the grid arithmetic would show it.
    func testMatchesTheEphemerisCenturiesOn() throws {
        let error = try worstRelativeError(
            SceneConfig(), frames: 30, startOffset: 400 * Constants.secondsPerJulianYear)
        XCTAssertLessThan(error, 1e-4, "worst relative error 400 years on \(error)")
    }

    /// A paused, resized or re-dated view can ask for any moment; the sampler
    /// must not assume time only moves forward by a frame.
    func testSurvivesJumpsInEitherDirection() throws {
        let model = DisplayModel(config: SceneConfig(), epoch: epoch)
        let sampler = TrailSampler(model: model)
        let year = Constants.secondsPerJulianYear
        for offset in [0, 3 * year, 2.9 * year, -40 * year, 500 * year, 499.99 * year, 0] {
            let error = try relativeError(sampler, model, at: epoch.addingTimeInterval(offset))
            XCTAssertLessThan(error, 1e-4, "offset \(offset / year) years: worst relative error \(error)")
        }
    }
}
