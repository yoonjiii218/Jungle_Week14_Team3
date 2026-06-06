// Generated from Content/Material/Auto/RedBeam.mat
// Domain: ParticleSprite

#include "Common/ConstantBuffers.hlsli"
#include "Common/VertexLayouts.hlsli"
#include "Common/Functions.hlsli"
#include "Common/SystemSamplers.hlsli"
#define USE_FOG 1
#include "Common/Fog.hlsli"
Texture2D GeneratedSceneColorTexture : register(t17);

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
    float2 n_26 = Input.UV0;
    float4 n_17 = Tex_Diffuse.Sample(LinearWrapSampler, n_26);
    FMaterialResult Result;
    Result.Color = (n_17).xyz;
    Result.Emissive = float3(0, 0, 0);
    Result.Opacity = (n_17).x;
    Result.UVOffset = float2(0, 0);
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


struct PS_Input_MaterialParticle
{
    float4 position       : SV_POSITION;
    float2 texcoord       : TEXCOORD0;
    float4 color          : COLOR;
    float  subImageIndex  : TEXCOORD1;
    float4 dynamicParam   : TEXCOORD2;
    float3 worldPos       : TEXCOORD3;
    float2 texcoord2      : TEXCOORD4;
    float2 texcoord3      : TEXCOORD5;
};

PS_Input_MaterialParticle VS(VS_Input_ParticleQuad quad, VS_Input_ParticleInstance inst)
{
    float sinR = sin(inst.rotation);
    float cosR = cos(inst.rotation);

    float2 rotUV = float2(
        quad.cornerUV.x * cosR - quad.cornerUV.y * sinR,
        quad.cornerUV.x * sinR + quad.cornerUV.y * cosR
    );

    float3 worldPos = inst.position
                    + FrameCameraRight * rotUV.x * inst.size.x
                    + FrameCameraUp * rotUV.y * inst.size.y;

    PS_Input_MaterialParticle output;
    output.position       = mul(float4(worldPos, 1.0f), mul(View, Projection));
    output.texcoord       = quad.cornerUV + 0.5f;
    output.color          = inst.color;
    output.subImageIndex  = inst.subImageIndex;
    output.dynamicParam   = inst.dynamicParam;
    output.worldPos       = worldPos;
    output.texcoord2      = float2(0, 0);
    output.texcoord3      = float2(0, 0);
    return output;
}

struct VS_Input_GeneratedParticleBeamTrail
{
    float3 position       : POSITION;
    float  relativeTime   : RELATIVE_TIME;
    float3 oldPosition    : OLD_POSITION;
    float  particleId     : PARTICLE_ID;
    float2 size           : SIZE;
    float  rotation       : ROTATION;
    float  subImageIndex  : SUBIMAGE_INDEX;
    float4 color          : COLOR;
    float2 texcoord       : TEXCOORD0;
    float2 texcoord2      : TEXCOORD1;
};

PS_Input_MaterialParticle VS_BeamTrail(VS_Input_GeneratedParticleBeamTrail input)
{
    float4 worldPos = float4(input.position, 1.0f);

    PS_Input_MaterialParticle output;
    output.position       = mul(worldPos, mul(View, Projection));
    output.texcoord       = input.texcoord;
    output.color          = input.color;
    output.subImageIndex  = input.subImageIndex;
    output.dynamicParam   = float4(input.relativeTime, input.particleId, input.size.x + input.size.y, input.rotation);
    output.worldPos       = worldPos.xyz;
    output.texcoord2      = input.texcoord2;
    output.texcoord3      = input.oldPosition.xy;
    return output;
}

float4 PS(PS_Input_MaterialParticle input) : SV_TARGET
{
    FMaterialPixelInput MaterialInput;
    MaterialInput.UV0           = input.texcoord;
    MaterialInput.UV1           = input.texcoord2;
    MaterialInput.UV2           = input.texcoord3;
    MaterialInput.ParticleColor = input.color;
    MaterialInput.VertexColor   = input.color;
    MaterialInput.Time          = Time;
    MaterialInput.SubImageIndex = input.subImageIndex;
    MaterialInput.DynamicParam  = input.dynamicParam;

    FMaterialEvalResult Eval = EvaluateMaterialWithRefraction(MaterialInput);
    FMaterialResult Result = Eval.Material;
    float4 FinalColor = float4(Result.Color + Result.Emissive, Result.Opacity);
    float ClipThreshold = Eval.RefractionEnabled >= 0.5f ? 0.0001f : 0.01f;
    clip(FinalColor.a - ClipThreshold);

    float4 ForegroundColor = ApplyFogTranslucent(FinalColor, input.worldPos, CameraWorldPos);
    if (Eval.RefractionEnabled < 0.5f)
    {
        return ForegroundColor;
    }

    // ParticleSprite refraction uses the same opaque SceneColor copy as Surface translucent refraction.
    // The material output is manually composited to avoid sampling the active render target directly.
    uint SceneWidth = 1;
    uint SceneHeight = 1;
    GeneratedSceneColorTexture.GetDimensions(SceneWidth, SceneHeight);
    float2 SceneSize = max(float2((float)SceneWidth, (float)SceneHeight), float2(1.0f, 1.0f));
    float2 ScreenUV = input.position.xy / SceneSize;
    float2 RefractedUV = saturate(ScreenUV + Eval.RefractionOffset);
    float4 BackgroundColor = GeneratedSceneColorTexture.Sample(LinearClampSampler, RefractedUV);

    float Alpha = saturate(ForegroundColor.a);
    float3 OutColor = ForegroundColor.rgb * Alpha + BackgroundColor.rgb * (1.0f - Alpha);
    return float4(OutColor, 1.0f);
}
