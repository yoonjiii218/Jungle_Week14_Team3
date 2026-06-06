#pragma once

#include "Render/RenderPass/RenderPassBase.h"

class FAlphaBlendPass final : public FRenderPassBase
{
public:
	FAlphaBlendPass();

	bool BeginPass(const FPassContext& Ctx) override;
	void EndPass(const FPassContext& Ctx) override;
};
