#include "SelectionMaskPass.h"
#include "RenderPassRegistry.h"

REGISTER_RENDER_PASS(FSelectionMaskPass)

FSelectionMaskPass::FSelectionMaskPass()
{
	PassType    = ERenderPass::SelectionMask;
	RenderState = { EDepthStencilState::StencilWrite, EBlendState::NoColor,
	                ERasterizerState::SolidNoCull, D3D11_PRIMITIVE_TOPOLOGY_TRIANGLELIST, false };
}

REGISTER_RENDER_PASS(FGameplayFocusMaskPass)

FGameplayFocusMaskPass::FGameplayFocusMaskPass()
{
	PassType = ERenderPass::GameplayFocusMask;
	RenderState = { EDepthStencilState::StencilWriteDepthTestGameplayFocus, EBlendState::NoColor,
		ERasterizerState::SolidNoCull, D3D11_PRIMITIVE_TOPOLOGY_TRIANGLELIST, false };
}
