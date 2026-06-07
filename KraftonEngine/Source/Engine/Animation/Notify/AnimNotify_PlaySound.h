#pragma once

#include "Animation/Notify/AnimNotify.h"
#include "Core/Types/CoreTypes.h"
#include "Math/Vector.h"
#include "Object/Ptr/SoftObjectPtr.h"

// 사운드 1회 재생 instant notify. 발자국 / 무기 swing / impact 같은 단발성 트리거에 사용.
//   - SoundPath 는 Content/Audio 하위 상대 경로 (예: "footstep_grass.wav").
//   - Volume / Pitch 는 UPROPERTY(Edit, Save) — Notify Properties 패널에서 편집 + .uasset round-trip.
//   - 첫 트리거 시 AudioManager 에 자동 LoadAudio (캐시 키 = "AnimNotify:" + path), 이후 PlayAudio.
//   - AudioManager 미초기화 (예: 에디터 비-PIE) 시 LoadAudio/PlayAudio 가 early-out → 무영향.

#include "Source/Engine/Animation/Notify/AnimNotify_PlaySound.generated.h"

UCLASS()
class UAnimNotify_PlaySound : public UAnimNotify
{
public:
	GENERATED_BODY()
	UAnimNotify_PlaySound() = default;
	~UAnimNotify_PlaySound() override = default;

	UPROPERTY(Edit, Save, Category="PlaySound", DisplayName="Sound Path", AssetType="Audio")
	FString SoundPath;

	UPROPERTY(Edit, Save, Category="PlaySound", DisplayName="Volume")
	float Volume = 1.0f;

	void Notify(USkeletalMeshComponent* MeshComp, UAnimSequenceBase* Anim) override;
};

UCLASS()
class UAnimNotify_PlayParticle : public UAnimNotify
{
public:
	GENERATED_BODY()
	UAnimNotify_PlayParticle() = default;
	~UAnimNotify_PlayParticle() override = default;

	UPROPERTY(Edit, Save, Category="PlayParticle", DisplayName="Particle System", AssetType="UParticleSystem")
	FSoftObjectPtr ParticleSystemPath = "None";

	UPROPERTY(Edit, Save, Category="PlayParticle", DisplayName="Socket Name", AssetType="Socket")
	FString SocketName;

	UPROPERTY(Edit, Save, Category="PlayParticle", DisplayName="Follow Socket")
	bool bFollowSocket = false;

	UPROPERTY(Edit, Save, Category="PlayParticle", DisplayName="Use Socket Rotation")
	bool bUseSocketRotation = false;

	UPROPERTY(Edit, Save, Category="PlayParticle", DisplayName="Use Character Rotation")
	bool bUseCharacterRotation = true;

	UPROPERTY(Edit, Save, Category="PlayParticle", DisplayName="Location Offset")
	FVector LocationOffset = FVector::ZeroVector;

	UPROPERTY(Edit, Save, Category="PlayParticle", DisplayName="Rotation Offset")
	FVector RotationOffset = FVector::ZeroVector;

	UPROPERTY(Edit, Save, Category="PlayParticle", DisplayName="Scale")
	FVector Scale = FVector::OneVector;

	UPROPERTY(Edit, Save, Category="PlayParticle", DisplayName="Auto Destroy After", Min=0.0f, Max=10.0f, Speed=0.1f)
	float AutoDestroyAfter = 1.0f;

	void Notify(USkeletalMeshComponent* MeshComp, UAnimSequenceBase* Anim) override;
};
