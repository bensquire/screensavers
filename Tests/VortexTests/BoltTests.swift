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

    func testBoltsFitInAnInlineBuffer() {
        // Lightning is uploaded with setVertexBytes rather than through a buffer,
        // which is only valid below 4KB. Subdividing 10 anchors four times gives
        // 145 points and so 290 vertices — but if that ever changes, the draw
        // would be silently skipped rather than fail, so pin it here.
        let bolts = allBolts()
        XCTAssertFalse(bolts.isEmpty)
        let largest = bolts.map(\.vertices.count).max()!
        XCTAssertEqual(largest, 290)
        XCTAssertLessThanOrEqual(
            largest * MemoryLayout<SIMD2<Float>>.stride, VortexRenderer.maxInlineBytes)
    }

    func testRibbonHasTwoVerticesPerPoint() {
        let points: [SIMD2<Double>] = (0..<20).map { SIMD2(Double($0) * 10, 0) }
        let ribbon = Bolt.ribbon(along: points, thickness: 4)
        XCTAssertEqual(ribbon.count, points.count * 2)

        // The path runs along x, so the ribbon spreads along y, and it tapers to
        // its thinnest at both ends.
        func halfWidth(at i: Int) -> Float { abs(ribbon[i * 2].y - ribbon[i * 2 + 1].y) / 2 }
        XCTAssertLessThan(halfWidth(at: 0), halfWidth(at: 10))
        XCTAssertLessThan(halfWidth(at: points.count - 1), halfWidth(at: 10))
    }

    func testShortBoltsAreRejected() {
        // On a tiny drawable the minimum-length gate should throw most away
        // rather than drawing a knot of noise a few pixels across.
        let tiny = Layout(pointWidth: 60, pointHeight: 40, backingScale: 1)
        var rng = SplitMix64(seed: 5)
        let made = (0..<200).compactMap { _ in
            Bolt(layout: tiny, bendX: 0, bendY: 0, spin: 0, rng: &rng)
        }
        for bolt in made {
            let span = bolt.vertices.last! - bolt.vertices.first!
            XCTAssertGreaterThan(
                (span.x * span.x + span.y * span.y).squareRoot(),
                Float(tiny.minDimension) * 0.05)
        }
    }

    func testBoltsFadeOutOverTheirLifetime() {
        var rng = SplitMix64(seed: 1)
        guard var bolt = Bolt(layout: layout, bendX: 0, bendY: 0, spin: 0, rng: &rng) else {
            return XCTFail("no bolt was generated")
        }
        // Snaps up over the first 12% of its life, then decays.
        bolt.advance(byMs: bolt.lifetimeMs * 0.12)
        let peak = bolt.intensity
        XCTAssertEqual(peak, 1.0, accuracy: 1e-4)

        bolt.advance(byMs: bolt.lifetimeMs * 0.5)
        XCTAssertLessThan(bolt.intensity, peak)
        XCTAssertGreaterThan(bolt.intensity, 0)

        bolt.advance(byMs: bolt.lifetimeMs)
        XCTAssertTrue(bolt.isFinished)
    }

    func testBoltsFollowTheTunnelWall() {
        // A bolt is drawn on the cylinder, so it should sit out in the annulus
        // rather than through the dark throat at the centre.
        let centre = SIMD2<Float>(Float(layout.centerX), Float(layout.centerY))
        for bolt in allBolts(count: 100) {
            let start = bolt.vertices.first!
            let offset = start - centre
            let distance = (offset.x * offset.x + offset.y * offset.y).squareRoot()
            XCTAssertGreaterThan(distance, Float(layout.minDimension) * 0.05)
        }
    }
}
