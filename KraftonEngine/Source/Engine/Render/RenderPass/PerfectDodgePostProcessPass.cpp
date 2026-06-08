#include "PerfectDodgePostProcessPass.h"
#include "RenderPassRegistry.h"

#include "Render/Device/D3DDevice.h"
#include "Render/Types/FrameContext.h"
#include "Render/Types/RenderConstants.h"
#include "Render/Command/DrawCommandList.h"

REGISTER_RENDER_PASS(FPerfectDodgePostProcessPass)

FPerfectDodgePostProcessPass::FPerfectDodgePostProcessPass()
{
	PassType = ERenderPass::PerfectDodge;
	RenderState = { EDepthStencilState::NoDepth, EBlendState::Opaque,
		ERasterizerState::SolidNoCull, D3D11_PRIMITIVE_TOPOLOGY_TRIANGLELIST, false };
}

bool FPerfectDodgePostProcessPass::BeginPass(const FPassContext& Ctx)
{
	const FFrameContext& Frame = Ctx.Frame;
	if (!PerfectDodgePostProcessDebug::IsPostProcessEnabled()
		|| !Frame.PerfectDodgePostProcess.bEnabled
		|| !Frame.SceneColorCopyTexture || !Frame.ViewportRenderTexture || !Frame.SceneColorCopySRV
		|| !Frame.DepthTexture || !Frame.DepthCopyTexture || !Frame.DepthCopySRV)
	{
		return false;
	}

	ID3D11DeviceContext* DC = Ctx.Device.GetDeviceContext();
	FStateCache& Cache = Ctx.Cache;

	ID3D11ShaderResourceView* NullSRV = nullptr;
	DC->PSSetShaderResources(ESystemTexSlot::SceneColor, 1, &NullSRV);
	DC->PSSetShaderResources(ESystemTexSlot::SceneDepth, 1, &NullSRV);
	DC->PSSetShaderResources(ESystemTexSlot::GBufferNormal, 1, &NullSRV);

	DC->OMSetRenderTargets(0, nullptr, nullptr);
	DC->CopyResource(Frame.SceneColorCopyTexture, Frame.ViewportRenderTexture);
	DC->CopyResource(Frame.DepthCopyTexture, Frame.DepthTexture);
	DC->OMSetRenderTargets(1, &Cache.RTV, Cache.DSV);

	ID3D11ShaderResourceView* SceneColorSRV = Frame.SceneColorCopySRV;
	ID3D11ShaderResourceView* DepthSRV = Frame.DepthCopySRV;
	DC->PSSetShaderResources(ESystemTexSlot::SceneColor, 1, &SceneColorSRV);
	DC->PSSetShaderResources(ESystemTexSlot::SceneDepth, 1, &DepthSRV);

	if (Frame.NormalSRV)
	{
		ID3D11ShaderResourceView* NormalSRV = Frame.NormalSRV;
		DC->PSSetShaderResources(ESystemTexSlot::GBufferNormal, 1, &NormalSRV);
	}

	Cache.bForceAll = true;
	return true;
}

void FPerfectDodgePostProcessPass::EndPass(const FPassContext& Ctx)
{
	ID3D11ShaderResourceView* NullSRV = nullptr;
	ID3D11DeviceContext* DC = Ctx.Device.GetDeviceContext();
	DC->PSSetShaderResources(ESystemTexSlot::SceneColor, 1, &NullSRV);
	DC->PSSetShaderResources(ESystemTexSlot::SceneDepth, 1, &NullSRV);
	DC->PSSetShaderResources(ESystemTexSlot::GBufferNormal, 1, &NullSRV);
}
