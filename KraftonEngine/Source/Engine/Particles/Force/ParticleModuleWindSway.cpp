#include "Particles/Force/ParticleModuleWindSway.h"

#include "Object/GarbageCollection.h"
#include "Particles/ParticleEmitterInstances.h"
#include "Particles/ParticleHelper.h"
#include "Particles/ParticleModuleRequired.h"
#include "Serialization/Archive.h"

#include <algorithm>
#include <cmath>

namespace
{
	constexpr float TwoPi = 6.28318530717958647692f;

	float SafeDistributionValue(const FRawDistributionFloat& Distribution, float Time, UObject* Data, float Fallback)
	{
		if (Distribution.Distribution || Distribution.IsSimple())
		{
			return Distribution.GetValue(Time, Data);
		}
		return Fallback;
	}
}

UParticleModuleWindSway::UParticleModuleWindSway()
{
	bSpawnModule = true;
	bUpdateModule = true;
	bFinalUpdateModule = false;
}

FVector UParticleModuleWindSway::ResolveDirection(FParticleEmitterInstance& Owner)
{
	FVector Direction = WindDirection;
	if (Direction.IsNearlyZero())
	{
		Direction = FVector::RightVector;
	}

	UParticleLODLevel* LODLevel = Owner.GetCurrentLODLevelChecked();
	UParticleModuleRequired* Required = LODLevel ? LODLevel->RequiredModule : nullptr;

	if (Required && Required->bUseLocalSpace)
	{
		if (bInWorldSpace)
		{
			Direction = Owner.SimulationToWorld.GetInverse().TransformVector(Direction);
		}
		else
		{
			Direction = Owner.EmitterToSimulation.TransformVector(Direction);
		}
	}
	else if (!bInWorldSpace)
	{
		Direction = Owner.EmitterToSimulation.TransformVector(Direction);
	}

	return Direction.GetSafeNormal(1.0e-6f, FVector::RightVector);
}

void UParticleModuleWindSway::Spawn(const FSpawnContext& Context)
{
	SPAWN_INIT;
	PARTICLE_ELEMENT(FParticleWindSwayPayload, WindPayload);

	FVector Direction = ResolveDirection(Context.Owner);

	const float Jitter = std::clamp(DirectionJitter, 0.0f, 1.0f);
	if (Jitter > 0.0f)
	{
		const float Angle = Context.Owner.BurstRandomStream.FRand() * TwoPi;
		const FVector JitterDir(std::cos(Angle), std::sin(Angle), 0.0f);
		Direction = (Direction * (1.0f - Jitter) + JitterDir * Jitter)
			.GetSafeNormal(1.0e-6f, Direction);
	}

	if (bRandomDirectionSign && Context.Owner.BurstRandomStream.FRand() < 0.5f)
	{
		Direction = -Direction;
	}

	WindPayload.Direction = Direction;
	WindPayload.PreviousOffset = FVector::ZeroVector;
	WindPayload.Amplitude = std::max(0.0f, SafeDistributionValue(Amplitude, Context.Owner.EmitterTime, Context.GetDistributionData(), 15.0f));
	WindPayload.Frequency = std::max(0.0f, SafeDistributionValue(Frequency, Context.Owner.EmitterTime, Context.GetDistributionData(), 0.75f));
	WindPayload.Phase = Context.Owner.BurstRandomStream.FRand() * TwoPi;
	WindPayload.GustStrength = std::max(0.0f, SafeDistributionValue(GustStrength, Context.Owner.EmitterTime, Context.GetDistributionData(), 0.0f));
	WindPayload.GustFrequency = std::max(0.0f, SafeDistributionValue(GustFrequency, Context.Owner.EmitterTime, Context.GetDistributionData(), 0.2f));
}

void UParticleModuleWindSway::Update(const FUpdateContext& Context)
{
	BEGIN_UPDATE_LOOP
	{
		PARTICLE_ELEMENT(FParticleWindSwayPayload, WindPayload);

		const float Lifetime = Particle.OneOverMaxLifetime > 1.0e-6f
			? (1.0f / Particle.OneOverMaxLifetime)
			: 0.0f;
		const float AgeSeconds = Particle.RelativeTime * Lifetime;

		float GustScale = 1.0f;
		if (WindPayload.GustStrength > 0.0f && WindPayload.GustFrequency > 0.0f)
		{
			const float GustPhase = WindPayload.Phase * 0.37f + AgeSeconds * WindPayload.GustFrequency * TwoPi;
			GustScale += WindPayload.GustStrength * (0.5f + 0.5f * std::sin(GustPhase));
		}

		const float Sway = std::sin(WindPayload.Phase + AgeSeconds * WindPayload.Frequency * TwoPi)
			* WindPayload.Amplitude
			* GustScale;
		const FVector NewOffset = WindPayload.Direction * Sway;
		Particle.Location += NewOffset - WindPayload.PreviousOffset;
		WindPayload.PreviousOffset = NewOffset;
	}
	END_UPDATE_LOOP
}

uint32 UParticleModuleWindSway::RequiredBytes(UParticleModuleTypeDataBase* TypeData)
{
	return sizeof(FParticleWindSwayPayload);
}

void UParticleModuleWindSway::Serialize(FArchive& Ar)
{
	UParticleModule::Serialize(Ar);

	int32 Version = 0;
	Ar << Version;

	Ar << WindDirection;
	Ar << bInWorldSpace;
	Ar << bRandomDirectionSign;
	Ar << DirectionJitter;
	Amplitude.Serialize(Ar);
	Frequency.Serialize(Ar);
	GustStrength.Serialize(Ar);
	GustFrequency.Serialize(Ar);

	if (Ar.IsLoading())
	{
		DirectionJitter = std::clamp(DirectionJitter, 0.0f, 1.0f);
	}
}

void UParticleModuleWindSway::AddReferencedObjects(FReferenceCollector& Collector)
{
	UParticleModule::AddReferencedObjects(Collector);
	Amplitude.AddReferencedObjects(Collector);
	Frequency.AddReferencedObjects(Collector);
	GustStrength.AddReferencedObjects(Collector);
	GustFrequency.AddReferencedObjects(Collector);
}

#if WITH_EDITOR
void UParticleModuleWindSway::PostEditChangeProperty(const FPropertyChangedEvent& PropertyChangedEvent)
{
	Super::PostEditChangeProperty(PropertyChangedEvent);
	DirectionJitter = std::clamp(DirectionJitter, 0.0f, 1.0f);
}
#endif
