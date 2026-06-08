#pragma once

#include "Animation/Notify/AnimNotify.h"
#include "Core/Types/CoreTypes.h"
#include "Math/Vector.h"

#include "Source/Engine/Animation/Notify/AnimNotify_SpawnFlyingSlash.generated.h"

UCLASS()
class UAnimNotify_SpawnFlyingSlash : public UAnimNotify
{
public:
	GENERATED_BODY()
	UAnimNotify_SpawnFlyingSlash() = default;
	~UAnimNotify_SpawnFlyingSlash() override = default;

	UPROPERTY(Edit, Save, Category="SpawnFlyingSlash", DisplayName="Attack Id")
	FString AttackId = "PlayerFlyingSlash";

	UPROPERTY(Edit, Save, Category="SpawnFlyingSlash", DisplayName="Translation Offset")
	FVector TranslationOffset = FVector::ZeroVector;

	UPROPERTY(Edit, Save, Category="SpawnFlyingSlash", DisplayName="Rotation Offset")
	FVector RotationOffset = FVector::ZeroVector;

	UPROPERTY(Edit, Save, Category="SpawnFlyingSlash", DisplayName="Scale")
	FVector Scale = FVector::OneVector;

	UPROPERTY(Edit, Save, Category="SpawnFlyingSlash", DisplayName="Flatten Direction")
	bool bFlattenDirection = true;

	void Notify(USkeletalMeshComponent* MeshComp, UAnimSequenceBase* Anim) override;
};
