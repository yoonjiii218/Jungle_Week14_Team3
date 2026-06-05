#include "AnimNotify_PlaySound.h"

#include "Audio/AudioManager.h"
#include "Component/Primitive/ParticleSystemComponent.h"
#include "Component/Primitive/SkeletalMeshComponent.h"
#include "Core/Logging/Log.h"
#include "Engine/Runtime/Engine.h"
#include "GameFramework/AActor.h"
#include "GameFramework/World.h"
#include "Object/Reflection/UClass.h"
#include "Particles/ParticleSystem.h"
#include "Particles/ParticleSystemManager.h"

namespace
{
	// 이미 LoadAudio 호출 완료한 path 캐시. AudioManager 의 내부 Audios map 에 직접 접근 못 하므로
	// notify 측에서 한 번만 load 보장 (LoadAudio 매번 호출 시 release+reload 비용 회피).
	// 프로세스 lifetime 동안 누적, 캐시 무효화 필요 시 process restart.
	static TSet<FString> GLoadedPlaySoundPaths;
}

void UAnimNotify_PlaySound::Notify(USkeletalMeshComponent* /*MeshComp*/, UAnimSequenceBase* /*Anim*/)
{
	if (SoundPath.empty() || SoundPath == "None") return;

	// 캐시 key — path 자체. "AnimNotify:" prefix 로 게임 측 pre-loaded key 들과 namespace 분리.
	const FString Key = FString("AnimNotify:") + SoundPath;

	if (GLoadedPlaySoundPaths.find(SoundPath) == GLoadedPlaySoundPaths.end())
	{
		if (FAudioManager::Get().LoadAudio(Key, SoundPath, /*bLoop=*/false))
		{
			GLoadedPlaySoundPaths.insert(SoundPath);
		}
		else
		{
			UE_LOG("[AnimNotify_PlaySound] LoadAudio failed: %s", SoundPath.c_str());
			return;
		}
	}

	FAudioManager::Get().PlayAudio(Key, Volume);
}

void UAnimNotify_PlayParticle::Notify(USkeletalMeshComponent* MeshComp, UAnimSequenceBase* /*Anim*/)
{
	if (!MeshComp) return;

	const FString Path = ParticleSystemPath.ToString();
	if (Path.empty() || Path == "None") return;

	UParticleSystem* Template = FParticleSystemManager::Get().Load(Path);
	if (!Template)
	{
		UE_LOG("[AnimNotify_PlayParticle] Load particle failed: %s", Path.c_str());
		return;
	}

	if (!GEngine) return;

	UWorld* World = GEngine->GetWorld();
	if (!World) return;

	UClass* ActorClass = UClass::FindByName("AActor");
	if (!ActorClass) return;

	AActor* ParticleActor = World->SpawnActorByClass(ActorClass);
	if (!ParticleActor) return;

	UParticleSystemComponent* PSC = ParticleActor->AddComponent<UParticleSystemComponent>();
	if (!PSC)
	{
		World->DestroyActor(ParticleActor);
		return;
	}

	ParticleActor->SetRootComponent(PSC);
	PSC->AttachToComponentWithSocket(MeshComp, SocketName);
	PSC->SetRelativeLocation(LocationOffset);
	PSC->SetRelativeRotation(RotationOffset);
	PSC->SetRelativeScale(Scale);
	PSC->SetTemplate(Template);
	PSC->SetAutoDestroyOwnerAfter(AutoDestroyAfter);
	PSC->Activate();
}
