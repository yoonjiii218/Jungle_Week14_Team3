#pragma once

#include "Animation/Notify/AnimNotify.h"
#include "Core/Types/CoreTypes.h"

#include "Source/Engine/Animation/Notify/AnimNotify_LuaFunction.generated.h"

UCLASS()
class UAnimNotify_LuaFunction : public UAnimNotify
{
public:
	GENERATED_BODY()
	UAnimNotify_LuaFunction() = default;
	~UAnimNotify_LuaFunction() override = default;

	UPROPERTY(Edit, Save, Category="LuaFunction", DisplayName="Function Name")
	FString FunctionName;

	void Notify(USkeletalMeshComponent* MeshComp, UAnimSequenceBase* Anim) override;
};

UCLASS()
class UAnimNotify_AttackEnd : public UAnimNotify_LuaFunction
{
public:
	GENERATED_BODY()
	UAnimNotify_AttackEnd();
	~UAnimNotify_AttackEnd() override = default;
};
