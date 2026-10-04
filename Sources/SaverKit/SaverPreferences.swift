import Foundation
import ScreenSaver

/// Preference storage for a screensaver module, written to two places.
///
/// `ScreenSaverDefaults` is the documented mechanism and works fine in a normal
/// process. But the options sheet is presented from a sandboxed host, and a write
/// there is not guaranteed to land — the setting can be accepted in System Settings
/// and then simply not be there next time. Mirroring into standard defaults costs
/// nothing and means the choice survives even when the ByHost write is refused.
///
/// Learned the hard way in the Solar System saver; every saver needs it, so it lives
/// here rather than being rediscovered per project.
public struct SaverPreferences {

    private let moduleDefaults: ScreenSaverDefaults?
    private let fallback: UserDefaults
    /// Prefix for the mirrored keys, so two savers cannot collide in the shared
    /// standard-defaults domain.
    private let fallbackPrefix: String

    public init(moduleIdentifier: String, fallback: UserDefaults = .standard) {
        self.moduleDefaults = ScreenSaverDefaults(forModuleWithName: moduleIdentifier)
        self.fallback = fallback
        self.fallbackPrefix = moduleIdentifier + "."
    }

    private func fallbackKey(_ key: String) -> String { fallbackPrefix + key }

    /// Registers defaults with the mirror only.
    ///
    /// Registering them with the module store as well — which this once did — made
    /// the mirror unreachable: a registered key always has a value, so every read
    /// below found one in the module store and stopped there, and a refused ByHost
    /// write came back as the default rather than as the mirrored choice. Lookups
    /// fall through to the mirror, so a default registered there still answers when
    /// neither store holds a choice.
    public func register(defaults values: [String: Any]) {
        var mirrored: [String: Any] = [:]
        for (key, value) in values { mirrored[fallbackKey(key)] = value }
        fallback.register(defaults: mirrored)
    }

    /// The module store wins when it has a value; the mirror answers when it does not.
    public func string(forKey key: String) -> String? {
        moduleDefaults?.string(forKey: key) ?? fallback.string(forKey: fallbackKey(key))
    }

    public func double(forKey key: String) -> Double {
        if let value = moduleDefaults?.object(forKey: key) as? Double { return value }
        return fallback.double(forKey: fallbackKey(key))
    }

    public func bool(forKey key: String) -> Bool {
        if let value = moduleDefaults?.object(forKey: key) as? Bool { return value }
        return fallback.bool(forKey: fallbackKey(key))
    }

    public func set(_ value: Any, forKey key: String) {
        moduleDefaults?.set(value, forKey: key)
        fallback.set(value, forKey: fallbackKey(key))
    }

    public func synchronize() {
        moduleDefaults?.synchronize()
    }
}
