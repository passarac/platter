// Hand-drawn crayon effect, ported from the `#ob-crayon` SVG filter in
// html-mockups/platter.html:
//   1. warp the input with low-frequency noise (wobbly edges)
//   2. draw a lightened copy as the "paper" base
//   3. add the wobbly input at 40% opacity
//   4. add the wobbly input masked by streaky grain noise (waxy strokes)
#include <flutter/runtime_effect.glsl>

precision highp float;

uniform vec2 uSize;  // set by the engine: input texture size, physical px
uniform float uScale;  // device pixel ratio, so noise matches CSS px
uniform sampler2D uTexture;  // set by the engine: the filtered widget

out vec4 fragColor;

vec2 hash22(vec2 p) {
  vec3 p3 = fract(vec3(p.xyx) * vec3(0.1031, 0.1030, 0.0973));
  p3 += dot(p3, p3.yzx + 33.33);
  return fract((p3.xx + p3.yz) * p3.zy) * 2.0 - 1.0;
}

// Gradient noise, roughly in [-0.7, 0.7] like feTurbulence's Perlin noise.
float gradientNoise(vec2 p, float seed) {
  p += seed * vec2(17.0, 59.0);
  vec2 i = floor(p);
  vec2 f = fract(p);
  vec2 u = f * f * (3.0 - 2.0 * f);
  float a = dot(hash22(i), f);
  float b = dot(hash22(i + vec2(1.0, 0.0)), f - vec2(1.0, 0.0));
  float c = dot(hash22(i + vec2(0.0, 1.0)), f - vec2(0.0, 1.0));
  float d = dot(hash22(i + vec2(1.0, 1.0)), f - vec2(1.0, 1.0));
  return mix(mix(a, b, u.x), mix(c, d, u.x), u.y);
}

// feTurbulence type="fractalNoise": octave sum mapped to [0, 1].
float fractalNoise2(vec2 p, vec2 freq, float seed) {
  float sum = gradientNoise(p * freq, seed)
      + 0.5 * gradientNoise(p * freq * 2.0, seed);
  return sum * 0.5 + 0.5;
}

float fractalNoise3(vec2 p, vec2 freq, float seed) {
  float sum = gradientNoise(p * freq, seed)
      + 0.5 * gradientNoise(p * freq * 2.0, seed)
      + 0.25 * gradientNoise(p * freq * 4.0, seed);
  return sum * 0.5 + 0.5;
}

vec3 toLinear(vec3 c) { return pow(c, vec3(2.2)); }
vec3 toSrgb(vec3 c) { return pow(c, vec3(1.0 / 2.2)); }

// Premultiplied source-over.
vec4 over(vec4 top, vec4 bottom) { return top + bottom * (1.0 - top.a); }

void main() {
  vec2 px = FlutterFragCoord().xy;
  vec2 css = px / uScale;

  // 1. Wobble: feDisplacementMap scale=3 driven by 0.04-frequency noise.
  vec2 warp = vec2(
      fractalNoise2(css, vec2(0.04), 7.0),
      fractalNoise2(css, vec2(0.04), 7.5));
  vec2 uv = (px + 3.0 * (warp - 0.5) * uScale) / uSize;
#ifdef IMPELLER_TARGET_OPENGLES
  uv.y = 1.0 - uv.y;
#endif
  vec4 wobbly = texture(uTexture, uv);
  if (wobbly.a <= 0.0) {
    fragColor = vec4(0.0);
    return;
  }
  vec3 color = wobbly.rgb / wobbly.a;

  // 2. Paper base: colour pulled 22% toward white (in linear light, as SVG
  //    filters compute by default).
  vec3 light = toSrgb(toLinear(color) * 0.78 + 0.22);
  vec4 paper = vec4(light, 1.0) * wobbly.a;

  // 3. Faint full-colour layer.
  vec4 faint = wobbly * 0.4;

  // 4. Waxy grain: streaky noise thresholded into an alpha mask.
  float grain = fractalNoise3(css, vec2(0.85, 0.22), 3.0);
  float mask = clamp(2.8 * grain - 0.45, 0.0, 1.0);
  vec4 waxy = wobbly * mask;

  fragColor = over(waxy, over(faint, paper));
}
