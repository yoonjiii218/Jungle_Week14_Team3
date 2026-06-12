#pragma once

#include "Component/SceneComponent.h"
#include "Component/Camera/CameraRayFadeSystem.h"
#include "Core/Types/CoreTypes.h"
#include "Core/Types/CollisionTypes.h"
#include "Math/Vector.h"
#include "Math/Quat.h"
#include "Math/Rotator.h"

#include "Source/Engine/Component/Camera/SpringArmComponent.generated.h"
// ============================================================
// USpringArmComponent — 부착 액터 뒤를 부드럽게 따라가는 카메라 부착점.
//
// 사용 패턴: Pawn(Owner) → SpringArm(자식) → Camera(SpringArm 의 자식).
// SpringArm 의 World 는 매 Tick 에 부모의 World 를 따라 갱신되되, lag 옵션이
// 켜져 있으면 부드러운 보간으로 따라온다. Camera 컴포넌트는 SpringArm 의
// World 를 자동 상속하므로 별도 후크 없이 부드럽게 끌려오는 효과가 난다.
//
// 차량/플레이어 뒤를 따라오는 3인칭 카메라, 흔들림 있는 카메라 마운트 등에 사용.
// 충돌 인지(raycast) 는 별도 PR 에서 추가 — 현재는 lag 만 처리.
// UE: USpringArmComponent (간소화)
// ============================================================
UCLASS()
class USpringArmComponent : public USceneComponent
{
public:
	GENERATED_BODY()
	USpringArmComponent();
	~USpringArmComponent() override = default;

	void BeginPlay() override;
	void TickComponent(float DeltaTime, ELevelTick TickType, FActorComponentTickFunction& ThisTickFunction) override;
	// ─── 튜닝 파라미터 ─────────────────────────────────────────────
	// arm 길이 — 부착점에서 카메라까지의 거리 (Local -X 방향).
	UPROPERTY(Edit, Save, Category="SpringArm", DisplayName="Target Arm Length", Min=0.0f, Max=100000.0f, Speed=1.0f)
	float TargetArmLength = 300.0f;

	// arm 끝점(카메라 위치) 에 추가되는 offset (Lagged 회전 기준 적용).
	UPROPERTY(Edit, Save, Category="SpringArm", DisplayName="Socket Offset", Type=Vec3, Min=0.0f, Max=0.0f, Speed=0.1f)
	FVector SocketOffset = FVector(0.0f, 0.0f, 0.0f);

	// 부착점 자체에 추가되는 offset (Lagged 회전 기준 적용). 보통 머리 위/어깨 높이.
	UPROPERTY(Edit, Save, Category="SpringArm", DisplayName="Target Offset", Type=Vec3, Min=0.0f, Max=0.0f, Speed=0.1f)
	FVector TargetOffset = FVector(0.0f, 0.0f, 0.0f);

	// Lag 옵션 — 끄면 부모를 즉시 따라감 (lag 없는 부착).
	UPROPERTY(Edit, Save, Category="SpringArm", DisplayName="Enable Camera Lag")
	bool bEnableCameraLag = false;
	UPROPERTY(Edit, Save, Category="SpringArm", DisplayName="Enable Rotation Lag")
	bool bEnableCameraRotationLag = false;
	UPROPERTY(Edit, Save, Category="SpringArm", DisplayName="Camera Lag Speed", Min=0.0f, Max=1000.0f, Speed=0.1f)
	float CameraLagSpeed = 10.0f;          // 클수록 빠르게 따라옴
	UPROPERTY(Edit, Save, Category="SpringArm", DisplayName="Camera Rotation Lag Speed", Min=0.0f, Max=1000.0f, Speed=0.1f)
	float CameraRotationLagSpeed = 10.0f;
	UPROPERTY(Edit, Save, Category="SpringArm", DisplayName="Camera Lag Max Distance", Min=0.0f, Max=100000.0f, Speed=1.0f)
	float CameraLagMaxDistance = 0.0f;     // 0 = 무제한

	// Collision 옵션 — 활성화 시 부착점 → ArmEnd 사이로 ray 를 쏴서 첫 충돌점까지만 arm
	// 길이를 단축. 카메라가 벽/지형 너머로 빠지는 현상 방지. Owner Pawn 은 ignore.
	// 기본 ProbeChannel 은 UE 의 ECC_Camera 에 대응하는 Camera 채널이다. Tree/foliage처럼
	// 카메라를 막으면 안 되는 컴포넌트는 Collision Responses > Camera 를 Ignore 로 설정한다.
	// (본 엔진은 sphere sweep 미지원이라 단일 ray + ProbeSize 안전 거리로 근사한다.)
	UPROPERTY(Edit, Save, Category="SpringArm", DisplayName="Do Collision Test")
	bool bDoCollisionTest = false;
	UPROPERTY(Edit, Save, Category="SpringArm", DisplayName="Probe Channel", Enum=ECollisionChannel)
	ECollisionChannel ProbeChannel = ECollisionChannel::Camera;
	UPROPERTY(Edit, Save, Category="SpringArm", DisplayName="Probe Size", Min=0.0f, Max=100.0f, Speed=0.01f)
	float ProbeSize = 0.12f;               // hit 지점에서 ProbeSize 만큼 안쪽에 정지

	// Camera ray fade — 카메라와 플레이어 사이를 가리는 mesh들을 통째로 반투명 처리한다.
	// DoCollisionTest와 독립적인 전용 채널(CameraFade)을 기본값으로 사용해서,
	// Camera probe 는 Ignore 이지만 fade 탐지에는 Block 인 구성을 쉽게 만들 수 있다.
	// 향후 partial mask/sweep으로 확장할 진입점이다.
	UPROPERTY(Edit, Save, Category="SpringArm|Camera Occlusion", DisplayName="Enable Camera Ray Fade")
	bool bEnableCameraRayFade = false;
	UPROPERTY(Edit, Save, Category="SpringArm|Camera Occlusion", DisplayName="Camera Ray Fade Channel", Enum=ECollisionChannel)
	ECollisionChannel CameraRayFadeChannel = ECollisionChannel::CameraFade;
	UPROPERTY(Edit, Save, Category="SpringArm|Camera Occlusion", DisplayName="Camera Ray Fade Opacity", Min=0.02f, Max=1.0f, Speed=0.01f)
	float CameraRayFadeOpacity = 0.01f;
	UPROPERTY(Edit, Save, Category="SpringArm|Camera Occlusion", DisplayName="Camera Ray Fade Half Width", Min=0.0f, Max=10.0f, Speed=0.01f)
	float CameraRayFadeHalfWidth = 0.4f;
	UPROPERTY(Edit, Save, Category="SpringArm|Camera Occlusion", DisplayName="Camera Ray Fade Update Rate", Min=1.0f, Max=120.0f, Speed=1.0f)
	float CameraRayFadeUpdateRate = 30.0f;
	UPROPERTY(Edit, Save, Category="SpringArm|Camera Occlusion", DisplayName="Camera Ray Fade Movement Threshold", Min=0.0f, Max=10.0f, Speed=0.01f)
	float CameraRayFadeMovementThreshold = 0.05f;
	UPROPERTY(Edit, Save, Category="SpringArm|Camera Occlusion", DisplayName="Camera Ray Fade Idle Refresh Interval", Min=0.02f, Max=2.0f, Speed=0.01f)
	float CameraRayFadeIdleRefreshInterval = 0.25f;
	UPROPERTY(Edit, Save, Category="SpringArm|Camera Occlusion", DisplayName="Camera Ray Fade Max Hits", Min=1.0f, Max=32.0f, Speed=1.0f)
	int CameraRayFadeMaxHits = 8;
	UPROPERTY(Edit, Save, Category="SpringArm|Camera Occlusion", DisplayName="Camera Ray Fade Debug")
	bool bCameraRayFadeDebug = false;

	// Control rotation 사용 옵션 (UE 패턴). true 면 부모 (capsule) 의 world rotation 대신
	// owner APawn 의 ControlRotation 을 desired rotation 으로 사용 — mouse look 이 capsule
	// 회전 안 건드리고 카메라만 움직이는 ThirdPerson 패턴.
	// bInheritPitch/Yaw/Roll 가 각 axis 별로 — false 면 그 axis 는 capsule rotation 사용.
	bool bUsePawnControlRotation = true;
	bool bInheritPitch           = true;
	bool bInheritYaw             = true;
	bool bInheritRoll            = false;

	// Arm 방향 오프셋 — 에디터에서 설정한 SpringArm RelativeRotation (Tick 이 덮어쓰기 전 값).
	UPROPERTY(Edit, Save, Category="SpringArm", DisplayName="Arm Pivot Rotation", Type=Vec3, Min=0.0f, Max=0.0f, Speed=0.1f)
	FRotator ArmPivotRotation = FRotator::ZeroRotator;

private:
	// 매 Tick 에 갱신되는 보간 상태 — 부착점 (parent + TargetOffset) 위치/회전.
	FVector LaggedAttachLoc = FVector(0.0f, 0.0f, 0.0f);
	FQuat LaggedAttachRot;
	bool bHasPreviousState = false;

	FCameraRayFadeState CameraRayFadeState;
	float CameraRayFadeTimeSinceQuery = 0.0f;
	FVector LastCameraRayFadeCameraWorld = FVector::ZeroVector;
	FVector LastCameraRayFadeTargetWorld = FVector::ZeroVector;
	bool bHasCameraRayFadeQuery = false;
	uint32 CameraRayFadeQueryCount = 0;

	void UpdateCameraRayFade(float DeltaTime, const FVector& CameraWorld, const FVector& TargetWorld);
	void ClearCameraRayFade();
};
