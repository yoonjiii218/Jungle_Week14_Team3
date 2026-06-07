#include "AnimNotify_SpawnSubUV.h"

#include <algorithm>
#include <cstring>

#include "Component/Primitive/SkeletalMeshComponent.h"
#include "Component/Primitive/SubUVComponent.h"
#include "Core/Logging/Log.h"
#include "GameFramework/AActor.h"
#include "GameFramework/World.h"
#include "Object/Reflection/UClass.h"
#include "Resource/ResourceManager.h"

void UAnimNotify_SpawnSubUV::Notify(USkeletalMeshComponent* MeshComp, UAnimSequenceBase* /*Anim*/)
{
	if (!MeshComp || Resource.IsNone())
	{
		return;
	}

	if (!FResourceManager::Get().FindParticle(Resource))
	{
		UE_LOG("[AnimNotify_SpawnSubUV] Particle resource not found: %s", Resource.ToString().c_str());
		return;
	}

	UWorld* World = MeshComp->GetWorld();
	if (!World)
	{
		return;
	}

	AActor* Owner = MeshComp->GetOwner();
	FVector Origin = MeshComp->GetWorldLocation();
	if (!SocketName.empty())
	{
		Origin = MeshComp->GetSocketTransform(FName(SocketName)).Location;
	}
	else if (Owner)
	{
		Origin = Owner->GetActorLocation();
	}

	const FVector Forward = Owner ? Owner->GetActorForward() : MeshComp->GetForwardVector();
	const FVector Right = Owner ? Owner->GetActorRight() : MeshComp->GetRightVector();
	const FVector SpawnLocation =
		Origin
		+ Forward * PositionOffset.X
		+ Right * PositionOffset.Y
		+ FVector::UpVector * PositionOffset.Z;

	UClass* ActorClass = UClass::FindByName("AActor");
	if (!ActorClass)
	{
		return;
	}

	AActor* SubUVActor = World->SpawnActorByClass(ActorClass);
	if (!SubUVActor)
	{
		return;
	}

	USubUVComponent* SubUV = SubUVActor->AddComponent<USubUVComponent>();
	if (!SubUV)
	{
		World->DestroyActor(SubUVActor);
		return;
	}

	SubUVActor->SetRootComponent(SubUV);
	SubUV->SetWorldLocation(SpawnLocation);
	SubUV->SetRelativeScale(Scale);
	SubUV->SetParticle(Resource);
	FVector EffectiveSpriteRotation = SpriteRotation;
	EffectiveSpriteRotation.Z += SpriteRoll;
	SubUV->SetSpriteRotation(EffectiveSpriteRotation);
	SubUV->SetFrameRate(std::max(FrameRate, 0.001f));
	SubUV->SetLoop(bLoop);
	SubUV->SetAutoDestroyOwnerOnFinished(bAutoDestroy);
	SubUV->SetCastShadow(bCastShadow);
	SubUV->SetVisibility(true);
	SubUV->Play();
}

void UAnimNotify_SpawnSubUV::PostEditProperty(const char* PropertyName)
{
	UObject::PostEditProperty(PropertyName);

	if (strcmp(PropertyName, "SpriteRotation") == 0 || strcmp(PropertyName, "Sprite Roll") == 0)
	{
		SpriteRoll = 0.0f;
	}
}
