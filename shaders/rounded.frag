#version 440
// Draws a texture cropped to fill, with anti-aliased rounded corners.

layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;

layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    vec2 itemSize;
    float radius;
    float dpr;
    vec4 uvRect;     // cropped part of the texture (x, y, w, h)
};
layout(binding = 1) uniform sampler2D source;

float roundedBox(vec2 p, vec2 halfSize, float r)
{
    vec2 q = abs(p) - halfSize + vec2(r);
    return length(max(q, 0.0)) + min(max(q.x, q.y), 0.0) - r;
}

void main()
{
    vec2 px = qt_TexCoord0 * itemSize;
    float d = roundedBox(px - itemSize * 0.5, itemSize * 0.5, min(radius, min(itemSize.x, itemSize.y) * 0.5));
    float mask = clamp(0.5 - d * dpr, 0.0, 1.0);
    fragColor = texture(source, uvRect.xy + qt_TexCoord0 * uvRect.zw) * (mask * qt_Opacity);
}
