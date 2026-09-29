#language slang 2026
// retro-crt.slang -- a multi-pass CRT monitor for kitty custom shaders.
//
// One file, several passes. retro-crt.pipeline runs it once per group with a
// different STAGE:
//
//   0  afterglow: max(new frame, decayed previous frame)             -> a
//   1  store that image in `persist` for the next frame              -> persist
//   2  bloom: 4x4 box downsample to 1/4 resolution                   -> b   (R_B0)
//   3  bloom: horizontal gaussian at 1/4 resolution                  -> a   (R_A0)
//   4  bloom: vertical gaussian at 1/4 resolution  ("glow")          -> b   (R_B1)
//   5  bloom: 4x4 box downsample of the glow to 1/16 resolution      -> a   (R_A1)
//   6  bloom: horizontal gaussian at 1/16 resolution                 -> b   (R_B2)
//   7  bloom: vertical gaussian at 1/16 resolution  ("halo")         -> a   (R_A2)
//   8  composite: curvature, hsync, chroma, scanlines, mask, bloom, tint,
//      noise, flicker, vignette, glass and bezel                     -> screen
//   9  tab-change glitch (event driven)                              -> screen
//
// The R_* rectangles below are viewport-UV regions of the shared `a`/`b`
// textures and MUST match the viewport_pos/viewport_size lines in
// retro-crt.pipeline.
//
// Every monitor lives in this one file and is chosen at run time, so switching
// never rebuilds the shader. Which monitor to show is read from kitty's
// `background` colour, which is what the `set_colors` action, `kitten @ set-colors`
// and the `crt` command change: an offset from black that nobody can see (blue =
// monitor number, red bit 0 = flat) and that this shader subtracts again.
//
// Static or live: kitty only redraws when something changes, so the afterglow
// (which needs a frame every ~16 ms while a trail fades) is compiled out unless
// crt-live.pipeline is loaded; it sets LIVE = 1 and adds a group that keeps
// kitty redrawing at 60 fps. Without it the monitor costs nothing while idle.
//
// All colours reaching this shader are linear RGB. Additive grading (noise,
// ambient light, vignette) is done in display (sRGB) space because that is
// where the numbers below are perceptually meaningful.

import kitty_custom_shader_types;

static const int STAGE = 0;                               // internal: which pass this group runs
static const int DEBUG_VIEW = 0;                          // 1 = phosphor image, 2 = glow, 3 = halo
static const int LIVE = 0;                                // 1 = afterglow enabled; only valid when something redraws every frame (crt-live.pipeline)

// ===========================================================================
// Monitors
// ===========================================================================

static const int NUM_MONITORS = 5;                        // amber green white ice color

struct Look {
    float3 phosphor;            // linear RGB of the phosphor at full intensity
    float tint;                 // 0 = keep terminal colours, 1 = monochrome phosphor
    float saturation;           // colour saturation when tint < 1
    float mono_value;           // tint: how much saturated colours keep their brightness (0 = pure luma)
    float3 persistence;         // afterglow decay time constant per channel, seconds
    float bloom_glow;           // tight glow around bright text
    float bloom_halo;           // wide halation across the glass
    float bloom_threshold;      // only light above this level blooms
    float softness;             // horizontal beam softness, pixels
    float chroma;               // RGB convergence error growing towards the edges, pixels
    float chroma_base;          // constant red/blue horizontal offset, pixels
    float scanlines;            // 0 = off, 1 = gaps fully black
    float scanline_pitch;       // scanline spacing, physical pixels
    float scanline_gap_power;   // higher = thinner dark gaps
    float scanline_beam_bloom;  // how much bright pixels fill the gaps (0..1)
    float mask;                 // aperture grille strength (0 for monochrome tubes)
    float mask_pitch;           // RGB triad width, physical pixels
    float curvature;            // barrel distortion, fraction of half-height at the corners
    float corner_radius;        // rounded glass corners, pixels
    float bezel_px;             // plastic frame width, pixels (hides that much of the window edge)
    float3 bezel_color;         // linear RGB
    float bezel_spill;          // how much screen light spills onto the frame
    float flicker;              // global brightness shimmer
    float noise;                // static snow amplitude
    float noise_size;           // snow grain size, pixels
    float jitter;               // whole-picture shake, pixels
    float hsync;                // per-line horizontal wobble, pixels
    float hum;                  // slow rolling brightness bar
    float gain;                 // brightness compensation for scanline / mask losses
    float ambient;              // glass never goes fully black (display space)
    float vignette;             // darkening towards the corners
    float glass_shine;          // soft reflection of the room on the glass
};

// Amber phosphor: the default, and the starting point of every other monitor.
Look
amber_look() {
    Look l;
    l.phosphor = float3(1.0, 0.44, 0.0);
    l.tint = 1.0;
    l.saturation = 1.0;
    l.mono_value = 0.55;
    l.persistence = float3(0.07);
    l.bloom_glow = 0.50;
    l.bloom_halo = 0.15;
    l.bloom_threshold = 0.0;
    l.softness = 0.45;
    l.chroma = 0.0;
    l.chroma_base = 0.0;
    l.scanlines = 0.55;
    l.scanline_pitch = 3.0;
    l.scanline_gap_power = 1.4;
    l.scanline_beam_bloom = 0.55;
    l.mask = 0.0;
    l.mask_pitch = 3.0;
    l.curvature = 0.06;
    l.corner_radius = 34.0;
    l.bezel_px = 10.0;
    l.bezel_color = float3(0.010, 0.009, 0.008);
    l.bezel_spill = 0.6;
    l.flicker = 0.02;
    l.noise = 0.035;
    l.noise_size = 1.5;
    l.jitter = 0.0;
    l.hsync = 0.3;
    l.hum = 0.03;
    l.gain = 1.3;
    l.ambient = 0.012;
    l.vignette = 0.35;
    l.glass_shine = 0.018;
    return l;
}

// The monitor table. Add a monitor by adding a case here and raising NUM_MONITORS.
Look
monitor_look(int monitor, bool flat) {
    Look l = amber_look();
    switch (monitor) {
    case 1: // green phosphor terminal with a long afterglow (P1/P31 style)
        l.phosphor = float3(0.03, 1.0, 0.07);
        l.persistence = float3(0.16);
        l.bloom_glow = 0.55;
        l.scanlines = 0.6;
        l.noise = 0.04;
        l.bezel_color = float3(0.008, 0.009, 0.008);
        break;
    case 2: // paper-white monochrome (P4 style)
        l.phosphor = float3(0.85, 0.95, 1.0);
        l.persistence = float3(0.05);
        l.scanlines = 0.45;
        l.bloom_glow = 0.4;
        l.mono_value = 0.4;
        break;
    case 3: // cold cyan phosphor, heavy bloom, a little convergence error
        l.phosphor = float3(0.10, 0.70, 1.0);
        l.persistence = float3(0.12);
        l.bloom_glow = 0.75;
        l.bloom_halo = 0.25;
        l.chroma = 0.8;
        l.curvature = 0.08;
        break;
    case 4: // full colour: aperture grille, RGB convergence error, softer beam
        l.tint = 0.0;
        l.mask = 0.30;
        l.chroma = 1.6;
        l.scanlines = 0.6;
        l.softness = 0.55;
        l.bloom_glow = 0.4;
        l.bloom_halo = 0.12;
        l.persistence = float3(0.04);
        break;
    default: // 0: amber
        break;
    }
    if (flat) { // no curvature, bezel, corner rounding or wobble: mouse selection lines up exactly
        l.curvature = 0.0;
        l.bezel_px = 0.0;
        l.corner_radius = 0.0;
        l.hsync = 0.0;
        l.jitter = 0.0;
        l.vignette = 0.2;
    }
    return l;
}

struct Control {
    int monitor;
    bool flat;
    float3 crush;               // the offset the code adds to the background, to be subtracted from the picture
};

// The monitor is carried by kitty's `background` colour as an offset from black:
// blue = monitor number, red bit 0 = flat. Anything that is not such a code (a
// theme with a real background colour) selects the default monitor.
Control
read_control(KittyCustomShaderData d) {
    float3 s = linear_to_srgb(d.background.rgb) * 255.0;
    int3 c = int3(floor(s + 0.5));
    bool valid = all(c <= int3(15));
    Control ctl;
    ctl.monitor = (valid && c.z < NUM_MONITORS) ? c.z : 0;
    ctl.flat = valid && ((c.x & 1) != 0);
    ctl.crush = valid ? d.background.rgb : float3(0.0);
    return ctl;
}

// ===========================================================================
// Shared regions of the a/b textures used by the bloom chain (viewport UV).
// ===========================================================================
static const float4 R_B0 = float4(0.0, 0.0, 0.25, 0.25);
static const float4 R_A0 = float4(0.0, 0.0, 0.25, 0.25);
static const float4 R_B1 = float4(0.25, 0.0, 0.25, 0.25);
static const float4 R_A1 = float4(0.0, 0.25, 0.0625, 0.0625);
static const float4 R_B2 = float4(0.5, 0.0, 0.0625, 0.0625);
static const float4 R_A2 = float4(0.0, 0.375, 0.0625, 0.0625);

static const float3 LUMA = float3(0.2126, 0.7152, 0.0722);
static const float TAU = 6.2831853;

// ===========================================================================
// Helpers
// ===========================================================================

float
hash11(float p) {
    p = frac(p * 0.1031);
    p *= p + 33.33;
    p *= p + p;
    return frac(p);
}

float
hash12(float2 p) {
    float3 p3 = frac(float3(p.x, p.y, p.x) * 0.1031);
    p3 += dot(p3, float3(p3.y, p3.z, p3.x) + 33.33);
    return frac((p3.x + p3.y) * p3.z);
}

// smooth 1-D value noise in [0, 1]
float
vnoise(float x) {
    float i = floor(x);
    float f = frac(x);
    f = f * f * (3.0 - 2.0 * f);
    return lerp(hash11(i), hash11(i + 1.0), f);
}

float3
srgb_to_linear(float3 c) {
    float3 lo = c / 12.92;
    float3 hi = pow((c + 0.055) / 1.055, float3(2.4));
    return lerp(lo, hi, step(float3(0.04045), c));
}

float3
linear_to_srgb(float3 c) {
    float3 lo = c * 12.92;
    float3 hi = 1.055 * pow(c, float3(1.0 / 2.4)) - 0.055;
    return lerp(lo, hi, step(float3(0.0031308), c));
}

// Signed distance to a rounded box centred on the origin with half extents b.
float
sd_round_box(float2 p, float2 b, float r) {
    float2 q = abs(p) - b + float2(r);
    return length(max(q, float2(0.0))) + min(max(q.x, q.y), 0.0) - r;
}

// Gentle highlight roll-off: linear up to 0.75, then asymptotic to 1.0.
float3
soft_clip(float3 x) {
    float3 over = max(x - 0.75, float3(0.0));
    return min(x, float3(0.75)) + 0.25 * (1.0 - exp(-over * 4.0));
}

// Map terminal colours onto the phosphor.
float3
tint_map(float3 c, Look L) {
    float luma = dot(c, LUMA);
    float l = lerp(luma, max(c.r, max(c.g, c.b)), L.mono_value);
    float3 sat = lerp(float3(luma), c, L.saturation);
    return lerp(sat, L.phosphor * l, L.tint);
}

// The picture as the phosphor holds it (the current frame plus its afterglow, as stage 1
// stored it), without the offset the monitor code adds to the background.
float3
image_at(KittyTextures t, KittyCustomShaderData d, Look L, float3 crush, float2 uv) {
    return max(t.persist.Sample(uv).rgb - crush, float3(0.0));
}

// The integer pixel rectangle (x, y, width, height) kitty draws a group's viewport
// region into: it truncates both corners, so the width is not region.z * vp.x.
float4
region_pixels(float4 region, float2 vp) {
    float2 p0 = floor(region.xy * vp);
    float2 p1 = floor((region.xy + region.zw) * vp);
    return float4(p0, max(p1 - p0, float2(1.0)));
}

// Sample a region of a shared texture. uv is local to the region, [0, 1], and maps
// onto the region's whole pixel rectangle, exactly as the group that wrote it drew it.
// Clamping to pixel centres keeps bilinear filtering from reading outside the region,
// where the texture holds stale or uninitialised data.
float3
sample_region(KittyTexture tex, float4 region, float2 uv, float2 vp) {
    float4 r = region_pixels(region, vp);
    float2 pos = clamp(r.xy + uv * r.zw, r.xy + 0.5, r.xy + r.zw - 0.5);
    return tex.Sample(pos / vp).rgb;
}

// 13 tap gaussian along `axis` (unit vector) inside a region.
float3
blur_region(KittyTexture tex, float4 region, float2 uv, float2 vp, float2 axis, float sigma) {
    float2 texel = 1.0 / region_pixels(region, vp).zw;
    float3 sum = float3(0.0);
    float wsum = 0.0;
    [ForceUnroll]
    for (int i = -6; i <= 6; i++) {
        float w = exp(-0.5 * float(i * i) / (sigma * sigma));
        sum += w * sample_region(tex, region, uv + axis * texel * float(i), vp);
        wsum += w;
    }
    return sum / wsum;
}

// 4x4 box downsample of a region (four bilinear taps, one texel apart).
float3
box4_region(KittyTexture tex, float4 region, float2 uv, float2 vp) {
    float2 texel = 1.0 / region_pixels(region, vp).zw;
    float3 s = sample_region(tex, region, uv + texel * float2(-1.0, -1.0), vp);
    s += sample_region(tex, region, uv + texel * float2(1.0, -1.0), vp);
    s += sample_region(tex, region, uv + texel * float2(-1.0, 1.0), vp);
    s += sample_region(tex, region, uv + texel * float2(1.0, 1.0), vp);
    return 0.25 * s;
}

// ===========================================================================
// Stages 0-7: afterglow and the bloom chain
// ===========================================================================

float4
stage_accumulate(float4 color, KittyTextures t, KittyCustomShaderData d, Look L) {
    float3 acc = color.rgb;
    if (LIVE == 1 && any(L.persistence > 0.0)) {
        float dt = clamp(d.timestamp - d.last_rendered_at, 0.0, 0.5);
        float3 decay = exp(-dt / max(L.persistence, float3(1e-4)));
        acc = max(acc, t.persist.Sample(t.pos).rgb * decay);
    }
    return float4(acc, 1.0);
}

float4
stage_store(KittyTextures t) {
    return float4(t.a.Sample(t.pos).rgb, 1.0);
}

float4
stage_downsample_full(KittyTextures t, KittyCustomShaderData d, Look L, float3 crush) {
    float2 px = 1.0 / float2(d.viewport_size_pixels);
    float3 s = image_at(t, d, L, crush, t.pos + px * float2(-1.0, -1.0));
    s += image_at(t, d, L, crush, t.pos + px * float2(1.0, -1.0));
    s += image_at(t, d, L, crush, t.pos + px * float2(-1.0, 1.0));
    s += image_at(t, d, L, crush, t.pos + px * float2(1.0, 1.0));
    return float4(max(0.25 * s - L.bloom_threshold, float3(0.0)), 1.0);
}

// ===========================================================================
// Stage 8: composite
// ===========================================================================

float4
stage_composite(KittyTextures t, KittyCustomShaderData d, Look L, float3 crush) {
    const float2 vp = float2(d.viewport_size_pixels);
    const float2 P = t.pos * vp;                          // pixel position, origin bottom-left
    const float T = fmod(d.timestamp, 3600.0);
    const float F = float(d.frame_counter % 65536u);
    const float yn = P.y / vp.y;

    // ---- glass opening and curvature ---------------------------------------
    const float2 C = 0.5 * vp;
    const float2 H = max(C - float2(L.bezel_px), float2(16.0));
    const float2 rel = P - C;
    const float dglass = sd_round_box(rel, H, min(L.corner_radius, min(H.x, H.y)));
    const float glass = 1.0 - smoothstep(-0.75, 0.75, dglass);

    float2 q = rel / H;                                   // -1..1 across the glass
    float2 K = L.curvature * float2(H.y / H.x, 1.0);      // equal bowing in pixels on both axes
    float2 src = C + q * (1.0 + K * float2(q.y * q.y, q.x * q.x)) * H;

    // ---- horizontal sync wobble and jitter ------------------------------------
    float bd = (yn - frac(T * 0.11)) / 0.035;
    float band = exp(-bd * bd);
    float wob = (vnoise(yn * 30.0 + T * 2.0) - 0.5) * 2.0;
    float tear = (hash11(floor(P.y * 0.5) + F) - 0.5) * band * 6.0;
    float2 jit = 2.0 * L.jitter * float2(hash11(F * 1.37) - 0.5, hash11(F * 2.11 + 7.0) - 0.5);
    src += float2(L.hsync * (wob + tear), 0.0) + jit;

    float2 uv = src / vp;

    if (DEBUG_VIEW == 1) return float4(image_at(t, d, L, crush, uv), 1.0);
    if (DEBUG_VIEW == 2) return float4(sample_region(t.b, R_B1, uv, vp), 1.0);
    if (DEBUG_VIEW == 3) return float4(sample_region(t.a, R_A2, uv, vp), 1.0);

    // ---- the beam: softness and chromatic error ------------------------------------
    float2 hx = float2(L.softness / vp.x, 0.0);
    float3 col;
    if (L.chroma == 0.0 && L.chroma_base == 0.0) {
        col = 0.5 * image_at(t, d, L, crush, uv)
            + 0.25 * (image_at(t, d, L, crush, uv - hx) + image_at(t, d, L, crush, uv + hx));
    } else {
        float2 cs = q * L.chroma + float2(L.chroma_base, 0.0);
        float2 uvR = (src - cs) / vp;
        float2 uvB = (src + cs) / vp;
        col.r = 0.5 * image_at(t, d, L, crush, uvR).r
              + 0.25 * (image_at(t, d, L, crush, uvR - hx).r + image_at(t, d, L, crush, uvR + hx).r);
        col.g = 0.5 * image_at(t, d, L, crush, uv).g
              + 0.25 * (image_at(t, d, L, crush, uv - hx).g + image_at(t, d, L, crush, uv + hx).g);
        col.b = 0.5 * image_at(t, d, L, crush, uvB).b
              + 0.25 * (image_at(t, d, L, crush, uvB - hx).b + image_at(t, d, L, crush, uvB + hx).b);
    }

    col = tint_map(col, L);
    float peak = max(col.r, max(col.g, col.b));

    // ---- scanlines and aperture grille ------------------------------------------------
    float gap = pow(0.5 - 0.5 * cos(TAU * P.y / L.scanline_pitch), L.scanline_gap_power);
    col *= 1.0 - L.scanlines * gap * (1.0 - L.scanline_beam_bloom * saturate(peak));
    if (L.mask > 0.0) {
        float3 w = 0.5 + 0.5 * cos(TAU * (frac(P.x / L.mask_pitch) - float3(0.16667, 0.5, 0.83333)));
        col *= lerp(float3(1.0), 2.0 * w, L.mask);
    }

    // ---- bloom ---------------------------------------------------------------------------
    float3 glow = sample_region(t.b, R_B1, uv, vp);
    float3 halo = sample_region(t.a, R_A2, uv, vp);
    float3 lin = soft_clip(col * L.gain + tint_map(glow, L) * L.bloom_glow + tint_map(halo, L) * L.bloom_halo);

    // ---- display space grading ------------------------------------------------------------
    float3 g = linear_to_srgb(lin);
    float3 ink = lerp(float3(1.0), L.phosphor / max(L.phosphor.r, max(L.phosphor.g, L.phosphor.b)), L.tint);

    g *= 1.0 + L.flicker * (0.6 * (hash11(F) - 0.5) * 2.0 + 0.4 * sin(TAU * 0.9 * T));
    g *= 1.0 - L.hum * (0.5 + 0.5 * sin(TAU * (yn * 1.3 - T * 0.08)));

    float snow = hash12(floor(P / L.noise_size) + float2(F * 1.7, F * 0.31));
    g += ink * (L.ambient + L.noise * (snow - 0.5));

    g *= 1.0 - L.vignette * pow(saturate(0.5 * dot(q, q)), 1.2);
    float2 e = (q - float2(-0.45, 0.6)) / float2(0.9, 0.5);
    g += L.glass_shine * exp(-dot(e, e));

    float3 screen = srgb_to_linear(saturate(g));

    // ---- plastic bezel ---------------------------------------------------------------------
    float outside = max(dglass, 0.0);
    float2 nearest = clamp(P, C - H, C + H) / vp;
    float3 spill = sample_region(t.a, R_A2, nearest, vp);
    float3 frame = L.bezel_color * (0.55 + 0.9 * yn) * (0.5 + 0.5 * smoothstep(0.0, 14.0, outside));
    frame += L.bezel_color * 3.0 * exp(-outside / 1.5);
    frame += tint_map(spill, L) * L.bezel_spill * exp(-outside / 12.0);

    return float4(lerp(frame, screen, glass), 1.0);
}

// ===========================================================================
// Stage 9: tab-change glitch. Runs only while its animation is active, after
// the composite, and distorts the finished picture.
// ===========================================================================

float4
stage_tab_glitch(float4 color, KittyTextures t, KittyCustomShaderData d, Look L) {
    float p = t.animation_progress;                       // 0 -> 1
    float k = (1.0 - p) * (1.0 - p);
    float2 vp = float2(d.viewport_size_pixels);
    float row = floor(t.pos.y * vp.y * 0.25);
    float F = float(d.frame_counter % 4096u);
    float slip = (hash11(row + F * 3.7) - 0.5) * 0.10 * k * step(0.55, hash11(row * 1.31 + F));
    float roll = 0.06 * k * sin(TAU * p * 2.0);
    float2 uv = float2(t.pos.x + slip, frac(t.pos.y + roll));
    float3 c = float3(t.backbuffer.Sample(uv + float2(0.004 * k, 0.0)).r,
                      t.backbuffer.Sample(uv).g,
                      t.backbuffer.Sample(uv - float2(0.004 * k, 0.0)).b);
    float snow = hash12(floor(t.pos * vp * 0.5) + F);
    c += 0.25 * k * (snow - 0.3) * lerp(float3(1.0), L.phosphor, L.tint);
    return float4(max(c, float3(0.0)), color.a);
}

public float4
fragment_main(float4 color, KittyTextures t, KittyCustomShaderData d) {
    if (STAGE == 1) return stage_store(t);
    const Control ctl = read_control(d);
    const Look L = monitor_look(ctl.monitor, ctl.flat);
    if (STAGE == 0) return stage_accumulate(color, t, d, L);
    if (STAGE == 2) return stage_downsample_full(t, d, L, ctl.crush);
    const float2 vp = float2(d.viewport_size_pixels);
    if (STAGE == 3) return float4(blur_region(t.b, R_B0, t.pos, vp, float2(1.0, 0.0), 2.4), 1.0);
    if (STAGE == 4) return float4(blur_region(t.a, R_A0, t.pos, vp, float2(0.0, 1.0), 2.4), 1.0);
    if (STAGE == 5) return float4(box4_region(t.b, R_B1, t.pos, vp), 1.0);
    if (STAGE == 6) return float4(blur_region(t.a, R_A1, t.pos, vp, float2(1.0, 0.0), 2.6), 1.0);
    if (STAGE == 7) return float4(blur_region(t.b, R_B2, t.pos, vp, float2(0.0, 1.0), 2.6), 1.0);
    if (STAGE == 9) return stage_tab_glitch(color, t, d, L);
    return stage_composite(t, d, L, ctl.crush);
}
