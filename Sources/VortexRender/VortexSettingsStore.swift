import Foundation
import SaverKit
import VortexCore

/// Persists `VortexSettings`.
///
/// Goes through `SaverPreferences` for the same reason every saver here does:
/// the options sheet runs in a sandboxed host where the ByHost write is not
/// guaranteed to land, so the values are mirrored into standard defaults too.
public final class VortexSettingsStore {

    public static let bundleIdentifier = "com.bensquire.SlidersVortex"

    private enum Key {
        static let flowSpeed = "flowSpeed"
        static let lightning = "lightning"
        static let density = "density"
    }

    private let defaults: SaverPreferences

    public init(defaults: SaverPreferences) {
        self.defaults = defaults
        let d = VortexSettings.default
        defaults.register(defaults: [
            Key.flowSpeed: d.flowSpeed,
            Key.lightning: d.lightning,
            Key.density: d.density,
        ])
    }

    /// Reading always goes through `VortexSettings.init`, which clamps — a stale
    /// or hand-edited plist cannot put the scene into a state the sheet could not
    /// have produced.
    public var settings: VortexSettings {
        get {
            VortexSettings(
                flowSpeed: defaults.double(forKey: Key.flowSpeed),
                lightning: defaults.bool(forKey: Key.lightning),
                density: defaults.double(forKey: Key.density))
        }
        set {
            defaults.set(newValue.flowSpeed, forKey: Key.flowSpeed)
            defaults.set(newValue.lightning, forKey: Key.lightning)
            defaults.set(newValue.density, forKey: Key.density)
            defaults.synchronize()
        }
    }
}
