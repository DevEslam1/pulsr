#version 460 core
#include <flutter/runtime_effect.glsl>

// Milkdrop-style warp shader. This executes on the GPU via Flutter's runtime
// effect pipeline and is driven by the parsed .milk preset scalars plus live
// audio bands. HSLSL -> GLSL transpilation of the original preset code is not
// performed; the shader reproduces the preset's motion character instead.

uniform vec2 uSize;
uniform float uTime;
uniform float uBass;
uniform float uMid;
uniform float uTreb;
uniform vec3 uColor;
uniform vec3 uWave;
uniform float uZoom;
uniform float uRot;
uniform float uWarp;
uniform float uDecay;

out vec4 fragColor;

void main() {
    vec2 res = uSize;
    vec2 p = (FlutterFragCoord().xy - 0.5 * res) / min(res.x, res.y);

    float angle = uRot * uTime;
    float c = cos(angle);
    float s = sin(angle);
    p = mat2(c, -s, s, c) * p;

    float r = length(p);
    float a = atan(p.y, p.x);

    // Warped tunnel depth: the closer to the center, the deeper the field.
    float zoom = max(uZoom, 0.2);
    float depth = zoom / (r + 0.12);

    // Rotating bands pushed outward by the bass.
    float bandFreq = 5.0 + uWarp * 4.0;
    float bands = sin(depth * bandFreq + uTime * (1.0 + uBass * 3.0) + a * 3.0);
    float rings = smoothstep(0.0, 0.9, bands) * (0.3 + uBass * 0.7);

    // Radial spokes brightened by mids.
    float spokes = 0.5 + 0.5 * sin(a * 12.0 + depth * 2.0 + uTime * (0.5 + uMid * 1.5));
    float energy = rings * (0.55 + 0.45 * spokes) + uTreb * 0.25 * spokes;

    // Decay drives the contrast of the composite.
    float contrast = mix(0.6, 1.4, clamp(uDecay, 0.0, 1.0));
    vec3 base = mix(vec3(0.02, 0.02, 0.05), uColor, 0.3 + 0.45 * uBass);
    vec3 col = base + uWave * energy * contrast;

    // Vignette toward the edges.
    col *= smoothstep(1.15, 0.05, r);
    col = pow(max(col, 0.0), vec3(0.85));

    fragColor = vec4(col, 1.0);
}
