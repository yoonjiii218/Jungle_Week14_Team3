#pragma once

#include "Animation/Notify/AnimNotify.h"
#include "Core/Types/CoreTypes.h"
#include "Math/Vector.h"
#include "Object/FName.h"

#include "Source/Engine/Animation/Notify/AnimNotify_SpawnSubUV.generated.h"

// Spawns a one-shot SubUV actor when the animation reaches this notify.
// PositionOffset uses owner-local axes: X=forward, Y=right, Z=world up.
UCLASS()
class UAnimNotify_SpawnSubUV : public UAnimNotify
{
public:
	GENERATED_BODY()
	UAnimNotify_SpawnSubUV() = default;
	~UAnimNotify_SpawnSubUV() override = default;

	UPROPERTY(Edit, Save, Category="SpawnSubUV", DisplayName="Resource", AssetType="Particle")
	FName Resource = FName("SlashTexture");

	UPROPERTY(Edit, Save, Category="SpawnSubUV", DisplayName="Socket Name")
	FString SocketName;

	UPROPERTY(Edit, Save, Category="SpawnSubUV", DisplayName="Position Offset")
	FVector PositionOffset = FVector::ZeroVector;

	UPROPERTY(Edit, Save, Category="SpawnSubUV", DisplayName="Scale")
	FVector Scale = FVector::OneVector;

	UPROPERTY(Edit, Save, Category="SpawnSubUV", DisplayName="Sprite Roll", Min=-360.0f, Max=360.0f, Speed=1.0f)
	float SpriteRoll = 0.0f;

	UPROPERTY(Edit, Save, Category="SpawnSubUV", DisplayName="Frame Rate", Min=1.0f, Max=120.0f, Speed=1.0f)
	float FrameRate = 15.0f;

	UPROPERTY(Edit, Save, Category="SpawnSubUV", DisplayName="Loop")
	bool bLoop = false;

	UPROPERTY(Edit, Save, Category="SpawnSubUV", DisplayName="Auto Destroy")
	bool bAutoDestroy = true;

	void Notify(USkeletalMeshComponent* MeshComp, UAnimSequenceBase* Anim) override;
};
