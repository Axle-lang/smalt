#version 450
// scene.frag — albedo x texel x baked colour, lit by a sun, up to eight point
// lights and an ambient term, then fogged. The sun is scaled by `extra.x`, the
// point lights by `extra.z` (`Material::directLight` / `lampLight`).
//
// The sun term is the CPU device's Blinn-Phong, line for line
// (`render/soft/shade.axle`), so a scene looks like itself on either backend.
#extension GL_GOOGLE_include_directive : require
#include "frame.glsl"

layout(set = 1, binding = 0) uniform sampler2DArray tex;

layout(location = 0) in vec3 vWorld;
layout(location = 1) in vec3 vNormal;
layout(location = 2) in vec2 vUv;
layout(location = 3) in vec4 vColor;
layout(location = 4) flat in uint vLayer;

layout(location = 0) out vec4 outColor;

// `normalize` of a zero vector is undefined (NaN on every driver): a mesh written with
// zero normals because it is never lit, or a sun of zero direction meaning "no sun", must
// shade as unlit rather than as garbage. The CPU's `Vec3::normalized` answers zero too.
vec3 safeNormalize(vec3 v) {
    float len2 = dot(v, v);
    return len2 > 1e-12 ? v * inversesqrt(len2) : vec3(0.0);
}

void main() {
    vec4 texel = texture(tex, vec3(vUv, float(vLayer)));
    vec4 base;
    if (dr.extra.y > 0.5) {
        // Baked light with a sky channel: the vertex colour's rgb is light from emitters
        // (torches), its alpha is the share of the sky that reaches this corner. The sky's
        // colour changes every frame — the time of day — while the vertices do not, so a
        // world turns from noon to night by changing one uniform and re-meshing nothing.
        // Opacity comes from the albedo and the texel alone in this mode.
        base = dr.albedo * texel;
        base.rgb *= vColor.rgb + fr.counts.yzw * vColor.a;
    } else {
        base = dr.albedo * texel * vColor;
    }

    // Alpha test: a leaf's holes are not drawn at all, so they neither blend
    // nor write depth. Zero cutoff means "no test".
    if (dr.params.w > 0.0 && base.a < dr.params.w) {
        discard;
    }

    vec3 n = safeNormalize(vNormal);
    vec3 toSun = -safeNormalize(fr.sunDir.xyz);
    float nd = max(dot(n, toSun), 0.0);

    // The sun and the lamps are scaled apart: a voxel face takes its sky light from the
    // vertices (no sun) and still lights up next to a torch (lamps).
    vec3 sun = fr.sunColor.rgb * nd;
    vec3 lamps = vec3(0.0);
    int count = int(fr.counts.x);
    for (int i = 0; i < MAX_POINT_LIGHTS; ++i) {
        if (i >= count) {
            break;
        }
        vec3 d = fr.lightPos[i].xyz - vWorld;
        float dist = length(d);
        float att = clamp(1.0 - dist / max(fr.lightPos[i].w, 0.0001), 0.0, 1.0);
        lamps += fr.lightCol[i].rgb * (max(dot(n, d / max(dist, 0.0001)), 0.0) * att * att);
    }

    vec3 light = fr.ambient.rgb * dr.params.x + sun * dr.extra.x + lamps * dr.extra.z;
    vec3 col = base.rgb * light;

    // The highlight is the sun's, so it is scaled with the sun. `pow(0, s)` is undefined
    // for s <= 0 and `pow(c, s)` for c < 0: both are kept out, as the CPU shader does.
    if (dr.params.y > 0.0001 && nd > 0.0 && dr.extra.x > 0.0) {
        vec3 toEye = safeNormalize(fr.eye.xyz - vWorld);
        float c = dot(n, safeNormalize(toSun + toEye));
        if (c > 0.0) {
            col += fr.sunColor.rgb * (pow(c, max(dr.params.z, 0.0)) * dr.params.y * dr.extra.x);
        }
    }

    if (fr.fogColor.w > 0.5) {
        float span = max(fr.fogRange.y - fr.fogRange.x, 0.0001);
        float f = clamp((length(fr.eye.xyz - vWorld) - fr.fogRange.x) / span, 0.0, 1.0);
        col = mix(col, fr.fogColor.rgb, f);
    }

    outColor = vec4(col, base.a);
}
