// Generated from Content/Material/Auto/M_Sci_Fi_Character_Body_3.mat
// Domain: Surface
// ShadingModel: DefaultLit

#include "Common/ConstantBuffers.hlsli"
#include "Common/VertexLayouts.hlsli"
#include "Common/Functions.hlsli"
#include "Common/SystemSamplers.hlsli"
#include "Common/ForwardLighting.hlsli"
#include "Common/GeneratedSurfacePass.hlsli"

Texture2D Tex_Diffuse : register(t0);

struct FMaterialEvalResult
{
    FMaterialResult Material;
    float2 RefractionOffset;
    float RefractionEnabled;
    float _Pad;
};

FMaterialEvalResult EvaluateMaterialWithRefraction(FMaterialPixelInput Input)
{
    float2 n_3 = Input.UV0;
    float4 n_5 = Tex_Diffuse.Sample(LinearWrapSampler, n_3);
    float3 n_25 = (float4((n_5).rgb, 0.0f)).rgb;
    float n_49 = 1.000000f;
    FMaterialResult Result;
    Result.BaseColor = n_25;
    Result.Normal = float3(0, 0, 1);
    Result.Roughness = 0.5f;
    Result.Metallic = 0.0f;
    Result.Emissive = float3(0, 0, 0);
    Result.Opacity = n_49;
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


MaterialSurfacePSOutput PS(MaterialSurfaceVSOutput input)
{
    FMaterialPixelInput MaterialInput = BuildGeneratedSurfaceMaterialInput(input);
#if MATERIAL_SHADING_MODEL_TOON
    FMaterialEvalResult Eval = EvaluateMaterialWithRefraction(MaterialInput);
    FMaterialResult Result = Eval.Material;
    return ShadeGeneratedSurfaceToon(input, Result, Eval);
#else
    FMaterialResult Result = EvaluateMaterial(MaterialInput);
    return ShadeGeneratedSurface(input, Result);
#endif
}
