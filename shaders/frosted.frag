#version 440
// Frosted glass, as in YouTube's player: the video behind the element is
// blurred (sampled from a small mip level) and darkened by `tint`, with
// anti-aliased rounded corners.

layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;

layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    vec2 itemSize;   // logical pixels
    float radius;    // logical pixels
    float tint;      // opacity of the black overlay
    vec4 area;       // blurred video area in window coordinates (x, y, w, h)
    vec2 viewport;   // window size in device pixels
    float dpr;
    float lod;
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

    vec2 frag = vec2(gl_FragCoord.x, viewport.y - gl_FragCoord.y) / dpr;
    vec2 uv = (frag - area.xy) / area.zw;
    vec2 o = exp2(lod) / vec2(textureSize(source, 0));
    vec3 c = textureLod(source, uv, lod).rgb * 0.2
           + textureLod(source, uv + vec2(o.x, o.y), lod).rgb * 0.2
           + textureLod(source, uv + vec2(-o.x, o.y), lod).rgb * 0.2
           + textureLod(source, uv + vec2(o.x, -o.y), lod).rgb * 0.2
           + textureLod(source, uv + vec2(-o.x, -o.y), lod).rgb * 0.2;

    fragColor = vec4(c * (1.0 - tint), 1.0) * (mask * qt_Opacity);
}
