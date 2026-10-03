#version 450
// copy.frag — the 3-D frame onto the window, when no pass of the program's does it.
//
// The scene is drawn into a colour target rather than into the window, so that a
// pass can read it; with no pass to read it, this is the one that puts it on screen.
// It declares only the one target it reads (`post.glsl` binds set 2 binding 0 the same).
layout(set = 2, binding = 0) uniform sampler2D prevColor;

layout(location = 0) in vec2 vUv;
layout(location = 0) out vec4 outColor;

void main() {
    outColor = vec4(texture(prevColor, vUv).rgb, 1.0);
}
