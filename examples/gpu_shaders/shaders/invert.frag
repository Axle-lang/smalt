#version 450
// invert.frag — a pass: the frame before it, inverted.
#extension GL_GOOGLE_include_directive : require
#include "frame.glsl"
#include "post.glsl"

layout(location = 0) out vec4 outColor;

void main() {
    outColor = vec4(1.0 - texture(prevColor, vUv).rgb, 1.0);
}
