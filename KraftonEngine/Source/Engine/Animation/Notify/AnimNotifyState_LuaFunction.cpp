#include "AnimNotifyState_LuaFunction.h"

#include "Animation/Instance/LuaAnimInstance.h"
#include "Component/Primitive/ParticleSystemComponent.h"
#include "Component/Primitive/SkeletalMeshComponent.h"
#include "Core/Logging/Log.h"
#include "GameFramework/AActor.h"
#include "GameFramework/World.h"
#include "Object/Reflection/UClass.h"
#include "Particles/ParticleSystem.h"
#include "Particles/ParticleSystemManager.h"

namespace
{
	constexpr const char* DefaultPreviewTrailPath = "Content/Data/SwordTrail2.uasset";

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

UAnimNotifyState_DashVanish::UAnimNotifyState_DashVanish()
{
	BeginFunctionName = "on_dash_vanish_begin";
	EndFunctionName = "on_dash_vanish_end";
}

void UAnimNotifyState_DashVanish::NotifyBegin(USkeletalMeshComponent* MeshComp, UAnimSequenceBase* Anim, float TotalDuration)
{
	UAnimNotifyState_LuaFunction::NotifyBegin(MeshComp, Anim, TotalDuration);

	if (bHidePreviewMesh && IsValid(MeshComp))
	{
		if (UWorld* World = MeshComp->GetWorld())
		{
			if (World->GetWorldType() == EWorldType::EditorPreview)
			{
				MeshComp->SetVisibility(false);
			}
		}
	}
}

void UAnimNotifyState_DashVanish::NotifyEnd(USkeletalMeshComponent* MeshComp, UAnimSequenceBase* Anim)
{
	UAnimNotifyState_LuaFunction::NotifyEnd(MeshComp, Anim);

	if (bHidePreviewMesh && IsValid(MeshComp))
	{
		if (UWorld* World = MeshComp->GetWorld())
		{
			if (World->GetWorldType() == EWorldType::EditorPreview)
			{
				MeshComp->SetVisibility(true);
			}
		}
	}
}

UAnimNotifyState_Trail::UAnimNotifyState_Trail()
{
	BeginFunctionName = "on_trail_activate";
	EndFunctionName = "on_trail_deactivate";
}

void UAnimNotifyState_Trail::NotifyBegin(USkeletalMeshComponent* MeshComp, UAnimSequenceBase* Anim, float TotalDuration)
{
	UAnimNotifyState_LuaFunction::NotifyBegin(MeshComp, Anim, TotalDuration);

	UParticleSystemComponent* PreviewTrail = GetOrCreatePreviewTrail(MeshComp);
	if (IsValid(PreviewTrail))
	{
		PreviewTrail->Activate();
	}
}

void UAnimNotifyState_Trail::NotifyEnd(USkeletalMeshComponent* MeshComp, UAnimSequenceBase* Anim)
{
	UAnimNotifyState_LuaFunction::NotifyEnd(MeshComp, Anim);

	if (!MeshComp)
	{
		return;
	}

	auto It = PreviewTrailsByMesh.find(MeshComp);
	if (It == PreviewTrailsByMesh.end())
	{
		return;
	}

	if (UParticleSystemComponent* PreviewTrail = It->second.Get())
	{
		PreviewTrail->Deactivate();
	}
	else
	{
		PreviewTrailsByMesh.erase(It);
	}
}

UParticleSystemComponent* UAnimNotifyState_Trail::GetOrCreatePreviewTrail(USkeletalMeshComponent* MeshComp)
{
	if (!IsValid(MeshComp))
	{
		return nullptr;
	}

	UWorld* World = MeshComp->GetWorld();
	if (!World || World->GetWorldType() != EWorldType::EditorPreview)
	{
		return nullptr;
	}

	if (UParticleSystemComponent* Existing = PreviewTrailsByMesh[MeshComp].Get())
	{
		return Existing;
	}

	FString Path = PreviewParticleSystemPath.ToString();
	if (Path.empty() || Path == "None")
	{
		Path = DefaultPreviewTrailPath;
	}

	UParticleSystem* Template = FParticleSystemManager::Get().Load(Path);
	if (!Template)
	{
		UE_LOG("[AnimNotifyState_Trail] Load preview particle failed: %s", Path.c_str());
		return nullptr;
	}

	UClass* ActorClass = UClass::FindByName("AActor");
	if (!ActorClass)
	{
		return nullptr;
	}

	AActor* TrailActor = World->SpawnActorByClass(ActorClass);
	if (!TrailActor)
	{
		return nullptr;
	}
	TrailActor->bTickInEditor = true;

	UParticleSystemComponent* PreviewTrail = TrailActor->AddComponent<UParticleSystemComponent>();
	if (!PreviewTrail)
	{
		World->DestroyActor(TrailActor);
		return nullptr;
	}

	TrailActor->SetRootComponent(PreviewTrail);
	PreviewTrail->SetHiddenInComponentTree(true);
	PreviewTrail->SetAnimTrailSourceComponent(MeshComp);
	PreviewTrail->SetTemplate(Template);
	PreviewTrailsByMesh[MeshComp] = PreviewTrail;
	return PreviewTrail;
}
