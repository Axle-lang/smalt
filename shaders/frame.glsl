// frame.glsl — the two blocks every scene shader reads, shared by text.
//
// Included by every stage smalt compiles and by a program's own shaders (glslang
// resolves `#include` with -I), so the layout is written once. The matching offsets
// live in `src/gpu/vk/vk_frame.axle`, and `examples/gpu_check` asserts the bytes that
// file writes; whoever edits a block here re-reads the offsets out of the compiled
// module (`spirv-dis`, `OpMemberDecorate … Offset`) and updates both.
//
// std140, and deliberately nothing but `mat4` and `vec4`: no `vec3` (padded to 16
// behind your back), no `float` arrays (stride 16), no `bool`. Every member's offset
// is then a multiple of 16 that anyone can count, and a CPU writer that fills "four
// floats at a time" cannot be wrong about it.
//
// `user` and `dr.user` are the program's: smalt writes what `Scene::setUser` and
// `Scene::setDrawUser` were given and reads neither — thirty-two vectors a frame, one a
// draw. They are how a program's own shader is told what its own frame is — a sky's
// colours, a fog's curve, a water's phase, its own constants — without smalt having
// to know.

#define MAX_POINT_LIGHTS 8
#define USER_VECTORS 32

layout(std140, set = 0, binding = 0) uniform Frame {
    mat4 viewProj;                      //   0  clip = viewProj * world (Vulkan clip space)
    vec4 eye;                           //  64  xyz camera position
    vec4 sunDir;                        //  80  xyz direction the light TRAVELS
    vec4 sunColor;                      //  96  rgb colour * intensity
    vec4 ambient;                       // 112  rgb ambient light
    vec4 fogColor;                      // 128  rgb colour, w = 1 when fog is on
    vec4 fogRange;                      // 144  x = start, y = end (distance from eye)
    vec4 lightPos[MAX_POINT_LIGHTS];    // 160  xyz position, w = range
    vec4 lightCol[MAX_POINT_LIGHTS];    // 288  rgb colour * intensity
    vec4 counts;                        // 416  x = point lights in use, yzw = sky light colour
    mat4 invViewProj;                   // 432  world = invViewProj * clip, the w divided out
    vec4 target;                        // 496  x, y = target size in pixels, z, w = 1 / size
    vec4 user[USER_VECTORS];            // 512  the program's own
} fr;                                   // 1024 bytes

layout(push_constant) uniform Draw {
    mat4 model;                         //   0
    vec4 albedo;                        //  64  rgb tint, a = opacity
    vec4 params;                        //  80  x ambient, y specular, z shininess, w alpha cutoff
    vec4 extra;                         //  96  x sun factor, y = 1 sky-lit vertex colour, z lamp factor
    vec4 user;                          // 112  the program's own, per draw
} dr;                                   // 128 bytes
