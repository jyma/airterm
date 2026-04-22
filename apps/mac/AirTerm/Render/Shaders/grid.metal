#include <metal_stdlib>
using namespace metal;

struct Uniforms {
    float2 viewportSize;
};

struct Instance {
    float2 cellOriginPx;
    float2 atlasOrigin;
    float2 atlasSize;
    float2 cellSizePx;
    float4 color;
};

struct VertexOut {
    float4 position [[position]];
    float2 uv;
    float4 color;
};

vertex VertexOut grid_vertex(
    uint vid [[vertex_id]],
    uint iid [[instance_id]],
    constant Instance* instances [[buffer(0)]],
    constant Uniforms& u [[buffer(1)]]
) {
    Instance inst = instances[iid];

    float2 corner = float2(float(vid & 1u), float((vid >> 1u) & 1u));
    float2 pixelPos = inst.cellOriginPx + corner * inst.cellSizePx;

    float2 ndc;
    ndc.x = (pixelPos.x / u.viewportSize.x) * 2.0 - 1.0;
    ndc.y = 1.0 - (pixelPos.y / u.viewportSize.y) * 2.0;

    VertexOut out;
    out.position = float4(ndc, 0.0, 1.0);
    out.uv = inst.atlasOrigin + corner * inst.atlasSize;
    out.color = inst.color;
    return out;
}

fragment float4 grid_fragment(
    VertexOut in [[stage_in]],
    texture2d<float> atlas [[texture(0)]],
    sampler atlasSampler [[sampler(0)]]
) {
    float coverage = atlas.sample(atlasSampler, in.uv).r;
    return float4(in.color.rgb * coverage, in.color.a * coverage);
}
