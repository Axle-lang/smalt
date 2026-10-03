#version 450
// tint.frag — the colour the vertex stage worked out.
layout(location = 0) in vec3 vTint;
layout(location = 0) out vec4 outColor;

void main() {
    outColor = vec4(vTint, 1.0);
}
