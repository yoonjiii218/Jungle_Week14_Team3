// Generated from Content/Data/UnrealImport/Tokyo/Materials/MI_Decal01_Light01_f4187b6c_Decal.mat
// Domain: Decal
// ShadingModel: DefaultLit

#include "Common/ConstantBuffers.hlsli"
#include "Common/VertexLayouts.hlsli"
#include "Common/Functions.hlsli"
#include "Common/SystemSamplers.hlsli"
cbuffer DecalConstants : register(b2)
{
    float4x4 WorldToDecal;
    float4 DecalColor;
};


struct FMaterialPixelInput
{
    float2 UV0;
    float2 UV1;
    float2 UV2;
    float4 ParticleColor;
    float4 VertexColor;
    float  Time;
    float  SubImageIndex;
    float4 DynamicParam;
};

struct FMaterialResult
{
    float3 BaseColor;
    float3 Normal;
    float Roughness;
    float Metallic;
    float3 Emissive;
    float Opacity;
};

Texture2D Tex_Diffuse : register(t0);

FMaterialResult EvaluateMaterial(FMaterialPixelInput Input)
{
    float4 n_12 = Tex_Diffuse.Sample(LinearWrapSampler, Input.UV0);
    float3 n_22 = float3(0.041667f, 0.034329f, 0.024306f);
    float3 n_24 = ((n_12).rgb * n_22);
    float n_31 = 1.000000f;
    float n_34 = 0.000000f;
    float n_39 = ((n_12).r + (n_12).g);
    float n_45 = (n_39 + (n_12).b);
    float n_51 = saturate(n_45);
    float n_37 = 0.400000f;
    float n_55 = (n_51 * n_37);
    FMaterialResult Result;
    Result.BaseColor = n_24;
    Result.Normal = float3(0, 0, 1);
    Result.Roughness = n_31;
    Result.Metallic = n_34;
    Result.Emissive = float3(0, 0, 0);
    Result.Opacity = n_55;
    return Result;
}


struct MaterialDecalVSOutput
{
    float4 position : SV_POSITION;
    float3 worldPos : TEXCOORD0;
    float3 normal : NORMAL;
    float4 color : COLOR0;
};

MaterialDecalVSOutput VS(VS_Input_PNCTT input)
{
    MaterialDecalVSOutput output;
    float4 worldPos = mul(float4(input.position, 1.0f), Model);
    output.position = mul(mul(worldPos, View), Projection);
    output.worldPos = worldPos.xyz / worldPos.w;
    output.normal = normalize(mul(input.normal, (float3x3)NormalMatrix));
    output.color = input.color;
    return output;
}

float4 PS(MaterialDecalVSOutput input) : SV_TARGET
{
    float3 decalPos = mul(float4(input.worldPos, 1.0f), WorldToDecal).xyz;

    clip(0.5f - abs(decalPos.x));
    clip(0.5f - abs(decalPos.y));
    clip(0.5f - abs(decalPos.z));

    FMaterialPixelInput MaterialInput;
    MaterialInput.UV0           = float2(decalPos.y + 0.5f, 0.5f - decalPos.z);
    MaterialInput.UV1           = float2(0, 0);
    MaterialInput.UV2           = float2(0, 0);
    MaterialInput.ParticleColor = float4(1, 1, 1, 1);
    MaterialInput.VertexColor   = input.color;
    MaterialInput.Time          = Time;
    MaterialInput.SubImageIndex = 0.0f;
    MaterialInput.DynamicParam  = float4(0, 0, 0, 0);

    FMaterialResult Result = EvaluateMaterial(MaterialInput);
    float4 FinalColor = float4(Result.BaseColor + Result.Emissive, Result.Opacity) * DecalColor;
    clip(FinalColor.a - 0.01f);
    return FinalColor;
}
