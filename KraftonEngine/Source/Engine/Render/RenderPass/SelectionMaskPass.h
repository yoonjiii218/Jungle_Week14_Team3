#pragma once

#include "Render/RenderPass/RenderPassBase.h"

class FSelectionMaskPass final : public FRenderPassBase
{
public:
	FSelectionMaskPass();
};

class FGameplayFocusMaskPass final : public FRenderPassBase
{
public:
	FGameplayFocusMaskPass();
};
