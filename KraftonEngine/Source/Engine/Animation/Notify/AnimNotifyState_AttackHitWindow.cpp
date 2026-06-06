#include "AnimNotifyState_AttackHitWindow.h"

#include "Animation/Instance/LuaAnimInstance.h"
#include "Component/Input/ActionComponent.h"
#include "Component/PrimitiveComponent.h"
#include "Component/Shape/BoxComponent.h"
#include "Component/Primitive/SkeletalMeshComponent.h"
#include "Core/Types/CollisionTypes.h"
#include "Core/Types/EngineTypes.h"
#include "Debug/DrawDebugHelpers.h"
#include "Core/Logging/Log.h"
#include "GameFramework/AActor.h"
#include "GameFramework/World.h"
#include "Mesh/Skeletal/SkeletalMesh.h"
#include "Mesh/Skeletal/SkeletalMeshAsset.h"
#include "Math/MathUtils.h"
#include "Object/Object.h"

namespace
{
	int32 FindBoneIndex(USkeletalMeshComponent* MeshComp, const FString& BoneName)
	{
		if (!IsValid(MeshComp) || BoneName.empty()) return -1;

		USkeletalMesh* Mesh = MeshComp->GetSkeletalMesh();
		FSkeletalMesh* Asset = Mesh ? Mesh->GetSkeletalMeshAsset() : nullptr;
		if (!Asset) return -1;

		for (int32 BoneIndex = 0; BoneIndex < static_cast<int32>(Asset->Bones.size()); ++BoneIndex)
		{
			if (Asset->Bones[BoneIndex].Name == BoneName)
			{
				return BoneIndex;
			}
		}

		return -1;
	}

	FVector MakeActorLocalOffset(AActor* Actor, const FVector& LocalOffset)
	{
		if (!IsValid(Actor)) return LocalOffset;

		return Actor->GetActorForward() * LocalOffset.X
			+ Actor->GetActorRight() * LocalOffset.Y
			+ FVector::UpVector * LocalOffset.Z;
	}

	FVector GetHitCenter(USkeletalMeshComponent* MeshComp, AActor* Owner, const FString& BoneName, const FVector& LocalOffset)
	{
		const FVector WorldOffset = MakeActorLocalOffset(Owner, LocalOffset);
		const int32 BoneIndex = FindBoneIndex(MeshComp, BoneName);
		if (BoneIndex >= 0)
		{
			return MeshComp->GetBoneLocationByIndex(BoneIndex) + WorldOffset;
		}

		return IsValid(Owner) ? Owner->GetActorLocation() + WorldOffset : WorldOffset;
	}

	float DistanceSquaredPointAABB(const FVector& Point, const FBoundingBox& Box)
	{
		const float X = Point.X < Box.Min.X ? Box.Min.X - Point.X : (Point.X > Box.Max.X ? Point.X - Box.Max.X : 0.0f);
		const float Y = Point.Y < Box.Min.Y ? Box.Min.Y - Point.Y : (Point.Y > Box.Max.Y ? Point.Y - Box.Max.Y : 0.0f);
		const float Z = Point.Z < Box.Min.Z ? Box.Min.Z - Point.Z : (Point.Z > Box.Max.Z ? Point.Z - Box.Max.Z : 0.0f);
		return X * X + Y * Y + Z * Z;
	}

	FVector ClosestPointOnAABB(const FVector& Point, const FBoundingBox& Box)
	{
		if (!Box.IsValid())
		{
			return Point;
		}

		return FVector(
			FMath::Clamp(Point.X, Box.Min.X, Box.Max.X),
			FMath::Clamp(Point.Y, Box.Min.Y, Box.Max.Y),
			FMath::Clamp(Point.Z, Box.Min.Z, Box.Max.Z));
	}

	void DrawDebugBounds(UWorld* World, const FBoundingBox& Bounds, const FColor& Color, float Duration)
	{
		if (!World || !Bounds.IsValid())
		{
			return;
		}

		DrawDebugBox(World, Bounds.GetCenter(), Bounds.GetExtent(), Color, Duration);
	}

	UActionComponent* GetOrCreateActionComponent(AActor* Actor, bool bAutoAdd)
	{
		if (!IsValid(Actor)) return nullptr;

		if (UActionComponent* Existing = Actor->GetComponentByClass<UActionComponent>())
		{
			return Existing;
		}

		return bAutoAdd ? Actor->AddComponent<UActionComponent>() : nullptr;
	}

	FVector ResolveKnockbackDirection(AActor* Attacker, AActor* Target, EAttackKnockbackMode Mode)
	{
		switch (Mode)
		{
		case EAttackKnockbackMode::Up:
			return FVector::UpVector;
		case EAttackKnockbackMode::AwayFromAttacker:
		{
			if (!IsValid(Attacker) || !IsValid(Target)) return FVector::ForwardVector;
			FVector Delta = Target->GetActorLocation() - Attacker->GetActorLocation();
			Delta.Z = 0.0f; // 수평 성분만 — 높낮이 차이로 위/아래로 날아가는 일 방지.
			if (Delta.IsNearlyZero()) return Attacker->GetActorForward();
			return Delta.Normalized();
		}
		case EAttackKnockbackMode::Forward:
		default:
			return IsValid(Attacker) ? Attacker->GetActorForward() : FVector::ForwardVector;
		}
	}

	void ApplyKnockback(AActor* Attacker, AActor* Target, EAttackKnockbackMode Mode,
		float Distance, float Duration, bool bAutoAddActionComponent)
	{
		if (Distance <= 0.0f || !IsValid(Target)) return;

		UActionComponent* Action = GetOrCreateActionComponent(Target, bAutoAddActionComponent);
		if (!Action) return;

		const FVector Dir = ResolveKnockbackDirection(Attacker, Target, Mode);
		Action->Knockback(Dir, Distance, Duration);
	}

	FHitResult MakeAttackHitResult(UBoxComponent* HitBox, AActor* OtherActor, UPrimitiveComponent* OtherComp,
		const FHitResult& SweepResult)
	{
		FHitResult Hit = SweepResult;
		Hit.bHit = true;
		Hit.HitActor = OtherActor;
		Hit.HitComponent = OtherComp;

		const FVector Center = HitBox ? HitBox->GetWorldLocation() : FVector::ZeroVector;
		const FBoundingBox Bounds = OtherComp ? OtherComp->GetWorldBoundingBox() : FBoundingBox();
		const FVector HitLocation = Bounds.IsValid()
			? ClosestPointOnAABB(Center, Bounds)
			: (OtherActor ? OtherActor->GetActorLocation() : Center);
		const FVector Delta = HitLocation - Center;
		const float Distance = Delta.Length();
		const FVector Normal = Distance > 0.001f ? Delta / Distance : FVector::ForwardVector;

		Hit.WorldHitLocation = HitLocation;
		Hit.WorldNormal = Normal;
		Hit.ImpactNormal = Normal;
		Hit.Distance = Distance;
		return Hit;
	}
}

void UAnimNotifyState_AttackHitWindow::NotifyBegin(USkeletalMeshComponent* MeshComp, UAnimSequenceBase* /*Anim*/, float /*TotalDuration*/)
{
	if (!IsValid(MeshComp) || Radius <= 0.0f)
	{
		return;
	}

	UBoxComponent* HitBox = GetOrCreateHitBox(MeshComp);
	if (!IsValid(HitBox))
	{
		return;
	}

	DisableHitBox(MeshComp);

	FActiveHitWindow& Active = ActiveWindowsByMesh[MeshComp];
	Active.HitActors.clear();

	UpdateHitBoxTransform(MeshComp, HitBox);
    HitBox->SetBoxExtent(FVector(Radius, Radius, Radius));
    HitBox->SetCollisionObjectType(ECollisionChannel::Trigger);
    HitBox->SetCollisionResponseToAllChannels(ECollisionResponse::Overlap);
    HitBox->SetGenerateOverlapEvents(false);
    HitBox->SetCollisionEnabled(ECollisionEnabled::NoCollision);
}

void UAnimNotifyState_AttackHitWindow::NotifyTick(USkeletalMeshComponent* MeshComp, UAnimSequenceBase* /*Anim*/, float /*FrameDeltaTime*/)
{
	if (!IsValid(MeshComp) || Radius <= 0.0f)
	{
		return;
	}

	AActor* Owner = MeshComp->GetOwner();
	UWorld* World = MeshComp->GetWorld();
	if (!IsValid(Owner) || !World)
	{
		return;
	}

	UBoxComponent* HitBox = HitBoxesByMesh[MeshComp].Get();
	if (!IsValid(HitBox))
	{
		return;
	}

	UpdateHitBoxTransform(MeshComp, HitBox);
	const FBoundingBox HitBounds = HitBox->GetWorldBoundingBox();
	if (HitBounds.IsValid())
	{
		for (AActor* OtherActor : World->GetActors())
		{
			if (!IsValid(OtherActor) || OtherActor == Owner)
			{
				continue;
			}

			for (UPrimitiveComponent* OtherComp : OtherActor->GetPrimitiveComponents())
			{
				if (!IsValid(OtherComp) || OtherComp == HitBox || !OtherComp->IsQueryCollisionEnabled())
				{
					continue;
				}
				if (UPrimitiveComponent::GetMinResponse(HitBox, OtherComp) == ECollisionResponse::Ignore)
				{
					continue;
				}

				const FBoundingBox OtherBounds = OtherComp->GetWorldBoundingBox();
				if (!OtherBounds.IsValid() || !HitBounds.IsIntersected(OtherBounds))
				{
					continue;
				}

				ProcessHit(MeshComp, HitBox, OtherActor, OtherComp);
			}
		}
	}

	if (bDrawDebugHitWindow)
	{
		DrawDebugBox(World, HitBox->GetWorldLocation(), HitBox->GetScaledBoxExtent(), FColor(255, 220, 0), DebugDrawDuration);
	}
}

void UAnimNotifyState_AttackHitWindow::NotifyEnd(USkeletalMeshComponent* MeshComp, UAnimSequenceBase* /*Anim*/)
{
	DisableHitBox(MeshComp);
}

UBoxComponent* UAnimNotifyState_AttackHitWindow::GetOrCreateHitBox(USkeletalMeshComponent* MeshComp)
{
	if (!IsValid(MeshComp))
	{
		return nullptr;
	}

	if (UBoxComponent* Existing = HitBoxesByMesh[MeshComp].Get())
	{
		return Existing;
	}

	AActor* Owner = MeshComp->GetOwner();
	if (!IsValid(Owner))
	{
		return nullptr;
	}

	UBoxComponent* HitBox = Owner->AddComponent<UBoxComponent>();
	if (!IsValid(HitBox))
	{
		return nullptr;
	}

	HitBox->SetHiddenInComponentTree(true);
	HitBox->SetVisibility(false);
	HitBox->SetBoxExtent(FVector(Radius, Radius, Radius));
	HitBox->SetSimulatePhysics(false);
	HitBox->SetEnableGravity(false);
    HitBox->SetGenerateOverlapEvents(false);
    HitBox->SetCollisionObjectType(ECollisionChannel::Trigger);
    HitBox->SetCollisionResponseToAllChannels(ECollisionResponse::Overlap);
    HitBox->SetCollisionEnabled(ECollisionEnabled::NoCollision);

	if (Owner->HasActorBegunPlay())
	{
		HitBox->BeginPlay();
	}

	HitBoxesByMesh[MeshComp] = HitBox;
	return HitBox;
}

void UAnimNotifyState_AttackHitWindow::UpdateHitBoxTransform(USkeletalMeshComponent* MeshComp, UBoxComponent* HitBox) const
{
	if (!IsValid(MeshComp) || !IsValid(HitBox))
	{
		return;
	}

	AActor* Owner = MeshComp->GetOwner();
	const FVector Center = GetHitCenter(MeshComp, Owner, BoneName, LocalOffset);
	HitBox->SetWorldLocation(Center);
	if (IsValid(Owner))
	{
		HitBox->SetRelativeRotation(Owner->GetActorRotation());
	}
}

void UAnimNotifyState_AttackHitWindow::DisableHitBox(USkeletalMeshComponent* MeshComp)
{
	if (!MeshComp)
	{
		return;
	}

	UBoxComponent* HitBox = HitBoxesByMesh[MeshComp].Get();
	auto It = ActiveWindowsByMesh.find(MeshComp);
	if (It != ActiveWindowsByMesh.end())
	{
		ActiveWindowsByMesh.erase(It);
	}

	if (IsValid(HitBox))
	{
		HitBox->SetGenerateOverlapEvents(false);
		HitBox->SetCollisionEnabled(ECollisionEnabled::NoCollision);
	}
}

void UAnimNotifyState_AttackHitWindow::ProcessHit(USkeletalMeshComponent* MeshComp, UBoxComponent* HitBox,
	AActor* OtherActor, UPrimitiveComponent* OtherComp)
{
	if (!IsValid(MeshComp) || !IsValid(HitBox) || !IsValid(OtherActor) || !IsValid(OtherComp))
	{
		return;
	}

	auto It = ActiveWindowsByMesh.find(MeshComp);
	if (It == ActiveWindowsByMesh.end())
	{
		return;
	}
	FActiveHitWindow* ActiveWindow = &It->second;

	AActor* Owner = MeshComp->GetOwner();
	if (!IsValid(Owner) || OtherActor == Owner)
	{
		return;
	}

	const bool bMatchesTargetActorTag = !TargetActorTag.empty() && OtherActor->HasTag(FName(TargetActorTag));
	if (bRequireTargetActorTag)
	{
		if (!bMatchesTargetActorTag)
		{
			return;
		}
	}
	else if (!TargetActorTag.empty() && !bMatchesTargetActorTag)
	{
		return;
	}

	if (bRequireQueryCollision && !OtherComp->IsQueryCollisionEnabled())
	{
		return;
	}

	if (!bHitWorldStatic && !bMatchesTargetActorTag && OtherComp->GetCollisionObjectType() == ECollisionChannel::WorldStatic)
	{
		return;
	}

	if (ActiveWindow->HitActors.find(OtherActor) != ActiveWindow->HitActors.end())
	{
		return;
	}

	ActiveWindow->HitActors.insert(OtherActor);
	if (bApplyKnockback)
	{
		ApplyKnockback(Owner, OtherActor, KnockbackMode, KnockbackDistance, KnockbackDuration, bAutoAddActionComponent);
	}

	FHitResult EmptySweepResult;
	const FHitResult HitResult = MakeAttackHitResult(HitBox, OtherActor, OtherComp, EmptySweepResult);
	if (!HitFunctionName.empty())
	{
		if (ULuaAnimInstance* LuaAnim = Cast<ULuaAnimInstance>(MeshComp->GetAnimInstance()))
		{
			LuaAnim->InvokeLuaFunction(HitFunctionName, OtherActor, HitBox, OtherComp, HitResult, HitStopDuration);
		}
	}

	if (bDrawDebugHitWindow && HitBox)
	{
		if (UWorld* World = MeshComp->GetWorld())
		{
			DrawDebugBox(World, HitBox->GetWorldLocation(), HitBox->GetScaledBoxExtent(), FColor(255, 40, 40), DebugDrawDuration);
		}
	}

	if (bDrawDebugTargetBounds)
	{
		if (UWorld* World = MeshComp->GetWorld())
		{
			DrawDebugBounds(World, OtherComp->GetWorldBoundingBox(), FColor(255, 40, 40), DebugDrawDuration);
		}
	}

	if (bLogHits)
	{
		const FVector Center = HitBox ? HitBox->GetWorldLocation() : FVector::ZeroVector;
		UE_LOG("[AttackHitWindow] %s hit %s via %s (center=%.1f, %.1f, %.1f extent=%.1f, %.1f, %.1f)",
			Owner->GetName().c_str(),
			OtherActor->GetName().c_str(),
			OtherComp->GetName().c_str(),
			Center.X,
			Center.Y,
			Center.Z,
			Radius,
			Radius,
			Radius);
	}
}
