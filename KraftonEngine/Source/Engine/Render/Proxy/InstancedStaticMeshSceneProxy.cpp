#include "Render/Proxy/InstancedStaticMeshSceneProxy.h"

#include "Component/Primitive/InstancedStaticMeshComponent.h"
#include "Object/Object.h"
#include "Render/Command/DrawCommand.h"
#include "Render/Types/VertexTypes.h"

FInstancedStaticMeshSceneProxy::FInstancedStaticMeshSceneProxy(UInstancedStaticMeshComponent* InComponent)
	: FStaticMeshSceneProxy(InComponent)
{
	ProxyFlags |= EPrimitiveProxyFlags::InstancedStaticMesh;
}

UInstancedStaticMeshComponent* FInstancedStaticMeshSceneProxy::GetInstancedStaticMeshComponent() const
{
	return Cast<UInstancedStaticMeshComponent>(GetOwner());
}

bool FInstancedStaticMeshSceneProxy::PrepareDrawBuffer(
	ID3D11Device* Device,
	ID3D11DeviceContext* Context,
	FDrawCommandBuffer& OutBuffer) const
{
	if (!FStaticMeshSceneProxy::PrepareDrawBuffer(Device, Context, OutBuffer))
	{
		return false;
	}

	UInstancedStaticMeshComponent* Component = GetInstancedStaticMeshComponent();
	if (!IsValid(Component))
	{
		return false;
	}

	const TArray<FVector4>& TransformRows = Component->GetInstanceTransformRows();
	const uint32 InstanceCount = static_cast<uint32>(Component->GetInstanceCount());
	if (InstanceCount == 0)
	{
		return false;
	}

	const uint32 CurrentVersion = Component->GetInstanceVersion();
	if (UploadedInstanceVersion != CurrentVersion || UploadedInstanceCount != InstanceCount)
	{
		if (InstanceBuffer.GetStride() != sizeof(FStaticMeshInstanceVertex))
		{
			InstanceBuffer.Create(Device, InstanceCount, sizeof(FStaticMeshInstanceVertex));
		}

		InstanceBuffer.EnsureCapacity(Device, InstanceCount);
		if (!InstanceBuffer.Update(Context, TransformRows.data(), InstanceCount))
		{
			return false;
		}

		UploadedInstanceVersion = CurrentVersion;
		UploadedInstanceCount = InstanceCount;
	}

	OutBuffer.InstanceVB = InstanceBuffer.GetBuffer();
	OutBuffer.InstanceStride = sizeof(FStaticMeshInstanceVertex);
	OutBuffer.InstanceCount = InstanceCount;
	return OutBuffer.InstanceVB != nullptr;
}
