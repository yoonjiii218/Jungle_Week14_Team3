#pragma once

#include "Core/Types/CoreTypes.h"

class UEditorEngine;

class FEditorWidget
{
public:
	virtual ~FEditorWidget() = default;

	void Initialize(UEditorEngine* InEditorEngine);
	virtual void Render(float DeltaTime) = 0;

protected:
	UEditorEngine* EditorEngine = nullptr;
};
