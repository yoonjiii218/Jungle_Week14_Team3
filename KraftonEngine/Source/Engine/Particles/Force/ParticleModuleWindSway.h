#pragma once

#include "Particles/ParticleModule.h"
#include "Distributions/DistributionFloat.h"

#include "Source/Engine/Particles/Force/ParticleModuleWindSway.generated.h"

/** Per-particle runtime state for UParticleModuleWindSway. */
struct FParticleWindSwayPayload
{
	FVector Direction = FVector::RightVector;
	FVector PreviousOffset = FVector::ZeroVector;
	float Amplitude = 0.0f;
	float Frequency = 1.0f;
	float Phase = 0.0f;
	float GustStrength = 0.0f;
	float GustFrequency = 0.0f;
};

/**
 * Adds a stable sinusoidal side-to-side offset to particles. Existing velocity
 * still controls falling/drifting, while this module adds the cherry-blossom
 * flutter/sway layer on top.
 */
UCLASS()
class UParticleModuleWindSway : public UParticleModule
{
public:
	GENERATED_BODY()

	UParticleModuleWindSway();

	/** Local or world-space lateral direction used for the sway offset. */
	UPROPERTY(Edit, Save, Category = "Wind", DisplayName = "Wind Direction")
	FVector WindDirection = FVector(1.0f, 0.0f, 0.0f);

	/** Interpret Wind Direction in world space. If false, it is emitter-local. */
	UPROPERTY(Edit, Save, Category = "Wind", DisplayName = "In World Space")
	bool bInWorldSpace = true;

	/** Randomly flips the sway direction per particle. */
	UPROPERTY(Edit, Save, Category = "Wind", DisplayName = "Random Direction Sign")
	bool bRandomDirectionSign = true;

	/** Adds random horizontal direction variance per particle. 0 disables jitter. */
	UPROPERTY(Edit, Save, Category = "Wind", DisplayName = "Direction Jitter", Min = "0.0", Max = "1.0", Speed = "0.01")
	float DirectionJitter = 0.35f;

	/** Sway distance in engine units. */
	UPROPERTY(EditAnywhere, Category = "Wind")
	FRawDistributionFloat Amplitude;

	/** Sway cycles per second. */
	UPROPERTY(EditAnywhere, Category = "Wind")
	FRawDistributionFloat Frequency;

	/** Extra amplitude multiplier used for slow gust pulses. 0 disables gusts. */
	UPROPERTY(EditAnywhere, Category = "Wind|Gust")
	FRawDistributionFloat GustStrength;

	/** Gust cycles per second. */
	UPROPERTY(EditAnywhere, Category = "Wind|Gust")
	FRawDistributionFloat GustFrequency;

	void Spawn(const FSpawnContext& Context) override;
	void Update(const FUpdateContext& Context) override;
	uint32 RequiredBytes(UParticleModuleTypeDataBase* TypeData) override;
	void Serialize(FArchive& Ar) override;
	void AddReferencedObjects(FReferenceCollector& Collector) override;

#if WITH_EDITOR
	void PostEditChangeProperty(const FPropertyChangedEvent& PropertyChangedEvent) override;
#endif

private:
	FVector ResolveDirection(FParticleEmitterInstance& Owner);
};
