#include "Render/Proxy/SubUVSceneProxy.h"
#include "Component/Primitive/SubUVComponent.h"
#include "Render/Types/FrameContext.h"
#include "Render/Resource/MeshBufferManager.h"
#include "Materials/Material.h"
#include "Object/Object.h"
#include "Math/MathUtils.h"
#include "Math/Quat.h"

#include <cmath>

namespace
{
	void RotateBasisAroundAxis(float Degrees, const FVector& Axis, FVector& A, FVector& B)
	{
		if (std::abs(Degrees) <= 0.0001f)
		{
			return;
		}

		const FVector SafeAxis = Axis.GetSafeNormal(1.0e-6f, FVector::ForwardVector);
		const FQuat Rotation = FQuat::FromAxisAngle(SafeAxis, Degrees * FMath::DegToRad);
		A = Rotation.RotateVector(A).GetSafeNormal(1.0e-6f, A);
		B = Rotation.RotateVector(B).GetSafeNormal(1.0e-6f, B);
	}
}

// ============================================================
// FSubUVSceneProxy
// ============================================================
FSubUVSceneProxy::FSubUVSceneProxy(USubUVComponent* InComponent)
	: FBillboardSceneProxy(static_cast<UBillboardComponent*>(InComponent))
{
	ProxyFlags &= ~EPrimitiveProxyFlags::ShowAABB;
}

FSubUVSceneProxy::~FSubUVSceneProxy()
{
	UVRegionCB.Release();
}

void FSubUVSceneProxy::UpdateTransform()
{
	FBillboardSceneProxy::UpdateTransform();

	if (USubUVComponent* Comp = GetSubUVComponent())
	{
		CachedSpriteRotation = Comp->GetSpriteRotation();
	}
}

void FSubUVSceneProxy::UpdateMesh()
{
	USubUVComponent* Comp = GetSubUVComponent();
	if (!IsValid(Comp))
	{
		MeshBuffer = nullptr;
		SectionDraws.clear();
		bVisible = false;
		return;
	}

	// TexturedQuad (FVertexPNCT with UVs) for rendering
	MeshBuffer = &FMeshBufferManager::Get().GetMeshBuffer(EMeshShape::TexturedQuad);

	UMaterial* SubUVMat = Comp->GetSubUVMaterial();

	// UV region CB를 Material에 바인딩 (b2 슬롯)
	if (SubUVMat)
		SubUVMat->BindPerShaderCB<FSubUVRegionConstants>(&UVRegionCB, ECBSlot::PerShader0);

	// Particle/FrameIndex 캐싱
	CachedParticle = Comp->GetParticle();
	CachedFrameIndex = Comp->GetFrameIndex();
	CachedSpriteRotation = Comp->GetSpriteRotation();

	// SectionDraws 단일 항목 — SubUVMaterial로 Particle SRV 바인딩
	SectionDraws.clear();
	if (SubUVMat)
	{
		const uint32 IdxCount = MeshBuffer->GetIndexBuffer().GetIndexCount();
		SectionDraws.push_back({ SubUVMat, 0, IdxCount });
	}
}

void FSubUVSceneProxy::UpdateMaterial()
{
	// TickComponent에서 FrameIndex 변경 시 Material dirty로 호출됨
	USubUVComponent* Comp = GetSubUVComponent();
	if (!IsValid(Comp))
	{
		SectionDraws.clear();
		bVisible = false;
		return;
	}
	CachedFrameIndex = Comp->GetFrameIndex();
	CachedParticle = Comp->GetParticle();
	CachedSpriteRotation = Comp->GetSpriteRotation();

	// SectionDraws 갱신 — SubUVMaterial의 CachedSRV는 Component가 관리
	SectionDraws.clear();
	UMaterial* SubUVMat = Comp->GetSubUVMaterial();
	if (SubUVMat)
	{
		const uint32 IdxCount = MeshBuffer ? MeshBuffer->GetIndexBuffer().GetIndexCount() : 0;
		SectionDraws.push_back({ SubUVMat, 0, IdxCount });
	}
}

void FSubUVSceneProxy::UpdatePerViewport(const FFrameContext& Frame)
{
	if (!bVisible) return;

	if (!CachedParticle || !CachedParticle->IsLoaded())
	{
		bVisible = false;
		return;
	}

	// Billboard matrix. SubUV keeps camera-facing alignment, then applies
	// billboard-local X/Y/Z sprite rotation for slash/streak orientation.
	FVector BillboardForward = Frame.CameraForward * -1.0f;
	FVector BillboardRight = Frame.CameraRight;
	FVector BillboardUp = Frame.CameraUp;

	if (!CachedSpriteRotation.IsNearlyZero(0.0001f))
	{
		RotateBasisAroundAxis(CachedSpriteRotation.X, BillboardRight, BillboardUp, BillboardForward);
		RotateBasisAroundAxis(CachedSpriteRotation.Y, BillboardUp, BillboardForward, BillboardRight);
		RotateBasisAroundAxis(CachedSpriteRotation.Z, BillboardForward, BillboardRight, BillboardUp);
	}

	FMatrix RotMatrix;
	RotMatrix.SetAxes(BillboardForward, BillboardRight, BillboardUp);
	FMatrix BillboardMatrix = FMatrix::MakeScaleMatrix(CachedScale)
		* RotMatrix * FMatrix::MakeTranslationMatrix(CachedLocation);

	PerObjectConstants = FPerObjectConstants::FromWorldMatrix(BillboardMatrix);
	MarkPerObjectCBDirty();

	// Update UV region from cached frame index
	const uint32 Cols = CachedParticle->Columns;
	const uint32 Rows = CachedParticle->Rows;
	if (Cols > 0 && Rows > 0)
	{
		const float FrameW = 1.0f / static_cast<float>(Cols);
		const float FrameH = 1.0f / static_cast<float>(Rows);
		const uint32 Col = CachedFrameIndex % Cols;
		const uint32 Row = CachedFrameIndex / Cols;

		UMaterial* SubUVMat = SectionDraws.empty() ? nullptr : SectionDraws[0].Material;
		if (!IsValid(SubUVMat)) return;
		FSubUVRegionConstants& Region = SubUVMat->GetPerShaderAs<FSubUVRegionConstants>();
		Region.U = Col * FrameW;
		Region.V = Row * FrameH;
		Region.Width = FrameW;
		Region.Height = FrameH;
	}
}

USubUVComponent* FSubUVSceneProxy::GetSubUVComponent() const
{
	return Cast<USubUVComponent>(GetOwner());
}
