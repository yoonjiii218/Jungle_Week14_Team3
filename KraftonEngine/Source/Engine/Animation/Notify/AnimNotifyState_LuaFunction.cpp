#include "AnimNotifyState_LuaFunction.h"

#include "Animation/Instance/LuaAnimInstance.h"
#include "Component/Primitive/SkeletalMeshComponent.h"

namespace
{
	void InvokeLuaAnimFunction(USkeletalMeshComponent* MeshComp, const FString& FunctionName)
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
}

void UAnimNotifyState_LuaFunction::NotifyBegin(USkeletalMeshComponent* MeshComp, UAnimSequenceBase* /*Anim*/, float /*TotalDuration*/)
{
	InvokeLuaAnimFunction(MeshComp, BeginFunctionName);
}

void UAnimNotifyState_LuaFunction::NotifyEnd(USkeletalMeshComponent* MeshComp, UAnimSequenceBase* /*Anim*/)
{
	InvokeLuaAnimFunction(MeshComp, EndFunctionName);
}

UAnimNotifyState_ComboWindow::UAnimNotifyState_ComboWindow()
{
	BeginFunctionName = "on_combo_window_open";
	EndFunctionName = "on_combo_window_close";
}

UAnimNotifyState_Trail::UAnimNotifyState_Trail()
{
	BeginFunctionName = "on_trail_activate";
	EndFunctionName = "on_trail_deactivate";
}
