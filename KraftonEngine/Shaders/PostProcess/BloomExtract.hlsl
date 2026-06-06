#include "Common/Functions.hlsli"
#include "Common/SystemResources.hlsli"
#include "Common/SystemSamplers.hlsli"

cbuffer BloomExtractCB : register(b2)
{
    float BloomThreshold;
    float BloomRadius;
    float2 _BloomPad;
};

PS_Input_UV VS(uint vertexID : SV_VertexID)
{
    return FullscreenTriangleVS(vertexID);
}

float3 ExtractBright(float3 color)
{
    float brightness = max(color.r, max(color.g, color.b));
    float contribution = max(brightness - BloomThreshold, 0.0f) / max(brightness, 0.0001f);
    return color * contribution;
}

float3 SampleBright(float2 uv)
{
    return ExtractBright(SceneColorTexture.SampleLevel(LinearClampSampler, uv, 0).rgb);
}

float4 PS(PS_Input_UV input) : SV_TARGET
{
    uint width;
    uint height;
    SceneColorTexture.GetDimensions(width, height);
    // The destination is half-resolution, so one bloom texel spans two SceneColor texels.
    float2 texelSize = rcp(float2(width, height)) * 2.0f;
    float radius = max(BloomRadius, 0.0f);

    float3 bloom = SampleBright(input.uv) * 0.227027f;
    bloom += SampleBright(input.uv + float2(texelSize.x * radius * 1.384615f, 0.0f)) * 0.316216f;
    bloom += SampleBright(input.uv - float2(texelSize.x * radius * 1.384615f, 0.0f)) * 0.316216f;
    bloom += SampleBright(input.uv + float2(texelSize.x * radius * 3.230769f, 0.0f)) * 0.070270f;
    bloom += SampleBright(input.uv - float2(texelSize.x * radius * 3.230769f, 0.0f)) * 0.070270f;

    return float4(bloom, 1.0f);
}
