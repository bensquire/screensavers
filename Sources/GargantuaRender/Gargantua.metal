//  Gargantua.metal — a spinning (Kerr) black hole, ray-traced per pixel.
//
//  Light paths are real null geodesics, integrated backwards from the camera in
//  Cartesian Kerr-Schild coordinates. The horizon, the photon ring, the Einstein
//  ring, the frame-dragged offset of the shadow and the disk arcing over and
//  under it are not drawn — they fall out of the integration.
//
//  Six passes:
//
//    march    the geodesic integration, at render scale, into an HDR buffer
//    taa      reproject the previous frame and accumulate into it
//    bright   threshold for bloom
//    down/up  the bloom pyramid
//    streak   optional anamorphic smear
//    post     tone map, grade and composite to the screen
//
//  A note on fragment coordinates. GL measures gl_FragCoord.y upward from the
//  bottom; Metal's [[position]] measures it downward from the top. Every
//  formula here was derived against the former, so `glPixel` converts once at
//  the top of each entry point and the rest is unchanged — which is safer than
//  re-deriving a dozen sign conventions. Texture sampling is the exception: all
//  the render targets are written by Metal, so they are sampled with Metal's own
//  convention, and `screenToUV` is the one place the two meet.

#include <metal_stdlib>
using namespace metal;

constant int MAX_STEPS = 1024;   // hard loop bound; `steps` is the runtime cap
constant int SPOT_COUNT = 3;
constant float3 LUMA = float3(0.2126, 0.7152, 0.0722);

static inline float luma(float3 c) { return dot(c, LUMA); }

// MARK: - Uniforms
//
// Field order and type are shared with Swift, which hands these over as raw
// memory. `UniformLayoutTests` asks the compiler for its own sizes and offsets
// rather than trusting that the two declarations still agree.

struct MarchUniforms {
    float4 spots[SPOT_COUNT];    // radius, cos(angle), sin(angle), strength
    float4 spotsB[SPOT_COUNT];   // arc width, 1 / radial width, unused, unused
    float3 camPos;
    float3 camRight;
    float3 camUp;
    float3 camFwd;
    float3 wind;                 // differential winding: phase A, phase B, blend
    float2 resolution;
    float2 jitter;
    float scale;                 // 2 * tan(fovY / 2)
    float rigid;                 // rigid carrier angle, folded to one turn
    float omegaRef;              // Omega at the disk's mid radius
    float noiseTexels;
    float steps;
    float diskIn;
    float diskOut;
    float innerEdge;
    float hA;                    // linearised half-thickness: h(r) = hA * r + hB
    float hB;
    float hMin;
    float diskStep;
    float stepScale;
    float photonStep;
    float photonR;
    float tempNorm;
    float diskTemp;
    float frameSeq;              // golden-ratio walk over the frame index
    float diskEmis;
    float diskDens;
    float absorb;
    float turb;
    float warp;
    float noiseScale;
    float spiral;
    float redshift;
    float beaming;
    float dir;
    float lens;
    float spin;
    float horizon;
    float stars;
    float nebula;
    float flare;
};

struct AccumulateUniforms {
    float3 camPos;
    float3 camRight;
    float3 camUp;
    float3 camFwd;
    float3 prevPos;
    float3 prevRight;
    float3 prevUp;
    float3 prevFwd;
    float2 resolution;
    float scale;
    float alpha;
    float clipK;
    float valid;
    float sharpen;
};

struct BrightUniforms {
    float2 texel;
    float threshold;
    float exposure;
};

struct BlurUniforms {
    float2 sourceTexel;
    float2 destinationTexel;
};

struct StreakUniforms {
    float2 texel;
    float stride;
};

struct PostUniforms {
    float2 resolution;
    float exposure;
    float bloom;
    float streak;
    float chromaticAberration;
    float vignette;
    float grain;
    float frame;
};

// MARK: - Shared helpers

// GL's gl_FragCoord from Metal's [[position]]: y measured up from the bottom.
static inline float2 glPixel(float4 position, float2 resolution) {
    return float2(position.x, resolution.y - position.y);
}

// Aspect-correct screen coordinates: origin at frame centre, one unit per frame
// height. Every pass that reasons about screen position uses this, so none of
// them can disagree about where a pixel is.
static inline float2 screenN(float2 pixel, float2 resolution) {
    return (pixel - 0.5 * resolution) / resolution.y;
}

// The inverse, landing in Metal texture coordinates — the one place the two
// vertical conventions have to be reconciled.
static inline float2 screenToUV(float2 n, float2 resolution) {
    float2 glUV = (n * resolution.y + 0.5 * resolution) / resolution;
    return float2(glUV.x, 1.0 - glUV.y);
}

static inline float3 rayDirection(
    float2 pixel, float2 resolution, float3 right, float3 up, float3 fwd, float scale)
{
    float2 n = screenN(pixel, resolution);
    return normalize(fwd + right * (n.x * scale) + up * (n.y * scale));
}

static inline float3 hash33(float3 p) {
    p = fract(p * float3(0.1031, 0.1030, 0.0973));
    p += dot(p, p.yxz + 33.33);
    return fract((p.xxy + p.yxx) * p.zyx);
}

// Chromaticity of a Planck radiator at K kelvin, via Tanner Helland's fit to the
// blackbody locus. Returns a normalised hue — brightness comes from the
// emissivity, not from here.
//
// Doing this properly rather than with a hand-tuned ramp buys one real thing:
// Doppler and gravitational shift become blackbody(T * g), because blueshifted
// gas looks white for the same reason genuinely hotter gas does.
static inline float3 blackbody(float kelvin) {
    float t = clamp(kelvin, 1000.0, 40000.0) * 0.01;
    float3 c;
    if (t <= 66.0) {
        c.r = 1.0;
        c.g = 0.3900815788 * log(t) - 0.6318414438;
    } else {
        c.r = 1.2929361860 * pow(t - 60.0, -0.1332047592);
        c.g = 1.1298908610 * pow(t - 60.0, -0.0755148492);
    }
    c.b = t >= 66.0 ? 1.0
        : t <= 19.0 ? 0.0
        : 0.5432067891 * log(t - 10.0) - 1.1962540891;
    return clamp(c, 0.0, 1.0);
}

// MARK: - Full-screen triangle
//
// One triangle rather than two, built from the vertex id, so there is no vertex
// buffer and no seam down the diagonal.

struct FullscreenOut {
    float4 position [[position]];
};

vertex FullscreenOut fullscreen_vertex(uint vid [[vertex_id]]) {
    float2 p = float2(float((vid << 1) & 2), float(vid & 2));
    FullscreenOut out;
    out.position = float4(p * 2.0 - 1.0, 0.0, 1.0);
    return out;
}

// MARK: - The disk

constant float IN_FADE = 0.90;   // where the disk fades in, as a fraction of diskIn

static inline float diskHalf(float r, constant MarchUniforms &u) {
    return max(u.hA * r + u.hB, u.hMin);
}

// Prograde circular orbit in Kerr; collapses to r^-3/2 when the hole is still.
static inline float omegaK(float r, float spin) {
    return 1.0 / (r * sqrt(r) + spin);
}

// Explicit LOD everywhere: the march has divergent control flow, so implicit
// derivatives — and therefore implicit mip selection — are undefined inside it.
//
// Two fetches, not four: the first one's spare channels drive the domain warp
// the second is sampled through. The LOD prefilters the field to the actual
// sample spacing, because one stochastic sample per step through a thin slab
// cannot resolve detail finer than the step, and asking it to just converts that
// detail into speckle.
static inline float fbmWarped(
    float3 p, float lod, texture3d<float> noise, sampler noiseSampler, constant MarchUniforms &u)
{
    float4 a = noise.sample(noiseSampler, p * 0.5, level(max(lod - 1.6, 0.0)));
    float3 q = p * 1.9 + (a.gba - 0.5) * u.warp;
    float b = noise.sample(noiseSampler, q, level(clamp(lod + 0.45, 0.0, 5.0))).g;
    return (a.r * 0.60 + b * 0.40) * 1.06;
}

// One layer of the co-rotating pattern: turbulent noise plus analytic spiral
// arms, both sampled at a given winding angle. Split out because the winding is
// cross-faded between two phases, so this runs once or twice.
static inline float diskPattern(
    float3 p, float invR, float lr, float th, float lod,
    texture3d<float> noise, sampler noiseSampler, constant MarchUniforms &u)
{
    float ct = cos(th), st = sin(th);
    float2 rot = float2(p.x * ct + p.z * st, p.z * ct - p.x * st);
    float n = fbmWarped(float3(rot.x, p.y * 2.6, rot.y) * u.noiseScale, lod, noise, noiseSampler, u);

    // Loose logarithmic spiral density waves, via double-angle on the rotated
    // vector so this stays free of atan. Two arm counts at different winding
    // rates, so the pattern shears into itself instead of reading as a rigid
    // pinwheel — and being analytic, it neither aliases nor gets blurred out by
    // the prefiltering that has to tame the noise octaves.
    if (u.spiral > 0.0) {
        float c1 = rot.x * invR, s1 = rot.y * invR;
        float c2 = c1 * c1 - s1 * s1, s2 = 2.0 * c1 * s1;
        float c3 = c2 * c1 - s2 * s1, s3 = s2 * c1 + c2 * s1;
        float sL = sin(lr), cL = cos(lr);
        float sL2 = 2.0 * sL * cL, cL2 = cL * cL - sL * sL;
        float sp = 0.5 + 0.5 * (sL * c2 - cL * s2);
        float sp3 = 0.5 + 0.5 * (sL2 * c3 - cL2 * s3);
        n = mix(n, n * (0.34 + 1.05 * sp * (0.55 + 0.60 * sp3)), u.spiral);
    }
    return n;
}

// Emission (rgb) and density (a) at a point.
//
// `r` is the Boyer-Lindquist radius, passed in rather than derived from p: with
// spin, surfaces of constant BL r are oblate spheroids, so the cylindrical
// radius of the sample point is not the radius the disk is defined on. The
// ISCO, the emissivity profile and the orbital rate are all functions of BL r.
static inline float4 sampleDisk(
    float3 p, float r, float seg, float lz,
    texture3d<float> noise, sampler noiseSampler, constant MarchUniforms &u)
{
    if (r < u.diskIn * IN_FADE || r > u.diskOut) return float4(0.0);
    float invR = 1.0 / max(r, 1.0e-4);

    float h = diskHalf(r, u);
    float vy = p.y / h;
    if (abs(vy) > 2.4) return float4(0.0);

    // Everything analytic first, so the fringe of the slab never pays for a
    // texture fetch.
    float vert = exp(-vy * vy * 1.25);
    float outFade = smoothstep(u.diskOut, u.diskOut * 0.70, r);
    float inFade = smoothstep(u.diskIn * IN_FADE, u.diskIn * 1.04, r);
    float base = vert * outFade * inFade;
    if (base < 0.0025) return float4(0.0);

    // Co-rotating sample frame, reached by rotating the point rather than taking
    // its angle: Omega ~ r^-3/2, so radii wind at different rates and the noise
    // shears into trailing filaments on its own.
    float uOmega = u.dir * omegaK(r, u.spin);

    // The pattern needs a finite memory. Winding neighbouring radii apart
    // forever destroys the disk: the shear grows without bound, and after a few
    // minutes the pattern is wound finer than a pixel, so the prefilter averages
    // it into smooth axisymmetric rings and every trace of turbulence drains
    // out. So the winding is split into a rigid carrier (folded to one turn on
    // the CPU) plus a differential term running as a sawtooth of unit slope. The
    // instantaneous rate at every radius is still exactly Omega(r); only the
    // accumulated history is discarded, under a cross-fade with a second copy
    // half a cycle out of phase, so the reset is never visible.
    float dOm = uOmega * u.dir - u.omegaRef;
    float lr = log2(r) * 4.5;
    float lod = clamp(log2(max(seg, 1.0e-3) * u.noiseScale * u.noiseTexels), 0.0, 5.0);
    float b = u.wind.z;
    float n;
    if (b < 0.002) {
        n = diskPattern(p, invR, lr, u.rigid + u.wind.x * dOm, lod, noise, noiseSampler, u);
    } else if (b > 0.998) {
        n = diskPattern(p, invR, lr, u.rigid + u.wind.y * dOm, lod, noise, noiseSampler, u);
    } else {
        float n0 = diskPattern(p, invR, lr, u.rigid + u.wind.x * dOm, lod, noise, noiseSampler, u);
        float n1 = diskPattern(p, invR, lr, u.rigid + u.wind.y * dOm, lod, noise, noiseSampler, u);
        // Two decorrelated fields averaged have root-two less contrast than
        // either, so a plain cross-fade would pulse the turbulence down and back
        // every cycle. Rescaling about the mean holds the contrast flat.
        n = 0.5 + (mix(n0, n1, b) - 0.5) * rsqrt(b * b + (1.0 - b) * (1.0 - b));
    }

    // Thin-disk emissivity: r^-3 with a stress-free inner boundary. innerEdge is
    // the exponent on that term — 1.0 is the physical Shakura-Sunyaev value.
    float rin = u.diskIn * invR;
    float edge = pow(clamp(1.0 - sqrt(rin), 0.0, 1.0), u.innerEdge);
    float radial = rin * rin * rin * edge;

    float turb = mix(1.0, n * n * 2.30, u.turb);
    float dens = u.diskDens * base * mix(0.30, 1.35, n);

    // g = E_observed / E_emitted for a circular equatorial orbit in Kerr, split
    // into the two effects it bundles:
    //   1/u^t             gravitational redshift plus the gas's own time
    //                     dilation. Symmetric, and always physically present.
    //   1/(1 - Omega*lam) the Doppler factor. Direction-dependent, and the sole
    //                     source of the bright-limb/dim-limb asymmetry Double
    //                     Negative dropped because it broke the shot.
    float g = 1.0;
    if (u.redshift > 0.0 || u.beaming > 0.0) {
        float r15 = r * sqrt(r);
        float invUt = sqrt(max(0.0, r * r * r - 3.0 * r * r + 2.0 * u.spin * r15))
            / max(r15 + u.spin, 1.0e-4);
        float gDopp = 1.0 / max(0.10, 1.0 - uOmega * lz);
        g = mix(1.0, invUt, u.redshift * u.lens) * mix(1.0, gDopp, u.beaming * u.lens);
    }

    // Stefan-Boltzmann: T ~ flux^(1/4). tempNorm is 1/peakFlux^(1/4), so the
    // hottest annulus sits at diskTemp kelvin and everything outside it cools
    // down the Planck locus on its own. Shifting T by g is the whole of the
    // redshift treatment: approaching gas whitens because it looks hotter.
    float T = u.diskTemp * clamp(sqrt(sqrt(radial)) * u.tempNorm, 0.0, 1.0);
    float3 bb = blackbody(T * g);
    float3 emi = bb * (u.diskEmis * u.flare * radial * base * turb);

    // Orbiting hot spots, sheared into a trailing arc as they age.
    for (int i = 0; i < SPOT_COUNT; i++) {
        float4 s = u.spots[i];
        if (s.w <= 0.0) continue;
        float2 sb = u.spotsB[i].xy;
        // Radially thin — this is gas at one orbital radius. Tested first
        // because it needs nothing but r, and most samples in the slab sit
        // outside any given spot's narrow annulus.
        float dr = (r - s.x) * sb.y;
        if (dr * dr > 9.0) continue;                   // 3 sigma; exp(-9) = 1.2e-4
        float cd = (p.x * s.y + p.z * s.z) * invR;     // cos(delta angle)
        float sd = (p.z * s.y - p.x * s.z) * invR;     // sin(delta angle)
        // The true angle, not the chord: 2(1-cos) saturates on the far side of
        // the disk and cannot express an arc longer than about 90 degrees, which
        // read as a diffuse ball rather than gas sheared along its orbit.
        float da = atan2(sd, cd);
        // Long trailing arc, sharp leading edge — differential rotation drags
        // the clump out behind itself. Blended rather than branched: a hard
        // switch on the sign tears a straight-edged wedge across the disk.
        float lead = smoothstep(-0.25, 0.25, da * u.dir);
        float w = mix(sb.x, sb.x * 0.30, lead);
        float e = exp(-dr * dr) * exp(-(da / w) * (da / w)) * vert;
        // A shade hotter than the surrounding gas, reached by leaning the
        // sample's own colour toward white rather than evaluating Planck again.
        emi += e * s.w * mix(bb, float3(1.0), 0.28) * u.diskEmis;
    }

    // Specific intensity scales as g^4 for a thermal source, and the hot spots
    // are the same gas, so the boost belongs here rather than at the call site.
    float g2 = g * g;
    return float4(emi * g2 * g2, dens);
}

// MARK: - Sky

static inline float2 cubeUV(float3 d, thread float &face) {
    float3 a = abs(d);
    if (a.x >= a.y && a.x >= a.z) { face = d.x > 0.0 ? 0.0 : 1.0; return float2(d.z, d.y) / a.x; }
    if (a.y >= a.z) { face = d.y > 0.0 ? 2.0 : 3.0; return float2(d.x, d.z) / a.y; }
    face = d.z > 0.0 ? 4.0 : 5.0;
    return float2(d.x, d.y) / a.z;
}

// `spread` is the on-screen angular footprint of this pixel. Near the photon
// ring it explodes, which is exactly right: the sky is compressed into an
// infinitely thin annulus there, so stars must smear and dim rather than alias
// into fireflies.
static inline float3 starLayer(float3 d, float dens, float spread, float seed, float gain) {
    float face;
    float2 uv = cubeUV(d, face) * dens;
    float2 cell = floor(uv), f = fract(uv);
    float3 h = hash33(float3(cell + seed, face * 17.0 + seed));
    if (h.z > 0.34) return float3(0.0);

    float2 sp = 0.25 + 0.5 * h.xy;
    float dist = length(f - sp) / dens;
    float base = 0.0022;
    float rad = max(base, spread * 0.85);
    float g = exp(-(dist * dist) / (rad * rad));
    float mag = pow(fract(h.x * 91.7 + h.y * 13.1), 5.0);
    float flux = (base * base) / (rad * rad);          // conserve flux as it blurs
    return blackbody(2600.0 + fract(h.y * 37.3) * 13400.0) * (g * flux * mag * gain);
}

static inline float3 sky(
    float3 d, float spread,
    texture3d<float> noise, sampler noiseSampler, constant MarchUniforms &u)
{
    float3 col = float3(0.0);

    if (u.nebula > 0.0) {
        // Dust band, mip-selected by the local magnification.
        float lod = clamp(log2(max(spread, 1e-5) * 240.0) + 2.0, 0.0, 5.0);
        float4 na = noise.sample(noiseSampler, d * 1.14, level(lod));
        float nb = na.r * 0.62
            + noise.sample(noiseSampler, d * 3.9 + na.gba * 0.4, level(lod)).g * 0.38;
        float3 gN = normalize(float3(0.32, 0.88, -0.35));
        float bd = dot(d, gN) * 2.6;
        float band = exp(-bd * bd);
        float3 nebC = mix(float3(0.055, 0.075, 0.16), float3(0.16, 0.10, 0.075), nb);
        col += nebC * band * smoothstep(0.35, 0.95, nb) * u.nebula * 0.55;
        col += float3(0.020, 0.028, 0.055) * band * nb * u.nebula;
    }

    col += starLayer(d, 34.0, spread, 0.0, 1.00) * u.stars;
    col += starLayer(d, 95.0, spread, 11.3, 0.45) * u.stars;
    return col;
}

// MARK: - Geodesics: Kerr, Cartesian Kerr-Schild
//
// Boyer-Lindquist is singular on the rotation axis: dphi/dsigma carries a
// lambda/sin^2(theta) that diverges there, and no amount of step refinement
// fixes it because the defect is in the chart, not the integration. Cartesian
// Kerr-Schild has no such singularity anywhere outside the ring.
//
//     g_uv = eta_uv + f k_u k_v,  k_t = 1,  f = 2 M r^3 / (r^4 + a^2 z^2)
//     k    = ( (rx + ay)/(r^2+a^2), (ry - ax)/(r^2+a^2), z/r )
//
// with r fixed by r^4 - (rho^2 - a^2) r^2 - a^2 z^2 = 0. With the conserved
// energy normalised to 1 and S = 1 + k.p the Hamiltonian is 2H = -1 + |p|^2 - f
// S^2, giving
//
//     dx/dl = p - f S k,   dp_i/dl = 1/2 [ (df/dx_i) S^2 + 2 f S (dk_j/dx_i) p_j ]
//
// No turning points, no sign bookkeeping, no constraint projection: RK4 holds
// the null condition and L_z to ~1e-6 on its own. f is the entire deviation from
// flat space, so scaling it by `lens` is an exact interpolation to Minkowski.

// The scene's spin axis is +Y; Kerr-Schild's is +Z. Swapping those two axes is
// an involution, so one swizzle serves both directions — written once here so
// the convention has a single home and a typo cannot re-orient the spacetime.
static inline float3 toKS(float3 v) { return v.xzy; }
static inline float3 fromKS(float3 v) { return v.xzy; }

static inline float ksRadius(float3 X, float spin) {
    float a2 = spin * spin;
    float rho2 = dot(X, X);
    float t = rho2 - a2;
    float D = sqrt(max(t * t + 4.0 * a2 * X.z * X.z, 0.0));
    return sqrt(max(0.5 * (t + D), 1.0e-10));
}

static inline void ksField(
    float3 X, constant MarchUniforms &u,
    thread float &f, thread float3 &k, thread float3 &df, thread float3x3 &dk,
    thread float &rOut)
{
    float a = u.spin, a2 = a * a;
    float rho2 = dot(X, X);
    float r = ksRadius(X, a);
    rOut = r;
    float r2 = r * r;
    float D = 2.0 * r2 - rho2 + a2;            // == sqrt((rho^2-a^2)^2 + 4a^2z^2)
    D = abs(D) < 1.0e-7 ? 1.0e-7 : D;
    float3 dr = float3(X.x * r / D, X.y * r / D, X.z * (r2 + a2) / (r * D));

    float W = r2 * r2 + a2 * X.z * X.z;
    f = 2.0 * r2 * r / W * u.lens;             // lens = 0 -> exactly Minkowski
    float3 dW = 4.0 * r2 * r * dr + float3(0.0, 0.0, 2.0 * a2 * X.z);
    df = (6.0 * r2 * dr * u.lens - f * dW) / W;

    float T = r2 + a2, T2 = T * T;
    float n0 = r * X.x + a * X.y, n1 = r * X.y - a * X.x;
    k = float3(n0 / T, n1 / T, X.z / r);

    // dk[i] holds d(k_x,k_y,k_z)/dx_i, so dk[i][j] = dk_j/dx_i.
    float dT;
    dT = 2.0 * r * dr.x;
    dk[0] = float3(((dr.x * X.x + r) * T - n0 * dT) / T2,
                   ((dr.x * X.y - a) * T - n1 * dT) / T2,
                   (-X.z * dr.x) / r2);
    dT = 2.0 * r * dr.y;
    dk[1] = float3(((dr.y * X.x + a) * T - n0 * dT) / T2,
                   ((dr.y * X.y + r) * T - n1 * dT) / T2,
                   (-X.z * dr.y) / r2);
    dT = 2.0 * r * dr.z;
    dk[2] = float3(((dr.z * X.x) * T - n0 * dT) / T2,
                   ((dr.z * X.y) * T - n1 * dT) / T2,
                   (r - X.z * dr.z) / r2);
}

// f and k without the derivatives, for the places that only need the metric.
static inline void ksFK(float3 X, constant MarchUniforms &u, thread float &f, thread float3 &k) {
    float a = u.spin, a2 = a * a;
    float r = ksRadius(X, a), r2 = r * r;
    f = 2.0 * r2 * r / max(r2 * r2 + a2 * X.z * X.z, 1.0e-9) * u.lens;
    k = float3((r * X.x + a * X.y) / (r2 + a2), (r * X.y - a * X.x) / (r2 + a2), X.z / r);
}

static inline void ksRhs(
    float3 X, float3 P, constant MarchUniforms &u,
    thread float3 &dX, thread float3 &dP,
    thread float &f, thread float3 &k, thread float &r)
{
    float3 df;
    float3x3 dk;
    ksField(X, u, f, k, df, dk, r);
    float S = 1.0 + dot(k, P);
    dX = P - (f * S) * k;
    dP = 0.5 * (df * (S * S)
        + (2.0 * f * S) * float3(dot(dk[0], P), dot(dk[1], P), dot(dk[2], P)));
}

static inline void ksRhs(
    float3 X, float3 P, constant MarchUniforms &u, thread float3 &dX, thread float3 &dP)
{
    float f, r;
    float3 k;
    ksRhs(X, P, u, dX, dP, f, k, r);
}

// Initial momentum for a static observer looking along n. The spatial metric is
// gamma = I + [f/(1-f)] k k^T — a rank-one update of the identity — so the
// observer's orthonormal frame is just a rescale along k, with no Gram-Schmidt
// and no arbitrary choice of basis orientation. Solving the null condition at
// fixed energy then gives the momentum in closed form.
static inline float3 ksLaunch(float3 X, float3 n, constant MarchUniforms &u) {
    float f;
    float3 k;
    ksFK(X, u, f, k);
    float K2 = max(dot(k, k), 1.0e-12);
    float3 kh = k * rsqrt(K2);
    float sc = rsqrt(max(1.0 + (f / max(1.0 - f, 1.0e-4)) * K2, 1.0e-6));
    float3 V = n + kh * (dot(n, kh) * (sc - 1.0));
    float kV = dot(k, V);
    float B = f * kV, G = f - 1.0;
    float A = dot(V, V) + f * kV * kV;
    float sN = rsqrt(max(B * B - A * G, 1.0e-12));
    float pt = (-1.0 - B * sN) / G;
    return (f * pt) * k + sN * (V + (f * kV) * k);
}

// MARK: - March

fragment float4 march_fragment(
    FullscreenOut in [[stage_in]],
    constant MarchUniforms &u [[buffer(0)]],
    texture3d<float> noise [[texture(0)]],
    sampler noiseSampler [[sampler(0)]])
{
    float2 px = glPixel(in.position, u.resolution);
    float3 rd = rayDirection(px + u.jitter, u.resolution, u.camRight, u.camUp, u.camFwd, u.scale);

    float3 acc = float3(0.0);
    float trans = 1.0;
    // Luminance-weighted mean disparity of everything this ray picked up, for
    // the accumulation buffer's reprojection.
    float dispSum = 0.0, wSum = 0.0;
    float3 dirEsc = float3(0.0);
    bool escaped = false;

    float3 X = toKS(u.camPos);                 // into the spin-along-Z frame
    float3 P = ksLaunch(X, toKS(rd), u);

    float r0 = length(u.camPos);
    float rEsc = max(4.0 * r0, 80.0);
    float rHor = u.horizon * 1.004;

    // Per-pixel stochastic sample offset, decorrelated across pixels by the hash
    // and stratified across frames by the golden-ratio sequence in frameSeq.
    float jit = fract(hash33(float3(px, 1.0)).x + u.frameSeq);

    for (int i = 0; i < MAX_STEPS; i++) {
        if (float(i) >= u.steps) break;

        float f0, r;
        float3 k0;
        float3 dX1, dP1;
        ksRhs(X, P, u, dX1, dP1, f0, k0, r);
        float spd = length(dX1) + 1.0e-9;

        // Adaptive step: coarse in empty space, tight through the disk slab and
        // anywhere near the photon sphere where the path curls hardest.
        float ds = clamp(u.stepScale * r, 0.06, 60.0);
        float3 pw = fromKS(X);                 // back to scene axes for the slab test
        if (r > u.diskIn * 0.70 && r < u.diskOut * 1.20) {
            float hh = diskHalf(r, u);
            float slab = hh * 2.6;
            float inSlab = max(hh * u.diskStep, 0.045);
            ds = min(ds, abs(pw.y) < slab ? inSlab : max(0.30 * (abs(pw.y) - slab), inSlab));
        }
        ds = min(ds, (0.12 + 0.45 * abs(r - u.photonR)) * u.photonStep);
        float h = clamp(ds / spd, 1.0e-6, 60.0);

        float3 dX2, dP2;
        ksRhs(X + 0.5 * h * dX1, P + 0.5 * h * dP1, u, dX2, dP2);
        float3 dX3, dP3;
        ksRhs(X + 0.5 * h * dX2, P + 0.5 * h * dP2, u, dX3, dP3);
        float3 dX4, dP4;
        ksRhs(X + h * dX3, P + h * dP3, u, dX4, dP4);

        float3 Xn = X + h * (dX1 + 2.0 * dX2 + 2.0 * dX3 + dX4) / 6.0;
        float3 Pn = P + h * (dP1 + 2.0 * dP2 + 2.0 * dP3 + dP4) / 6.0;

        float rn = ksRadius(Xn, u.spin);
        float3 nw = fromKS(Xn);

        float t01 = fract(jit + float(i) * 0.6180339887);
        float rmid = mix(r, rn, t01);

        // Gate on the annulus before paying for anything: seg needs a sqrt and
        // lam a cross product, and for a ray that never crosses the disk's
        // radial band both would be computed only to be thrown away.
        if (rmid > u.diskIn * IN_FADE && rmid < u.diskOut) {
            // Proper length of the step, from the static observer's spatial
            // metric. The straight chord understates it near the hole — where
            // the disk is brightest — and that error would feed into both
            // emission and optical depth.
            float3 dseg = Xn - X;
            float kdot = dot(k0, dseg);
            float seg = sqrt(max(
                dot(dseg, dseg) + (f0 / max(1.0 - f0, 1.0e-4)) * kdot * kdot, 0.0));
            float3 mid = mix(pw, nw, t01);
            float lam = cross(X, P).z;         // L_z / E, conserved

            float4 sD = sampleDisk(mid, rmid, seg, lam, noise, noiseSampler, u);
            if (sD.a > 0.0 || dot(sD.rgb, sD.rgb) > 0.0) {
                float3 contrib = trans * sD.rgb * seg;
                acc += contrib;
                float w = luma(contrib);
                if (w > 0.0) {
                    dispSum += w / max(length(mid - u.camPos), 0.5);
                    wSum += w;
                }
                trans *= exp(-sD.a * seg * u.absorb);
                if (trans < 0.004) break;
            }
        }

        X = Xn;
        P = Pn;

        if (rn < rHor) break;                  // through the horizon
        if (rn > rEsc && dot(Xn, dX4) > 0.0) {
            dirEsc = normalize(fromKS(dX4));
            escaped = true;
            break;
        }
    }

    // Derivatives are taken here, after control flow has reconverged.
    float spread = max(length(dfdx(dirEsc)), length(dfdy(dirEsc)));
    spread = clamp(spread, 1.0e-5, 1.5);

    float3 col = acc;
    if (escaped) col += trans * sky(dirEsc, spread, noise, noiseSampler, u);

    // Sky sits at effectively infinite distance, so it contributes no disparity
    // and a sky-only pixel falls through to the far value — which makes the same
    // reprojection formula correct for both stars and gas.
    float depth = wSum > 0.0 ? wSum / max(dispSum, 1.0e-8) : 1.0e5;
    return float4(max(col, 0.0), min(depth, 1.0e5));
}

// MARK: - Temporal accumulation

static inline float3 tonemapForBlend(float3 c) {
    return c / (1.0 + max(max(c.r, c.g), c.b));
}
static inline float3 untonemapForBlend(float3 c) {
    return c / max(1.0e-4, 1.0 - max(max(c.r, c.g), c.b));
}

fragment float4 accumulate_fragment(
    FullscreenOut in [[stage_in]],
    constant AccumulateUniforms &u [[buffer(0)]],
    texture2d<float> current [[texture(0)]],
    texture2d<float> history [[texture(1)]],
    sampler linearSampler [[sampler(0)]])
{
    float2 px = glPixel(in.position, u.resolution);
    float2 uv = in.position.xy / u.resolution;
    float4 currentSample = current.sample(linearSampler, uv);
    float3 cur = currentSample.rgb;

    // Reconstruct where this pixel's light came from and re-project that world
    // point through the previous camera — position included. Rotation alone is
    // not enough once the camera orbits: the disk is only tens of M away, so the
    // parallax across one frame is several pixels and shows up as smeared trails.
    float3 rd = rayDirection(px, u.resolution, u.camRight, u.camUp, u.camFwd, u.scale);
    float3 rel = (u.camPos - u.prevPos) + rd * currentSample.a;
    float3 c = float3(dot(rel, u.prevRight), dot(rel, u.prevUp), dot(rel, u.prevFwd));

    // The 3x3 neighbourhood is needed for variance clipping anyway, so the
    // unsharp mask that recovers detail lost to upscaling rides along for free
    // here at render resolution instead of costing nine taps at native.
    float3 m1 = float3(0.0), m2 = float3(0.0);
    for (int y = -1; y <= 1; y++) {
        for (int x = -1; x <= 1; x++) {
            float3 s = tonemapForBlend(
                current.sample(linearSampler, uv + float2(float(x), float(y)) / u.resolution).rgb);
            m1 += s;
            m2 += s * s;
        }
    }
    m1 /= 9.0;
    m2 /= 9.0;

    float3 outc = cur;
    if (c.z > 1.0e-4 && u.valid > 0.5) {
        float2 pn = c.xy / (c.z * u.scale);
        float2 puv = screenToUV(pn, u.resolution);
        if (all(puv >= 0.0) && all(puv <= 1.0)) {
            float3 sd = sqrt(max(m2 - m1 * m1, float3(0.0)));
            float3 hs = clamp(
                tonemapForBlend(history.sample(linearSampler, puv).rgb),
                m1 - sd * u.clipK, m1 + sd * u.clipK);
            outc = untonemapForBlend(mix(hs, tonemapForBlend(cur), u.alpha));
        }
    }

    if (u.sharpen > 0.0) {
        // Scale linear radiance by bounded local contrast, measured in the
        // compressed space so the disk's huge dynamic range cannot detonate it.
        // Asymmetric on purpose: symmetric unsharp masking digs a dark halo
        // around an isolated star, and at a 3x upscale that halo reads as a
        // donut. Allow it to crispen highlights, barely to dig.
        float lc = luma(tonemapForBlend(outc)), lm = luma(m1);
        outc *= clamp(1.0 + u.sharpen * (lc - lm) / max(lc, 1.0e-3), 0.94, 1.7);
    }
    return float4(max(outc, 0.0), 1.0);
}

// MARK: - Bloom chain

fragment float4 bright_fragment(
    FullscreenOut in [[stage_in]],
    constant BrightUniforms &u [[buffer(0)]],
    texture2d<float> source [[texture(0)]],
    sampler linearSampler [[sampler(0)]])
{
    float2 uv = in.position.xy * u.texel;
    float3 c = source.sample(linearSampler, uv).rgb * u.exposure;
    float l = luma(c);
    float k = max(0.0, l - u.threshold);
    return float4(c * (k / max(l, 1.0e-4)), 1.0);
}

fragment float4 downsample_fragment(
    FullscreenOut in [[stage_in]],
    constant BlurUniforms &u [[buffer(0)]],
    texture2d<float> source [[texture(0)]],
    sampler linearSampler [[sampler(0)]])
{
    float2 uv = in.position.xy * u.destinationTexel;
    float2 t = u.sourceTexel;
    float3 s = source.sample(linearSampler, uv + t * float2(-1.0, -1.0)).rgb
        + source.sample(linearSampler, uv + t * float2(1.0, -1.0)).rgb
        + source.sample(linearSampler, uv + t * float2(-1.0, 1.0)).rgb
        + source.sample(linearSampler, uv + t * float2(1.0, 1.0)).rgb;
    float3 m = source.sample(linearSampler, uv).rgb * 4.0
        + source.sample(linearSampler, uv + t * float2(-2.0, 0.0)).rgb
        + source.sample(linearSampler, uv + t * float2(2.0, 0.0)).rgb
        + source.sample(linearSampler, uv + t * float2(0.0, -2.0)).rgb
        + source.sample(linearSampler, uv + t * float2(0.0, 2.0)).rgb;
    return float4(s * 0.125 + m * 0.0625, 1.0);
}

fragment float4 upsample_fragment(
    FullscreenOut in [[stage_in]],
    constant BlurUniforms &u [[buffer(0)]],
    texture2d<float> source [[texture(0)]],
    sampler linearSampler [[sampler(0)]])
{
    float2 uv = in.position.xy * u.destinationTexel;
    float2 t = u.sourceTexel;
    float3 c = source.sample(linearSampler, uv + t * float2(-1.0, -1.0)).rgb
        + source.sample(linearSampler, uv + t * float2(0.0, -1.0)).rgb * 2.0
        + source.sample(linearSampler, uv + t * float2(1.0, -1.0)).rgb
        + source.sample(linearSampler, uv + t * float2(-1.0, 0.0)).rgb * 2.0
        + source.sample(linearSampler, uv).rgb * 4.0
        + source.sample(linearSampler, uv + t * float2(1.0, 0.0)).rgb * 2.0
        + source.sample(linearSampler, uv + t * float2(-1.0, 1.0)).rgb
        + source.sample(linearSampler, uv + t * float2(0.0, 1.0)).rgb * 2.0
        + source.sample(linearSampler, uv + t * float2(1.0, 1.0)).rgb;
    return float4(c / 16.0, 1.0);
}

fragment float4 streak_fragment(
    FullscreenOut in [[stage_in]],
    constant StreakUniforms &u [[buffer(0)]],
    texture2d<float> source [[texture(0)]],
    sampler linearSampler [[sampler(0)]])
{
    float2 uv = in.position.xy * u.texel;
    float3 c = float3(0.0);
    float wsum = 0.0;
    for (int i = -6; i <= 6; i++) {
        float fi = float(i);
        float w = exp(-fi * fi * 0.09);
        c += source.sample(linearSampler, uv + float2(fi * u.stride * u.texel.x, 0.0)).rgb * w;
        wsum += w;
    }
    return float4(c / wsum, 1.0);
}

// MARK: - Composite

static inline float3 aces(float3 x) {
    return clamp((x * (2.51 * x + 0.03)) / (x * (2.43 * x + 0.59) + 0.14), 0.0, 1.0);
}

static inline float hash12(float2 p) {
    float3 p3 = fract(float3(p.x, p.y, p.x) * 0.1031);
    p3 += dot(p3, p3.yzx + 33.33);
    return fract((p3.x + p3.y) * p3.z);
}

fragment float4 post_fragment(
    FullscreenOut in [[stage_in]],
    constant PostUniforms &u [[buffer(0)]],
    texture2d<float> scene [[texture(0)]],
    texture2d<float> bloom [[texture(1)]],
    texture2d<float> streak [[texture(2)]],
    sampler linearSampler [[sampler(0)]])
{
    float2 uv = in.position.xy / u.resolution;
    float2 cen = uv - 0.5;
    float k = u.chromaticAberration * dot(cen, cen) * 4.0;

    float3 c;
    c.r = scene.sample(linearSampler, uv - cen * k).r;
    c.g = scene.sample(linearSampler, uv).g;
    c.b = scene.sample(linearSampler, uv + cen * k).b;

    c *= u.exposure;
    c = max(c, 0.0);
    c += bloom.sample(linearSampler, uv).rgb * u.bloom;
    // Branching on a constant-buffer value is uniform across the pass, so this
    // is free — and it saves a full-resolution fetch per pixel on every look
    // that does not use streaks, which is the shipped one.
    if (u.streak > 0.0) {
        c += streak.sample(linearSampler, uv).rgb * u.streak * float3(0.85, 0.92, 1.25);
    }

    c = aces(c);

    float v = 1.0 - u.vignette * dot(cen, cen) * 2.2;
    c *= clamp(v, 0.0, 1.0);

    c = pow(c, float3(1.0 / 2.2));

    float2 px = in.position.xy;
    c += (hash12(px + u.frame * 17.13) - 0.5) * u.grain;
    c += (hash12(px * 1.7 + u.frame) - 0.5) / 255.0;   // dither
    return float4(c, 1.0);
}

// MARK: - Layout probe
//
// Reports what the compiler decided the shared structs look like, so a test can
// check Swift's view against the GPU's instead of assuming they still agree.

kernel void uniform_layout_probe(
    device uint *out [[buffer(0)]],
    const device MarchUniforms *march [[buffer(1)]],
    const device AccumulateUniforms *accumulate [[buffer(2)]])
{
    const device char *m = (const device char *)march;
    const device char *a = (const device char *)accumulate;
    out[0] = (uint)sizeof(MarchUniforms);
    out[1] = (uint)sizeof(AccumulateUniforms);
    out[2] = (uint)((const device char *)&march->camPos - m);
    out[3] = (uint)((const device char *)&march->resolution - m);
    out[4] = (uint)((const device char *)&march->flare - m);
    out[5] = (uint)((const device char *)&accumulate->resolution - a);
    out[6] = (uint)((const device char *)&accumulate->sharpen - a);
    out[7] = (uint)sizeof(PostUniforms);
}
