import AppKit
import ScreenSaver
import XCTest

@testable import SaverKit

/// The host stopped telling screensavers when to stop, so these signals are the
/// only thing that does. Each is checked against a local notification centre:
/// posting the real session notification would stop every screensaver running
/// on the machine.
final class SaverLifecycleTests: XCTestCase {

    private let frameInterval = 1.0 / 30

    private func makeView(isPreview: Bool = false) -> ScreenSaverView {
        ScreenSaverView(frame: NSRect(x: 0, y: 0, width: 64, height: 40), isPreview: isPreview)!
    }

    /// The interval the timer should run at when awake, on this machine as it is.
    private var awakeInterval: TimeInterval {
        ProcessInfo.processInfo.isLowPowerModeEnabled ? 2 * frameInterval : frameInterval
    }

    /// The host no longer stops a saver when the screensaver is dismissed;
    /// without this signal a full-screen instance keeps drawing after it.
    func testSessionEndStopsAFullScreenInstance() {
        let center = NotificationCenter()
        var ended = 0
        let lifecycle = SaverLifecycle(
            view: makeView(), frameInterval: frameInterval, sessionCenter: center
        ) { ended += 1 }

        center.post(name: SaverLifecycle.sessionWillStop, object: nil)

        XCTAssertEqual(ended, 1, "the session end stopped the saver \(ended) times, not once")
        withExtendedLifetime(lifecycle) {}
    }

    /// The System Settings thumbnail is not part of a session, and stopping it
    /// would leave a dead tile until the pane was reopened.
    func testSessionEndLeavesThePreviewAlone() {
        let center = NotificationCenter()
        var ended = 0
        let lifecycle = SaverLifecycle(
            view: makeView(isPreview: true), frameInterval: frameInterval, sessionCenter: center
        ) { ended += 1 }

        center.post(name: SaverLifecycle.sessionWillStop, object: nil)

        XCTAssertEqual(ended, 0, "the session end stopped the preview")
        withExtendedLifetime(lifecycle) {}
    }

    /// A lifecycle that has gone away must not call back into a view that has
    /// gone with it.
    func testObserversGoWithTheLifecycle() {
        let center = NotificationCenter()
        var ended = 0
        var lifecycle: SaverLifecycle? = SaverLifecycle(
            view: makeView(), frameInterval: frameInterval, sessionCenter: center
        ) { ended += 1 }
        lifecycle = nil

        center.post(name: SaverLifecycle.sessionWillStop, object: nil)

        XCTAssertEqual(ended, 0, "a released lifecycle still answered the session end")
        XCTAssertNil(lifecycle)
    }

    /// While the displays sleep nothing is drawn, and the timer slows right down
    /// rather than waking the processor thirty times a second to do nothing.
    func testTheTimerSlowsWhileTheDisplaysSleep() {
        let view = makeView()
        let lifecycle = SaverLifecycle(
            view: view, frameInterval: frameInterval, sessionCenter: NotificationCenter()
        ) {}
        var changes = 0
        lifecycle.onChange = { changes += 1 }
        let workspace = NSWorkspace.shared.notificationCenter

        XCTAssertFalse(lifecycle.isSuspended)
        XCTAssertEqual(
            view.animationTimeInterval, awakeInterval, accuracy: 1e-9,
            "awake, the timer runs every \(view.animationTimeInterval) s")

        workspace.post(name: NSWorkspace.screensDidSleepNotification, object: nil)
        XCTAssertTrue(lifecycle.isSuspended)
        XCTAssertEqual(
            view.animationTimeInterval, SaverLifecycle.sleepingInterval, accuracy: 1e-9,
            "asleep, the timer runs every \(view.animationTimeInterval) s")
        XCTAssertEqual(changes, 1, "sleeping reported \(changes) changes, not 1")

        workspace.post(name: NSWorkspace.screensDidWakeNotification, object: nil)
        XCTAssertFalse(lifecycle.isSuspended)
        XCTAssertEqual(
            view.animationTimeInterval, awakeInterval, accuracy: 1e-9,
            "woken, the timer runs every \(view.animationTimeInterval) s")
        XCTAssertEqual(changes, 2, "sleeping and waking reported \(changes) changes, not 2")
    }

    /// Low Power Mode halves the frame rate. Which applies depends on the machine
    /// running the test, so both are checked against what it reports.
    func testFrameRateFollowsLowPowerMode() {
        let view = makeView()
        let lifecycle = SaverLifecycle(
            view: view, frameInterval: frameInterval, sessionCenter: NotificationCenter()
        ) {}
        let lowPower = ProcessInfo.processInfo.isLowPowerModeEnabled
        XCTAssertEqual(
            lifecycle.framesPerSecond,
            lowPower ? FrameClock.framesPerSecond / 2 : FrameClock.framesPerSecond,
            "with Low Power Mode \(lowPower ? "on" : "off") the saver runs at \(lifecycle.framesPerSecond) fps"
        )
        XCTAssertEqual(
            view.animationTimeInterval, awakeInterval, accuracy: 1e-9,
            "the timer runs every \(view.animationTimeInterval) s")
    }
}
