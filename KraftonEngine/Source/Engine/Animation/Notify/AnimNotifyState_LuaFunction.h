#pragma once

#include "Animation/Notify/AnimNotifyState.h"
#include "Core/Types/CoreTypes.h"
#include "Object/Ptr/SoftObjectPtr.h"
#include "Object/Ptr/WeakObjectPtr.h"

class UParticleSystemComponent;

#include "Source/Engine/Animation/Notify/AnimNotifyState_LuaFunction.generated.h"

UCLASS()
class UAnimNotifyState_LuaFunction : public UAnimNotifyState
{
public:
	GENERATED_BODY()
	UAnimNotifyState_LuaFunction() = default;
	~UAnimNotifyState_LuaFunction() override = default;

	UPROPERTY(Edit, Save, Category="LuaFunction", DisplayName="Begin Function")
	FString BeginFunctionName;

	UPROPERTY(Edit, Save, Category="LuaFunction", DisplayName="End Function")
	FString EndFunctionName;

	void NotifyBegin(USkeletalMeshComponent* MeshComp, UAnimSequenceBase* Anim, float TotalDuration) override;
	void NotifyEnd(USkeletalMeshComponent* MeshComp, UAnimSequenceBase* Anim) override;
};

UCLASS()
class UAnimNotifyState_ComboWindow : public UAnimNotifyState_LuaFunction
{
public:
	GENERATED_BODY()
	UAnimNotifyState_ComboWindow();
	~UAnimNotifyState_ComboWindow() override = default;
};

UCLASS()
class UAnimNotifyState_DashVanish : public UAnimNotifyState_LuaFunction
{
public:
	GENERATED_BODY()
	UAnimNotifyState_DashVanish();
	~UAnimNotifyState_DashVanish() override = default;

	UPROPERTY(Edit, Save, Category="DashVanish", DisplayName="Hide Preview Mesh")
	bool bHidePreviewMesh = true;

	void NotifyBegin(USkeletalMeshComponent* MeshComp, UAnimSequenceBase* Anim, float TotalDuration) override;
	void NotifyEnd(USkeletalMeshComponent* MeshComp, UAnimSequenceBase* Anim) override;
};

UCLASS()
class UAnimNotifyState_Trail : public UAnimNotifyState_LuaFunction
{
public:
	GENERATED_BODY()
	UAnimNotifyState_Trail();
	~UAnimNotifyState_Trail() override = default;

	UPROPERTY(Edit, Save, Category="Trail", DisplayName="Preview Particle System", AssetType="UParticleSystem")
	FSoftObjectPtr PreviewParticleSystemPath = "Content/Data/SwordTrail2.uasset";

	void NotifyBegin(USkeletalMeshComponent* MeshComp, UAnimSequenceBase* Anim, float TotalDuration) override;
	void NotifyEnd(USkeletalMeshComponent* MeshComp, UAnimSequenceBase* Anim) override;

private:
	UParticleSystemComponent* GetOrCreatePreviewTrail(USkeletalMeshComponent* MeshComp);

	TMap<USkeletalMeshComponent*, TWeakObjectPtr<UParticleSystemComponent>> PreviewTrailsByMesh;
};
