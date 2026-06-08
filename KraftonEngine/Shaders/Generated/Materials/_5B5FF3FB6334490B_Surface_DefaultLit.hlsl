// Generated from Content/Material/Auto/MI_HAIR_Straight_01.mat
// Domain: Surface
// ShadingModel: DefaultLit

#include "Common/ConstantBuffers.hlsli"
#include "Common/VertexLayouts.hlsli"
#include "Common/Functions.hlsli"
#include "Common/SystemSamplers.hlsli"
#define USE_FOG 1
#include "Common/Fog.hlsli"
#include "Common/ForwardLighting.hlsli"
#include "Common/GeneratedSurfacePass.hlsli"
Texture2D GeneratedSceneColorTexture : register(t17);

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
    float4 n_14 = Input.VertexColor;
    float3 n_21 = ((n_5).rgb * (n_14).rgb);
    float3 n_25 = (float4(n_21, 0.0f)).rgb;
    float3 n_61 = float3(0.491000f, 0.181000f, 0.329000f);
    float3 n_70 = float3(0.000000f, 0.300000f, 0.300000f);
    float n_72 = (float4(n_3, 0.0f, 0.0f)).g;
    float3 n_75 = lerp(n_61, n_70, n_72);
    float3 n_63 = (n_25 * n_75);
    FMaterialResult Result;
    Result.BaseColor = n_63;
    Result.Normal = float3(0, 0, 1);
    Result.Roughness = 0.5f;
    Result.Metallic = 0.0f;
    Result.Emissive = float3(0, 0, 0);
    Result.Opacity = (n_5).r;
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
