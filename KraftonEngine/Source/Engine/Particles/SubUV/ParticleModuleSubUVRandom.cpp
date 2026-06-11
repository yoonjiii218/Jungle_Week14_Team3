#include "Particles/SubUV/ParticleModuleSubUVRandom.h"

#include "Particles/ParticleEmitterInstances.h"
#include "Particles/ParticleHelper.h"
#include "Particles/ParticleModuleRequired.h"
#include "Serialization/Archive.h"

#include <algorithm>

UParticleModuleSubUVRandom::UParticleModuleSubUVRandom()
{
	bSpawnModule = true;
	bUpdateModule = false;
	bFinalUpdateModule = false;
}

void UParticleModuleSubUVRandom::Spawn(const FSpawnContext& Context)
{
	SPAWN_INIT;
	PARTICLE_ELEMENT(FFullSubUVPayload, SubUVPayload);

	UParticleLODLevel* LODLevel = Context.Owner.GetCurrentLODLevelChecked();
	UParticleModuleRequired* Required = LODLevel ? LODLevel->RequiredModule : nullptr;

	const int32 Columns = Required ? std::max(1, Required->SubImages_Horizontal) : 1;
	const int32 Rows = Required ? std::max(1, Required->SubImages_Vertical) : 1;
	const int32 TotalImages = std::max(1, Columns * Rows);

	int32 MinImage = std::clamp(FirstImageIndex, 0, TotalImages - 1);
	int32 MaxImage = LastImageIndex >= 0
		? std::clamp(LastImageIndex, 0, TotalImages - 1)
		: TotalImages - 1;
	if (MaxImage < MinImage)
	{
		std::swap(MinImage, MaxImage);
	}

	const int32 ImageIndex = (MinImage == MaxImage)
		? MinImage
		: Context.Owner.BurstRandomStream.RandRange(MinImage, MaxImage);

	// ParticleSubUV material node expects a normalized [0, 1) value and converts
	// it to a discrete atlas frame. Use the center of the selected frame's range
	// to avoid boundary precision issues.
	SubUVPayload.ImageIndex = (static_cast<float>(ImageIndex) + 0.5f) / static_cast<float>(TotalImages);
	SubUVPayload.RandomImageTime = static_cast<float>(ImageIndex);
}

uint32 UParticleModuleSubUVRandom::RequiredBytes(UParticleModuleTypeDataBase* TypeData)
{
	return sizeof(FFullSubUVPayload);
}

EModuleType UParticleModuleSubUVRandom::GetModuleType() const
{
	return EPMT_SubUV;
}

void UParticleModuleSubUVRandom::Serialize(FArchive& Ar)
{
	UParticleModule::Serialize(Ar);

	int32 Version = 0;
	Ar << Version;

	Ar << FirstImageIndex;
	Ar << LastImageIndex;

	if (Ar.IsLoading())
	{
		FirstImageIndex = std::max(0, FirstImageIndex);
	}
}
