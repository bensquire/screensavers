import Foundation
import ThreeBodyCore

/// Persists `SimulationSettings`.
///
/// Backed by whatever `UserDefaults` it is handed: `ScreenSaverDefaults` when
/// running as a screensaver (System Settings sandboxes those separately), and
/// the standard defaults in the preview app.
public final class SettingsStore {

    public static let bundleIdentifier = "com.bensquire.three-body-problem"

    private enum Key {
        static let mode = "sceneMode"
        static let accuracy = "accuracy"
        static let speed = "speed"
        static let trailSeconds = "trailSeconds"
        static let sceneDuration = "sceneDuration"
        static let adaptivePlayback = "adaptivePlayback"
        static let showHUD = "showHUD"
        static let showGlow = "showGlow"
        static let showStars = "showStars"
        static let starDensity = "starDensity"
    }

    private let defaults: UserDefaults

    public init(defaults: UserDefaults) {
        self.defaults = defaults
        let d = SimulationSettings.default
        defaults.register(defaults: [
            Key.mode: d.mode.rawValue,
            Key.accuracy: d.accuracy.rawValue,
            Key.speed: d.speed,
            Key.trailSeconds: d.trailSeconds,
            Key.sceneDuration: d.sceneDuration,
            Key.adaptivePlayback: d.adaptivePlayback,
            Key.showHUD: d.showHUD,
            Key.showGlow: d.showGlow,
            Key.showStars: d.showStars,
            Key.starDensity: d.starDensity,
        ])
    }

    public var settings: SimulationSettings {
        get {
            var s = SimulationSettings()
            s.mode = SceneMode(rawValue: defaults.string(forKey: Key.mode) ?? "") ?? .both
            s.accuracy = Accuracy(rawValue: defaults.string(forKey: Key.accuracy) ?? "") ?? .high
            s.speed = defaults.double(forKey: Key.speed)
            s.trailSeconds = defaults.double(forKey: Key.trailSeconds)
            s.sceneDuration = defaults.double(forKey: Key.sceneDuration)
            s.adaptivePlayback = defaults.bool(forKey: Key.adaptivePlayback)
            s.showHUD = defaults.bool(forKey: Key.showHUD)
            s.showGlow = defaults.bool(forKey: Key.showGlow)
            s.showStars = defaults.bool(forKey: Key.showStars)
            s.starDensity = defaults.double(forKey: Key.starDensity)
            return s.clamped()
        }
        set {
            let s = newValue.clamped()
            defaults.set(s.mode.rawValue, forKey: Key.mode)
            defaults.set(s.accuracy.rawValue, forKey: Key.accuracy)
            defaults.set(s.speed, forKey: Key.speed)
            defaults.set(s.trailSeconds, forKey: Key.trailSeconds)
            defaults.set(s.sceneDuration, forKey: Key.sceneDuration)
            defaults.set(s.adaptivePlayback, forKey: Key.adaptivePlayback)
            defaults.set(s.showHUD, forKey: Key.showHUD)
            defaults.set(s.showGlow, forKey: Key.showGlow)
            defaults.set(s.showStars, forKey: Key.showStars)
            defaults.set(s.starDensity, forKey: Key.starDensity)
            defaults.synchronize()
        }
    }
}

public extension SimulationSettings {
    /// Guards against out-of-range values from a stale or hand-edited plist.
    public func clamped() -> SimulationSettings {
        let fallback = SimulationSettings.default
        var s = self
        s.speed = Limits.speed.clamp(s.speed, fallback: fallback.speed)
        s.trailSeconds = Limits.trailSeconds.clamp(s.trailSeconds, fallback: fallback.trailSeconds)
        s.sceneDuration = Limits.sceneDuration.clamp(
            s.sceneDuration, fallback: fallback.sceneDuration)
        s.starDensity = Limits.starDensity.clamp(s.starDensity, fallback: fallback.starDensity)
        return s
    }
}
