#pragma once

#include "Render/RenderPass/RenderPassBase.h"

class FBloomExtractPass final : public FRenderPassBase
{
public:
	FBloomExtractPass();
	bool BeginPass(const FPassContext& Ctx) override;
	void EndPass(const FPassContext& Ctx) override;
};
