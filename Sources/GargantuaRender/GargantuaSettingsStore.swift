import Foundation
import GargantuaCore
import SaverKit

/// Persists `GargantuaSettings`.
///
/// Goes through `SaverPreferences` for the same reason every saver here does:
/// the options sheet runs in a sandboxed host where the ByHost write is not
/// guaranteed to land, so the values are mirrored into standard defaults too.
public final class GargantuaSettingsStore {

    public static let bundleIdentifier = "com.bensquire.Gargantua"

    private enum Key {
        static let pace = "pace"
        static let beaming = "beaming"
        static let stars = "stars"
        static let adaptiveResolution = "adaptiveResolution"
        static let renderScale = "renderScale"
    }

    private let defaults: SaverPreferences

    public init(defaults: SaverPreferences) {
        self.defaults = defaults
        let d = GargantuaSettings.default
        defaults.register(defaults: [
            Key.pace: d.pace,
            Key.beaming: d.beaming,
            Key.stars: d.stars,
            Key.adaptiveResolution: d.adaptiveResolution,
            Key.renderScale: d.renderScale,
        ])
    }

    /// Reading always goes through `GargantuaSettings.init`, which clamps — a
    /// stale or hand-edited plist cannot put the scene into a state the sheet
    /// could not have produced.
    public var settings: GargantuaSettings {
        get {
            GargantuaSettings(
                pace: defaults.double(forKey: Key.pace),
                beaming: defaults.double(forKey: Key.beaming),
                stars: defaults.double(forKey: Key.stars),
                adaptiveResolution: defaults.bool(forKey: Key.adaptiveResolution),
                renderScale: defaults.double(forKey: Key.renderScale))
        }
        set {
            defaults.set(newValue.pace, forKey: Key.pace)
            defaults.set(newValue.beaming, forKey: Key.beaming)
            defaults.set(newValue.stars, forKey: Key.stars)
            defaults.set(newValue.adaptiveResolution, forKey: Key.adaptiveResolution)
            defaults.set(newValue.renderScale, forKey: Key.renderScale)
            defaults.synchronize()
        }
    }
}
