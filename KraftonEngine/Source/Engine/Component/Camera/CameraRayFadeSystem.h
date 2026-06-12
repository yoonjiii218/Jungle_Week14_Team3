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
	float RayHalfWidth = 0.0f;
	int MaxHits = 8;
	bool bDebug = false;
	bool bLogQuerySummary = false;
	uint32 QueryId = 0;
};

struct FCameraRayFadeState
{
	TArray<UPrimitiveComponent*> FadedComponents;
};

struct FCameraOcclusionResolveParams
{
	// SpringArm의 probe와 같은 의미로 쓰기 위해 기본값은 Camera 채널.
	ECollisionChannel Channel = ECollisionChannel::Camera;
	float FocusHeightOffset = 1.2f;
	float YawStepDegrees = 18.0f;
	int CandidateCount = 5;
	bool bDebug = false;
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

	static FVector ResolveBestCameraLocation(
		UWorld* World,
		const FVector& FocusWorld,
		const FVector& DesiredCameraWorld,
		AActor* IgnoreActor,
		const FCameraOcclusionResolveParams& Params)
	{
		if (!World)
		{
			return DesiredCameraWorld;
		}

		const int CandidateCount = std::max<int>(1, std::min<int>(Params.CandidateCount, 15));
		const float YawStepRadians = Params.YawStepDegrees * 3.14159265358979323846f / 180.0f;
		const FVector FocusTarget = FocusWorld + FVector(0.0f, 0.0f, Params.FocusHeightOffset);
		const FVector DesiredOffset = DesiredCameraWorld - FocusWorld;

		FVector BestLocation = DesiredCameraWorld;
		float BestScore = 3.402823466e+38F;
		float BestYawDegrees = 0.0f;
		int BestHitCount = 0;

		for (int Index = 0; Index < CandidateCount; ++Index)
		{
			const int Ring = (Index + 1) / 2;
			const float Sign = (Index == 0) ? 0.0f : ((Index % 2) == 1 ? 1.0f : -1.0f);
			const float YawRadians = Sign * static_cast<float>(Ring) * YawStepRadians;

			const float CosYaw = std::cos(YawRadians);
			const float SinYaw = std::sin(YawRadians);
			FVector RotatedOffset(
				DesiredOffset.X * CosYaw - DesiredOffset.Y * SinYaw,
				DesiredOffset.X * SinYaw + DesiredOffset.Y * CosYaw,
				DesiredOffset.Z);

			const FVector Candidate = FocusWorld + RotatedOffset;
			int HitCount = 0;
			float NearestHitDistance = 3.402823466e+38F;
			EvaluateCameraPath(World, Candidate, FocusTarget, IgnoreActor, Params.Channel, HitCount, NearestHitDistance);

			// hit 수가 압도적으로 우선, 그 다음 가까운 곳에서 막히는 정도, 마지막으로 원래 구도에서 벗어난 yaw를 벌점.
			const float Distance = (FocusTarget - Candidate).Length();
			const float ClearRatio = (NearestHitDistance < 3.402823466e+37F && Distance > 1e-4f)
				? (1.0f - std::max<float>(0.0f, std::min<float>(NearestHitDistance / Distance, 1.0f)))
				: 0.0f;
			const float AbsYawDegrees = std::abs(YawRadians * 180.0f / 3.14159265358979323846f);
			const float Score = static_cast<float>(HitCount) * 10000.0f + ClearRatio * 1000.0f + AbsYawDegrees * 2.0f;

			if (Score < BestScore)
			{
				BestScore = Score;
				BestLocation = Candidate;
				BestYawDegrees = YawRadians * 180.0f / 3.14159265358979323846f;
				BestHitCount = HitCount;
			}
		}

		if (Params.bDebug)
		{
			UE_LOG("[CameraOcclusion] selected yaw=%.1f hits=%d score=%.1f loc=(%.2f, %.2f, %.2f)",
				BestYawDegrees,
				BestHitCount,
				BestScore,
				BestLocation.X,
				BestLocation.Y,
				BestLocation.Z);
		}

		return BestLocation;
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

		TArray<UPrimitiveComponent*> NewFadeComponents;
		TArray<UPrimitiveComponent*> NewHitComponents;
		const int MaxFadeHits = std::max<int>(1, Params.MaxHits);
		const FVector CenterDir = Diff / Distance;
		const float RayHalfWidth = std::max<float>(0.0f, Params.RayHalfWidth);
		const FVector RayRight = FVector::UpVector.Cross(CenterDir).GetSafeNormal(1e-4f, FVector::RightVector);
		const int RayCount = RayHalfWidth > 1e-4f ? 3 : 1;
		const FVector RayTargets[3] =
		{
			TargetWorld,
			TargetWorld - RayRight * RayHalfWidth,
			TargetWorld + RayRight * RayHalfWidth
		};
		size_t TotalHitCount = 0;

		for (int RayIndex = 0; RayIndex < RayCount; ++RayIndex)
		{
			const FVector RayDiff = RayTargets[RayIndex] - CameraWorld;
			const float RayDistance = RayDiff.Length();
			if (RayDistance <= 1e-4f)
			{
				continue;
			}

			TArray<FHitResult> RayHits;
			if (!World->PhysicsRaycastMulti(
				CameraWorld,
				RayDiff / RayDistance,
				RayDistance,
				RayHits,
				Params.Channel,
				IgnoreActor))
			{
				continue;
			}

			TotalHitCount += RayHits.size();
			for (const FHitResult& Hit : RayHits)
			{
				UPrimitiveComponent* FadeComponent = ResolveFadePrimitive(Hit.HitComponent);
				if (!IsValid(FadeComponent) || Contains(NewFadeComponents, FadeComponent))
				{
					continue;
				}

				NewFadeComponents.push_back(FadeComponent);
				NewHitComponents.push_back(Hit.HitComponent);
				if (static_cast<int>(NewFadeComponents.size()) >= MaxFadeHits)
				{
					break;
				}
			}

			if (static_cast<int>(NewFadeComponents.size()) >= MaxFadeHits)
			{
				break;
			}
		}

		if (Params.bDebug && Params.bLogQuerySummary)
		{
			UE_LOG("[CameraRayFade][Trace] query=%u rays=%d halfWidth=%.3f rawHits=%zu fadeTargets=%zu",
				Params.QueryId,
				RayCount,
				RayHalfWidth,
				TotalHitCount,
				NewFadeComponents.size());
		}

		for (UPrimitiveComponent* OldComponent : State.FadedComponents)
		{
			if (IsValid(OldComponent) && !Contains(NewFadeComponents, OldComponent))
			{
				if (Params.bDebug)
				{
					AActor* Owner = OldComponent->GetOwner();
					UE_LOG("[CameraRayFade][Restore] actor=%s component=%s opacity=%.3f->1.000",
						IsValid(Owner) ? Owner->GetName().c_str() : "(null)",
						OldComponent->GetName().c_str(),
						OldComponent->GetCameraRayFadeOpacity());
				}
				OldComponent->SetCameraRayFadeOpacity(1.0f);
			}
		}

		const TArray<UPrimitiveComponent*> PreviousFadeComponents = State.FadedComponents;
		State.FadedComponents = NewFadeComponents;
		const float ClampedOpacity = std::max<float>(0.0f, std::min<float>(Params.Opacity, 1.0f));
		for (size_t Index = 0; Index < State.FadedComponents.size(); ++Index)
		{
			UPrimitiveComponent* FadeComponent = State.FadedComponents[Index];
			if (IsValid(FadeComponent))
			{
				const bool bNewlyFaded = !Contains(PreviousFadeComponents, FadeComponent);
				const float PreviousOpacity = FadeComponent->GetCameraRayFadeOpacity();
				FadeComponent->SetCameraRayFadeOpacity(ClampedOpacity);
				if (Params.bDebug && bNewlyFaded)
				{
					UPrimitiveComponent* HitComponent = Index < NewHitComponents.size()
						? NewHitComponents[Index]
						: nullptr;
					AActor* Owner = FadeComponent->GetOwner();
					const ECollisionResponse HitResponse = IsValid(HitComponent)
						? HitComponent->GetCollisionResponseToChannel(Params.Channel)
						: ECollisionResponse::Ignore;
					UE_LOG("[CameraRayFade][Apply] actor=%s hit=%s render=%s channel=%d response=%d opacity=%.3f->%.3f proxyReady=%s",
						IsValid(Owner) ? Owner->GetName().c_str() : "(null)",
						IsValid(HitComponent) ? HitComponent->GetName().c_str() : "(null)",
						FadeComponent->GetName().c_str(),
						static_cast<int>(Params.Channel),
						static_cast<int>(HitResponse),
						PreviousOpacity,
						FadeComponent->GetCameraRayFadeOpacity(),
						FadeComponent->GetSceneProxy() ? "true" : "false");
				}
			}
		}

		if (Params.bDebug)
		{
			bool bStateChanged = PreviousFadeComponents.size() != State.FadedComponents.size();
			if (!bStateChanged)
			{
				for (UPrimitiveComponent* Component : State.FadedComponents)
				{
					if (!Contains(PreviousFadeComponents, Component))
					{
						bStateChanged = true;
						break;
					}
				}
			}

			if (bStateChanged && State.FadedComponents.empty())
			{
				UE_LOG("[CameraRayFade] no fade target rawHits=%zu", TotalHitCount);
			}
			else if (bStateChanged)
			{
				UE_LOG("[CameraRayFade] fading %zu component(s) from %zu raw hit(s) opacity=%.2f",
					State.FadedComponents.size(), TotalHitCount, ClampedOpacity);
			}
		}
	}

private:
	static void EvaluateCameraPath(
		UWorld* World,
		const FVector& CameraWorld,
		const FVector& TargetWorld,
		AActor* IgnoreActor,
		ECollisionChannel Channel,
		int& OutHitCount,
		float& OutNearestHitDistance)
	{
		OutHitCount = 0;
		OutNearestHitDistance = 3.402823466e+38F;

		if (!World)
		{
			return;
		}

		const FVector Diff = TargetWorld - CameraWorld;
		const float Distance = Diff.Length();
		if (Distance <= 1e-4f)
		{
			return;
		}

		const FVector Dir = Diff / Distance;
		TArray<FHitResult> Hits;
		if (!World->PhysicsRaycastMulti(CameraWorld, Dir, Distance, Hits, Channel, IgnoreActor))
		{
			return;
		}

		constexpr float EndIgnoreDistance = 2.0f;
		for (const FHitResult& Hit : Hits)
		{
			if (!Hit.bHit)
			{
				continue;
			}
			if (IgnoreActor && Hit.HitActor == IgnoreActor)
			{
				continue;
			}
			// Focus 바로 앞의 target/owner collision이 후보 점수에 과하게 반영되지 않게 끝부분은 무시한다.
			if (Hit.Distance >= Distance - EndIgnoreDistance)
			{
				continue;
			}

			++OutHitCount;
			OutNearestHitDistance = std::min<float>(OutNearestHitDistance, Hit.Distance);
		}
	}

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
