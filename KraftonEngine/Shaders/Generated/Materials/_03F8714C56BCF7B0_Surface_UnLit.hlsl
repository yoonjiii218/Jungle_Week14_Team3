// Generated from Content/Data/UnrealImport/Tokyo/Materials/MI_Decal01_Dark02_d8a0d0a4.mat
// Domain: Surface
// ShadingModel: UnLit

#include "Common/ConstantBuffers.hlsli"
#include "Common/VertexLayouts.hlsli"
#include "Common/Functions.hlsli"
#include "Common/SystemSamplers.hlsli"
#define USE_FOG 1
#include "Common/Fog.hlsli"
#include "Common/ForwardLighting.hlsli"
#include "Common/GeneratedSurfacePass.hlsli"
Texture2D GeneratedSceneColorTexture : register(t17);

struct FMaterialEvalResult
{
    FMaterialResult Material;
    float2 RefractionOffset;
    float RefractionEnabled;
    float _Pad;
};

FMaterialEvalResult EvaluateMaterialWithRefraction(FMaterialPixelInput Input)
{
    float3 n_10 = float3(0.041667f, 0.034329f, 0.024306f);
    float n_13 = 1.000000f;
    float n_16 = 0.000000f;
    float n_19 = 1.000000f;
    FMaterialResult Result;
    Result.BaseColor = n_10;
    Result.Normal = float3(0, 0, 1);
    Result.Roughness = n_13;
    Result.Metallic = n_16;
    Result.Emissive = float3(0, 0, 0);
    Result.Opacity = n_19;
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


float4 PS(MaterialSurfaceVSOutput input) : SV_TARGET
{
    FMaterialPixelInput MaterialInput = BuildGeneratedSurfaceMaterialInput(input);
    FMaterialEvalResult Eval = EvaluateMaterialWithRefraction(MaterialInput);
    FMaterialResult Result = Eval.Material;

    const float3 N = ApplyGeneratedSurfaceNormal(input, Result);
#if MATERIAL_SHADING_MODEL_TOON
    float4 FinalColor = float4(ComputeGeneratedSurfaceToonColor(input, Result, Eval, N), Result.Opacity);
#elif MATERIAL_SHADING_MODEL_UNLIT
    float4 FinalColor = float4(Result.BaseColor + Result.Emissive, Result.Opacity);
#else
    float4 FinalColor = float4(ComputeGeneratedSurfaceLighting(input.worldPos, input.position, N, Result), Result.Opacity);
#endif
    clip(FinalColor.a - 0.01f);

    // Without RefractionOffset, keep the existing hardware alpha blending path.
    if (Eval.RefractionEnabled < 0.5f)
    {
        return ApplyFogTranslucent(FinalColor, input.worldPos, CameraWorldPos);
    }

    // Refraction path: sample the copied opaque scene color at screen UV + user offset,
    // then manually composite: final = foreground * alpha + refractedBackground * (1 - alpha).
    uint SceneWidth = 1;
    uint SceneHeight = 1;
    GeneratedSceneColorTexture.GetDimensions(SceneWidth, SceneHeight);
    float2 SceneSize = max(float2((float)SceneWidth, (float)SceneHeight), float2(1.0f, 1.0f));
    float2 ScreenUV = input.position.xy / SceneSize;
    float2 RefractedUV = saturate(ScreenUV + Eval.RefractionOffset);
    float4 BackgroundColor = GeneratedSceneColorTexture.Sample(LinearClampSampler, RefractedUV);

    float4 ForegroundColor = ApplyFogTranslucent(FinalColor, input.worldPos, CameraWorldPos);
    float Alpha = saturate(ForegroundColor.a);
    float3 OutColor = ForegroundColor.rgb * Alpha + BackgroundColor.rgb * (1.0f - Alpha);
    return float4(OutColor, 1.0f);
}
