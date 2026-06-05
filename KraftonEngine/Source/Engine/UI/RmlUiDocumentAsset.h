#pragma once

#include "Object/Object.h"

#include "Source/Engine/UI/RmlUiDocumentAsset.generated.h"

class FArchive;

UCLASS()
class URmlUiDocumentAsset : public UObject
{
public:
	GENERATED_BODY()

	URmlUiDocumentAsset() = default;
	~URmlUiDocumentAsset() override = default;

	void SetSourcePath(const FString& InSourcePath) { SourcePath = InSourcePath; }
	const FString& GetSourcePath() const { return SourcePath; }

	void SetDocumentSource(const FString& InDocumentSource) { DocumentSource = InDocumentSource; }
	const FString& GetDocumentSource() const { return DocumentSource; }

	void SetDesignerState(const FString& InDesignerState) { DesignerState = InDesignerState; }
	const FString& GetDesignerState() const { return DesignerState; }

	void InitializeDefault();
	void Serialize(FArchive& Ar) override;

private:
	FString SourcePath;
	FString DocumentSource;
	FString DesignerState;
};
