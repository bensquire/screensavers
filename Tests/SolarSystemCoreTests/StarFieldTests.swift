import Metal
import SaverKit
import SceneKit
import XCTest

@testable import SolarSystemRender

/// The star field streams past forever, so the thing worth checking is that it
/// never visibly resets — the fault it was rebuilt to remove, where the whole
/// field snapped back by a slab length every couple of minutes and the far end
/// of the sky popped.
final class StarFieldTests: XCTestCase {

    private let extent = 1.0
    private let parallax = 1.0
    /// The field's period along the drift axis: `StarField` sizes it as 30 extents.
    private var period: Double { 30 * extent }

    /// Looks down the drift axis from the Sun, which is where the old field's far
    /// end was in view.
    private func render(_ field: StarField, driftDistance: Double) throws -> [UInt8] {
        guard let device = MTLCreateSystemDefaultDevice(), !device.isParavirtual else {
            // SceneKit cannot render offscreen on a virtualised GPU; it asserts.
            throw XCTSkip("no GPU SceneKit can render offscreen on")
        }
        field.update(driftDistance: driftDistance)
        let scene = SCNScene()
        scene.background.contents = NSColor.black
        scene.rootNode.addChildNode(field.node)
        let eye = SCNNode()
        eye.camera = SCNCamera()
        eye.camera?.zNear = 0.01
        eye.camera?.zFar = 1000
        eye.look(at: SCNVector3(0, 1, 0), up: SCNVector3(0, 0, 1), localFront: SCNVector3(0, 0, -1))
        scene.rootNode.addChildNode(eye)

        let renderer = SCNRenderer(device: device, options: nil)
        renderer.scene = scene
        renderer.pointOfView = eye
        let image = renderer.snapshot(
            atTime: 0, with: CGSize(width: 320, height: 200), antialiasingMode: .none)
        guard let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            throw XCTSkip("SceneKit returned no frame")
        }
        var pixels = [UInt8](repeating: 0, count: cg.width * cg.height * 4)
        let context = CGContext(
            data: &pixels, width: cg.width, height: cg.height, bitsPerComponent: 8,
            bytesPerRow: cg.width * 4, space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)
        context?.draw(cg, in: CGRect(x: 0, y: 0, width: cg.width, height: cg.height))
        return pixels
    }

    /// Total brightness change between two frames.
    private func change(_ a: [UInt8], _ b: [UInt8]) -> Int {
        zip(a, b).reduce(0) { $0 + abs(Int($1.0) - Int($1.1)) }
    }

    /// A hair's breadth of travel must change the frame by a hair, wherever along
    /// the period it happens. Sixty points across a period, checked a hair either
    /// side, against a quarter of a period's travel; the old field snapped back at
    /// three of them, popping a whole slab of stars into the far end of the sky.
    func testATinyStepNeverChangesMuchAnywhereInThePeriod() throws {
        let field = StarField(sceneExtent: extent, parallax: parallax)
        let hair = period * 1e-5
        let reference = change(
            try render(field, driftDistance: 0), try render(field, driftDistance: period / 4))
        XCTAssertGreaterThan(reference, 0, "the field did not move")
        for i in 0..<60 {
            let at = Double(i) * period / 60
            let jump = change(
                try render(field, driftDistance: at - hair),
                try render(field, driftDistance: at + hair))
            XCTAssertLessThan(jump, reference / 100, "the sky jumped at \(i)/60 of the period")
        }
    }

    func testAWholePeriodLaterLooksTheSame() throws {
        let field = StarField(sceneExtent: extent, parallax: parallax)
        let start = try render(field, driftDistance: 7.3)
        let later = try render(field, driftDistance: 7.3 + period * 1000)
        let moved = try render(field, driftDistance: 7.3 + period * 0.25)
        // Exactly a whole number of periods on, every star is back where it was;
        // a quarter of one on, they are not.
        XCTAssertLessThan(change(start, later), change(start, moved) / 50)
    }
}
