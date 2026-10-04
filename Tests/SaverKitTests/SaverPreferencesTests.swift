import ScreenSaver
import XCTest

@testable import SaverKit

/// The mirror into standard defaults exists for one case — the sandboxed host
/// refusing the module store's write — so that is the case worth checking: a
/// value only the mirror holds must be the one read back, defaults registered
/// or not.
final class SaverPreferencesTests: XCTestCase {

    /// Fixed rather than unique per run: the stores are emptied afterwards, but
    /// the system keeps an empty file for each domain, and one is enough.
    private let identifier = "com.bensquire.saverkit-tests"
    private let suiteName = "com.bensquire.saverkit-tests.fallback"
    private var fallback: UserDefaults!

    override func setUp() {
        super.setUp()
        fallback = UserDefaults(suiteName: suiteName)
        fallback.removePersistentDomain(forName: suiteName)
    }

    override func tearDown() {
        fallback.removePersistentDomain(forName: suiteName)
        if let module = ScreenSaverDefaults(forModuleWithName: identifier) {
            for key in ["speed", "enabled", "mode"] { module.removeObject(forKey: key) }
            module.synchronize()
        }
        super.tearDown()
    }

    private func makePreferences() -> SaverPreferences {
        let preferences = SaverPreferences(moduleIdentifier: identifier, fallback: fallback)
        preferences.register(defaults: ["speed": 1.0, "enabled": true, "mode": "both"])
        return preferences
    }

    func testRegisteredDefaultsAnswerWhenNothingIsStored() {
        let preferences = makePreferences()
        XCTAssertEqual(preferences.double(forKey: "speed"), 1.0)
        XCTAssertTrue(preferences.bool(forKey: "enabled"))
        XCTAssertEqual(preferences.string(forKey: "mode"), "both")
    }

    /// What a refused ByHost write leaves behind: the choice in the mirror and
    /// nothing in the module store. Registering defaults with the module store
    /// used to hide the mirror entirely, and the choice read back as the default.
    func testTheMirrorAnswersWhenTheModuleStoreHasNothing() {
        let preferences = makePreferences()
        fallback.set(3.0, forKey: "\(identifier).speed")
        fallback.set(false, forKey: "\(identifier).enabled")
        fallback.set("catalogue", forKey: "\(identifier).mode")
        XCTAssertEqual(preferences.double(forKey: "speed"), 3.0)
        XCTAssertFalse(preferences.bool(forKey: "enabled"))
        XCTAssertEqual(preferences.string(forKey: "mode"), "catalogue")
    }

    func testAWriteReadsBackFromEitherStore() {
        let preferences = makePreferences()
        preferences.set(2.5, forKey: "speed")
        XCTAssertEqual(preferences.double(forKey: "speed"), 2.5)
        XCTAssertEqual(fallback.double(forKey: "\(identifier).speed"), 2.5)
    }
}
