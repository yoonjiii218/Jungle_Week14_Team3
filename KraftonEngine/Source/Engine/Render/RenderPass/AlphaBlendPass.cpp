#include "AlphaBlendPass.h"
#include "RenderPassRegistry.h"

#include "Render/Device/D3DDevice.h"
#include "Render/Types/FrameContext.h"
#include "Render/Types/RenderConstants.h"
#include "Render/Command/DrawCommandList.h"

REGISTER_RENDER_PASS(FAlphaBlendPass)

FAlphaBlendPass::FAlphaBlendPass()
{
	PassType    = ERenderPass::AlphaBlend;
	RenderState = { EDepthStencilState::DepthReadOnly, EBlendState::AlphaBlend,
	                ERasterizerState::SolidNoCull, D3D11_PRIMITIVE_TOPOLOGY_TRIANGLELIST, true };
}
bool FAlphaBlendPass::BeginPass(const FPassContext& Ctx)
{
	ID3D11DeviceContext* DC = Ctx.Device.GetDeviceContext();
	const FFrameContext& Frame = Ctx.Frame;

	// Refraction materials need the already-rendered opaque scene as background.
	// A render target cannot be sampled directly while it is also the current RT,
	// so copy the viewport color into the dedicated SceneColorCopy texture before
	// drawing AlphaBlend objects, then bind that copy as t17.
	if (Frame.SceneColorCopyTexture && Frame.SceneColorCopySRV && Frame.ViewportRenderTexture)
	{
		ID3D11ShaderResourceView* NullSRV = nullptr;
		DC->PSSetShaderResources(ESystemTexSlot::SceneColor, 1, &NullSRV);

		DC->CopyResource(Frame.SceneColorCopyTexture, Frame.ViewportRenderTexture);

		ID3D11ShaderResourceView* SceneColorSRV = Frame.SceneColorCopySRV;
		DC->PSSetShaderResources(ESystemTexSlot::SceneColor, 1, &SceneColorSRV);
	}

	Ctx.Cache.bForceAll = true;
	return true;
}

void FAlphaBlendPass::EndPass(const FPassContext& Ctx)
{
	ID3D11ShaderResourceView* NullSRV = nullptr;
	Ctx.Device.GetDeviceContext()->PSSetShaderResources(ESystemTexSlot::SceneColor, 1, &NullSRV);
	Ctx.Cache.bForceAll = true;
}
