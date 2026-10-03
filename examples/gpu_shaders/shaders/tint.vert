#version 450
// tint.vert — a mesh shader that reads what the built-in stages leave alone: the
// normal's fourth byte and the layer word's upper bits.
#extension GL_GOOGLE_include_directive : require
#include "frame.glsl"

layout(location = 0) in vec3 inPos;
layout(location = 1) in vec2 inUv;
layout(location = 2) in vec4 inNormal;
layout(location = 3) in vec4 inColor;
layout(location = 4) in uint inLayer;

layout(location = 0) out vec3 vTint;

void main() {
    float bits = float((inLayer >> 8) & 0xFFu) / 255.0;
    vTint = dr.user.rgb * bits * inNormal.w * inColor.rgb;
    gl_Position = fr.viewProj * dr.model * vec4(inPos, 1.0);
}
