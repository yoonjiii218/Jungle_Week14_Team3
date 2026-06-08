#pragma once

#include "Component/ActorComponent.h"
#include "Math/Vector.h"

#include "Source/Engine/Component/Input/ActionComponent.generated.h"
class USceneComponent;

UCLASS()
class UActionComponent : public UActorComponent
{
public:
	GENERATED_BODY()
	UActionComponent() = default;
	~UActionComponent() override = default;

	void BeginPlay() override;
	void EndPlay() override;
	void BeginDestroy() override;
	void TickComponent(float DeltaTime, ELevelTick TickType, FActorComponentTickFunction& ThisTickFunction) override;

	void HitStop(float Duration, float TimeDilation);
	void LocalHitStop(float Duration);
	void HitSquash(const FVector& SquashedScale, float SquashInDuration, float RecoverDuration);
	void HitSquashComponent(USceneComponent* TargetComponent, const FVector& SquashedScale, float SquashInDuration, float RecoverDuration);
	void HitSquashComponentByMultiplier(USceneComponent* TargetComponent, const FVector& ScaleMultiplier, float SquashInDuration, float RecoverDuration);
	void HitShakeComponent(USceneComponent* TargetComponent, float Amplitude, float Duration, float Frequency);
	void Knockback(const FVector& Direction, float Distance, float Duration);
	void Slomo(float Duration, float TimeDilation);
	void TimeRush(float Duration, float WorldTimeDilation, float PlayerSpeedScale);

	void StopHitStop();
	void StopLocalHitStop();
	void StopHitSquash();
	void StopHitShake();
	void StopKnockback();
	void StopSlomo();
	void StopTimeRush();
	void StopAllActions();

	// 넉백 면역. true 면 Knockback() 호출이 무시된다. (예: 보스는 넉백을 받지 않음)
	void SetKnockbackImmune(bool bImmune) { bKnockbackImmune = bImmune; }
	bool IsKnockbackImmune() const { return bKnockbackImmune; }

private:
	float GetRawDeltaTime(float FallbackDeltaTime) const;
	USceneComponent* GetTargetSceneComponent() const;
	float GetDesiredGlobalTimeDilation() const;
	void RequestDesiredGlobalTimeDilation() const;
	void CaptureOwnerCustomTimeDilationBase();
	void RebuildOwnerCustomTimeDilation();
	float GetTimeRushOwnerCustomTimeDilationScale() const;
	bool HasActiveOwnerCustomTimeDilationLayer() const;

	struct FTimedDilationAction
	{
		bool bActive = false;
		float Duration = 0.0f;
		float RemainingTime = 0.0f;
		float TimeDilation = 1.0f;
	};

	struct FHitSquashAction
	{
		bool bActive = false;
		float SquashInDuration = 0.0f;
		float RecoverDuration = 0.0f;
		float ElapsedTime = 0.0f;
		FVector StartScale = FVector::OneVector;
		FVector SquashedScale = FVector::OneVector;
		USceneComponent* TargetComponent = nullptr;
	};

	struct FHitShakeAction
	{
		bool bActive = false;
		float Duration = 0.0f;
		float ElapsedTime = 0.0f;
		float Amplitude = 0.0f;
		float Frequency = 45.0f;
		FVector BaseRelativeLocation = FVector::ZeroVector;
		USceneComponent* TargetComponent = nullptr;
	};

	struct FLocalHitStopAction
	{
		bool bActive = false;
		float Duration = 0.0f;
		float RemainingTime = 0.0f;
		float PreviousCustomTimeDilation = 1.0f;
	};

	struct FKnockbackAction
	{
		bool bActive = false;
		float Duration = 0.0f;
		float RemainingTime = 0.0f;
		FVector RemainingOffset = FVector::ZeroVector;
	};

	bool HasActiveTimeDilationAction(const FTimedDilationAction& Action) const;
	bool HasActiveTimeDilation() const;

	FTimedDilationAction HitStopAction;
	FTimedDilationAction SlomoAction;
	FTimedDilationAction TimeRushAction;
	float TimeRushPlayerSpeedScale = 1.0f;
	float OwnerCustomTimeDilationBase = 1.0f;
	bool bHasOwnerCustomTimeDilationBase = false;
	FHitSquashAction HitSquashAction;
	FHitShakeAction HitShakeAction;
	FLocalHitStopAction LocalHitStopAction;
	FKnockbackAction KnockbackAction;

	bool bKnockbackImmune = false;
};
