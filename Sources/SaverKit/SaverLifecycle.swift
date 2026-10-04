import AppKit
import CoreGraphics
import QuartzCore
import ScreenSaver

/// Stands in for the lifecycle calls the screensaver host no longer makes.
///
/// The `legacyScreenSaver` process that hosts third-party savers — widely reported
/// since macOS 14, and seen here on 26.6 — neither calls `stopAnimation()` when
/// the screensaver is dismissed nor releases the view. Every session's views stay
/// alive, timers still firing, in a process that outlives them by weeks, and the
/// next session gets fresh ones. One host on the machine this was written on had
/// been up for 21 days holding 79 Solar System and 42 Three-Body instances —
/// 22.8 GB, 13.8 GB of it GPU memory — with one leaked SceneKit view still
/// rendering at nearly a full core while nothing was on screen.
///
/// Two signals are still dependable, and this listens for both:
///
/// - `com.apple.screensaver.willstop`, which the system posts as a session ends.
///   The view is told to stop, which is where every saver here hands back its GPU
///   resources — so although the host keeps the view, what it keeps is small and
///   idle.
/// - Display sleep. A screensaver routinely outlasts the display-sleep timer, and
///   nothing else stops the host animating into a powered-down panel all night.
///
/// It also halves the frame rate in Low Power Mode, which is the one setting where
/// the user has said outright that energy matters more than smoothness.
///
/// Both are done by setting the view's `animationTimeInterval`, which the host's
/// timer follows even mid-animation, rather than by skipping ticks: a skipped tick
/// still wakes the processor, and a whole night of them keeps it out of its
/// deepest idle for nothing.
public final class SaverLifecycle {

    /// Posted by the system as a screensaver session ends.
    public static let sessionWillStop = Notification.Name("com.apple.screensaver.willstop")

    /// The timer's interval while the displays sleep. Each tick confirms they still
    /// are, in case the wake notification never arrives — which would otherwise
    /// leave the saver black until it was dismissed.
    static let sleepingInterval: TimeInterval = 5

    /// Called on the main thread whenever `isSuspended` or `framesPerSecond` may have
    /// changed, for a renderer that paces itself rather than drawing on the timer.
    public var onChange: (() -> Void)?

    private weak var view: ScreenSaverView?
    private let frameInterval: TimeInterval
    private var tokens: [(center: NotificationCenter, token: NSObjectProtocol)] = []
    private var displaysAsleep = false
    /// When sleep was reported. The display is only asked after a full sleeping
    /// interval: asked straight away, it can still say awake.
    private var asleepSince: CFTimeInterval = 0
    private var lowPower = ProcessInfo.processInfo.isLowPowerModeEnabled

    /// - Parameters:
    ///   - view: the saver. Its `animationTimeInterval` is managed from here on.
    ///   - frameInterval: the timer interval at full rate.
    ///   - sessionCenter: where the session notification arrives. Only tests pass
    ///     anything else: posting the real one would stop every screensaver on the
    ///     machine.
    ///   - onSessionEnd: called on the main thread when the session ends. Owners
    ///     stop animating and release whatever they can rebuild on the next start.
    ///     Never for the System Settings thumbnail, which is not part of a session:
    ///     the notification still reaches it, and stopping it would leave a dead
    ///     tile until the pane is reopened.
    public init(
        view: ScreenSaverView,
        frameInterval: TimeInterval,
        sessionCenter: NotificationCenter = DistributedNotificationCenter.default(),
        onSessionEnd: @escaping () -> Void
    ) {
        self.view = view
        self.frameInterval = frameInterval
        if !view.isPreview {
            observe(sessionCenter, Self.sessionWillStop) { _ in onSessionEnd() }
        }
        let workspace = NSWorkspace.shared.notificationCenter
        observe(workspace, NSWorkspace.screensDidSleepNotification) { [weak self] _ in
            self?.update {
                $0.displaysAsleep = true
                $0.asleepSince = CACurrentMediaTime()
            }
        }
        observe(workspace, NSWorkspace.screensDidWakeNotification) { [weak self] _ in
            self?.update { $0.displaysAsleep = false }
        }
        observe(NotificationCenter.default, .NSProcessInfoPowerStateDidChange) { [weak self] _ in
            self?.update { $0.lowPower = ProcessInfo.processInfo.isLowPowerModeEnabled }
        }
        view.animationTimeInterval = animationInterval
    }

    deinit {
        for (center, token) in tokens { center.removeObserver(token) }
    }

    private func observe(
        _ center: NotificationCenter, _ name: Notification.Name,
        _ handler: @escaping (Notification) -> Void
    ) {
        tokens.append((center, center.addObserver(forName: name, object: nil, queue: .main, using: handler)))
    }

    private func update(_ change: (SaverLifecycle) -> Void) {
        change(self)
        view?.animationTimeInterval = animationInterval
        onChange?()
    }

    /// True while the displays are asleep, when there is nobody to draw for.
    /// Asking also confirms it with the display, at the slow tick rate sleep sets.
    public var isSuspended: Bool {
        if displaysAsleep, CACurrentMediaTime() - asleepSince >= Self.sleepingInterval,
            CGDisplayIsAsleep(CGMainDisplayID()) == 0
        {
            update { $0.displaysAsleep = false }
        }
        return displaysAsleep
    }

    /// The frame rate to run at right now: the shared policy, halved in Low Power
    /// Mode. For a renderer that drives itself, such as SceneKit.
    public var framesPerSecond: Double {
        lowPower ? FrameClock.framesPerSecond / 2 : FrameClock.framesPerSecond
    }

    /// What the view's timer should be running at right now.
    var animationInterval: TimeInterval {
        displaysAsleep ? Self.sleepingInterval : (lowPower ? 2 * frameInterval : frameInterval)
    }
}
