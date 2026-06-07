#include "Common/ConstantBuffers.hlsli"
#include "Common/VertexLayouts.hlsli"
#include "Common/SystemSamplers.hlsli"
#define USE_FOG 1
#include "Common/Fog.hlsli"

Texture2D ParticleTexture : register(t0);

// b2: emitter별 sprite 확장 축. Billboard가 꺼지면 카메라 축 대신 emitter 축이 들어온다.
cbuffer ParticleFrameBuffer : register(b2)
{
    float3 ParticleFrameRight;
    float ParticleFramePad0;
    float3 ParticleFrameUp;
    float ParticleFramePad1;
}

struct PS_Input_Particle
{
    float4 position : SV_POSITION;
    float2 texcoord : TEXCOORD0;
    float4 color    : COLOR;
    float3 worldPos : TEXCOORD1;
};

PS_Input_Particle VS(VS_Input_ParticleQuad quad, VS_Input_ParticleInstance inst)
{
    float sinR = sin(inst.rotation);
    float cosR = cos(inst.rotation);

    float2 rotUV = float2(
        quad.cornerUV.x * cosR - quad.cornerUV.y * sinR,
        quad.cornerUV.x * sinR + quad.cornerUV.y * cosR
    );

    float3 worldPos = inst.position
                    + ParticleFrameRight * rotUV.x * inst.size.x
                    + ParticleFrameUp * rotUV.y * inst.size.y;

    PS_Input_Particle output;
    output.position = mul(float4(worldPos, 1.0f), mul(View, Projection));
    output.texcoord = quad.cornerUV + 0.5f;
    output.color    = inst.color;
    output.worldPos = worldPos;
    return output;
}

float4 PS(PS_Input_Particle input) : SV_TARGET
{
    float4 col = ParticleTexture.Sample(LinearClampSampler, input.texcoord);
    col *= input.color;
    clip(col.a - 0.01f);
    return ApplyFogTranslucent(col, input.worldPos, CameraWorldPos);
}
