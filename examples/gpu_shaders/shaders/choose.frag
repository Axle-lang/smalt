#version 450
// choose.frag — the last pass: where the scene drew nothing (depth 1), the kept colour —
// the frame as the scene drew it; elsewhere what the pass before made of it.
#extension GL_GOOGLE_include_directive : require
#include "frame.glsl"
#include "post.glsl"

layout(location = 0) out vec4 outColor;

void main() {
    float depth = texture(sceneDepth, vUv).r;
    vec3 c = depth >= 0.99999 ? texture(baseColor, vUv).rgb : texture(prevColor, vUv).rgb;
    outColor = vec4(c, 1.0);
}
