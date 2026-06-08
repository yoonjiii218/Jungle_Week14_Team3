Texture2D SceneDepthTexture : register(t16);
Texture2D SceneColorTexture : register(t17);
Texture2D GBufferNormalTexture : register(t18);

SamplerState LinearClampSampler : register(s0);
SamplerState PointClampSampler : register(s2);

cbuffer FrameBuffer : register(b0)
{
	float4x4 View;
	float4x4 Projection;
	float4x4 InvProj;
	float4x4 InvViewProj;
	float bIsWireframe;
	float3 WireframeColor;
	float Time;
	float3 CameraWorldPos;
	float _FramePad0;
	float3 CameraRight;
	float _FramePad1;
	float3 CameraUp;
	float _FramePad2;
};

cbuffer PerfectDodgePostProcessCB : register(b2)
{
	float4 BlueTintColor;
	float4 GridColor;

	float EffectAmount;
	float EnterAmount;
	float SustainAmount;
	float ExitAmount;

	float RadialBlurStrength;
	float FocusFlashStrength;
	float BlueTintStrength;
	float GridIntensity;

	float GlitchIntensity;
	float VignetteIntensity;
	float ElapsedTime;
	float Duration;

	float WorldGridIntensity;
	float WorldGridScale;
	float WorldGridThickness;
	float WorldGridDepthFadeDistance;

	float SceneDarkening;
	float GammaPower;
	float WorldGridSurfaceBias;
	float ScreenGridIntensity;
};

struct VSOut
{
	float4 Position : SV_POSITION;
	float2 UV : TEXCOORD0;
};

VSOut VS(uint VertexID : SV_VertexID)
{
	VSOut Out;
	float2 UV = float2((VertexID << 1) & 2, VertexID & 2);
	Out.Position = float4(UV * float2(2.0, -2.0) + float2(-1.0, 1.0), 0.0, 1.0);
	Out.UV = UV;
	return Out;
}

float Hash21(float2 P)
{
	P = frac(P * float2(123.34, 456.21));
	P += dot(P, P + 45.32);
	return frac(P.x * P.y);
}

float GridLine(float2 UV, float Scale, float Width)
{
	float2 GV = abs(frac(UV * Scale) - 0.5);
	float2 Line = smoothstep(Width, 0.0, GV);
	return saturate(max(Line.x, Line.y));
}

float AxisLine(float Value, float Scale, float Width)
{
	float GridCoord = Value * Scale;
	float Cell = frac(GridCoord);
	float DistanceToPlane = min(Cell, 1.0 - Cell);
	float AA = max(fwidth(GridCoord), 0.0015);
	return 1.0 - smoothstep(Width, Width + AA * 1.75, DistanceToPlane);
}

float3 ReconstructWorldPosition(float2 UV, float DeviceDepth)
{
	float2 NDC = float2(UV.x * 2.0 - 1.0, 1.0 - UV.y * 2.0);
	float4 WorldH = mul(float4(NDC, DeviceDepth, 1.0), InvViewProj);
	return WorldH.xyz / max(abs(WorldH.w), 1.0e-5);
}

float3 SafeNormalize(float3 V, float3 Fallback)
{
	float Len2 = dot(V, V);
	return (Len2 > 1.0e-6) ? (V * rsqrt(Len2)) : Fallback;
}

float3 BuildViewRay(float2 UV)
{
	float3 W0 = ReconstructWorldPosition(UV, 0.0);
	float3 W1 = ReconstructWorldPosition(UV, 1.0);
	float3 RayA = W0 - CameraWorldPos;
	float3 RayB = W1 - CameraWorldPos;
	return SafeNormalize((dot(RayB, RayB) > dot(RayA, RayA)) ? RayB : RayA, float3(0.0, 0.0, 1.0));
}

float GridWireAtPoint(float3 P, float Scale, float Width)
{
	float X = AxisLine(P.x, Scale, Width);
	float Y = AxisLine(P.y, Scale, Width);
	float Z = AxisLine(P.z, Scale, Width);

	// 3D wire grid line: two axes must be close to grid planes.
	// This makes lines exist in world-space volume instead of drawing a 2D screen overlay.
	return saturate(max(max(X * Y, X * Z), Y * Z));
}

float GridSurfaceAtPoint(float3 P, float Scale, float Width)
{
	float X = AxisLine(P.x, Scale, Width);
	float Y = AxisLine(P.y, Scale, Width);
	float Z = AxisLine(P.z, Scale, Width);

	// Surface helper: one axis is enough, so floors/walls still get readable grid lines.
	return saturate(max(max(X, Y), Z));
}

float VolumetricWorldGrid(float2 UV, float DeviceDepth, float TimeValue, float Glitch)
{
	float MaxDistance = max(WorldGridDepthFadeDistance, 1.0);
	float3 RayDir = BuildViewRay(UV);

	float3 SurfaceWorld = ReconstructWorldPosition(UV, DeviceDepth);
	float SurfaceDistance = length(SurfaceWorld - CameraWorldPos);

	// Handle both normal-Z and reversed-Z projects. If the copied depth is clear/background,
	// keep the grid in front of the camera instead of failing the effect completely.
	float bClearDepth = step(DeviceDepth, 0.00001) + step(0.99999, DeviceDepth);
	float RayEndDistance = lerp(min(SurfaceDistance, MaxDistance), MaxDistance, saturate(bClearDepth));
	RayEndDistance = clamp(RayEndDistance, 0.1, MaxDistance);

	float Scale = max(WorldGridScale, 0.001);
	float Width = saturate(WorldGridThickness);
	float Grid = 0.0;

	// Fixed small raymarch. This is intentionally cheap and only runs while TimeRush PP is active.
	[unroll]
	for (int i = 1; i <= 14; ++i)
	{
		float T = (float)i / 14.0;
		float Distance = RayEndDistance * T;
		float3 P = CameraWorldPos + RayDir * Distance;

		float Slice = floor((P.x + P.y * 0.37 + P.z * 0.19) * Scale + TimeValue * 9.0);
		float SliceNoise = Hash21(float2(Slice, floor(TimeValue * 24.0)));
		float JitterMask = step(0.78, SliceNoise) * Glitch;
		P += float3(SliceNoise - 0.5, Hash21(float2(Slice + 11.0, TimeValue)) - 0.5, Hash21(float2(Slice + 23.0, TimeValue)) - 0.5)
			* (0.16 * JitterMask);

		float Wire = GridWireAtPoint(P, Scale, Width);
		float Fade = (1.0 - T) * smoothstep(0.0, MaxDistance * 0.18, Distance);
		Grid = max(Grid, Wire * Fade);
	}

	// Also draw a surface grid at the depth hit, but do not depend on it. The volumetric part
	// above is what makes the effect look like a 3D grid existing in the scene.
	float bUsableSurfaceDepth = 1.0 - saturate(bClearDepth);
	float SurfaceGrid = GridSurfaceAtPoint(SurfaceWorld, Scale, Width * 0.72)
		* bUsableSurfaceDepth
		* (1.0 - smoothstep(MaxDistance * 0.65, MaxDistance, SurfaceDistance));

	return saturate(Grid + SurfaceGrid * 0.65);
}

float4 PS(VSOut In) : SV_Target
{
	float2 UV = In.UV;
	float2 Center = float2(0.5, 0.5);
	float2 Dir = UV - Center;
	float Dist = length(Dir);
	float TimeValue = ElapsedTime;

	float Glitch = GlitchIntensity * EffectAmount;
	float Band = floor(UV.y * 72.0);
	float BandNoise = Hash21(float2(Band, floor(TimeValue * 48.0)));
	float BandMask = step(0.88, BandNoise);
	float Offset = (BandNoise - 0.5) * 0.03 * Glitch * BandMask;
	UV.x += Offset;

	float Radial = RadialBlurStrength * (EnterAmount * 2.2 + EffectAmount * 0.45);
	float3 Color = SceneColorTexture.Sample(LinearClampSampler, UV).rgb;
	Color += SceneColorTexture.Sample(LinearClampSampler, UV - Dir * Radial * 0.45).rgb;
	Color += SceneColorTexture.Sample(LinearClampSampler, UV - Dir * Radial * 0.90).rgb;
	Color /= 3.0;

	float CA = (EnterAmount * 0.006 + Glitch * 0.006) * saturate(Dist * 1.8);
	float R = SceneColorTexture.Sample(LinearClampSampler, UV + Dir * CA).r;
	float B = SceneColorTexture.Sample(LinearClampSampler, UV - Dir * CA).b;
	Color.r = lerp(Color.r, R, saturate(EnterAmount + Glitch));
	Color.b = lerp(Color.b, B, saturate(EnterAmount + Glitch));

	float Luma = dot(Color, float3(0.299, 0.587, 0.114));
	float3 Desat = lerp(Color, float3(Luma, Luma, Luma), 0.32 * EffectAmount);
	Color = lerp(Color, Desat, EffectAmount);
	Color = pow(max(Color, float3(0.0, 0.0, 0.0)), lerp(1.0, max(GammaPower, 1.0), EffectAmount));
	Color *= lerp(1.0, 1.0 - saturate(SceneDarkening), EffectAmount);
	Color = lerp(Color, BlueTintColor.rgb * max(Luma, 0.05), BlueTintStrength * EffectAmount);

	// Grid generation is intentionally disabled. Keep the time-rush color grading,
	// radial focus, chromatic aberration, glitch band offset, vignette, and flash only.
	// A real 3D grid should be implemented later as geometry/line rendering rather than
	// as this fullscreen post-process approximation.

	float Vignette = smoothstep(0.20, 0.92, Dist) * VignetteIntensity * EffectAmount;
	Color *= (1.0 - Vignette * 0.60);

	float Flash = FocusFlashStrength * EnterAmount * smoothstep(0.85, 0.0, Dist);
	Color += float3(Flash, Flash, Flash);

	return float4(Color, 1.0);
}
