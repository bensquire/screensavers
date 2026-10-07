import SaverKit
import XCTest

@testable import VortexCore
@testable import VortexRender

final class BoltTests: XCTestCase {

    private let layout = Layout(pointWidth: 2560, pointHeight: 1600, backingScale: 2)

    /// Every bolt the generator can produce, so the bounds below are not
    /// measured against one lucky sample.
    private func allBolts(count: Int = 400) -> [Bolt] {
        var rng = SplitMix64(seed: 99)
        return (0..<count).compactMap { _ in
            Bolt(layout: layout, bendX: 300, bendY: -200, spin: 0.4, rng: &rng)
        }
    }

    /// Lightning is uploaded with setVertexBytes rather than through a buffer,
    /// which is only valid below 4KB. Subdividing 10 anchors four times gives 145
    /// points and so 290 vertices — but if that ever changes, the draw would be
    /// silently skipped rather than fail.
    func testBoltsFitInAnInlineBuffer() throws {
        let bolts = allBolts()

        let largest = try XCTUnwrap(bolts.map(\.vertices.count).max(), "no bolt was generated")

        XCTAssertEqual(largest, 290, "the largest bolt has \(largest) vertices, not 290")
        XCTAssertLessThanOrEqual(
            largest * MemoryLayout<SIMD2<Float>>.stride, VortexRenderer.maxInlineBytes,
            "a \(largest)-vertex bolt is too big for setVertexBytes")
    }

    /// The ribbon is drawn as a triangle strip, which needs a vertex either side
    /// of every point; a bolt that did not taper would end in blunt bars.
    func testRibbonHasTwoVerticesPerPoint() {
        let points: [SIMD2<Double>] = (0..<20).map { SIMD2(Double($0) * 10, 0) }

        let ribbon = Bolt.ribbon(along: points, thickness: 4)

        XCTAssertEqual(
            ribbon.count, points.count * 2, "\(ribbon.count) vertices for \(points.count) points")
        // The path runs along x, so the ribbon spreads along y, and it tapers to
        // its thinnest at both ends.
        func halfWidth(at i: Int) -> Float { abs(ribbon[i * 2].y - ribbon[i * 2 + 1].y) / 2 }
        XCTAssertLessThan(halfWidth(at: 0), halfWidth(at: 10), "the ribbon does not taper at its start")
        XCTAssertLessThan(
            halfWidth(at: points.count - 1), halfWidth(at: 10), "the ribbon does not taper at its end")
    }

    /// On a tiny drawable the minimum-length gate should throw most away rather
    /// than drawing a knot of noise a few pixels across.
    func testShortBoltsAreRejected() {
        let tiny = Layout(pointWidth: 60, pointHeight: 40, backingScale: 1)
        var rng = SplitMix64(seed: 5)
        let made = (0..<200).compactMap { _ in
            Bolt(layout: tiny, bendX: 0, bendY: 0, spin: 0, rng: &rng)
        }
        for (index, bolt) in made.enumerated() {
            let span = bolt.vertices.last! - bolt.vertices.first!
            let length = (span.x * span.x + span.y * span.y).squareRoot()
            XCTAssertGreaterThan(
                length, Float(tiny.minDimension) * 0.05,
                "bolt \(index) spans only \(length) points on a 60x40 drawable")
        }
    }

    /// A bolt snaps up over the first 12% of its life, then decays and ends; one
    /// that never finished would stay on screen, and one that never peaked
    /// would never be seen.
    func testBoltsFadeOutOverTheirLifetime() {
        var rng = SplitMix64(seed: 1)
        guard var bolt = Bolt(layout: layout, bendX: 0, bendY: 0, spin: 0, rng: &rng) else {
            return XCTFail("no bolt was generated")
        }
        bolt.advance(byMs: bolt.lifetimeMs * 0.12)
        let peak = bolt.intensity
        XCTAssertEqual(peak, 1.0, accuracy: 1e-4, "at 12% of its life the bolt is at \(peak)")

        bolt.advance(byMs: bolt.lifetimeMs * 0.5)
        XCTAssertLessThan(bolt.intensity, peak, "the bolt has not faded from its peak")
        XCTAssertGreaterThan(bolt.intensity, 0, "the bolt went out halfway through its life")

        bolt.advance(byMs: bolt.lifetimeMs)
        XCTAssertTrue(bolt.isFinished)
    }

    /// A bolt is drawn on the cylinder, so it should sit out in the annulus
    /// rather than through the dark throat at the centre.
    func testBoltsFollowTheTunnelWall() {
        let centre = SIMD2<Float>(Float(layout.centerX), Float(layout.centerY))
        for (index, bolt) in allBolts(count: 100).enumerated() {
            let start = bolt.vertices.first!
            let offset = start - centre
            let distance = (offset.x * offset.x + offset.y * offset.y).squareRoot()
            XCTAssertGreaterThan(
                distance, Float(layout.minDimension) * 0.05,
                "bolt \(index) starts \(distance) points from the centre, in the throat")
        }
    }
}
