#include "Component/Camera/CameraComponent.h"
#include "Component/Camera/CineCameraComponent.h"
#include "Object/Reflection/ObjectFactory.h"
#include "GameFramework/AActor.h"
#include "GameFramework/World.h"
#include "GameFramework/GameMode/PlayerController.h"
#include "GameFramework/Camera/PlayerCameraManager.h"
#include "Render/Types/MinimalViewInfo.h"
#include <cmath>

void UCameraComponent::BeginPlay()
{
	Super::BeginPlay();

	// E.2/3: PC 가 BeginPlay 시점엔 아직 spawn 전 → PlayerCameraManager nullptr.
	// PC 의 BeginPlay 에서 World 의 모든 카메라 컴포넌트를 catch up 등록하므로 안전.
	if (UWorld* World = GetWorld())
	{
		if (APlayerController* PC = World->GetFirstPlayerController())
		{
			if (APlayerCameraManager* CM = PC->GetPlayerCameraManager())
			{
				CM->RegisterCamera(this);
			}
		}
	}
}

void UCameraComponent::EndPlay()
{
	Super::EndPlay();
	if (UWorld* World = GetWorld())
	{
		if (APlayerController* PC = World->GetFirstPlayerController())
		{
			if (APlayerCameraManager* CM = PC->GetPlayerCameraManager())
			{
				CM->UnregisterCamera(this);
			}
		}
	}
}

void UCameraComponent::LookAt(const FVector& Target)
{
	FVector Position = GetWorldLocation();
	FVector Diff = (Target - Position).Normalized();

	constexpr float Rad2Deg = 180.0f / 3.14159265358979f;

	FRotator LookRotation = GetRelativeRotation();
	LookRotation.Pitch = -asinf(Diff.Z) * Rad2Deg;

	if (fabsf(Diff.Z) < 0.999f) {
		LookRotation.Yaw = atan2f(Diff.Y, Diff.X) * Rad2Deg;
	}

	SetRelativeRotation(LookRotation);
}

void UCameraComponent::OnResize(int32 Width, int32 Height)
{
	CameraState.AspectRatio = static_cast<float>(Width) / static_cast<float>(Height);
}

void UCameraComponent::SetCameraState(const FCameraState& NewState)
{
	CameraState = NewState;
}

void UCameraComponent::GetCameraView(float /*DeltaTime*/, FMinimalViewInfo& OutPOV) const
{
	UpdateWorldMatrix();
	OutPOV.Location    = GetWorldLocation();
	OutPOV.Rotation    = GetWorldMatrix().ToRotator();
	OutPOV.FOV         = CameraState.FOV;
	OutPOV.AspectRatio = CameraState.AspectRatio;
	OutPOV.OrthoWidth  = CameraState.OrthoWidth;
	OutPOV.NearClip    = CameraState.NearZ;
	OutPOV.FarClip     = CameraState.FarZ;
	OutPOV.bIsOrtho    = CameraState.bIsOrthogonal;

	const UCineCameraComponent* CineCamera = Cast<UCineCameraComponent>(const_cast<UCameraComponent*>(this));
	if (CineCamera)
	{
		const FCineDepthOfFieldSettings& DepthOfField = CineCamera->GetDepthOfFieldSettings();
		const float SensorHeight = 24.0f;
		OutPOV.FOV = 2.0f * atanf((SensorHeight * 0.5f) / DepthOfField.FocalLength);
	}
}

bool UCameraComponent::ProjectWorldToScreen(const FVector& WorldPosition, FVector& OutScreenPosition, float ScreenWidth, float ScreenHeight) const
{
	FMinimalViewInfo POV;
	GetCameraView(0.0f, POV);

	FMatrix ViewProj = POV.CalculateViewProjectionMatrix();

	// W 성분을 계산하여 카메라 뒤에 있는지 판단 (Perspective LH 기준 W는 뷰공간 Z와 대략 동일)
	float W = WorldPosition.X * ViewProj.M[0][3] + WorldPosition.Y * ViewProj.M[1][3] + WorldPosition.Z * ViewProj.M[2][3] + ViewProj.M[3][3];

	if (W <= POV.NearClip)
	{
		return false;
	}

	FVector Ndc = ViewProj.TransformPositionWithW(WorldPosition);

	float ScreenX = (Ndc.X * 0.5f + 0.5f) * ScreenWidth;
	float ScreenY = (1.0f - (Ndc.Y * 0.5f + 0.5f)) * ScreenHeight;

	OutScreenPosition.X = ScreenX;
	OutScreenPosition.Y = ScreenY;
	OutScreenPosition.Z = Ndc.Z;

	return true;
}
