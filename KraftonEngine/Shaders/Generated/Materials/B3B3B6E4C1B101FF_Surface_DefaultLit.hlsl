// Generated from Content/Data/UnrealImport/Tokyo/Materials/MI_StreetTrim_Matte_DarkGray_cb82fed7.mat
// Domain: Surface
// ShadingModel: DefaultLit

#include "Common/ConstantBuffers.hlsli"
#include "Common/VertexLayouts.hlsli"
#include "Common/Functions.hlsli"
#include "Common/SystemSamplers.hlsli"
#include "Common/ForwardLighting.hlsli"
#include "Common/GeneratedSurfacePass.hlsli"

Texture2D Tex_Diffuse : register(t0);
Texture2D Tex_Normal : register(t1);
Texture2D Tex_RMO : register(t2);
Texture2D Tex_Emissive : register(t4);

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
    float3 n_22 = float3(0.182292f, 0.182292f, 0.182292f);
    float3 n_24 = ((n_12).rgb * n_22);
    float4 n_33 = Tex_Normal.Sample(LinearWrapSampler, Input.UV0);
    float4 n_46 = Tex_RMO.Sample(LinearWrapSampler, Input.UV0);
    float n_56 = 1.400000f;
    float n_58 = ((n_46).r * n_56);
    float n_64 = 0.000000f;
    float n_66 = ((n_46).g * n_64);
    float4 n_76 = Tex_Emissive.Sample(LinearWrapSampler, Input.UV0);
    float3 n_86 = float3(0.000000f, 0.000000f, 0.000000f);
    float3 n_88 = ((n_76).rgb * n_86);
    FMaterialResult Result;
    Result.BaseColor = n_24;
    Result.Normal = (n_33).rgb;
    Result.Roughness = n_58;
    Result.Metallic = n_66;
    Result.Emissive = n_88;
    Result.Opacity = 1.0f;
    Result.OpacityMask = 1.0f;
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
