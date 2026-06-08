#pragma once

#include "AnimNotifyState.h"
#include "Core/Delegate.h"
#include "Core/Types/CollisionTypes.h"
#include "Core/Types/CoreTypes.h"
#include "Math/Vector.h"
#include "Object/Ptr/WeakObjectPtr.h"

#include "Source/Engine/Animation/Notify/AnimNotifyState_AttackHitWindow.generated.h"

class AActor;
class UBoxComponent;
class UPrimitiveComponent;
class USkeletalMeshComponent;

// 히트 시 대상에게 줄 충격 방향. UActionComponent::Knockback 의 Direction 인자로 사용.
UENUM()
enum class EAttackKnockbackMode : uint8
{
	Forward,            // 공격자(attacker) 의 forward 방향 — "앞으로 밀기"
	Up,                 // world up — "위로 띄우기" (launcher)
	AwayFromAttacker,   // attacker→target 의 수평 방향 (다양한 위치에서 자연스럽게 멀어짐)
};

inline const char* GAttackKnockbackModeNames[] = {
	"Forward",
	"Up",
	"AwayFromAttacker",
};
inline constexpr uint32 GAttackKnockbackModeCount = sizeof(GAttackKnockbackModeNames) / sizeof(GAttackKnockbackModeNames[0]);

UCLASS()
class UAnimNotifyState_AttackHitWindow : public UAnimNotifyState
{
public:
	GENERATED_BODY()
	UAnimNotifyState_AttackHitWindow() = default;
	~UAnimNotifyState_AttackHitWindow() override = default;

	UPROPERTY(Edit, Save, Category="AttackHitWindow", DisplayName="Bone Name")
	FString BoneName = "Bip001 R Hand";

	UPROPERTY(Edit, Save, Category="AttackHitWindow", DisplayName="Local Offset")
	FVector LocalOffset = FVector(25.0f, 0.0f, 0.0f);

	UPROPERTY(Edit, Save, Category="AttackHitWindow", DisplayName="Radius", Min=1.0f, Max=1000.0f, Speed=1.0f)
	float Radius = 60.0f;

	UPROPERTY(Edit, Save, Category="AttackHitWindow", DisplayName="Hit Stop Duration", Min=0.0f, Max=1.0f, Speed=0.01f)
	float HitStopDuration = 0.08f;

	// Number of damage applications after this window detects a target once.
	// Keep these edit-only, not Save, because old AnimSequence packages serialize
	// notify-state payloads as a raw property stream. Adding new saved fields here
	// changes that stream layout and can make existing attack animations fail to load.
	// Persistent per-attack defaults live in PlayerConfig.Combat.AttackHitCounts / Intervals.
	UPROPERTY(Edit, Category="AttackHitWindow", DisplayName="Hit Count", Min=1.0f, Max=20.0f, Speed=1.0f)
	int32 HitCount = 1;

	UPROPERTY(Edit, Category="AttackHitWindow", DisplayName="Hit Interval", Min=0.0f, Max=1.0f, Speed=0.01f)
	float HitInterval = 0.06f;

	UPROPERTY(Edit, Save, Category="AttackHitWindow", DisplayName="Apply Knockback")
	bool bApplyKnockback = false;

	UPROPERTY(Edit, Save, Category="AttackHitWindow", DisplayName="Knockback Mode", Enum=EAttackKnockbackMode)
	EAttackKnockbackMode KnockbackMode = EAttackKnockbackMode::Forward;

	UPROPERTY(Edit, Save, Category="AttackHitWindow", DisplayName="Knockback Distance", Min=0.0f, Max=100.0f, Speed=0.1f)
	float KnockbackDistance = 5.0f;

	UPROPERTY(Edit, Save, Category="AttackHitWindow", DisplayName="Knockback Duration", Min=0.0f, Max=2.0f, Speed=0.01f)
	float KnockbackDuration = 0.25f;

	UPROPERTY(Edit, Save, Category="AttackHitWindow", DisplayName="Draw Debug Hit Window")
	bool bDrawDebugHitWindow = true;

	UPROPERTY(Edit, Save, Category="AttackHitWindow", DisplayName="Debug Draw Duration", Min=0.0f, Max=1.0f, Speed=0.01f)
	float DebugDrawDuration = 0.05f;

	UPROPERTY(Edit, Save, Category="AttackHitWindow", DisplayName="Debug Draw Segments", Min=4.0f, Max=64.0f, Speed=1.0f)
	int32 DebugDrawSegments = 24;

	UPROPERTY(Edit, Save, Category="AttackHitWindow", DisplayName="Draw Debug Target Bounds")
	bool bDrawDebugTargetBounds = true;

	UPROPERTY(Edit, Save, Category="AttackHitWindow", DisplayName="Require Query Collision")
	bool bRequireQueryCollision = false;

	UPROPERTY(Edit, Save, Category="AttackHitWindow", DisplayName="Hit World Static")
	bool bHitWorldStatic = true;

	UPROPERTY(Edit, Save, Category="AttackHitWindow", DisplayName="Auto Add Action Component")
	bool bAutoAddActionComponent = true;

	UPROPERTY(Edit, Save, Category="AttackHitWindow", DisplayName="Require Target Actor Tag")
	bool bRequireTargetActorTag = true;

	UPROPERTY(Edit, Save, Category="AttackHitWindow", DisplayName="Target Actor Tag")
	FString TargetActorTag = "HitTarget";

	UPROPERTY(Edit, Save, Category="AttackHitWindow", DisplayName="Lua Hit Function")
	FString HitFunctionName = "on_attack_hit";

	UPROPERTY(Edit, Save, Category="AttackHitWindow", DisplayName="Log Hits")
	bool bLogHits = true;

	UPROPERTY(Edit, Save, Category="AttackHitWindow", DisplayName="Log Misses")
	bool bLogMisses = true;

	void NotifyBegin(USkeletalMeshComponent* MeshComp, UAnimSequenceBase* Anim, float TotalDuration) override;
	void NotifyTick(USkeletalMeshComponent* MeshComp, UAnimSequenceBase* Anim, float FrameDeltaTime) override;
	void NotifyEnd(USkeletalMeshComponent* MeshComp, UAnimSequenceBase* Anim) override;

private:
	struct FActiveHitWindow
	{
		TSet<AActor*> HitActors;
		int32 WindowSerial = 0;
	};

	void ProcessHit(USkeletalMeshComponent* MeshComp, UBoxComponent* HitBox, AActor* OtherActor, UPrimitiveComponent* OtherComp);

	UBoxComponent* GetOrCreateHitBox(USkeletalMeshComponent* MeshComp);
	void UpdateHitBoxTransform(USkeletalMeshComponent* MeshComp, UBoxComponent* HitBox) const;
	void DisableHitBox(USkeletalMeshComponent* MeshComp);

	TMap<USkeletalMeshComponent*, TWeakObjectPtr<UBoxComponent>> HitBoxesByMesh;
	TMap<USkeletalMeshComponent*, FActiveHitWindow> ActiveWindowsByMesh;
	int32 NextHitWindowSerial = 0;
};
