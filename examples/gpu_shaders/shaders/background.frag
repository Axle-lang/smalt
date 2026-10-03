#version 450
// background.frag — the frame behind everything: the program's texture, stretched.
#extension GL_GOOGLE_include_directive : require
#include "frame.glsl"

layout(set = 1, binding = 0) uniform sampler2DArray tex;
layout(location = 0) in vec2 vUv;
layout(location = 0) out vec4 outColor;

void main() {
    outColor = vec4(texture(tex, vec3(vUv, 0.0)).rgb, 1.0);
}
