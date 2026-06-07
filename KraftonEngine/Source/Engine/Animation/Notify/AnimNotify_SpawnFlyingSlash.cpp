#include "AnimNotify_SpawnFlyingSlash.h"

#include "Animation/Instance/LuaAnimInstance.h"
#include "Component/Primitive/SkeletalMeshComponent.h"

void UAnimNotify_SpawnFlyingSlash::Notify(USkeletalMeshComponent* MeshComp, UAnimSequenceBase* /*Anim*/)
{
	if (!MeshComp)
	{
		return;
	}

	if (ULuaAnimInstance* LuaAnim = Cast<ULuaAnimInstance>(MeshComp->GetAnimInstance()))
	{
		LuaAnim->DispatchSpawnFlyingSlashNotify(
			AttackId,
			TranslationOffset,
			RotationOffset,
			Scale,
			bFlattenDirection
		);
	}
}
