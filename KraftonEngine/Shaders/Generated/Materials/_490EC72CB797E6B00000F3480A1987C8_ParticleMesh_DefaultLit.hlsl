// Generated from Content/Material/VFX/M_Slash_Effect.mat
// Domain: ParticleMesh
// ShadingModel: DefaultLit

#include "Common/ConstantBuffers.hlsli"
#include "Common/VertexLayouts.hlsli"
#include "Common/Functions.hlsli"
#include "Common/SystemSamplers.hlsli"
#define USE_FOG 1
#include "Common/Fog.hlsli"

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
    float3 Color;
    float3 Emissive;
    float Opacity;
    float2 UVOffset;
};

Texture2D Tex_SlashAtlas : register(t0);

cbuffer PerMaterial : register(b2)
{
    float Param_EmissiveIntensity;
    float3 _Pad0;
};

FMaterialResult EvaluateMaterial(FMaterialPixelInput Input)
{
    float2 n_42 = ((float2(fmod(floor(saturate(Input.SubImageIndex) * (16 - 0.0001f)), 4), floor(floor(saturate(Input.SubImageIndex) * (16 - 0.0001f)) / 4)) + Input.UV0) * float2(1.0f/4, 1.0f/4));
    float4 n_32 = Tex_SlashAtlas.Sample(LinearWrapSampler, n_42);
    float3 n_45 = ((n_32).rgb * float3((n_32).a, (n_32).a, (n_32).a));
    float4 n_1 = Input.ParticleColor;
    float3 n_72 = (n_45 * (n_1).rgb);
    float n_59 = Param_EmissiveIntensity;
    float3 n_100 = (n_72 * float3(n_59, n_59, n_59));
    FMaterialResult Result;
    Result.Color = float3(0, 0, 0);
    Result.Emissive = n_100;
    Result.Opacity = 1.0f;
    Result.UVOffset = float2(0, 0);
    return Result;
}


struct PS_Input_MaterialMeshParticle
{
    float4 position       : SV_POSITION;
    float3 normal         : NORMAL;
    float2 texcoord       : TEXCOORD0;
    float4 color          : COLOR;
    float  subImageIndex  : TEXCOORD1;
    float4 dynamicParam   : TEXCOORD2;
    float3 worldPos       : TEXCOORD3;
};

PS_Input_MaterialMeshParticle VS(VS_Input_PNCT vert, VS_Input_MeshParticleInstance inst)
{
    float4 worldPos = mul(float4(vert.position, 1.0f), inst.transform);
    // 비균일 스케일에서 노말 왜곡 방지: 역전치 행렬 사용
    float3x3 M = (float3x3)inst.transform;
    float3x3 invTransM = transpose(float3x3(
        cross(M[1], M[2]),
        cross(M[2], M[0]),
        cross(M[0], M[1])
    ));
    float3 worldNormal = mul(vert.normal, invTransM);

    PS_Input_MaterialMeshParticle output;
    output.position       = mul(worldPos, mul(View, Projection));
    output.normal         = normalize(worldNormal);
    output.texcoord       = vert.texcoord;
    output.color          = vert.color * inst.color;
    output.subImageIndex  = inst.subImageIndex;
    output.dynamicParam   = inst.dynamicParam;
    output.worldPos       = worldPos.xyz / worldPos.w;
    return output;
}

float4 PS(PS_Input_MaterialMeshParticle input) : SV_TARGET
{
    FMaterialPixelInput MaterialInput;
    MaterialInput.UV0           = input.texcoord;
    MaterialInput.UV1           = float2(0, 0);
    MaterialInput.UV2           = float2(0, 0);
    MaterialInput.ParticleColor = input.color;
    MaterialInput.VertexColor   = input.color;
    MaterialInput.Time          = Time;
    MaterialInput.SubImageIndex = input.subImageIndex;
    MaterialInput.DynamicParam  = input.dynamicParam;

    FMaterialResult Result = EvaluateMaterial(MaterialInput);
    float3 BaseColor = Result.Color;

    float4 FinalColor = float4(BaseColor + Result.Emissive, Result.Opacity);
    clip(FinalColor.a - 0.01f);
    return FinalColor;
}
