// Generated from Content/Material/Auto/M_SciFITrooper-01_Top.mat
// Domain: Surface
// ShadingModel: Toon

#include "Common/ConstantBuffers.hlsli"
#include "Common/VertexLayouts.hlsli"
#include "Common/Functions.hlsli"
#include "Common/SystemSamplers.hlsli"
#include "Common/ForwardLighting.hlsli"
#include "Common/GeneratedSurfacePass.hlsli"

Texture2D Tex_Diffuse : register(t0);

cbuffer PerMaterial : register(b2)
{
    float3 Param_ToonShadowTint;
    float _Pad0;
    float Param_ToonThreshold;
    float3 _Pad1;
    float3 Param_ToonRimColor;
    float _Pad2;
    float Param_ToonSoftness;
    float3 _Pad3;
    float Param_ToonShadowStrength;
    float3 _Pad4;
    float Param_ToonRimStrength;
    float3 _Pad5;
};

struct FMaterialEvalResult
{
    FMaterialResult Material;
    float2 RefractionOffset;
    float RefractionEnabled;
    float _Pad;
    float ToonThreshold;
    float ToonSoftness;
    float ToonShadowStrength;
    float ToonRimStrength;
    float3 ToonShadowTint;
    float _PadToon0;
    float3 ToonRimColor;
    float _PadToon1;
};

FMaterialEvalResult EvaluateMaterialWithRefraction(FMaterialPixelInput Input)
{
    float2 n_3 = Input.UV0;
    float4 n_5 = Tex_Diffuse.Sample(LinearWrapSampler, n_3);
    float n_14 = Param_ToonThreshold;
    float n_16 = Param_ToonSoftness;
    float n_18 = Param_ToonShadowStrength;
    float3 n_20 = Param_ToonShadowTint;
    float3 n_22 = Param_ToonRimColor;
    float n_24 = Param_ToonRimStrength;
    FMaterialResult Result;
    Result.BaseColor = (n_5).rgb;
    Result.Normal = float3(0, 0, 1);
    Result.Roughness = 0.5f;
    Result.Metallic = 0.0f;
    Result.Emissive = float3(0, 0, 0);
    Result.Opacity = 1.0f;
    Result.OpacityMask = 1.0f;
    Result.NormalConnected = 0.0f;
    FMaterialEvalResult Eval;
    Eval.Material = Result;
    Eval.RefractionOffset = float2(0, 0);
    Eval.RefractionEnabled = 0.0f;
    Eval._Pad = 0.0f;
    Eval.ToonThreshold = n_14;
    Eval.ToonSoftness = n_16;
    Eval.ToonShadowStrength = n_18;
    Eval.ToonRimStrength = n_24;
    Eval.ToonShadowTint = n_20;
    Eval._PadToon0 = 0.0f;
    Eval.ToonRimColor = n_22;
    Eval._PadToon1 = 0.0f;
    return Eval;
}

FMaterialResult EvaluateMaterial(FMaterialPixelInput Input)
{
    return EvaluateMaterialWithRefraction(Input).Material;
}

#define MATERIAL_SHADING_MODEL_TOON 1
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


float3 ComputeGeneratedSurfaceToonColor(MaterialSurfaceVSOutput input, FMaterialResult Result, FMaterialEvalResult Eval, float3 N)
{
    MaterialSurfacePSOutput DefaultOutput = ShadeGeneratedSurface(input, Result);

    const float3 LumaWeights = float3(0.2126f, 0.7152f, 0.0722f);
    float3 LitNoEmissive = max(DefaultOutput.Color.rgb - Result.Emissive, float3(0.0f, 0.0f, 0.0f));
    float BaseLuma = max(dot(max(Result.BaseColor, float3(0.0f, 0.0f, 0.0f)), LumaWeights), 0.04f);
    float LightRatio = dot(LitNoEmissive, LumaWeights) / BaseLuma;

    float Threshold = saturate(Eval.ToonThreshold);
    float Softness = max(abs(Eval.ToonSoftness), 0.001f);
    float LitBand = smoothstep(Threshold - Softness, Threshold + Softness, LightRatio);

    float ShadowStrength = saturate(Eval.ToonShadowStrength);
    float3 ShadowTint = saturate(Eval.ToonShadowTint);
    float3 ShadowColor = Result.BaseColor * ShadowTint * ShadowStrength;
    float3 LitColor = max(LitNoEmissive, Result.BaseColor);
    float3 ToonColor = lerp(ShadowColor, LitColor, LitBand);

    float3 V = normalize(CameraWorldPos - input.worldPos);
    float Rim = pow(1.0f - saturate(dot(normalize(N), V)), 3.0f) * saturate(Eval.ToonRimStrength);
    ToonColor += saturate(Eval.ToonRimColor) * Rim;

    return ToonColor + Result.Emissive;
}

MaterialSurfacePSOutput ShadeGeneratedSurfaceToon(MaterialSurfaceVSOutput input, FMaterialResult Result, FMaterialEvalResult Eval)
{
    MaterialSurfacePSOutput Output = ShadeGeneratedSurface(input, Result);
    float3 N = ApplyGeneratedSurfaceNormal(input, Result);
    Output.Color.rgb = ComputeGeneratedSurfaceToonColor(input, Result, Eval, N);
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
