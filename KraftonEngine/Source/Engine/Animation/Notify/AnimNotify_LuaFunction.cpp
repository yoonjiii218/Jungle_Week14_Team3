#include "AnimNotify_LuaFunction.h"

#include "Animation/Instance/LuaAnimInstance.h"
#include "Component/Primitive/SkeletalMeshComponent.h"

void UAnimNotify_LuaFunction::Notify(USkeletalMeshComponent* MeshComp, UAnimSequenceBase* /*Anim*/)
{
	if (!MeshComp || FunctionName.empty())
	{
		return;
	}

	if (ULuaAnimInstance* LuaAnim = Cast<ULuaAnimInstance>(MeshComp->GetAnimInstance()))
	{
		LuaAnim->InvokeLuaFunction(FunctionName);
	}
}

UAnimNotify_AttackEnd::UAnimNotify_AttackEnd()
{
	FunctionName = "on_attack_end";
}
