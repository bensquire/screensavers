import Foundation

/// Everything the look is made of.
///
/// The WebGL original carried a forty-slider development panel over the top of
/// this, gated off in the shipping build. Only the shipped configuration is
/// here: the values below are that build's, which is `DEFAULTS` with the
/// `interstellar` preset and the screensaver's own deviations already folded in,
/// so there is one set of numbers rather than three layers to compose.
///
/// The handful a viewer can actually change lives in `GargantuaSettings`.
public struct SceneParameters: Equatable {

    // MARK: Disk geometry and emission

    /// Inner edge floor. The ISCO wins whenever it is larger.
    public var diskIn = 1.00
    public var diskOut = 25.0
    /// Half-thickness coefficient; h(r) = diskH * (r/diskIn)^1.15.
    public var diskH = 0.05
    /// Stress-free inner boundary exponent. 1 is the physical Shakura-Sunyaev
    /// value; lower is an artistic softening that keeps the rim too bright.
    public var innerEdge = 1.00
    /// Kelvin at the hottest annulus; the rest follows T ~ F^(1/4).
    public var diskTemp = 5800.0
    public var diskEmis = 34.0
    public var diskDens = 2.4
    /// Optical depth multiplier — the near side occludes the far side.
    public var absorb = 0.42
    public var turb = 1.0
    /// Multiplier on Keplerian shear.
    public var turbSpeed = 3.2
    /// Domain warp strength, which is what makes filaments rather than blobs.
    public var warp = 0.95
    public var noiseScale = 0.45
    /// Analytic, so it survives prefiltering and never aliases.
    public var spiral = 0.80

    /// Master motion rate. Gargantua's real ISCO period is about twelve hours,
    /// so any visible churn is artistic licence already; this is the dial for
    /// how much.
    public var pace = 1.00

    // MARK: Relativity

    /// Kerr a/M. Interstellar's Gargantua was rendered at 0.6.
    public var spin = 0.60
    /// Gravitational and orbital time dilation. Real physics, on.
    public var redshift = 1.00
    /// Doppler asymmetry — the part the film deliberately cut, because the
    /// bright-limb/dim-limb contrast broke the shot.
    public var beaming = 0.00
    /// 0 disables light bending entirely, and morphs continuously to flat space.
    public var lensing = 1.00
    public var spinDir = 1.00

    // MARK: Camera

    public var dist = 79.7
    public var fov = 34.0
    /// Degrees above the disk plane. The drift stays inside this.
    public var incl = 3.4
    /// 0 freezes the camera wander.
    public var drift = 1.4
    /// How far the aim point wanders off the hole.
    ///
    /// Zero for the screensaver: unattended on a wall, a composition that slowly
    /// slides off centre reads as an error rather than as life. The scene still
    /// breathes through inclination, distance and roll.
    public var aimDrift = 0.0

    // MARK: Sky

    /// The `interstellar` look is a measured match to Double Negative's render,
    /// whose sky genuinely is black — these are the screensaver's own addition,
    /// because a black sky takes away a motion channel. The disk is
    /// axisymmetric, so a whole revolution of azimuth reads as almost nothing
    /// with no starfield to stream past.
    public var stars = 0.110
    public var nebula = 0.0

    // MARK: Quality

    public var steps = 448.0
    /// Sample spacing through the disk, in half-thicknesses.
    public var diskStep = 1.0
    /// Empty-space stride, as a fraction of r.
    public var stepScale = 0.45
    /// Stride limit near the photon sphere.
    public var photonStep = 2.00
    /// Accumulation time constant, in seconds rather than frames.
    public var taaTau = 0.20
    /// Neighbourhood variance clipping width.
    public var clipK = 2.20

    // MARK: Post

    public var exposure = 1.45
    public var bloom = 0.20
    public var bloomThresh = 2.2
    /// Anamorphic streaks, off in the shipped look — the renderer skips the
    /// whole three-pass chain when this is zero.
    public var streak = 0.0
    public var chromaticAberration = 0.0
    public var vignette = 0.0
    public var grain = 0.0
    /// Off by default: it runs at render resolution, so under a heavy upscale it
    /// sharpens the low-res grid rather than the image.
    public var sharpen = 0.0

    public init() {}

    // MARK: - Derived

    /// Which way the gas goes. One rule, so the churn and the beaming cannot
    /// disagree about it.
    public var spinSign: Double { spinDir >= 0 ? 1 : -1 }

    /// Signed a/M as the shader sees it.
    public var signedSpin: Double {
        min(abs(spin), KerrGeometry.maxSpin) * spinSign
    }

    /// The disk's actual inner edge: the ISCO unless the parameter pushes it
    /// out. Everything needing to know where the disk starts asks here, so the
    /// hot spots cannot drift away from the geometry being rendered.
    public var diskInnerRadius: Double {
        max(diskIn, KerrGeometry.isco(spin: signedSpin))
    }

    public var diskOuterRadius: Double {
        max(diskOut, diskInnerRadius + 0.5)
    }

    /// Half-thickness at the outer edge. The camera's tilt floor is derived from
    /// this, so it has to be the same number the shader gets.
    public var diskHalfOuter: Double {
        diskH * pow(diskOuterRadius / diskInnerRadius, 1.15)
    }

    /// h(r) linearised through its endpoints: one multiply-add in the shader's
    /// inner loop instead of a pow, and visually indistinguishable.
    public var diskHalfCoefficients: (a: Double, b: Double, min: Double) {
        let inner = diskInnerRadius
        let a = (diskHalfOuter - diskH) / (diskOuterRadius - inner)
        return (a, diskH - a * inner, diskH * 0.25)
    }

    /// The rate of the rigid carrier the disk pattern turns at: Omega at the
    /// disk's mid radius. Everything beyond this is differential, and the
    /// differential part is what has to be given a finite memory.
    public var omegaReference: Double {
        1 / (pow(diskInnerRadius * diskOuterRadius, 0.75) + signedSpin)
    }

    /// How much winding the pattern may accumulate before it is reset, in churn
    /// units so it is independent of the churn rate.
    ///
    /// Set by where the shear would decorrelate one noise feature: the winding
    /// phase difference across a feature of size 1/noiseScale, at 1.5x the inner
    /// edge where the disk is both bright and shearing hard, reaches a full turn
    /// at this much winding.
    public var windPeriod: Double {
        let a = signedSpin
        let rc = diskInnerRadius * 1.5
        let dOmega = 1.5 * rc.squareRoot() / pow(rc * rc.squareRoot() + a, 2)
        return min(max(2 * .pi * noiseScale / max(dOmega, 1e-6), 40), 400)
    }
}
