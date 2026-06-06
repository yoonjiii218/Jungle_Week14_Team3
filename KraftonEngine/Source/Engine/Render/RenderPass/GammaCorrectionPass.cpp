#include "GammaCorrectionPass.h"
#include "RenderPassRegistry.h"

#include "Render/Device/D3DDevice.h"
#include "Render/Types/FrameContext.h"
#include "Render/Types/RenderConstants.h"
#include "Render/Command/DrawCommandList.h"

REGISTER_RENDER_PASS(FGammaCorrectionPass)

FGammaCorrectionPass::FGammaCorrectionPass()
{
	PassType = ERenderPass::GammaCorrection;
	RenderState = { EDepthStencilState::NoDepth, EBlendState::Opaque,
					ERasterizerState::SolidNoCull, D3D11_PRIMITIVE_TOPOLOGY_TRIANGLELIST, false };
}

bool FGammaCorrectionPass::BeginPass(const FPassContext& Ctx)
{
	const FFrameContext& Frame = Ctx.Frame;
	if (!Frame.SceneColorCopyTexture || !Frame.ViewportRenderTexture || !Frame.SceneColorCopySRV || !Frame.BloomSRV)
	{
		return false;
	}

	ID3D11DeviceContext* DC = Ctx.Device.GetDeviceContext();
	FStateCache& Cache = Ctx.Cache;

	DC->CopyResource(Frame.SceneColorCopyTexture, Frame.ViewportRenderTexture);
	DC->OMSetRenderTargets(1, &Cache.RTV, Cache.DSV);

	ID3D11ShaderResourceView* SceneColorSRV = Frame.SceneColorCopySRV;
	DC->PSSetShaderResources(ESystemTexSlot::SceneColor, 1, &SceneColorSRV);
	ID3D11ShaderResourceView* BloomSRV = Frame.BloomSRV;
	DC->PSSetShaderResources(ESystemTexSlot::Bloom, 1, &BloomSRV);

	Cache.bForceAll = true;
	return true;
}

void FGammaCorrectionPass::EndPass(const FPassContext& Ctx)
{
	ID3D11ShaderResourceView* NullSRVs[2] = { nullptr, nullptr };
	Ctx.Device.GetDeviceContext()->PSSetShaderResources(ESystemTexSlot::SceneColor, 1, &NullSRVs[0]);
	Ctx.Device.GetDeviceContext()->PSSetShaderResources(ESystemTexSlot::Bloom, 1, &NullSRVs[1]);
}
