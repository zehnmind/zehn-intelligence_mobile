#include <flutter/runtime_effect.glsl>

/**
 * The soap bubble — Figma `zehn/intelligence`.
 *
 * Not a picture of a bubble: a thin-film interference simulation. Every colour
 * on screen is computed from a film thickness in nanometres, the Fresnel
 * coefficients of a water/air interface, and the CIE colour matching functions.
 * That is why it behaves like a bubble rather than like a gradient — the hues
 * slide through the Newton series as the film drains, the limb saturates
 * because the optical path shortens at grazing, and the whole thing breathes.
 */

// Set via shader.setFloat(0..7, ...) in this exact order:
uniform vec2  uRes;    // [0..1] widget size in physical or logical pixels
uniform float uTime;   // [2] seconds elapsed
uniform float uDrive;  // [3] 0..1 microphone / voice energy
uniform float uKick;   // [4] 0..1 tap burst
uniform vec3  uBack;   // [5..7] what shows THROUGH the film (page or scrim colour in 0..1)

out vec4 fragColor;

const float PI = 3.14159265359;
const float NF = 1.33;  // refractive index of soapy water

// The painted disc is deliberately smaller than the canvas. The capillary
// wobble scales the silhouette by up to 1.072 under a tap, and at 0.5 that
// growth would be sheared off by the canvas edge.
const float DISC_R = 0.45;

/* ── film thickness field, in nanometres ──────────────────────────────────
   Radial profile is dominated by the quadratic term, so the middle of the
   disc stays near the core thickness and only the outer third thickens —
   that is what keeps the lime centre wide and packs the saturated hues into
   a ring at the limb. */
const float D0    = 235.2;   // at the centre
const float DR1   =  -3.9;   // linear in r
const float DR2   = 107.9;   // quadratic in r
const float AZ_A1 =  53.6;   // azimuthal tilt, linear in r
const float AZ_A2 =  54.4;   // azimuthal tilt, quadratic in r
const float AZ_PH =   0.70;  // tilt direction (rad, 0 = +x, CCW)
const float AZ_H2 = -11.5;   // second azimuthal harmonic

/* ── living motion ────────────────────────────────────────────────────────
   Amplitudes are a percentage of a ~300nm film, so they slide the hues along
   the Newton series without ever jumping an order — the palette stays the
   design's at every instant, it just never sits still. */
const float NOISE_A = 12.0;  // Marangoni / turbulence amplitude (nm)
const float NOISE_S = 2.4;   // its spatial scale
const float BREATH  = 0.038; // slow whole-film thickening / thinning
const float DRAIN_A = 0.042; // gravitational drainage, apex to base
const float DRAIN_W = 0.050; // travelling drainage wave

/* ── how the film tints what is behind it ─────────────────────────────────
   Beer-Lambert on the film's CHROMATIC DEVIATION, then renormalised to hold
   the backdrop's luminance. */
const float SUBT  = 1.15;    // chromatic depth
const float ADDT  = 0.07;    // additive (front-surface reflection) strength
const float STR_A = 0.62;    // tint strength at the core
const float STR_B = 1.00;    // ... added toward the limb
const float LOSS  = 0.55;    // how much reflected-away energy darkens the film

/* ── fringe visibility ──────────────────────────────────────────────────── */
const float SIG_A =  82.0;   // RMS optical-path spread at the core (nm)
const float SIG_B = -82.0;   // ... change toward the limb (falls to ~0)

/* ── lighting ───────────────────────────────────────────────────────────── */
const vec2  SPEC_A_C = vec2(0.34, 0.46);   // key sheen, upper right
const float SPEC_A_R = 0.42;
const float SPEC_A_E = 0.34;               // ellipticity
const float SPEC_A_T = -0.60;              // rotation (rad)
const float SPEC_A_I = 0.58;
const vec2  SPEC_B_C = vec2(-0.42, -0.40); // fill sheen, lower left
const float SPEC_B_R = 0.40;
const float SPEC_B_E = 0.32;
const float SPEC_B_T = 0.72;
const float SPEC_B_I = 0.30;
const float LIP_I    = 0.55;               // bright lip at the silhouette
const float LIP_W    = 0.035;
const float SHADE    = 0.12;               // limb shading under the lip
const float ARC_R    = 0.80;               // far wall's silhouette, radius
const float ARC_W    = 0.13;               // ... width
const float ARC_PH   = 3.75;               // ... brightest azimuth (rad)
const float ARC_I    = 0.34;               // ... intensity
const float BACK_A   = 0.42;               // far-wall reflection weight
const float BACK_S   = 0.95;               // ... thickness scale
const float BACK_O   = -25.0;              // ... thickness offset (nm)
const float CORE_L   = 0.04;               // luminous core lift
const float DARK_G   = 1.00;               // reflected-light gain on a dark backdrop
const float DARK_ENV = 12.0;               // brightness of the room the film reflects

/* ── analytic CIE 1931 colour matching functions ──────────────────────────
   Wyman, Sloan & Shirley (2013), "Simple Analytic Approximations to the CIE
   XYZ Color Matching Functions" — multi-lobe piecewise-Gaussian fits. */
float gpw(float x, float mu, float s1, float s2) {
  float t = (x - mu) * (x < mu ? 1.0 / s1 : 1.0 / s2);
  return exp(-0.5 * t * t);
}

vec3 cie(float w) {
  return vec3(
    1.056 * gpw(w, 599.8, 37.9, 31.0)
  + 0.362 * gpw(w, 442.0, 16.0, 26.7)
  - 0.065 * gpw(w, 501.1, 20.4, 26.2),
    0.821 * gpw(w, 568.8, 46.9, 40.5)
  + 0.286 * gpw(w, 530.9, 16.3, 31.1),
    1.217 * gpw(w, 437.0, 11.8, 36.0)
  + 0.681 * gpw(w, 459.0, 26.0, 13.8)
  );
}

vec3 xyzToLinearSrgb(vec3 c) {
  return vec3(
    dot(c, vec3( 3.2404542, -1.5371385, -0.4985314)),
    dot(c, vec3(-0.9692660,  1.8760108,  0.0415560)),
    dot(c, vec3( 0.0556434, -0.2040259,  1.0572252))
  );
}

/* ── value noise + fbm ────────────────────────────────────────────────── */
float hash(vec2 p) {
  p = fract(p * vec2(123.34, 456.21));
  p += dot(p, p + 45.32);
  return fract(p.x * p.y);
}

float vnoise(vec2 p) {
  vec2 i = floor(p), f = fract(p);
  f = f * f * (3.0 - 2.0 * f);
  return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), f.x),
             mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), f.x), f.y);
}

float fbm(vec2 p) {
  float a = 0.5, s = 0.0;
  for (int i = 0; i < 4; i++) {
    s += a * vnoise(p);
    p *= 2.03;
    a *= 0.5;
  }
  return s;
}

/* ── the thickness field ────────────────────────────────────────────────── */
float thickness(vec3 N, float rr, float t, float extra) {
  float az = atan(N.y, N.x);
  float rr2 = rr * rr;
  float d = D0 + DR1 * rr + DR2 * rr2
          + cos(az - AZ_PH) * (AZ_A1 * rr + AZ_A2 * rr2)
          + AZ_H2 * cos(2.0 * (az - AZ_PH)) * rr2
          + extra;

  vec2 q = N.xy * NOISE_S;
  float e = 0.35;
  float n1 = fbm(q + vec2(0.0, t * 0.14));
  float n2 = fbm(q + vec2(e, t * 0.14));
  float n3 = fbm(q + vec2(0.0, e + t * 0.14));
  vec2 curl = vec2(n3 - n1, n1 - n2) / e;
  vec2 sp = q + curl * (0.70 + 0.9 * uDrive) + vec2(t * 0.075, -t * 0.045);

  float drain = -N.y * DRAIN_A
              + DRAIN_W * sin(3.4 * N.y - t * 0.72)
              + 0.020 * sin(t * 0.21);

  float breathe = 1.0 + BREATH * sin(t * 0.31) + 0.6 * BREATH * sin(t * 0.17);

  float ring = uKick * 22.0 * sin(9.0 * rr - t * 7.0)
             + uDrive * 24.0 * sin(6.0 * rr - t * 3.2);

  float turb = fbm(sp) - 0.5 + 0.6 * (fbm(sp * 2.7 + 11.3) - 0.5);
  return d * (1.0 + drain) * breathe
       + NOISE_A * turb * (1.0 + 2.2 * uDrive + 1.4 * uKick)
       + ring;
}

/* ── thin-film reflectance, integrated against the CMFs ─────────────────── */
vec3 filmColour(float d, float cosI, float cosT, float rNorm) {
  float rs = (cosI - NF * cosT) / (cosI + NF * cosT);
  float rp = (NF * cosI - cosT) / (NF * cosI + cosT);
  float Rs = clamp(rs * rs, 0.0, 0.9999);
  float Rp = clamp(rp * rp, 0.0, 0.9999);

  float Fs = 4.0 * Rs / ((1.0 - Rs) * (1.0 - Rs));
  float Fp = 4.0 * Rp / ((1.0 - Rp) * (1.0 - Rp));

  float opd = 2.0 * NF * d * cosT;   // optical path difference, nanometres
  float sigma = max(0.0, SIG_A + SIG_B * rNorm);

  vec3 xyz = vec3(0.0);
  float wsum = 0.0;
  for (int i = 0; i < 16; i++) {
    float w = 400.0 + (float(i) + 0.5) * (300.0 / 16.0);
    float vis = exp(-2.0 * (PI * sigma / w) * (PI * sigma / w));
    float phase = 0.5 * (1.0 - vis * cos(2.0 * PI * opd / w));
    float ssS = Fs * phase;
    float ssP = Fp * phase;
    float R = 0.5 * (ssS / (1.0 + ssS) + ssP / (1.0 + ssP));
    vec3 cmf = cie(w);
    xyz += R * cmf;
    wsum += cmf.y;
  }
  return xyzToLinearSrgb(xyz / max(wsum, 1e-4));
}

float ellipse(vec2 p, vec2 c, float rx, float ry, float rot) {
  vec2 q = p - c;
  float cs = cos(rot), sn = sin(rot);
  vec2 e = vec2(q.x * cs + q.y * sn, -q.x * sn + q.y * cs);
  return length(vec2(e.x / max(rx, 1e-5), e.y / max(ry, 1e-5)));
}

float aGauss(vec2 p, vec2 c, float rx, float ry, float rot) {
  float e = ellipse(p, c, rx, ry, rot);
  return exp(-e * e);
}

float softBox(vec2 p, vec2 c, float rx, float ry, float rot, float edge) {
  return smoothstep(1.0, 1.0 - edge, ellipse(p, c, rx, ry, rot));
}

vec3 linearToSrgb(vec3 c) {
  c = clamp(c, 0.0, 1.0);
  return mix(12.92 * c, 1.055 * pow(c, vec3(1.0 / 2.4)) - 0.055, step(vec3(0.0031308), c));
}

vec3 srgbToLinear(vec3 c) {
  return mix(c / 12.92, pow((c + 0.055) / 1.055, vec3(2.4)), step(vec3(0.04045), c));
}

void main() {
  vec2 fragCoord = FlutterFragCoord().xy;
  // In Flutter, Y increases downwards from the top. Invert Y so +p.y is screen-up,
  // matching WebGL and preserving the physical gravity drainage and azimuthal tilt:
  fragCoord.y = uRes.y - fragCoord.y;
  vec2 p = (fragCoord - 0.5 * uRes) / (DISC_R * min(uRes.x, uRes.y));

  float rlen = length(p);
  float inv = 1.0 / max(rlen, 1e-5);
  float ca = p.x * inv, sa = p.y * inv;
  float cos2 = ca * ca - sa * sa;
  float cos3 = ca * (ca * ca - 3.0 * sa * sa);
  float amp = 0.006 + 0.020 * uDrive + 0.030 * uKick;
  float wob = 1.0
    + amp * cos2 * cos(uTime * 1.70)
    + amp * 0.6 * cos3 * cos(uTime * 3.29)
    + amp * 0.4 * sin(uTime * 2.30);
  float rr = rlen / wob;

  // Analytic derivative-free anti-aliasing:
  float aa = 1.6 / (DISC_R * min(uRes.x, uRes.y));
  float cover = 1.0 - smoothstep(1.0 - aa, 1.0, rr);
  if (cover <= 0.0) {
    fragColor = vec4(0.0);
    return;
  }

  float rc = min(rr, 0.99999);
  vec3 N = normalize(vec3(p / wob, sqrt(max(1.0 - rc * rc, 0.0))));
  float cosI = clamp(N.z, 0.0, 1.0);
  float sinT2 = (1.0 - cosI * cosI) / (NF * NF);
  float cosT = sqrt(max(1.0 - sinT2, 0.0));

  vec3 cF = filmColour(thickness(N, rc, uTime, 0.0), cosI, cosT, rc);

  // Far-wall reflection across the hollow volume:
  vec3 cB = filmColour(
    thickness(vec3(N.x, -N.y, N.z), rc * BACK_S, uTime * 0.83 + 4.0, BACK_O),
    cosI, cosT, rc
  );

  vec3 c = max(cF + cB * BACK_A, 0.0);
  float m = max((c.r + c.g + c.b) / 3.0, 1e-4);
  vec3 dev = (c - m) / m;
  float strength = STR_A + STR_B * rc * rc;

  vec3 back = srgbToLinear(uBack);
  float backLum = dot(back, vec3(0.2126, 0.7152, 0.0722));
  float dark = 1.0 - smoothstep(0.12, 0.55, backLum);

  vec3 tint = exp(-SUBT * strength * dev);
  tint /= max(dot(tint, vec3(0.2126, 0.7152, 0.0722)), 1e-4);

  float shimmer = 1.0 - LOSS * m;
  vec3 transmitted = back * tint * shimmer + ADDT * strength * max(dev, 0.0);

  vec3 reflTint = c / max(m, 1e-4);
  float lit = DARK_ENV * m * shimmer;
  lit = lit / (1.0 + lit);
  vec3 reflected = back + DARK_G * lit * reflTint;

  vec3 col = mix(transmitted, reflected, dark);
  col += CORE_L * N.z * N.z * vec3(1.0, 0.985, 0.93);

  float sheenA = softBox(N.xy, SPEC_A_C, SPEC_A_R, SPEC_A_R * SPEC_A_E, SPEC_A_T, 0.55);
  float sheenB = aGauss(N.xy, SPEC_B_C, SPEC_B_R, SPEC_B_R * SPEC_B_E, SPEC_B_T);

  float az = atan(N.y, N.x);
  float crescent = smoothstep(ARC_R - ARC_W, ARC_R, rc)
                 * (1.0 - smoothstep(ARC_R, ARC_R + ARC_W, rc))
                 * (0.45 + 0.55 * cos(az - ARC_PH));
  col = mix(col, vec3(1.0),
            clamp(sheenA * SPEC_A_I + sheenB * SPEC_B_I + max(crescent, 0.0) * ARC_I, 0.0, 0.95));

  col *= 1.0 - SHADE * (1.0 - dark) * smoothstep(0.45, 0.97, rc);

  float lip = smoothstep(1.0 - LIP_W, 1.0 - LIP_W * 0.25, rc)
            * (1.0 - smoothstep(0.994, 1.0, rc));
  col = mix(col, vec3(1.0), clamp(lip * LIP_I, 0.0, 1.0));

  // Premultiplied alpha output
  fragColor = vec4(linearToSrgb(col) * cover, cover);
}
