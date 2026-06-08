#include "Common/Functions.hlsli"
#include "Common/VertexLayouts.hlsli"
#include "Common/SystemSamplers.hlsli"

Texture2D FontAtlas : register(t0);

PS_Input_Tex VS(VS_Input_PT input)
{
    PS_Input_Tex output;
    output.position = ApplyVP(input.position);
    output.color = input.color;
    output.texcoord = input.texcoord;
    return output;
}

float4 PS(PS_Input_Tex input) : SV_TARGET
{
    float4 col = FontAtlas.Sample(PointClampSampler, input.texcoord);
    if (!bIsWireframe && ShouldDiscardFontPixel(col.r))
        discard;

    float4 tinted = float4(input.color.rgb, input.color.a * col.a);
    return float4(ApplyWireframe(tinted.rgb), bIsWireframe ? 1.0f : tinted.a);
}
