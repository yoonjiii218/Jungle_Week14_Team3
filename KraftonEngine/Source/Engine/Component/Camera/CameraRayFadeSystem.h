#pragma once

#include "Component/PrimitiveComponent.h"
#include "Core/Logging/Log.h"
#include "Core/Types/CollisionTypes.h"
#include "GameFramework/AActor.h"
#include "GameFramework/World.h"
#include "Math/Vector.h"
#include <algorithm>
#include <cmath>

struct FCameraRayFadeParams
{
	ECollisionChannel Channel = ECollisionChannel::CameraFade;
	float Opacity = 0.35f;
	int MaxHits = 8;
	bool bDebug = false;
};

struct FCameraRayFadeState
{
	TArray<UPrimitiveComponent*> FadedComponents;
};

class FCameraRayFadeSystem
{
public:
	static void Clear(FCameraRayFadeState& State)
	{
		for (UPrimitiveComponent* Component : State.FadedComponents)
		{
			if (IsValid(Component))
			{
				Component->SetCameraRayFadeOpacity(1.0f);
			}
		}
		State.FadedComponents.clear();
	}

	static FCameraRayFadeState& GetCinematicState()
	{
		static FCameraRayFadeState State;
		return State;
	}

	static void ClearCinematic()
	{
		Clear(GetCinematicState());
	}

	static void UpdateCinematic(
		UWorld* World,
		const FVector& CameraWorld,
		const FVector& TargetWorld,
		AActor* IgnoreActor,
		const FCameraRayFadeParams& Params)
	{
		Update(World, CameraWorld, TargetWorld, IgnoreActor, Params, GetCinematicState());
	}

	static void Update(
		UWorld* World,
		const FVector& CameraWorld,
		const FVector& TargetWorld,
		AActor* IgnoreActor,
		const FCameraRayFadeParams& Params,
		FCameraRayFadeState& State)
	{
		if (!World)
		{
			Clear(State);
			return;
		}

		const FVector Diff = TargetWorld - CameraWorld;
		const float Distance = Diff.Length();
		if (Distance <= 1e-4f)
		{
			Clear(State);
			return;
		}

		const FVector Dir = Diff / Distance;
		TArray<FHitResult> Hits;
		TArray<UPrimitiveComponent*> NewFadeComponents;
		const int MaxFadeHits = std::max<int>(1, Params.MaxHits);

		if (World->PhysicsRaycastMulti(CameraWorld, Dir, Distance, Hits, Params.Channel, IgnoreActor))
		{
			for (const FHitResult& Hit : Hits)
			{
				UPrimitiveComponent* FadeComponent = ResolveFadePrimitive(Hit.HitComponent);
				if (!IsValid(FadeComponent) || Contains(NewFadeComponents, FadeComponent))
				{
					continue;
				}

				NewFadeComponents.push_back(FadeComponent);
				if (static_cast<int>(NewFadeComponents.size()) >= MaxFadeHits)
				{
					break;
				}
			}
		}

		for (UPrimitiveComponent* OldComponent : State.FadedComponents)
		{
			if (IsValid(OldComponent) && !Contains(NewFadeComponents, OldComponent))
			{
				OldComponent->SetCameraRayFadeOpacity(1.0f);
			}
		}

		State.FadedComponents = NewFadeComponents;
		const float ClampedOpacity = std::max<float>(0.0f, std::min<float>(Params.Opacity, 1.0f));
		for (UPrimitiveComponent* FadeComponent : State.FadedComponents)
		{
			if (IsValid(FadeComponent))
			{
				FadeComponent->SetCameraRayFadeOpacity(ClampedOpacity);
			}
		}

		if (Params.bDebug)
		{
			if (State.FadedComponents.empty())
			{
				UE_LOG("[CameraRayFade] no fade target hits=%zu", Hits.size());
			}
			else
			{
				UE_LOG("[CameraRayFade] fading %zu component(s) from %zu hit(s) opacity=%.2f",
					State.FadedComponents.size(), Hits.size(), ClampedOpacity);
			}
		}
	}

private:
	static bool Contains(const TArray<UPrimitiveComponent*>& Components, UPrimitiveComponent* Component)
	{
		return std::find(Components.begin(), Components.end(), Component) != Components.end();
	}

	static UPrimitiveComponent* ResolveFadePrimitive(UPrimitiveComponent* HitComponent)
	{
		if (!IsValid(HitComponent))
		{
			return nullptr;
		}

		if (HitComponent->CanCameraRayFade()
			&& HitComponent->IsVisible()
			&& HitComponent->GetMeshBuffer())
		{
			return HitComponent;
		}

		AActor* HitOwner = HitComponent->GetOwner();
		if (!IsValid(HitOwner))
		{
			return nullptr;
		}

		// Collision-only proxy(Box/Sphere/Capsule 등)에 맞은 경우, 같은 Actor의 실제 render primitive를 찾는다.
		for (UPrimitiveComponent* Primitive : HitOwner->GetPrimitiveComponents())
		{
			if (!IsValid(Primitive) || Primitive == HitComponent)
			{
				continue;
			}
			if (!Primitive->CanCameraRayFade() || !Primitive->IsVisible())
			{
				continue;
			}
			if (Primitive->GetMeshBuffer())
			{
				return Primitive;
			}
		}

		return nullptr;
	}
};
