import Foundation
import SolarSystemCore

/// The three ways the scene can be scaled, in one place so the app, the screensaver's
/// options sheet and the command-line script cannot disagree about what each one means.
public enum ScalePreset: String, CaseIterable, Sendable {

    /// Where the chosen preset is stored.
    ///
    /// Lives with the enum because `rawValue` *is* the stored contract — the case list
    /// and the persisted strings have to change together. Previously the domain and keys
    /// were literals in the saver and again in Scripts/scale-mode.sh, four copies that
    /// could drift silently.
    public enum Preference {
        public static let domain = "com.solarsystem.screensaver"
        /// Per-host key, written by the options sheet and `defaults -currentHost`.
        public static let key = "scaleMode"
        /// Mirror in standard defaults, for when the sandboxed host refuses the ByHost write.
        public static let fallbackKey = "\(domain).\(key)"
    }

    /// The presets offered in the screensaver's options. `allCases` additionally
    /// includes ones that exist only as command-line demonstrations.
    public static let selectable: [ScalePreset] = [.stylised, .trueDistances, .birdsEye]

    /// The default. Distances and sizes both compressed so the whole system is legible
    /// at once and the galactic helix is visible.
    case stylised

    /// Looking straight down on the ecliptic from a fixed camera, with the galactic
    /// drift switched off so the orbits close into ellipses. An orrery.
    case birdsEye

    /// Real relative distances — Neptune genuinely 30× Earth's orbit rather than 3.6× —
    /// with the drift still compressed so the helix reads, and bodies still drawn far
    /// oversized so they are visible at all.
    case trueDistances

    /// Everything at 1×. Correct, and almost entirely empty: every body falls below a
    /// pixel and the whole system flattens to a sliver.
    ///
    /// Not offered in the screensaver — it is a demonstration rather than something to
    /// look at, and it is reachable from the app with `--true-scale`.
    case trueScale

    /// What the camera should size itself to in this preset.
    private var framing: SolarSystemRenderer.Framing {
        switch self {
        case .stylised, .trueDistances, .birdsEye: return .wholeTrail
        case .trueScale: return .orbitalExtent
        }
    }

    /// Applies everything about this preset that lives on the renderer rather than in
    /// the scene config — framing and the camera — so the app, the screensaver and any
    /// script all get the same view for the same preset.
    public func apply(to renderer: SolarSystemRenderer) {
        renderer.framing = framing
        // Only the orrery touches the camera; the rest keep the renderer's defaults.
        guard case .birdsEye = self else { return }

        // Straight down the ecliptic pole: the plane the planets orbit in lies flat to
        // the camera, so the orbits read as the nested ellipses they are.
        //
        // `fixedDirection` alone is what stops the camera moving — `cameraDirection`
        // short-circuits on it before it ever consults `orbit.enabled`, so setting that
        // flag as well was a dead store implying the stillness depended on it.
        renderer.fixedDirection = GalacticFrame.eclipticPoleInGalactic
        renderer.orbit.rollDegrees = 0
        // ~2.4 px/s, so a star crosses the frame in about eleven minutes. Slower than the
        // drifting modes' ~6 px/s: alive without competing with the orbits.
        renderer.idleStarDriftFraction = 0.008
    }

    public var title: String {
        switch self {
        case .stylised: return "Balanced"
        case .birdsEye: return "Bird's eye"
        case .trueDistances: return "True distances"
        case .trueScale: return "True scale"
        }
    }

    /// One line, shown under the title in the screensaver's options. Kept short — it is
    /// a chooser, not documentation; the long-form reasoning lives in the README.
    public var blurb: String {
        switch self {
        case .stylised:
            return "The whole system at once, drifting through the galaxy."
        case .trueDistances:
            return "Real orbit spacing — Neptune 30× Earth, not 3.6×."
        case .birdsEye:
            return "Fixed view from above. No drift, so orbits close."
        case .trueScale:
            return "Everything at 1×. Almost nothing is visible."
        }
    }

    /// The scene configuration this preset implies.
    ///
    /// `trueDistances` needs its own body sizing: the scene is ~8× larger than the
    /// stylised one, so radii tuned for that scene would leave every planet sub-pixel.
    /// A flatter size exponent and a Sun scaled to the larger scene keep the ordering
    /// legible without the Sun swallowing Mercury's orbit.
    public func config(base: SceneConfig = SceneConfig()) -> SceneConfig {
        var c = base
        switch self {
        case .stylised:
            return c
        case .trueDistances:
            c.scale = .compressed(
                radialExponent: 1.0,
                driftUnitsPerYear: base.scale.driftUnitsPerYear
            )
            // Bounded by Mercury's perihelion, which is 0.3075 at this scale — the Sun's
            // disc must never reach the closest a planet actually comes to it.
            c.sunDisplayRadius = 0.28
            c.bodyRadiusExponent = 0.35
            c.minimumBodyRadius = 0.055
            return c
        case .birdsEye:
            // Drift zero is what makes this an orrery: with any drift at all the paths
            // are helices and never close. Distances stay compressed as in the default,
            // and each trail spans exactly one revolution so every planet shows one
            // complete ellipse rather than a partial arc.
            c.scale = .compressed(
                radialExponent: base.scale.radialExponent, driftUnitsPerYear: 0
            )
            c.trail = .orbits(1.0)
            // Dropping the drift shrinks the scene about sevenfold, and the Sun's radius
            // is absolute in scene units — left alone it would fill the inner system.
            c.sunDisplayRadius = base.sunDisplayRadius * 0.5
            return c
        case .trueScale:
            c.scale = .trueScale
            // A 70-year trail is 3,396 AU long against a ~60 AU frame, so framing the
            // orbits would leave a single streak crossing the picture with no shape to
            // it. Under a year of travel is comparable to the frame, which is what lets
            // the spatial arrangement read at all.
            c.trail = .years(0.8)
            return c
        }
    }
}
