//  Vortex.metal — every pass the tunnel is drawn with.
//
//  Five pipelines, in the order they run:
//
//    background  one full-screen pass: vignette, three parallax fog layers, stars
//    streak      the particle field as stretched quads, additive
//    sprite      glints and haze puffs as round points, additive
//    bolt        lightning ribbons, additive
//    post        chromatic aberration, hue drift, vignette; offscreen -> screen
//
//  The first four render into an offscreen texture at reduced resolution; `post`
//  is the only pass that touches the drawable.
//
//  `SceneUniforms` and `Particle` are declared identically in Swift. The buffers
//  are handed over as raw memory, so the two definitions must agree exactly —
//  `UniformLayoutTests` asks the GPU for its sizes and offsets and checks them
//  against Swift's rather than trusting that they still line up.

#include <metal_stdlib>
using namespace metal;

// MARK: - Shared types

struct Particle {
    float angle;
    float radius;
    float z0;
    float speed;
    float hue;
    float brightness;
    float swirl;
    float wobbleAmplitude;
    float wobbleFrequency;
    float wobblePhase;
    float twinklePhase;
    float kind;
};

// The float4 array leads so the 16-byte-aligned member sits at offset 0 and the
// rest packs without the compiler inserting padding Swift would have to guess at.
struct SceneUniforms {
    float4 shocks[4];          // (x, y, radius, intensity); intensity 0 means empty
    // The full drawable, in device pixels — not the size of whatever is being
    // rendered into. The scene passes project into this space and are then
    // rasterised into a smaller viewport, which is exactly what makes rendering
    // the scene at reduced internal resolution a one-line change.
    float2 resolution;
    float2 bendPixels;
    float2 vanishingPoint;
    float focal;
    float time;                // real clock, ms
    float particleTime;        // the particles' own clock, ms
    float tubeSpin;
    float zNear;
    float zFar;
    float tailMs;
    float streakScale;
    float spriteScale;
    float hueShift;
    float chromaticAberration;
};

struct BoltUniforms {
    float4 color;              // rgb, with intensity in a
};

// MARK: - Shared helpers

// Coldest to hottest. Selected by threshold rather than by index because `hue`
// arrives as a float attribute.
static inline float3 colorForHue(float h) {
    if (h < 0.5) return float3(0.157, 0.353, 0.706);
    if (h < 1.5) return float3(0.275, 0.588, 0.902);
    if (h < 2.5) return float3(0.510, 0.902, 0.961);
    return float3(0.902, 0.980, 1.000);
}

// GLSL's mod(), whose result takes the sign of y. C's fmod() truncates toward
// zero instead, which would let a wrapped z fall outside the tunnel.
static inline float glslMod(float x, float y) {
    return x - y * floor(x / y);
}

// How hard the shockwaves are hitting this point: a thin ring at each shock's
// current radius, broadening as it fades so the wave softens as it spreads.
static inline float shockKick(float2 pos, constant SceneUniforms &u) {
    float kick = 0.0;
    for (int i = 0; i < 4; i++) {
        float4 shock = u.shocks[i];
        if (shock.w <= 0.0) continue;
        float bandWidth = 28.0 + 80.0 * (1.0 - shock.w);
        float t = (distance(pos, shock.xy) - shock.z) / bandWidth;
        kick += exp(-t * t) * shock.w;
    }
    return clamp(kick, 0.0, 1.8);
}

// Where a particle is at clock `ts`, in target pixels, with y measured downward.
static inline float2 projectParticle(
    Particle p, constant SceneUniforms &u, float ts, thread float &zOut)
{
    float zRange = u.zFar - u.zNear;
    // Drift toward the eye, wrapping back to the far end. With GLSL mod
    // semantics the result is always within [zNear, zFar), so no extra guard.
    float z = u.zNear + glslMod(p.z0 - ts * p.speed - u.zNear, zRange);
    zOut = z;

    float angle = p.angle + p.swirl * ts + u.tubeSpin;
    float radius = p.radius + sin(ts * p.wobbleFrequency + p.wobblePhase) * p.wobbleAmplitude;
    // Bend grows with the square of depth, so the near end of the tunnel stays
    // put and only the far end swings.
    float depth = (z - u.zNear) / zRange;
    float2 bend = u.bendPixels * depth * depth;
    return u.resolution * 0.5 + bend + float2(cos(angle), sin(angle)) * radius * (u.focal / z);
}

// Fade in at the far end and out as a particle reaches the eye plane, plus a
// slow per-particle twinkle.
static inline float particleAlpha(Particle p, constant SceneUniforms &u, float z) {
    float farFade = clamp((u.zFar - z) / (u.zFar * 0.4), 0.0, 1.0);
    float nearFade = z < (u.zNear + 0.25) ? clamp((z - u.zNear) / 0.25, 0.0, 1.0) : 1.0;
    float twinkle = 0.78 + 0.22 * sin(u.particleTime * 0.004 + p.twinklePhase);
    return p.brightness * farFade * nearFade * twinkle;
}

// Pixels -> clip space. y is negated because the scene works top-left down while
// clip space runs bottom-up.
static inline float4 pixelToClip(float2 pixel, float2 resolution) {
    float2 clip = (pixel / resolution) * 2.0 - 1.0;
    return float4(clip.x, -clip.y, 0.0, 1.0);
}

// MARK: - Full-screen quad
//
// Four corners as a triangle strip, generated from the vertex id so no buffer is
// needed. `uv` runs bottom-up, matching GL's convention — see the note in
// post_fragment about why that is worth preserving rather than tidying away.

struct QuadOut {
    float4 position [[position]];
    float2 uv;
};

vertex QuadOut quad_vertex(uint vid [[vertex_id]]) {
    const float2 corners[4] = {
        float2(-1.0, -1.0), float2(1.0, -1.0), float2(-1.0, 1.0), float2(1.0, 1.0)
    };
    float2 corner = corners[vid];
    QuadOut out;
    out.position = float4(corner, 0.0, 1.0);
    out.uv = corner * 0.5 + 0.5;
    return out;
}

// MARK: - Streaks
//
// One instance per particle, four corners each: `vertex_id` arrives already
// mapped through a six-entry index buffer, so the (two-projection) vertex
// function runs four times per streak rather than six.

struct StreakOut {
    float4 position [[position]];
    float alpha;
    float3 color;
    float along;   // 0 at the tail, 1 at the head
    float side;    // -1 or +1 across the width
    float shock;
};

vertex StreakOut streak_vertex(
    uint corner [[vertex_id]],
    uint particleIndex [[instance_id]],
    const device Particle *particles [[buffer(0)]],
    constant SceneUniforms &u [[buffer(1)]])
{
    Particle p = particles[particleIndex];
    float along = float(corner >> 1);
    float side = float(corner & 1) * 2.0 - 1.0;

    // Project both ends of the trail so the quad can be laid along the direction
    // the particle is actually travelling on screen.
    float zHead, zTail;
    float2 head = projectParticle(p, u, u.particleTime, zHead);
    float2 tail = projectParticle(p, u, u.particleTime - u.tailMs, zTail);

    float2 position = mix(tail, head, along);
    float z = mix(zTail, zHead, along);

    float2 segment = head - tail;
    float segmentLength = length(segment);
    // Below half a pixel the direction is noise, so pick an arbitrary axis
    // rather than letting the quad spin.
    float2 direction = segmentLength > 0.5 ? segment / segmentLength : float2(1.0, 0.0);
    float2 perpendicular = float2(-direction.y, direction.x);

    float nearness = clamp(1.0 / (z * z + 0.15), 0.0, 8.0);
    float width = (0.9 + nearness * 1.3) * u.streakScale;
    float kick = shockKick(head, u);
    width *= 1.0 + kick * 1.2;
    position += perpendicular * side * width;

    StreakOut out;
    out.position = pixelToClip(position, u.resolution);
    out.alpha = particleAlpha(p, u, z);
    out.color = colorForHue(p.hue);
    out.along = along;
    out.side = side;
    out.shock = kick;
    return out;
}

fragment float4 streak_fragment(StreakOut in [[stage_in]]) {
    // Bright at the head, dim at the tail; bright along the spine, zero at the
    // edges. The exponent keeps the core tight so the streak stays a line.
    float widthFalloff = pow(1.0 - abs(in.side), 1.2);
    float alpha = in.alpha * (0.25 + 0.75 * in.along) * widthFalloff;
    alpha *= 1.0 + in.shock * 1.8;
    float3 color = mix(in.color, float3(0.85, 0.95, 1.0), clamp(in.shock * 0.6, 0.0, 0.8));
    return float4(color * alpha, alpha);
}

// MARK: - Sprites

struct SpriteOut {
    float4 position [[position]];
    float size [[point_size]];
    float alpha;
    float3 color;
    float kind;
    float shock;
};

vertex SpriteOut sprite_vertex(
    uint particleIndex [[vertex_id]],
    const device Particle *particles [[buffer(0)]],
    constant SceneUniforms &u [[buffer(1)]])
{
    Particle p = particles[particleIndex];
    float z;
    float2 position = projectParticle(p, u, u.particleTime, z);

    float nearness = clamp(1.0 / (z * z + 0.15), 0.0, 8.0);
    // Haze is much larger and much fainter than a glint; between them they cover
    // the gap between a point of light and the fog it sits in.
    float size = p.kind < 1.5 ? (8.0 + nearness * 28.0) : (20.0 + nearness * 90.0);
    float kick = shockKick(position, u);
    size *= 1.0 + kick * 0.9;

    SpriteOut out;
    out.position = pixelToClip(position, u.resolution);
    out.size = size * u.spriteScale;
    out.alpha = particleAlpha(p, u, z);
    out.color = colorForHue(p.hue);
    out.kind = p.kind;
    out.shock = kick;
    return out;
}

fragment float4 sprite_fragment(SpriteOut in [[stage_in]], float2 coord [[point_coord]]) {
    float2 uv = coord * 2.0 - 1.0;
    float d = length(uv);
    if (d > 1.0) discard_fragment();

    float alpha;
    float3 color;
    if (in.kind < 1.5) {
        // Glint: a hard white core inside a soft coloured halo.
        float core = pow(max(0.0, 1.0 - d * 3.0), 2.0);
        float halo = pow(1.0 - d, 2.8);
        alpha = (halo * 0.5 + core) * in.alpha;
        color = mix(in.color, float3(1.0), core);
    } else {
        alpha = pow(1.0 - d, 3.0) * in.alpha * 0.22;
        color = in.color * 0.9;
    }
    alpha *= 1.0 + in.shock * 1.5;
    color = mix(color, float3(0.9, 0.97, 1.0), clamp(in.shock * 0.5, 0.0, 0.7));
    return float4(color * alpha, alpha);
}

// MARK: - Lightning

vertex float4 bolt_vertex(
    uint vid [[vertex_id]],
    const device float2 *vertices [[buffer(0)]],
    constant SceneUniforms &u [[buffer(1)]])
{
    return pixelToClip(vertices[vid], u.resolution);
}

fragment float4 bolt_fragment(constant BoltUniforms &bolt [[buffer(0)]]) {
    return float4(bolt.color.rgb * bolt.color.a, bolt.color.a);
}

// MARK: - Background

static inline float hash21(float2 p) {
    p = fract(p * float2(123.34, 456.21));
    p += dot(p, p + 45.32);
    return fract(p.x * p.y);
}

static inline float valueNoise(float2 p) {
    float2 cell = floor(p);
    float2 f = fract(p);
    float a = hash21(cell);
    float b = hash21(cell + float2(1.0, 0.0));
    float c = hash21(cell + float2(0.0, 1.0));
    float d = hash21(cell + float2(1.0, 1.0));
    float2 t = f * f * (3.0 - 2.0 * f);
    return mix(mix(a, b, t.x), mix(c, d, t.x), t.y);
}

// Two octaves, with the low end crushed so the bands read as wisps rather than
// a solid sheet.
static inline float fogBand(float2 s, float scale) {
    float n = valueNoise(s * scale) + 0.5 * valueNoise(s * scale * 2.1 + 7.3);
    return smoothstep(0.35, 0.95, n * (1.0 / 1.5));
}

// The fog is sampled against an angle from atan2, which has a branch cut at ±π.
// The theta multipliers are non-integer so the noise does not wrap on its own;
// near the cut this cross-fades toward the other unwrapping of theta, which
// makes both sides meet at the same value. Away from the cut (w == 0) it is
// exactly fogBand.
static inline float fogBandWrapped(
    float theta, float thetaAlt, float w, float thetaMul, float xOffset, float y, float scale)
{
    float f = fogBand(float2(theta * thetaMul + xOffset, y), scale);
    if (w > 0.0) {
        f = mix(f, fogBand(float2(thetaAlt * thetaMul + xOffset, y), scale), w);
    }
    return f;
}

fragment float4 background_fragment(QuadOut in [[stage_in]], constant SceneUniforms &u [[buffer(0)]]) {
    float2 px = in.uv * u.resolution;
    float minDim = min(u.resolution.x, u.resolution.y);
    float2 fromVanishing = px - u.vanishingPoint;
    float d = length(fromVanishing) / minDim;
    float theta = atan2(fromVanishing.y, fromVanishing.x);

    // Undulate the silhouette: three counter-rotating waves around theta, at
    // frequencies with no common factor so the edge never looks periodic.
    float ripple =
        0.018 * sin(theta * 5.0 + u.time * 0.00055 + u.tubeSpin * 1.2) +
        0.012 * sin(theta * 9.0 - u.time * 0.00032 - u.tubeSpin * 0.7) +
        0.007 * sin(theta * 13.0 + u.time * 0.00078);
    // Applied at the outer wall only, so the dark pupil stays circular.
    float rippled = d + ripple * smoothstep(0.15, 0.6, d);

    float3 color = float3(0.012, 0.031, 0.086);
    float halo = smoothstep(0.85, 0.15, rippled) * smoothstep(0.0, 0.15, rippled);
    color += float3(0.098, 0.333, 0.706) * halo * 0.25;

    // Three fog layers read in (theta, log radius) space, which is what makes
    // them parallax like texture on a wall: near bands sweep past, far bands
    // barely move.
    float logRadius = log(max(d, 0.02));
    float seamBlend = smoothstep(M_PI_F - 0.35, M_PI_F, abs(theta)) * 0.5;
    float thetaAlt = theta - sign(theta) * 2.0 * M_PI_F;
    float near = fogBandWrapped(theta, thetaAlt, seamBlend, 1.2,
                                u.tubeSpin * 1.9 + u.time * 0.00020,
                                logRadius * 1.4 - u.time * 0.00018, 2.2);
    float mid = fogBandWrapped(theta, thetaAlt, seamBlend, 1.6,
                               -u.tubeSpin * 0.85 - u.time * 0.00013,
                               logRadius * 2.0 - u.time * 0.00010, 3.4);
    float far = fogBandWrapped(theta, thetaAlt, seamBlend, 2.1,
                               u.tubeSpin * 0.35 + u.time * 0.00006,
                               logRadius * 2.8 - u.time * 0.00005, 5.0);

    float wall = smoothstep(0.10, 0.35, rippled) * smoothstep(1.05, 0.55, rippled);
    color += (float3(0.18, 0.42, 0.85) * near * 0.22 +
              float3(0.12, 0.30, 0.70) * mid * 0.18 +
              float3(0.06, 0.18, 0.50) * far * 0.14) * wall;

    // Darken the throat. Uses the un-rippled distance so the pupil stays round.
    color = mix(color, float3(0.0, 0.008, 0.039), smoothstep(0.35, 0.0, d) * 0.92);

    // Stars, folded into this pass rather than costing a second full-screen one.
    float2 starSpace = fromVanishing;
    starSpace.x += u.time * 0.006;
    float2 cellUv = starSpace / (minDim * 0.05);
    float2 cell = floor(cellUv);
    float occupied = hash21(cell);
    if (occupied >= 0.75) {          // roughly a quarter of cells hold a star
        float2 local = fract(cellUv) - 0.5;
        float jitterX = hash21(cell + 17.0);
        float jitterY = hash21(cell + 31.0);
        float sd = length(local - (float2(jitterX, jitterY) - 0.5) * 0.6);
        float brightness =
            (smoothstep(0.04, 0.0, sd) + smoothstep(0.25, 0.0, sd) * 0.35) *
            (0.6 + 0.4 * sin(u.time * 0.003 + occupied * 60.0));
        float3 tint = mix(float3(0.82, 0.95, 1.0), float3(0.55, 0.85, 1.0), jitterX);
        // Anchored to the screen centre, not the vanishing point, so leaning the
        // tunnel to one side does not strand a field of stars on the other.
        float fromCentre = length(px - u.resolution * 0.5) / minDim;
        float mask = (0.55 + 0.45 * smoothstep(0.0, 0.25, fromCentre)) *
                     mix(0.35, 1.0, smoothstep(0.05, 0.35, d));
        color += tint * brightness * mask;
    }

    return float4(color, 1.0);
}

// MARK: - Post

// Rotate hue through YIQ, which costs two matrix multiplies and keeps luminance
// untouched — cheaper and steadier than a round trip through HSV.
static inline float3 shiftHue(float3 c, float radians) {
    const float3x3 toYIQ = float3x3(float3(0.299, 0.596, 0.211),
                                    float3(0.587, -0.274, -0.523),
                                    float3(0.114, -0.322, 0.312));
    const float3x3 toRGB = float3x3(float3(1.0, 1.0, 1.0),
                                    float3(0.9563, -0.2721, -1.1070),
                                    float3(0.6210, -0.6474, 1.7046));
    float3 yiq = toYIQ * c;
    float cs = cos(radians), sn = sin(radians);
    yiq.yz = float2x2(float2(cs, -sn), float2(sn, cs)) * yiq.yz;
    return toRGB * yiq;
}

fragment float4 post_fragment(
    QuadOut in [[stage_in]],
    texture2d<float> scene [[texture(0)]],
    sampler sceneSampler [[sampler(0)]],
    constant SceneUniforms &u [[buffer(0)]])
{
    // `in.uv` runs bottom-up, so sampling needs it flipped. Both forms are kept:
    // the pixel coordinate below is deliberately the bottom-up one, because that
    // is what the original computed, and it means the aberration radiates from
    // the vanishing point mirrored about the horizontal midline rather than from
    // the vanishing point itself. That is not what the original intended, but it
    // is what it has always looked like, so it is preserved on purpose.
    float2 sampleUV = float2(in.uv.x, 1.0 - in.uv.y);
    float2 px = in.uv * u.resolution;

    float2 direction = (px - u.vanishingPoint) / max(u.resolution.x, u.resolution.y);
    float fromVanishing = length(direction);
    // Aberration grows toward the edges, the way a real lens does.
    float magnitude = u.chromaticAberration * (0.4 + 2.0 * fromVanishing);
    float2 offset = normalize(direction + 1e-6) * magnitude / u.resolution;
    float2 sampleOffset = float2(offset.x, -offset.y);

    float3 color = float3(
        scene.sample(sceneSampler, sampleUV + sampleOffset).r,
        scene.sample(sceneSampler, sampleUV).g,
        scene.sample(sceneSampler, sampleUV - sampleOffset).b);

    color = shiftHue(color, u.hueShift);
    color += float3(0.06, 0.25, 0.35) * (1.0 - smoothstep(0.1, 0.9, fromVanishing)) * 0.08;
    color *= 1.0 - smoothstep(0.45, 1.1, fromVanishing) * 0.55;
    return float4(color, 1.0);
}

// MARK: - Layout probe
//
// Reports what the compiler decided the shared structs look like, so a test can
// check Swift's view against the GPU's instead of assuming they still agree.

kernel void uniform_layout_probe(
    device uint *out [[buffer(0)]],
    const device SceneUniforms *ref [[buffer(1)]])
{
    const device char *base = (const device char *)ref;
    out[0] = (uint)sizeof(SceneUniforms);
    out[1] = (uint)sizeof(Particle);
    out[2] = (uint)((const device char *)&ref->resolution - base);
    out[3] = (uint)((const device char *)&ref->focal - base);
    out[4] = (uint)((const device char *)&ref->chromaticAberration - base);
}
