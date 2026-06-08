#include "Component/Primitive/InstancedStaticMeshComponent.h"

#include "Mesh/Static/StaticMesh.h"
#include "Mesh/Static/StaticMeshAsset.h"
#include "Render/Proxy/InstancedStaticMeshSceneProxy.h"
#include "Serialization/Archive.h"

#include <algorithm>
#include <cfloat>
#include <cstring>
#include <cmath>

FPrimitiveSceneProxy* UInstancedStaticMeshComponent::CreateSceneProxy()
{
	return new FInstancedStaticMeshSceneProxy(this);
}

void UInstancedStaticMeshComponent::Serialize(FArchive& Ar)
{
	UStaticMeshComponent::Serialize(Ar);
	Ar << InstanceTransformRows;
	if (Ar.IsLoading())
	{
		MarkInstancesDirty();
	}
}

void UInstancedStaticMeshComponent::PostLoad()
{
	Super::PostLoad();
	MarkInstancesDirty();
}

void UInstancedStaticMeshComponent::PostEditProperty(const char* PropertyName)
{
	UStaticMeshComponent::PostEditProperty(PropertyName);
	if (PropertyName && std::strcmp(PropertyName, "InstanceTransformRows") == 0)
	{
		MarkInstancesDirty();
	}
}

int32 UInstancedStaticMeshComponent::AddInstanceTransform(const FMatrix& Transform)
{
	AppendInstanceTransformRows(Transform);
	MarkInstancesDirty();
	return GetInstanceCount() - 1;
}

void UInstancedStaticMeshComponent::SetInstanceTransforms(const TArray<FMatrix>& Transforms)
{
	InstanceTransformRows.clear();
	InstanceTransformRows.reserve(Transforms.size() * 4);
	for (const FMatrix& Transform : Transforms)
	{
		AppendInstanceTransformRows(Transform);
	}
	MarkInstancesDirty();
}

void UInstancedStaticMeshComponent::ClearInstances()
{
	InstanceTransformRows.clear();
	MarkInstancesDirty();
}

FMatrix UInstancedStaticMeshComponent::GetInstanceTransform(int32 Index) const
{
	const int32 RowIndex = Index * 4;
	if (Index < 0 || RowIndex + 3 >= static_cast<int32>(InstanceTransformRows.size()))
	{
		return FMatrix::Identity;
	}

	const FVector4& R0 = InstanceTransformRows[RowIndex + 0];
	const FVector4& R1 = InstanceTransformRows[RowIndex + 1];
	const FVector4& R2 = InstanceTransformRows[RowIndex + 2];
	const FVector4& R3 = InstanceTransformRows[RowIndex + 3];
	return FMatrix(
		R0.X, R0.Y, R0.Z, R0.W,
		R1.X, R1.Y, R1.Z, R1.W,
		R2.X, R2.Y, R2.Z, R2.W,
		R3.X, R3.Y, R3.Z, R3.W);
}

void UInstancedStaticMeshComponent::AppendInstanceTransformRows(const FMatrix& Transform)
{
	InstanceTransformRows.emplace_back(
		Transform.M[0][0],
		Transform.M[0][1],
		Transform.M[0][2],
		Transform.M[0][3]);
	InstanceTransformRows.emplace_back(
		Transform.M[1][0],
		Transform.M[1][1],
		Transform.M[1][2],
		Transform.M[1][3]);
	InstanceTransformRows.emplace_back(
		Transform.M[2][0],
		Transform.M[2][1],
		Transform.M[2][2],
		Transform.M[2][3]);
	InstanceTransformRows.emplace_back(
		Transform.M[3][0],
		Transform.M[3][1],
		Transform.M[3][2],
		Transform.M[3][3]);
}

void UInstancedStaticMeshComponent::MarkInstancesDirty()
{
	++InstanceVersion;
	if (InstanceVersion == 0)
	{
		InstanceVersion = 1;
	}
	MarkWorldBoundsDirty();
	MarkProxyDirty(EDirtyFlag::Mesh);
	MarkRenderTransformDirty();
}

void UInstancedStaticMeshComponent::UpdateWorldAABB() const
{
	UStaticMesh* Mesh = GetStaticMesh();
	FStaticMesh* Asset = Mesh ? Mesh->GetStaticMeshAsset() : nullptr;
	if (!Asset || Asset->Vertices.empty() || GetInstanceCount() == 0)
	{
		UStaticMeshComponent::UpdateWorldAABB();
		return;
	}

	if (!Asset->bBoundsValid)
	{
		Asset->CacheBounds();
	}

	const FVector LocalCenter = Asset->BoundsCenter;
	const FVector LocalExtent = Asset->BoundsExtent;
	const FMatrix ComponentWorld = GetWorldMatrix();

	bool bInitialized = false;
	FVector BoundsMin;
	FVector BoundsMax;

	for (int32 InstanceIndex = 0; InstanceIndex < GetInstanceCount(); ++InstanceIndex)
	{
		const FMatrix InstanceTransform = GetInstanceTransform(InstanceIndex);
		const FMatrix WorldMatrix = InstanceTransform * ComponentWorld;
		const FVector WorldCenter = WorldMatrix.TransformPositionWithW(LocalCenter);

		const float Ex = std::abs(WorldMatrix.M[0][0]) * LocalExtent.X
			+ std::abs(WorldMatrix.M[1][0]) * LocalExtent.Y
			+ std::abs(WorldMatrix.M[2][0]) * LocalExtent.Z;
		const float Ey = std::abs(WorldMatrix.M[0][1]) * LocalExtent.X
			+ std::abs(WorldMatrix.M[1][1]) * LocalExtent.Y
			+ std::abs(WorldMatrix.M[2][1]) * LocalExtent.Z;
		const float Ez = std::abs(WorldMatrix.M[0][2]) * LocalExtent.X
			+ std::abs(WorldMatrix.M[1][2]) * LocalExtent.Y
			+ std::abs(WorldMatrix.M[2][2]) * LocalExtent.Z;

		const FVector InstanceMin = WorldCenter - FVector(Ex, Ey, Ez);
		const FVector InstanceMax = WorldCenter + FVector(Ex, Ey, Ez);

		if (!bInitialized)
		{
			BoundsMin = InstanceMin;
			BoundsMax = InstanceMax;
			bInitialized = true;
		}
		else
		{
			BoundsMin.X = (std::min)(BoundsMin.X, InstanceMin.X);
			BoundsMin.Y = (std::min)(BoundsMin.Y, InstanceMin.Y);
			BoundsMin.Z = (std::min)(BoundsMin.Z, InstanceMin.Z);
			BoundsMax.X = (std::max)(BoundsMax.X, InstanceMax.X);
			BoundsMax.Y = (std::max)(BoundsMax.Y, InstanceMax.Y);
			BoundsMax.Z = (std::max)(BoundsMax.Z, InstanceMax.Z);
		}
	}

	WorldAABBMinLocation = BoundsMin;
	WorldAABBMaxLocation = BoundsMax;
	bWorldAABBDirty = false;
	bHasValidWorldAABB = true;
}

bool UInstancedStaticMeshComponent::LineTraceComponent(const FRay& Ray, FHitResult& OutHitResult)
{
	bool bHit = false;
	float BestDistance = FLT_MAX;
	const FMatrix ComponentWorld = GetWorldMatrix();

	for (int32 InstanceIndex = 0; InstanceIndex < GetInstanceCount(); ++InstanceIndex)
	{
		const FMatrix InstanceTransform = GetInstanceTransform(InstanceIndex);
		const FMatrix WorldMatrix = InstanceTransform * ComponentWorld;
		FHitResult Candidate;
		if (LineTraceStaticMeshFast(Ray, WorldMatrix, WorldMatrix.GetInverse(), Candidate) &&
			Candidate.Distance < BestDistance)
		{
			BestDistance = Candidate.Distance;
			OutHitResult = Candidate;
			bHit = true;
		}
	}

	return bHit;
}
