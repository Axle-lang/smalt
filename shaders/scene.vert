#version 450
// scene.vert — one corner of a triangle, through the model and the camera.
//
// The vertex is smalt's GPU vertex, 32 bytes (see `gpu/mesh_builder.axle`):
//   0 position  float x3     12 uv  float x2     20 normal  snorm8 x4
//  24 colour    unorm8 x4    28 layer  uint (0 .. 255, MeshBuilder::MAX_LAYER)
#extension GL_GOOGLE_include_directive : require
#include "frame.glsl"

layout(location = 0) in vec3 inPos;
layout(location = 1) in vec2 inUv;
layout(location = 2) in vec4 inNormal;
layout(location = 3) in vec4 inColor;
layout(location = 4) in uint inLayer;

layout(location = 0) out vec3 vWorld;
layout(location = 1) out vec3 vNormal;
layout(location = 2) out vec2 vUv;
layout(location = 3) out vec4 vColor;
layout(location = 4) flat out uint vLayer;

void main() {
    vec4 world = dr.model * vec4(inPos, 1.0);
    vWorld = world.xyz;
    // The normal follows the model as a direction. Exact for the rigid and
    // uniformly scaled transforms a game uses (the CPU device says the same).
    vNormal = mat3(dr.model) * inNormal.xyz;
    vUv = inUv;
    vColor = inColor;
    vLayer = inLayer & 0xFFFFu;
    gl_Position = fr.viewProj * world;
}
