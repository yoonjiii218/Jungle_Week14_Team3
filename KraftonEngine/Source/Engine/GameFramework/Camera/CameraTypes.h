#pragma once

#include "Core/Types/CoreTypes.h"
#include "Core/Types/EngineTypes.h"
#include "Math/Vector.h"
#include "Math/Rotator.h"

// ============================================================
// EViewTargetBlendFunction — SetViewTargetWithBlend 의 블렌딩 함수
// UE: EViewTargetBlendFunction
// ============================================================
enum class EViewTargetBlendFunction : uint8
{
	VTBlend_Linear,
	VTBlend_Cubic,
	VTBlend_EaseIn,
	VTBlend_EaseOut,
	VTBlend_EaseInOut,
	VTBlend_PreBlended,
};

// ============================================================
// FViewTargetTransitionParams — view target 전환 파라미터
// UE: FViewTargetTransitionParams
// ============================================================
struct FViewTargetTransitionParams
{
	float BlendTime = 0.0f;
	EViewTargetBlendFunction BlendFunction = EViewTargetBlendFunction::VTBlend_Linear;
	float BlendExp = 0.0f;
	bool bLockOutgoing = false;
};

// ============================================================
// ECameraShakePlaySpace — Shake 가 적용되는 좌표 공간
// UE: ECameraShakePlaySpace
// ============================================================
enum class ECameraShakePlaySpace : uint8
{
	CameraLocal,    // 카메라 로컬
	World,          // 월드 좌표
	UserDefined,    // UserPlaySpaceRot 기준
};

// ============================================================
// FCameraShakeUpdateResult — 매 프레임 Shake 결과 (additive)
// UE: FCameraShakeUpdateResult (간소화)
// ============================================================
struct FCameraShakeUpdateResult
{
	FVector Location = FVector(0.0f, 0.0f, 0.0f);   // additive world-space offset
	FRotator Rotation;                              // additive Pitch/Yaw/Roll (degrees)
	float FOV = 0.0f;                               // additive radians (FCameraState/FMinimalViewInfo 단위와 통일)
};

struct FCameraFadeState
{
	bool bEnabled = false;
	float Amount = 0.0f;
	FLinearColor Color = FLinearColor::Black();
	bool bFadeAudio = false;
};

struct FCameraVignetteState
{
	bool bEnabled = false;
	float Intensity = 0.0f;
	float Radius = 0.75f;
	float Softness = 0.35f;
	FLinearColor Color = FLinearColor::Black();
};

struct FCameraLetterboxState
{
	bool bEnabled = false;
	float Amount = 1.0f;
	float Thickness = 0.12f;
	FLinearColor Color = FLinearColor::Black();
};

namespace PerfectDodgePostProcessDebug
{
	// Editor console debug toggle. Kept inline intentionally so render/editor code can read the
	// same process-local flag without adding another subsystem for a game-jam effect.
	inline bool bPostProcessEnabled = true;

	inline bool IsPostProcessEnabled()
	{
		return bPostProcessEnabled;
	}

	inline void SetPostProcessEnabled(bool bEnabled)
	{
		bPostProcessEnabled = bEnabled;
	}

	inline bool TogglePostProcessEnabled()
	{
		bPostProcessEnabled = !bPostProcessEnabled;
		return bPostProcessEnabled;
	}
}

struct FPerfectDodgePostProcessState
{
	bool bEnabled = false;
	float Duration = 0.0f;
	float ElapsedTime = 0.0f;
	float Intensity = 0.0f;

	float EnterDuration = 0.16f;
	float ExitDuration = 0.25f;
	float RadialBlurStrength = 0.045f;
	float FocusFlashStrength = 0.35f;

	float BlueTintStrength = 0.28f;
	float GridIntensity = 0.0f;
	float GlitchIntensity = 0.42f;
	float VignetteIntensity = 0.72f;

	// Grid generation is disabled in the shader for now. Keep these legacy fields
	// so the constant buffer layout stays compatible with existing patches.
	float WorldGridIntensity = 0.0f;
	float WorldGridScale = 1.15f;
	float WorldGridThickness = 0.035f;
	float WorldGridDepthFadeDistance = 80.0f;

	// Time-rush 진입 시 세상이 어두워지는 느낌. GammaPower > 1이면 중간톤이 내려간다.
	float SceneDarkening = 0.42f;
	float GammaPower = 1.28f;
	float WorldGridSurfaceBias = 0.0f;
	float ScreenGridIntensity = 0.0f;

	FLinearColor BlueTintColor = FLinearColor(0.12f, 0.48f, 0.95f, 1.0f);
	FLinearColor GridColor = FLinearColor(0.2f, 0.95f, 1.0f, 1.0f); // Legacy; currently unused.
};
