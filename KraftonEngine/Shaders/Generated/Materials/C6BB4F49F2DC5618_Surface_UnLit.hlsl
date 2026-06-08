// Generated from Content/Data/UnrealImport/Tokyo/Materials/MI_DecalMasked_Yellow_587ba970.mat
// Domain: Surface
// ShadingModel: UnLit

#include "Common/ConstantBuffers.hlsli"
#include "Common/VertexLayouts.hlsli"
#include "Common/Functions.hlsli"
#include "Common/SystemSamplers.hlsli"
#include "Common/ForwardLighting.hlsli"
#include "Common/GeneratedSurfacePass.hlsli"

Texture2D Tex_Diffuse : register(t0);
Texture2D Tex_Normal : register(t1);
Texture2D Tex_OpacityMask : register(t6);

struct FMaterialEvalResult
{
    FMaterialResult Material;
    float2 RefractionOffset;
    float RefractionEnabled;
    float _Pad;
};

FMaterialEvalResult EvaluateMaterialWithRefraction(FMaterialPixelInput Input)
{
    float4 n_12 = Tex_Diffuse.Sample(LinearWrapSampler, Input.UV0);
    float3 n_22 = float3(0.489583f, 0.199397f, 0.020399f);
    float3 n_24 = ((n_12).rgb * n_22);
    float4 n_33 = Tex_Normal.Sample(LinearWrapSampler, Input.UV0);
    float n_44 = 0.700000f;
    float n_47 = 0.000000f;
    float4 n_52 = Tex_OpacityMask.Sample(LinearWrapSampler, Input.UV0);
    FMaterialResult Result;
    Result.BaseColor = n_24;
    Result.Normal = (n_33).rgb;
    Result.Roughness = n_44;
    Result.Metallic = n_47;
    Result.Emissive = float3(0, 0, 0);
    Result.Opacity = (n_52).r;
    Result.OpacityMask = (n_52).r;
    Result.NormalConnected = 1.0f;
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

MaterialSurfaceVSOutput VS_InstancedStaticMesh(VS_Input_PNCTT input, VS_Input_StaticMeshInstance inst)
{
    return BuildGeneratedSurfaceInstancedStaticMesh(input, inst);
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
