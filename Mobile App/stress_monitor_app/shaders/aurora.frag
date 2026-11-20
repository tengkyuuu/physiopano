#version 460 core
// PHYSIOPAÑO paper surface: a warm paper base with very fine fibre grain and a
// slow, faint wash of light drifting across it. uIntensity scales the wash:
// ~0.05 on paper (barely there), ~0.35 inside the ink feature card.
// uCalm (0..1) nudges the wash from blue toward a warmer tone when arousal rises.

#include <flutter/runtime_effect.glsl>

uniform vec2 uSize;
uniform float uTime;
uniform float uIntensity;
uniform float uCalm;
uniform vec4 uBase;
uniform vec4 uTint;
uniform vec4 uWarm;

out vec4 fragColor;

float hash(vec2 p) {
  return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float noise(vec2 p) {
  vec2 i = floor(p);
  vec2 f = fract(p);
  vec2 u = f * f * (3.0 - 2.0 * f);
  return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), u.x),
             mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), u.x), u.y);
}

float fbm(vec2 p) {
  float v = 0.0;
  float a = 0.5;
  for (int i = 0; i < 4; i++) {
    v += a * noise(p);
    p = p * 2.02 + vec2(3.1, 7.7);
    a *= 0.5;
  }
  return v;
}

void main() {
  vec2 frag = FlutterFragCoord().xy;
  vec2 uv = frag / uSize;
  vec2 p = vec2(uv.x * uSize.x / uSize.y, uv.y);
  float t = uTime * 0.03;

  // Slow light wash: two soft lobes drifting.
  float wash = fbm(p * 1.4 + vec2(t, -t * 0.7));
  float lobe = smoothstep(0.45, 0.9, wash) * (1.0 - smoothstep(0.0, 1.0, uv.y));
  vec3 tint = mix(uTint.rgb, uWarm.rgb, clamp(1.0 - uCalm, 0.0, 1.0) * 0.6);
  vec3 col = mix(uBase.rgb, tint, lobe * uIntensity);

  // Paper fibre: fine anisotropic grain, static so it reads as material.
  float fibre = noise(frag * vec2(0.9, 0.35)) * 0.5 + noise(frag * 1.7) * 0.5;
  col += (fibre - 0.5) * 0.018;

  fragColor = vec4(col, 1.0);
}
