#pragma once

#include "Particles/ParticleModule.h"

#include "Source/Engine/Particles/SubUV/ParticleModuleSubUVRandom.generated.h"

/**
 * Selects one SubUV atlas cell once at particle spawn time and keeps it for the
 * whole particle lifetime. This is useful for atlas sheets that contain
 * different static variants, such as cherry blossom petals, rather than
 * animation frames.
 */
UCLASS()
class UParticleModuleSubUVRandom : public UParticleModule
{
public:
	GENERATED_BODY()

	UParticleModuleSubUVRandom();

	/** Inclusive first atlas frame. Clamped to the Required module's total SubUV cell count. */
	UPROPERTY(Edit, Save, Category = "SubUV", DisplayName = "First Image Index", Min = "0")
	int32 FirstImageIndex = 0;

	/** Inclusive last atlas frame. -1 means the last cell in the Required module's SubUV grid. */
	UPROPERTY(Edit, Save, Category = "SubUV", DisplayName = "Last Image Index", Min = "-1")
	int32 LastImageIndex = -1;

	void Spawn(const FSpawnContext& Context) override;
	uint32 RequiredBytes(UParticleModuleTypeDataBase* TypeData) override;
	EModuleType GetModuleType() const override;
	void Serialize(FArchive& Ar) override;
};
