#include "AnimNotify_PlaySound.h"

#include "Audio/AudioManager.h"
#include "Component/Primitive/ParticleSystemComponent.h"
#include "Component/Primitive/SkeletalMeshComponent.h"
#include "Core/Logging/Log.h"
#include "GameFramework/AActor.h"
#include "GameFramework/World.h"
#include "Math/MathUtils.h"
#include "Object/Reflection/UClass.h"
#include "Particles/ParticleSystem.h"
#include "Particles/ParticleSystemManager.h"

#include <cstring>

namespace
{
	// 이미 LoadAudio 호출 완료한 path 캐시. AudioManager 재초기화로 내부 sound 가 해제될 수 있으므로
	// Notify 에서는 캐시와 실제 AudioManager 상태를 함께 확인한다.
	static TSet<FString> GLoadedPlaySoundPaths;

	bool IsCinematicImpactSound(const FString& SoundPath)
	{
		return SoundPath.find("Cinematic_Impact") != FString::npos;
	}

	enum class ENotifyParticleTransformMode
	{
		World,
		FollowSocket,
		SocketRotation,
		CharacterRotation,
	};

	static ENotifyParticleTransformMode ResolveNotifyParticleTransformMode(
		bool bFollowSocket,
		bool bUseSocketRotation,
		bool bUseCharacterRotation
	)
	{
		// Preserve the old runtime priority for assets saved with multiple flags enabled.
		if (bFollowSocket)
		{
			return ENotifyParticleTransformMode::FollowSocket;
		}
		if (bUseSocketRotation)
		{
			return ENotifyParticleTransformMode::SocketRotation;
		}
		if (bUseCharacterRotation)
		{
			return ENotifyParticleTransformMode::CharacterRotation;
		}
		return ENotifyParticleTransformMode::World;
	}

	static FMatrix GetNotifySocketWorldMatrix(const USkeletalMeshComponent* MeshComp, const FString& SocketName)
	{
		if (!MeshComp)
		{
			return FMatrix::Identity;
		}

		const FName AttachSocketName(SocketName);
		if (!SocketName.empty() && MeshComp->HasSocket(AttachSocketName))
		{
			return MeshComp->GetSocketTransform(AttachSocketName).ToMatrix();
		}

		return MeshComp->GetWorldMatrix();
	}

	static FVector GetNotifySocketWorldLocation(const USkeletalMeshComponent* MeshComp, const FString& SocketName)
	{
		return GetNotifySocketWorldMatrix(MeshComp, SocketName).GetLocation();
	}

	static FRotator GetNotifyCharacterFacingRotation(const USkeletalMeshComponent* MeshComp)
	{
		FVector Forward = FVector::ForwardVector;
		if (MeshComp)
		{
			if (const AActor* Owner = MeshComp->GetOwner())
			{
				Forward = Owner->GetActorForward();
			}
			else
			{
				Forward = MeshComp->GetForwardVector();
			}
		}

		Forward.Z = 0.0f;
		if (Forward.IsNearlyZero())
		{
			Forward = FVector::ForwardVector;
		}
		Forward.Normalize();

		return FRotator(0.0f, atan2f(Forward.Y, Forward.X) * RAD_TO_DEG, 0.0f);
	}

	static void SetNotifySpawnTransform(
		UParticleSystemComponent* PSC,
		const FVector& Origin,
		const FRotator& BasisRotation,
		const FVector& LocationOffset,
		const FVector& RotationOffset,
		const FVector& Scale
	)
	{
		if (!PSC)
		{
			return;
		}

		const FVector SpawnLocation = Origin
			+ BasisRotation.GetForwardVector() * LocationOffset.X
			+ BasisRotation.GetRightVector() * LocationOffset.Y
			+ BasisRotation.GetUpVector() * LocationOffset.Z;
		const FQuat SpawnRotation = BasisRotation.ToQuaternion() * FRotator(RotationOffset).ToQuaternion();

		PSC->SetRelativeLocation(SpawnLocation);
		PSC->SetRelativeRotation(SpawnRotation);
		PSC->SetRelativeScale(Scale);
	}
}

void UAnimNotify_PlaySound::NormalizePlaybackSettings()
{
	if (Pitch <= 0.0f)
	{
		Pitch = 1.0f;
	}
	PlayChance = FMath::Clamp(PlayChance, 0.0f, 1.0f);
}

void UAnimNotify_PlaySound::PreSave()
{
	UObject::PreSave();
	NormalizePlaybackSettings();
	bPlayChanceInitialized = true;
}

void UAnimNotify_PlaySound::PostLoad()
{
	UObject::PostLoad();
	if (!bPlayChanceInitialized)
	{
		if (FMath::Abs(PlayChance - 0.5f) > FMath::KINDA_SMALL_NUMBER)
		{
			PlayChance = 1.0f;
		}
		bPlayChanceInitialized = true;
	}
	NormalizePlaybackSettings();
}

void UAnimNotify_PlaySound::PreGetEditableProperties()
{
	NormalizePlaybackSettings();
}

void UAnimNotify_PlaySound::PostEditProperty(const char* PropertyName)
{
	UObject::PostEditProperty(PropertyName);
	if (PropertyName && (std::strcmp(PropertyName, "PlayChance") == 0 || std::strcmp(PropertyName, "Play Chance") == 0))
	{
		bPlayChanceInitialized = true;
	}
	NormalizePlaybackSettings();
}

void UAnimNotify_PlaySound::Notify(USkeletalMeshComponent* /*MeshComp*/, UAnimSequenceBase* /*Anim*/)
{
	if (SoundPath.empty() || SoundPath == "None") return;
	NormalizePlaybackSettings();
	if (PlayChance <= 0.0f || (PlayChance < 1.0f && FMath::FRand() >= PlayChance))
	{
		return;
	}

	// 캐시 key — path 자체. "AnimNotify:" prefix 로 게임 측 pre-loaded key 들과 namespace 분리.
	const FString Key = FString("AnimNotify:") + SoundPath;

	if (GLoadedPlaySoundPaths.find(SoundPath) == GLoadedPlaySoundPaths.end()
		|| !FAudioManager::Get().IsAudioLoaded(Key))
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

	FAudioManager::Get().PlayAudio(Key, Volume, Pitch, 0, bPriority || IsCinematicImpactSound(SoundPath));
}

void UAnimNotify_PlayParticle::PostEditProperty(const char* PropertyName)
{
	UObject::PostEditProperty(PropertyName);
	if (!PropertyName)
	{
		return;
	}

	if ((std::strcmp(PropertyName, "bFollowSocket") == 0 || std::strcmp(PropertyName, "Follow Socket") == 0) && bFollowSocket)
	{
		bUseSocketRotation = false;
		bUseCharacterRotation = false;
	}
	else if ((std::strcmp(PropertyName, "bUseSocketRotation") == 0 || std::strcmp(PropertyName, "Use Socket Rotation") == 0) && bUseSocketRotation)
	{
		bFollowSocket = false;
		bUseCharacterRotation = false;
	}
	else if ((std::strcmp(PropertyName, "bUseCharacterRotation") == 0 || std::strcmp(PropertyName, "Use Character Rotation") == 0) && bUseCharacterRotation)
	{
		bFollowSocket = false;
		bUseSocketRotation = false;
	}
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

	UWorld* World = MeshComp->GetWorld();
	if (!World) return;

	UClass* ActorClass = UClass::FindByName("AActor");
	if (!ActorClass) return;

	AActor* ParticleActor = World->SpawnActorByClass(ActorClass);
	if (!ParticleActor) return;
	ParticleActor->bTickInEditor = true;

	UParticleSystemComponent* PSC = ParticleActor->AddComponent<UParticleSystemComponent>();
	if (!PSC)
	{
		World->DestroyActor(ParticleActor);
		return;
	}

	ParticleActor->SetRootComponent(PSC);

	const ENotifyParticleTransformMode TransformMode = ResolveNotifyParticleTransformMode(
		bFollowSocket,
		bUseSocketRotation,
		bUseCharacterRotation
	);

	if (TransformMode == ENotifyParticleTransformMode::FollowSocket)
	{
		PSC->AttachToComponentWithSocket(MeshComp, SocketName);
		PSC->SetRelativeLocation(LocationOffset);
		PSC->SetRelativeRotation(RotationOffset);
		PSC->SetRelativeScale(Scale);
	}
	else
	{
		const FMatrix SocketWorldMatrix = GetNotifySocketWorldMatrix(MeshComp, SocketName);
		if (TransformMode == ENotifyParticleTransformMode::SocketRotation)
		{
			SetNotifySpawnTransform(
				PSC,
				SocketWorldMatrix.GetLocation(),
				SocketWorldMatrix.ToRotator(),
				LocationOffset,
				RotationOffset,
				Scale
			);
		}
		else if (TransformMode == ENotifyParticleTransformMode::CharacterRotation)
		{
			SetNotifySpawnTransform(
				PSC,
				GetNotifySocketWorldLocation(MeshComp, SocketName),
				GetNotifyCharacterFacingRotation(MeshComp),
				LocationOffset,
				RotationOffset,
				Scale
			);
		}
		else
		{
			PSC->SetRelativeLocation(SocketWorldMatrix.GetLocation() + LocationOffset);
			PSC->SetRelativeRotation(RotationOffset);
			PSC->SetRelativeScale(Scale);
		}
	}

	PSC->SetTemplate(Template);
	PSC->SetAutoDestroyOwnerAfter(AutoDestroyAfter);
	PSC->Activate();
}
