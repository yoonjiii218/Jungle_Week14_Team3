#include "Common/Functions.hlsli"
#include "Common/SystemResources.hlsli"
#include "Common/SystemSamplers.hlsli"

cbuffer GammaCorrectionCB : register(b2)
{
    float Gamma;
    float BloomIntensity;
    float Exposure;
    float BloomRadius;
};

PS_Input_UV VS(uint vertexID : SV_VertexID)
{
    return FullscreenTriangleVS(vertexID);
}

float3 LinearToSRGB(float3 color)
{
    color = max(color, 0.0f);
    float3 low = color * 12.92f;
    float safeGamma = max(Gamma, 0.01f);
    float3 high = 1.055f * pow(color, 1.0f / safeGamma) - 0.055f;
    return lerp(low, high, step(0.0031308f, color));
}

float3 ACESFilm(float3 color)
{
    const float a = 2.51f;
    const float b = 0.03f;
    const float c = 2.43f;
    const float d = 0.59f;
    const float e = 0.14f;
    return saturate((color * (a * color + b)) / (color * (c * color + d) + e));
}

float3 SampleBloom(float2 uv)
{
    uint width;
    uint height;
    BloomTexture.GetDimensions(width, height);
    float2 texelSize = rcp(float2(width, height));
    float radius = max(BloomRadius, 0.0f);

    float3 bloom = BloomTexture.SampleLevel(LinearClampSampler, uv, 0).rgb * 0.227027f;
    bloom += BloomTexture.SampleLevel(LinearClampSampler, uv + float2(0.0f, texelSize.y * radius * 1.384615f), 0).rgb * 0.316216f;
    bloom += BloomTexture.SampleLevel(LinearClampSampler, uv - float2(0.0f, texelSize.y * radius * 1.384615f), 0).rgb * 0.316216f;
    bloom += BloomTexture.SampleLevel(LinearClampSampler, uv + float2(0.0f, texelSize.y * radius * 3.230769f), 0).rgb * 0.070270f;
    bloom += BloomTexture.SampleLevel(LinearClampSampler, uv - float2(0.0f, texelSize.y * radius * 3.230769f), 0).rgb * 0.070270f;
    return bloom;
}

float4 PS(PS_Input_UV input) : SV_TARGET
{
    float4 sceneColor = SceneColorTexture.SampleLevel(LinearClampSampler, input.uv, 0);
    float3 bloom = SampleBloom(input.uv) * BloomIntensity;
    float3 toneMapped = ACESFilm((sceneColor.rgb + bloom) * max(Exposure, 0.0f));
    return float4(LinearToSRGB(toneMapped), sceneColor.a);
}
