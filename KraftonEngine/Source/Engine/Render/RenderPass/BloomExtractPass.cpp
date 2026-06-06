#include "BloomExtractPass.h"
#include "RenderPassRegistry.h"

#include "Render/Device/D3DDevice.h"
#include "Render/Types/FrameContext.h"
#include "Render/Types/RenderConstants.h"
#include "Render/Command/DrawCommandList.h"

REGISTER_RENDER_PASS(FBloomExtractPass)

FBloomExtractPass::FBloomExtractPass()
{
	PassType = ERenderPass::BloomExtract;
	RenderState = { EDepthStencilState::NoDepth, EBlendState::Opaque,
		ERasterizerState::SolidNoCull, D3D11_PRIMITIVE_TOPOLOGY_TRIANGLELIST, false };
}

bool FBloomExtractPass::BeginPass(const FPassContext& Ctx)
{
	const FFrameContext& Frame = Ctx.Frame;
	if (!Frame.RenderOptions.ShowFlags.bBloom || !Frame.RenderOptions.ShowFlags.bGammaCorrection
		|| !Frame.SceneColorCopyTexture || !Frame.SceneColorCopySRV || !Frame.ViewportRenderTexture || !Frame.BloomRTV)
	{
		return false;
	}

	ID3D11DeviceContext* DC = Ctx.Device.GetDeviceContext();
	ID3D11ShaderResourceView* NullSRVs[2] = { nullptr, nullptr };
	DC->PSSetShaderResources(ESystemTexSlot::SceneColor, 1, &NullSRVs[0]);
	DC->PSSetShaderResources(ESystemTexSlot::Bloom, 1, &NullSRVs[1]);

	DC->OMSetRenderTargets(0, nullptr, nullptr);
	DC->CopyResource(Frame.SceneColorCopyTexture, Frame.ViewportRenderTexture);
	DC->OMSetRenderTargets(1, &Frame.BloomRTV, nullptr);

	D3D11_VIEWPORT BloomViewport = {};
	BloomViewport.Width = static_cast<float>((static_cast<uint32>(Frame.ViewportWidth) + 1) / 2);
	BloomViewport.Height = static_cast<float>((static_cast<uint32>(Frame.ViewportHeight) + 1) / 2);
	BloomViewport.MinDepth = 0.0f;
	BloomViewport.MaxDepth = 1.0f;
	DC->RSSetViewports(1, &BloomViewport);

	ID3D11ShaderResourceView* SceneColorSRV = Frame.SceneColorCopySRV;
	DC->PSSetShaderResources(ESystemTexSlot::SceneColor, 1, &SceneColorSRV);

	Ctx.Cache.bForceAll = true;
	return true;
}

void FBloomExtractPass::EndPass(const FPassContext& Ctx)
{
	ID3D11DeviceContext* DC = Ctx.Device.GetDeviceContext();
	ID3D11ShaderResourceView* NullSRV = nullptr;
	DC->PSSetShaderResources(ESystemTexSlot::SceneColor, 1, &NullSRV);

	D3D11_VIEWPORT Viewport = {};
	Viewport.Width = Ctx.Frame.ViewportWidth;
	Viewport.Height = Ctx.Frame.ViewportHeight;
	Viewport.MinDepth = 0.0f;
	Viewport.MaxDepth = 1.0f;
	DC->RSSetViewports(1, &Viewport);
	DC->OMSetRenderTargets(1, &Ctx.Cache.RTV, Ctx.Cache.DSV);
	Ctx.Cache.bForceAll = true;
}
