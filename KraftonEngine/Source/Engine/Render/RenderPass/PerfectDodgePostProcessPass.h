#pragma once

#include "Render/RenderPass/RenderPassBase.h"

class FPerfectDodgePostProcessPass final : public FRenderPassBase
{
public:
	FPerfectDodgePostProcessPass();
	bool BeginPass(const FPassContext& Ctx) override;
	void EndPass(const FPassContext& Ctx) override;
};
