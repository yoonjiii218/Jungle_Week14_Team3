#pragma once

#include "Asset/AssetRegistry.h"
#include "Core/Singleton.h"
#include "Core/Types/CoreTypes.h"
#include "Object/GarbageCollection.h"

class URmlUiDocumentAsset;

class FRmlUiDocumentManager : public TSingleton<FRmlUiDocumentManager>, public FGCObject
{
	friend class TSingleton<FRmlUiDocumentManager>;

public:
	URmlUiDocumentAsset* Load(const FString& Path);
	URmlUiDocumentAsset* Reload(const FString& Path);
	URmlUiDocumentAsset* Find(const FString& Path) const;
	bool Save(URmlUiDocumentAsset* Asset);

	void RefreshAvailableDocuments();
	const TArray<FAssetListItem>& GetAvailableDocumentFiles() const { return AvailableDocumentFiles; }

	const char* GetReferencerName() const override { return "FRmlUiDocumentManager"; }
	void AddReferencedObjects(FReferenceCollector& Collector) override;
	void ClearCache();

private:
	TMap<FString, URmlUiDocumentAsset*> LoadedDocuments;
	TArray<FAssetListItem> AvailableDocumentFiles;
};
