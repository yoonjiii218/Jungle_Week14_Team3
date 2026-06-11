#include "BlendStateManager.h"
#include <algorithm>
#include <cmath>

#define SAFE_RELEASE(Obj) if (Obj) { Obj->Release(); Obj = nullptr; }

void FBlendStateManager::Create(ID3D11Device* InDevice)
{
	// Alpha Blend
	D3D11_BLEND_DESC Desc = {};
	Desc.RenderTarget[0].BlendEnable = TRUE;
	Desc.RenderTarget[0].SrcBlend = D3D11_BLEND_SRC_ALPHA;
	Desc.RenderTarget[0].DestBlend = D3D11_BLEND_INV_SRC_ALPHA;
	Desc.RenderTarget[0].BlendOp = D3D11_BLEND_OP_ADD;
	Desc.RenderTarget[0].SrcBlendAlpha = D3D11_BLEND_SRC_ALPHA;
	Desc.RenderTarget[0].DestBlendAlpha = D3D11_BLEND_INV_SRC_ALPHA;
	Desc.RenderTarget[0].BlendOpAlpha = D3D11_BLEND_OP_ADD;
	Desc.RenderTarget[0].RenderTargetWriteMask = D3D11_COLOR_WRITE_ENABLE_ALL;
	InDevice->CreateBlendState(&Desc, &Alpha);

	// CameraRayFade: shader alpha와 무관하게 per-command blend factor로 RGB를 합성.
	// RGB = Src * factor + Dst * (1 - factor). 카메라 occluder 전체 페이드 전용.
	Desc = {};
	Desc.AlphaToCoverageEnable = FALSE;
	Desc.IndependentBlendEnable = FALSE;
	Desc.RenderTarget[0].BlendEnable = TRUE;
	Desc.RenderTarget[0].SrcBlend = D3D11_BLEND_BLEND_FACTOR;
	Desc.RenderTarget[0].DestBlend = D3D11_BLEND_INV_BLEND_FACTOR;
	Desc.RenderTarget[0].BlendOp = D3D11_BLEND_OP_ADD;
	Desc.RenderTarget[0].SrcBlendAlpha = D3D11_BLEND_ONE;
	Desc.RenderTarget[0].DestBlendAlpha = D3D11_BLEND_ZERO;
	Desc.RenderTarget[0].BlendOpAlpha = D3D11_BLEND_OP_ADD;
	Desc.RenderTarget[0].RenderTargetWriteMask = D3D11_COLOR_WRITE_ENABLE_ALL;
	InDevice->CreateBlendState(&Desc, &CameraRayFade);

	// Additive: alpha-weighted additive — RGB = Src*SrcAlpha + Dest*1
	Desc = {};
	Desc.AlphaToCoverageEnable = FALSE;
	Desc.IndependentBlendEnable = FALSE;
	Desc.RenderTarget[0].BlendEnable = TRUE;
	Desc.RenderTarget[0].SrcBlend = D3D11_BLEND_SRC_ALPHA;
	Desc.RenderTarget[0].DestBlend = D3D11_BLEND_ONE;
	Desc.RenderTarget[0].BlendOp = D3D11_BLEND_OP_ADD;
	Desc.RenderTarget[0].SrcBlendAlpha = D3D11_BLEND_ONE;
	Desc.RenderTarget[0].DestBlendAlpha = D3D11_BLEND_ZERO;
	Desc.RenderTarget[0].BlendOpAlpha = D3D11_BLEND_OP_ADD;
	Desc.RenderTarget[0].RenderTargetWriteMask = D3D11_COLOR_WRITE_ENABLE_ALL;
	InDevice->CreateBlendState(&Desc, &Additive);

	// No Color Write
	Desc = {};
	Desc.AlphaToCoverageEnable = FALSE;
	Desc.IndependentBlendEnable = FALSE;
	Desc.RenderTarget[0].BlendEnable = FALSE;
	Desc.RenderTarget[0].SrcBlend = D3D11_BLEND_ONE;
	Desc.RenderTarget[0].DestBlend = D3D11_BLEND_ZERO;
	Desc.RenderTarget[0].BlendOp = D3D11_BLEND_OP_ADD;
	Desc.RenderTarget[0].SrcBlendAlpha = D3D11_BLEND_ONE;
	Desc.RenderTarget[0].DestBlendAlpha = D3D11_BLEND_ZERO;
	Desc.RenderTarget[0].BlendOpAlpha = D3D11_BLEND_OP_ADD;
	Desc.RenderTarget[0].RenderTargetWriteMask = 0;
	InDevice->CreateBlendState(&Desc, &NoColorWrite);
}

void FBlendStateManager::Release()
{
	SAFE_RELEASE(Alpha);
	SAFE_RELEASE(CameraRayFade);
	SAFE_RELEASE(Additive);
	SAFE_RELEASE(NoColorWrite);
}

void FBlendStateManager::Set(ID3D11DeviceContext* InContext, EBlendState InState, float InBlendFactor)
{
	const float ClampedFactor = std::max(0.0f, std::min(InBlendFactor, 1.0f));
	const bool bUsesBlendFactor = (InState == EBlendState::CameraRayFade);
	if (CurrentState == InState && (!bUsesBlendFactor || std::abs(CurrentBlendFactor - ClampedFactor) <= 1e-4f))
	{
		return;
	}

	const float ZeroFactor[4] = { 0, 0, 0, 0 };
	const float FadeFactor[4] = { ClampedFactor, ClampedFactor, ClampedFactor, ClampedFactor };

	switch (InState)
	{
	case EBlendState::Opaque:        InContext->OMSetBlendState(nullptr, ZeroFactor, 0xffffffff);       break;
	case EBlendState::AlphaBlend:    InContext->OMSetBlendState(Alpha, ZeroFactor, 0xffffffff);         break;
	case EBlendState::CameraRayFade: InContext->OMSetBlendState(CameraRayFade, FadeFactor, 0xffffffff); break;
	case EBlendState::Additive:      InContext->OMSetBlendState(Additive, ZeroFactor, 0xffffffff);      break;
	case EBlendState::NoColor:       InContext->OMSetBlendState(NoColorWrite, ZeroFactor, 0xFFFFFFFF);  break;
	}

	CurrentState = InState;
	CurrentBlendFactor = bUsesBlendFactor ? ClampedFactor : -1.0f;
}
