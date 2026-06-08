#ifndef GENERATED_SURFACE_PASS_HLSLI
#define GENERATED_SURFACE_PASS_HLSLI

// Generated material shaders provide EvaluateMaterial().
// This include owns the shared Surface/Opaque vertex factory + lighting/output path.

#include "Common/Skinning.hlsli"
#include "Common/ForwardLighting.hlsli"

#ifndef GENERATED_SURFACE_ALPHA_CLIP
#define GENERATED_SURFACE_ALPHA_CLIP 0.333f
#endif

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
    float3 Normal;           // Tangent-space normal. If connected from texture, 0..1 encoded is accepted.
    float  Roughness;
    float  Metallic;
    float3 Emissive;
    float  Opacity;
    float  OpacityMask;
    float  NormalConnected;  // 0: use vertex normal, 1: apply Result.Normal through TBN.
};

struct MaterialSurfaceVSOutput
{
    float4 position     : SV_POSITION;
    float3 worldPos     : TEXCOORD0;
    float3 worldNormal  : TEXCOORD1;
    float4 worldTangent : TEXCOORD2;
    float2 texcoord     : TEXCOORD3;
    float4 color        : COLOR0;
};

struct MaterialSurfacePSOutput
{
    float4 Color   : SV_TARGET0;
    float4 Normal  : SV_TARGET1;
    float4 Culling : SV_TARGET2;
};

float3 GeneratedSurfaceTransformNormal(float3 LocalNormal)
{
    return normalize(mul(LocalNormal, (float3x3)NormalMatrix));
}

float4 GeneratedSurfaceTransformTangent(float4 LocalTangent)
{
    float3 WorldTangent = normalize(mul(LocalTangent.xyz, (float3x3)Model));
    return float4(WorldTangent, LocalTangent.w);
}

MaterialSurfaceVSOutput BuildGeneratedSurfaceVaryings(float3 LocalPosition, float3 LocalNormal, float4 LocalTangent, float2 UV, float4 Color)
{
    float4 WorldPos = mul(float4(LocalPosition, 1.0f), Model);

    MaterialSurfaceVSOutput Output;
    Output.position = mul(mul(WorldPos, View), Projection);
    Output.worldPos = WorldPos.xyz / max(WorldPos.w, 0.00001f);
    Output.worldNormal = GeneratedSurfaceTransformNormal(LocalNormal);
    Output.worldTangent = GeneratedSurfaceTransformTangent(LocalTangent);
    Output.texcoord = UV;
    Output.color = Color;
    return Output;
}

MaterialSurfaceVSOutput BuildGeneratedSurfaceStaticMesh(VS_Input_PNCTT Input)
{
    return BuildGeneratedSurfaceVaryings(Input.position, Input.normal, Input.tangent, Input.texcoord, Input.color);
}

MaterialSurfaceVSOutput BuildGeneratedSurfaceInstancedStaticMesh(VS_Input_PNCTT Input, VS_Input_StaticMeshInstance Instance)
{
    float4 ComponentPosition = TransformStaticMeshInstanceVector(float4(Input.position, 1.0f), Instance);
    float3 ComponentNormal = TransformStaticMeshInstanceVector(float4(Input.normal, 0.0f), Instance).xyz;
    float4 ComponentTangent = float4(
        TransformStaticMeshInstanceVector(float4(Input.tangent.xyz, 0.0f), Instance).xyz,
        Input.tangent.w);
    return BuildGeneratedSurfaceVaryings(ComponentPosition.xyz, ComponentNormal, ComponentTangent, Input.texcoord, Input.color);
}

MaterialSurfaceVSOutput BuildGeneratedSurfaceSkeletalMesh(VS_Input_PNCTTBB Input)
{
    FSkinningResult Skinned = ApplyLinearBlendSkinning(
        Input.position,
        Input.normal,
        Input.tangent.xyz,
        Input.boneIndices,
        Input.boneWeights);

    return BuildGeneratedSurfaceVaryings(
        Skinned.position.xyz,
        Skinned.normal,
        float4(Skinned.tangent, Input.tangent.w),
        Input.texcoord,
        Input.color);
}

FMaterialPixelInput BuildGeneratedSurfaceMaterialInput(MaterialSurfaceVSOutput Input)
{
    FMaterialPixelInput MaterialInput;
    MaterialInput.UV0           = Input.texcoord;
    MaterialInput.UV1           = float2(0, 0);
    MaterialInput.UV2           = float2(0, 0);
    MaterialInput.ParticleColor = float4(1, 1, 1, 1);
    MaterialInput.VertexColor   = Input.color;
    MaterialInput.Time          = Time;
    MaterialInput.SubImageIndex = 0.0f;
    MaterialInput.DynamicParam  = float4(0, 0, 0, 0);
    return MaterialInput;
}

float3 DecodeGeneratedSurfaceTangentNormal(float3 N)
{
    const bool bLooksTextureEncoded = all(N >= float3(0.0f, 0.0f, 0.0f)) && all(N <= float3(1.0f, 1.0f, 1.0f));
    return normalize(bLooksTextureEncoded ? (N * 2.0f - 1.0f) : N);
}

float3 ApplyGeneratedSurfaceNormal(MaterialSurfaceVSOutput Input, FMaterialResult Material)
{
    float3 VertexN = normalize(Input.worldNormal);
    if (Material.NormalConnected < 0.5f)
    {
        return VertexN;
    }

    float3 T = normalize(Input.worldTangent.xyz);
    T = normalize(T - VertexN * dot(VertexN, T));
    float3 B = normalize(cross(VertexN, T) * Input.worldTangent.w);
    float3 TangentN = DecodeGeneratedSurfaceTangentNormal(Material.Normal);

    return normalize(T * TangentN.x + B * TangentN.y + VertexN * TangentN.z);
}

float3 ComputeGeneratedSurfaceLighting(float3 WorldPos, float4 ClipPos, float3 N, FMaterialResult Material)
{
    float3 V = normalize(CameraWorldPos - WorldPos);
    float SpecPower = lerp(128.0f, 8.0f, saturate(Material.Roughness));
    float3 SpecColor = lerp(float3(0.04f, 0.04f, 0.04f), Material.BaseColor, saturate(Material.Metallic));

    float ViewDepth = abs(mul(float4(WorldPos, 1.0f), View).z);
    float DirectionalShadow = CalcDirectionalShadowFactor(WorldPos, ViewDepth, N);

    float3 DiffuseLighting = CalcAmbient(AmbientLight.Color.rgb, AmbientLight.Intensity);
    DiffuseLighting += CalcDirectionalDiffuse(
        DirectionalLight.Color.rgb,
        DirectionalLight.Direction,
        DirectionalLight.Intensity,
        N) * DirectionalShadow;
    AccumulatePointSpotDiffuse(WorldPos, N, ClipPos, DiffuseLighting);

    float3 SpecularLighting = CalcDirectionalSpecular(
        DirectionalLight.Color.rgb,
        DirectionalLight.Direction,
        DirectionalLight.Intensity,
        N,
        V,
        SpecPower) * DirectionalShadow;

    return DiffuseLighting * Material.BaseColor + SpecularLighting * SpecColor + Material.Emissive;
}

MaterialSurfacePSOutput ShadeGeneratedSurface(MaterialSurfaceVSOutput Input, FMaterialResult Material)
{
    clip(min(Material.Opacity, Material.OpacityMask) - GENERATED_SURFACE_ALPHA_CLIP);

    const float3 N = ApplyGeneratedSurfaceNormal(Input, Material);

    MaterialSurfacePSOutput Output;
    Output.Color = float4(ComputeGeneratedSurfaceLighting(Input.worldPos, Input.position, N, Material), Material.Opacity);
    Output.Normal = float4(N, 1.0f);
    Output.Culling = float4(0, 0, 0, 0);
    return Output;
}

#endif // GENERATED_SURFACE_PASS_HLSLI
