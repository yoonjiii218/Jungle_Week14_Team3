#pragma once

#include "Component/Primitive/StaticMeshComponent.h"
#include "Math/Matrix.h"
#include "Math/Vector.h"

class FPrimitiveSceneProxy;

#include "Source/Engine/Component/Primitive/InstancedStaticMeshComponent.generated.h"

UCLASS()
class UInstancedStaticMeshComponent : public UStaticMeshComponent
{
public:
	GENERATED_BODY()

	FPrimitiveSceneProxy* CreateSceneProxy() override;
	void Serialize(FArchive& Ar) override;
	void PostLoad() override;
	void PostEditProperty(const char* PropertyName) override;

	int32 AddInstanceTransform(const FMatrix& Transform);
	void SetInstanceTransforms(const TArray<FMatrix>& Transforms);
	void ClearInstances();

	const TArray<FVector4>& GetInstanceTransformRows() const { return InstanceTransformRows; }
	FMatrix GetInstanceTransform(int32 Index) const;
	uint32 GetInstanceVersion() const { return InstanceVersion; }
	int32 GetInstanceCount() const { return static_cast<int32>(InstanceTransformRows.size() / 4); }

	void UpdateWorldAABB() const override;
	bool LineTraceComponent(const FRay& Ray, FHitResult& OutHitResult) override;

private:
	void MarkInstancesDirty();
	void AppendInstanceTransformRows(const FMatrix& Transform);

	UPROPERTY(Save, Category="Instancing")
	TArray<FVector4> InstanceTransformRows;

	uint32 InstanceVersion = 1;
};
