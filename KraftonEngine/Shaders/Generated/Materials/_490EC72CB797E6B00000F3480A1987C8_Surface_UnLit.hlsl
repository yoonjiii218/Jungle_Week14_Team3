// Generated from Content/Material/VFX/M_Slash_Effect.mat
// Domain: Surface
// ShadingModel: UnLit

#include "Common/ConstantBuffers.hlsli"
#include "Common/VertexLayouts.hlsli"
#include "Common/Functions.hlsli"
#include "Common/SystemSamplers.hlsli"
#include "Common/ForwardLighting.hlsli"
#include "Common/GeneratedSurfacePass.hlsli"

Texture2D Tex_SlashAtlas : register(t0);

cbuffer PerMaterial : register(b2)
{
    float Param_EmissiveIntensity;
    float3 _Pad0;
};

struct FMaterialEvalResult
{
    FMaterialResult Material;
    float2 RefractionOffset;
    float RefractionEnabled;
    float _Pad;
};

FMaterialEvalResult EvaluateMaterialWithRefraction(FMaterialPixelInput Input)
{
    float2 n_42 = ((float2(fmod(floor(saturate(Input.SubImageIndex) * (16 - 0.0001f)), 4), floor(floor(saturate(Input.SubImageIndex) * (16 - 0.0001f)) / 4)) + Input.UV0) * float2(1.0f/4, 1.0f/4));
    float4 n_32 = Tex_SlashAtlas.Sample(LinearWrapSampler, n_42);
    float3 n_45 = ((n_32).rgb * float3((n_32).a, (n_32).a, (n_32).a));
    float4 n_1 = Input.ParticleColor;
    float3 n_72 = (n_45 * (n_1).rgb);
    float n_59 = Param_EmissiveIntensity;
    float3 n_100 = (n_72 * float3(n_59, n_59, n_59));
    FMaterialResult Result;
    Result.BaseColor = float3(1, 1, 1);
    Result.Normal = float3(0, 0, 1);
    Result.Roughness = 0.5f;
    Result.Metallic = 0.0f;
    Result.Emissive = n_100;
    Result.Opacity = 1.0f;
    Result.OpacityMask = 1.0f;
    Result.NormalConnected = 0.0f;
    FMaterialEvalResult Eval;
    Eval.Material = Result;
    Eval.RefractionOffset = float2(0, 0);
    Eval.RefractionEnabled = 0.0f;
    Eval._Pad = 0.0f;
    return Eval;
}

FMaterialResult EvaluateMaterial(FMaterialPixelInput Input)
{
    return EvaluateMaterialWithRefraction(Input).Material;
}

#define MATERIAL_SHADING_MODEL_TOON 0
#define MATERIAL_SHADING_MODEL_UNLIT 1

MaterialSurfaceVSOutput VS_StaticMesh(VS_Input_PNCTT input)
{
    return BuildGeneratedSurfaceStaticMesh(input);
}

MaterialSurfaceVSOutput VS_SkeletalMesh(VS_Input_PNCTTBB input)
{
    return BuildGeneratedSurfaceSkeletalMesh(input);
}

// Legacy entry point. Kept so old cache paths that compile "VS" still render as StaticMesh.
MaterialSurfaceVSOutput VS(VS_Input_PNCTT input)
{
    return VS_StaticMesh(input);
}


MaterialSurfacePSOutput ShadeGeneratedSurfaceUnLit(MaterialSurfaceVSOutput input, FMaterialResult Result)
{
    clip(min(Result.Opacity, Result.OpacityMask) - GENERATED_SURFACE_ALPHA_CLIP);

    const float3 N = ApplyGeneratedSurfaceNormal(input, Result);

    MaterialSurfacePSOutput Output;
    Output.Color = float4(Result.BaseColor + Result.Emissive, Result.Opacity);
    Output.Normal = float4(N, 1.0f);
    Output.Culling = float4(0, 0, 0, 0);
    return Output;
}


MaterialSurfacePSOutput PS(MaterialSurfaceVSOutput input)
{
    FMaterialPixelInput MaterialInput = BuildGeneratedSurfaceMaterialInput(input);
#if MATERIAL_SHADING_MODEL_TOON
    FMaterialEvalResult Eval = EvaluateMaterialWithRefraction(MaterialInput);
    FMaterialResult Result = Eval.Material;
    return ShadeGeneratedSurfaceToon(input, Result, Eval);
#elif MATERIAL_SHADING_MODEL_UNLIT
    FMaterialResult Result = EvaluateMaterial(MaterialInput);
    return ShadeGeneratedSurfaceUnLit(input, Result);
#else
    FMaterialResult Result = EvaluateMaterial(MaterialInput);
    return ShadeGeneratedSurface(input, Result);
#endif
}
