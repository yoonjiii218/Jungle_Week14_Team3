#pragma once

#include "Core/Types/CoreTypes.h"

class UWorld;
struct ID3D11Device;

struct FUnrealSceneImportResult
{
	bool bSuccess = false;
	int32 MeshCount = 0;
	int32 ActorCount = 0;
	int32 EngineActorCount = 0;
	int32 InstancedGroupCount = 0;
	int32 InstancedPlacementCount = 0;
	int32 MatrixTransformCount = 0;
	int32 CorrectedMatrixTransformCount = 0;
	int32 TextureCount = 0;
	int32 MaterialCount = 0;
	int32 MaterialAssignmentCount = 0;
	int32 EnvironmentActorCount = 0;
	int32 DecalActorCount = 0;
	int32 BlockingVolumeCount = 0;
	int32 FailedMeshCount = 0;
	int32 FailedTextureCount = 0;
	int32 FailedMaterialCount = 0;
	int32 SkippedActorCount = 0;
	int32 NegativeScaleCount = 0;
	FString DestinationDirectory;
	FString ErrorMessage;
};

struct FUnrealSceneImportOptions
{
	bool bOptimizeStaticMeshInstances = false;
};

class FUnrealSceneManifestImporter
{
public:
	static FUnrealSceneImportResult Import(
		const FString& ManifestPath,
		UWorld* World,
		ID3D11Device* Device,
		const FUnrealSceneImportOptions& Options = FUnrealSceneImportOptions());
};
