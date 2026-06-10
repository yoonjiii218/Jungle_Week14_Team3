#include "UI/RmlUiDocumentManager.h"

#include "Asset/AssetPackage.h"
#include "Object/GarbageCollection.h"
#include "Platform/Paths.h"
#include "Serialization/WindowsArchive.h"
#include "UI/RmlUiDocumentAsset.h"

#include <algorithm>
#include <filesystem>

URmlUiDocumentAsset* FRmlUiDocumentManager::Load(const FString& Path)
{
	const FString NormalizedPath = FPaths::MakeProjectRelative(Path);

	auto It = LoadedDocuments.find(NormalizedPath);
	if (It != LoadedDocuments.end())
	{
		return It->second;
	}

	if (!FAssetPackage::IsAssetPackagePath(NormalizedPath))
	{
		return nullptr;
	}

	FWindowsBinReader Ar(NormalizedPath);
	if (!Ar.IsValid())
	{
		return nullptr;
	}

	FAssetPackageHeader Header;
	Ar << Header;
	if (!Header.IsValid(EAssetPackageType::RmlUiDocument))
	{
		return nullptr;
	}

	FAssetImportMetadata Metadata;
	Ar << Metadata;

	URmlUiDocumentAsset* NewAsset = UObjectManager::Get().CreateObject<URmlUiDocumentAsset>();
	NewAsset->Serialize(Ar);
	if (!Ar.IsValid())
	{
		UObjectManager::Get().DestroyObject(NewAsset);
		return nullptr;
	}

	NewAsset->SetSourcePath(NormalizedPath);
	LoadedDocuments.emplace(NormalizedPath, NewAsset);
	return NewAsset;
}

URmlUiDocumentAsset* FRmlUiDocumentManager::Reload(const FString& Path)
{
	const FString NormalizedPath = FPaths::MakeProjectRelative(Path);
	LoadedDocuments.erase(NormalizedPath);
	return Load(NormalizedPath);
}

URmlUiDocumentAsset* FRmlUiDocumentManager::Find(const FString& Path) const
{
	const FString NormalizedPath = FPaths::MakeProjectRelative(Path);
	auto It = LoadedDocuments.find(NormalizedPath);
	return It != LoadedDocuments.end() ? It->second : nullptr;
}

bool FRmlUiDocumentManager::Save(URmlUiDocumentAsset* Asset)
{
	if (!Asset)
	{
		return false;
	}

	const FString& Path = Asset->GetSourcePath();
	if (Path.empty())
	{
		return false;
	}

	FWindowsBinWriter Ar(FPaths::MakeProjectRelative(Path));
	if (!Ar.IsValid())
	{
		return false;
	}

	FAssetPackageHeader Header;
	Header.Type = static_cast<uint32>(EAssetPackageType::RmlUiDocument);
	FAssetImportMetadata Metadata;

	Ar << Header;
	Ar << Metadata;
	Asset->Serialize(Ar);
	return Ar.IsValid();
}

void FRmlUiDocumentManager::RefreshAvailableDocuments()
{
	const std::filesystem::path ContentRoot = std::filesystem::path(FPaths::RootDir()) / L"Content";
	if (!std::filesystem::exists(ContentRoot))
	{
		return;
	}

	const std::filesystem::path ProjectRoot(FPaths::RootDir());
	AvailableDocumentFiles.clear();

	for (const auto& Entry : std::filesystem::recursive_directory_iterator(ContentRoot))
	{
		if (!Entry.is_regular_file())
		{
			continue;
		}

		std::wstring Ext = Entry.path().extension().wstring();
		std::transform(Ext.begin(), Ext.end(), Ext.begin(), ::towlower);
		if (Ext != L".uasset")
		{
			continue;
		}

		const FString RelPath = FPaths::MakeProjectRelative(FPaths::ToUtf8(Entry.path().wstring()));
		FAssetImportMetadata Metadata;
		if (!FAssetPackage::ReadMetadata(RelPath, EAssetPackageType::RmlUiDocument, Metadata))
		{
			continue;
		}

		FAssetListItem Item;
		Item.DisplayName = FPaths::ToUtf8(Entry.path().stem().wstring());
		Item.FullPath = RelPath;
		AvailableDocumentFiles.push_back(std::move(Item));
	}
}

void FRmlUiDocumentManager::AddReferencedObjects(FReferenceCollector& Collector)
{
	for (auto& Pair : LoadedDocuments)
	{
		Collector.AddReferencedObject(Pair.second);
	}
}

void FRmlUiDocumentManager::ClearCache()
{
	LoadedDocuments.clear();
	AvailableDocumentFiles.clear();
}
