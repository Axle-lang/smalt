#version 450
// overlay.frag — the CPU-drawn 2-D layer, over the finished 3-D frame.
//
// `Frame` writes packed 0x00RRGGBB words and knows no alpha, so the layer's
// transparency is a colour key: a pixel that is entirely zero is "nothing was
// drawn here". The texture is B8G8R8A8, so a word reads back as (r, g, b, a)
// in the order the shader sees. A program that wants a black pixel on the
// overlay writes 0x010101.
layout(set = 1, binding = 0) uniform sampler2DArray tex;

layout(location = 0) in vec2 vUv;
layout(location = 0) out vec4 outColor;

void main() {
    vec4 t = texture(tex, vec3(vUv, 0.0));
    float drawn = (t.r + t.g + t.b + t.a) > 0.0 ? 1.0 : 0.0;
    outColor = vec4(t.rgb, drawn);
}
