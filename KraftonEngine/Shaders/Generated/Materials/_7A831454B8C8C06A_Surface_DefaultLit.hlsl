// Generated from Content/Material/Auto/M_UE4Man_ChestLogo.mat
// Domain: Surface
// ShadingModel: DefaultLit

#include "Common/ConstantBuffers.hlsli"
#include "Common/VertexLayouts.hlsli"
#include "Common/Functions.hlsli"
#include "Common/SystemSamplers.hlsli"
#include "Common/ForwardLighting.hlsli"
#include "Common/GeneratedSurfacePass.hlsli"

struct FMaterialEvalResult
{
    FMaterialResult Material;
    float2 RefractionOffset;
    float RefractionEnabled;
    float _Pad;
};

FMaterialEvalResult EvaluateMaterialWithRefraction(FMaterialPixelInput Input)
{
    float3 n_50 = float3(1.000000f, 1.000000f, 1.000000f);
    float n_47 = 1.000000f;
    FMaterialResult Result;
    Result.BaseColor = n_50;
    Result.Normal = float3(0, 0, 1);
    Result.Roughness = 0.5f;
    Result.Metallic = 0.0f;
    Result.Emissive = float3(0, 0, 0);
    Result.Opacity = n_47;
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
#define MATERIAL_SHADING_MODEL_UNLIT 0

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
