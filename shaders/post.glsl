// post.glsl — what a full-screen pass of a program samples.
//
// Included by a `ShaderKind::Pass` fragment shader after `frame.glsl`. The vertex
// stage is smalt's (`overlay.vert`): one triangle over the target, `vUv` running
// from (0, 0) at the top-left corner to (1, 1) at the bottom-right.
//
//   tex         the texture the pass was added with (the white texel if none)
//   prevColor   what the pass before this one drew — the 3-D frame for the first
//   baseColor   the last pass added with `keep`, or the 3-D frame when none was
//   sceneDepth  the 3-D frame's depth, 0 at the near plane and 1 at the far one
//
// Where the device has 16-bit float targets (most do), they hold more than 0 .. 1: a pass
// may brighten past white and a later one bring it back, and only the last pass's output
// is clamped, by the window's format. Where it has not, every pass is clamped to 0 .. 1.

layout(set = 1, binding = 0) uniform sampler2DArray tex;
layout(set = 2, binding = 0) uniform sampler2D prevColor;
layout(set = 2, binding = 1) uniform sampler2D baseColor;
layout(set = 2, binding = 2) uniform sampler2D sceneDepth;

layout(location = 0) in vec2 vUv;
