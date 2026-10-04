import Metal
import SaverKit
import SceneKit
import XCTest

@testable import SolarSystemRender

/// The star field streams past forever, so the thing worth checking is that it
/// never visibly resets — the fault it was rebuilt to remove, where the whole
/// field snapped back by a slab length every couple of minutes and the far end
/// of the sky popped.
///
/// These render through SceneKit, which cannot render offscreen on the
/// virtualised GPU CI runs on, so they skip there and run on a real Mac.
final class StarFieldTests: XCTestCase {

    /// A field and everything needed to look at it, built once per test.
    private struct Viewer {
        let field: StarField
        let renderer: SCNRenderer
        let queue: MTLCommandQueue

        /// Looks down the drift axis from the Sun, which is where the old field's
        /// far end was in view.
        init() throws {
            guard let device = MTLCreateSystemDefaultDevice(), !device.isParavirtual,
                let queue = device.makeCommandQueue()
            else { throw XCTSkip("no GPU SceneKit can render offscreen on") }
            let field = StarField(sceneExtent: 1, parallax: 1)
            let scene = SCNScene()
            scene.background.contents = NSColor.black
            scene.rootNode.addChildNode(field.node)
            let eye = SCNNode()
            eye.camera = SCNCamera()
            eye.camera?.zNear = 0.01
            eye.camera?.zFar = 1000
            eye.look(at: SCNVector3(0, 1, 0), up: SCNVector3(0, 0, 1), localFront: SCNVector3(0, 0, -1))
            scene.rootNode.addChildNode(eye)
            renderer = SCNRenderer(device: device, options: nil)
            renderer.scene = scene
            renderer.pointOfView = eye
            self.field = field
            self.queue = queue
        }

        func frame(driftDistance: Double) throws -> [UInt8] {
            field.update(driftDistance: driftDistance)
            // Outside a render callback the change sits in an implicit transaction
            // until the run loop turns, which a test's never does.
            SCNTransaction.flush()
            let size = CGSize(width: 320, height: 200)
            guard let image = SolarSystemSceneView.renderOffscreen(renderer, size: size, queue: queue)
            else { throw XCTSkip("SceneKit returned no frame") }
            return image.bgraBytes
        }
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
        let viewer = try Viewer()
        let period = viewer.field.length
        let hair = period * 1e-5
        let reference = change(
            try viewer.frame(driftDistance: 0), try viewer.frame(driftDistance: period / 4))
        XCTAssertGreaterThan(reference, 0, "the field did not move")
        for i in 0..<60 {
            let at = Double(i) * period / 60
            let jump = change(
                try viewer.frame(driftDistance: at - hair),
                try viewer.frame(driftDistance: at + hair))
            XCTAssertLessThan(jump, reference / 100, "the sky jumped at \(i)/60 of the period")
        }
    }

    func testAWholePeriodLaterLooksTheSame() throws {
        let viewer = try Viewer()
        let period = viewer.field.length
        let start = try viewer.frame(driftDistance: 7.3)
        let later = try viewer.frame(driftDistance: 7.3 + period * 1000)
        let moved = try viewer.frame(driftDistance: 7.3 + period * 0.25)
        // Exactly a whole number of periods on, every star is back where it was;
        // a quarter of one on, they are not.
        XCTAssertLessThan(change(start, later), change(start, moved) / 50)
    }
}
