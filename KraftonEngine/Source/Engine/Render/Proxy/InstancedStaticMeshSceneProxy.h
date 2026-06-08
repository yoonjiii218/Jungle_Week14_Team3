#pragma once

#include "Render/Proxy/StaticMeshSceneProxy.h"
#include "Render/Resource/Buffer.h"

class UInstancedStaticMeshComponent;

class FInstancedStaticMeshSceneProxy : public FStaticMeshSceneProxy
{
public:
	FInstancedStaticMeshSceneProxy(UInstancedStaticMeshComponent* InComponent);
	~FInstancedStaticMeshSceneProxy() override = default;

	bool PrepareDrawBuffer(ID3D11Device* Device, ID3D11DeviceContext* Context,
		FDrawCommandBuffer& OutBuffer) const override;

private:
	UInstancedStaticMeshComponent* GetInstancedStaticMeshComponent() const;

	mutable FDynamicVertexBuffer InstanceBuffer;
	mutable uint32 UploadedInstanceVersion = 0;
	mutable uint32 UploadedInstanceCount = 0;
};
