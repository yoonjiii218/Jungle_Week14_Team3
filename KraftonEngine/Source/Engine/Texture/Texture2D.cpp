#include "Texture/Texture2D.h"
#include "Object/Reflection/ObjectFactory.h"
#include "Object/GarbageCollection.h"
#include "Core/Logging/Log.h"
#include "Platform/Paths.h"
#include "WICTextureLoader.h"
#include "DDSTextureLoader.h"
#include "stb_image.h"

#include <algorithm>
#include <cstdio>
#include <cstring>
#include <cwctype>
#include <d3d11.h>
#include <filesystem>
#include <fstream>
#include <vector>

std::map<FString, UTexture2D*> UTexture2D::TextureCache;

class FTexture2DCacheRoot final : public FGCObject
{
public:
    const char* GetReferencerName() const override { return "FTexture2DCacheRoot"; }
    void AddReferencedObjects(FReferenceCollector& Collector) override
    {
        for (auto& Pair : UTexture2D::TextureCache)
        {
            Collector.AddReferencedObject(Pair.second);
        }
    }
};

namespace
{
    FTexture2DCacheRoot GTexture2DCacheRoot;
}

FString UTexture2D::MakeCacheKey(const FString& FilePath, ETextureColorSpace ColorSpace)
{
	return FilePath + (ColorSpace == ETextureColorSpace::SRGB ? "#srgb" : "#linear");
}

UTexture2D::~UTexture2D()
{
	if (SRV)
	{
		if (TrackedTextureMemory > 0)
		{
			MemoryStats::SubTextureMemory(TrackedTextureMemory);
			TrackedTextureMemory = 0;
		}

		SRV->Release();
		SRV = nullptr;
	}

	// 캐시에서 제거
	auto It = TextureCache.find(MakeCacheKey(SourceFilePath, ColorSpace));
	if (It != TextureCache.end() && It->second == this)
	{
		TextureCache.erase(It);
	}
}

void UTexture2D::ReleaseAllGPU()
{
	for (auto& [Path, Texture] : TextureCache)
	{
        if (!Texture) continue;
	    
		if (Texture && Texture->SRV)
		{
			if (Texture->TrackedTextureMemory > 0)
			{
				MemoryStats::SubTextureMemory(Texture->TrackedTextureMemory);
				Texture->TrackedTextureMemory = 0;
			}
			Texture->SRV->Release();
			Texture->SRV = nullptr;
		}

	}
	TextureCache.clear();
}

UTexture2D* UTexture2D::LoadFromFile(const FString& FilePath, ID3D11Device* Device, ETextureColorSpace InColorSpace)
{
	if (FilePath.empty() || !Device) return nullptr;

	// 캐시 히트
	const FString CacheKey = MakeCacheKey(FilePath, InColorSpace);
	auto It = TextureCache.find(CacheKey);
	if (It != TextureCache.end())
	{
		return It->second;
	}

	// 새 UTexture2D 생성
	UTexture2D* Texture = UObjectManager::Get().CreateObject<UTexture2D>();
	if (!Texture->LoadInternal(FilePath, Device, InColorSpace))
	{
		UObjectManager::Get().DestroyObject(Texture);
		return nullptr;
	}

	TextureCache[CacheKey] = Texture;
	return Texture;
}

UTexture2D* UTexture2D::LoadFromCached(const FString& FilePath, ETextureColorSpace InColorSpace)
{
	if (FilePath.empty()) return nullptr;

	auto It = TextureCache.find(MakeCacheKey(FilePath, InColorSpace));
	if (It != TextureCache.end())
	{
		return It->second;
	}

	return nullptr;
}

namespace
{
	std::wstring LowerExtension(const FString& FilePath)
	{
		std::wstring Ext = std::filesystem::path(FPaths::ToWide(FilePath)).extension().wstring();
		std::transform(Ext.begin(), Ext.end(), Ext.begin(),
			[](wchar_t c) { return static_cast<wchar_t>(std::towlower(c)); });
		return Ext;
	}

	// .tga 같이 WIC 가 native 로 못 까는 확장자를 구분.
	bool IsStbHandledExtension(const FString& FilePath)
	{
		return LowerExtension(FilePath) == L".tga";
	}

	bool IsDdsExtension(const FString& FilePath)
	{
		return LowerExtension(FilePath) == L".dds";
	}

	bool HasCommandLineFlag(const std::wstring& CommandLine, const std::wstring& Flag)
	{
		size_t Position = CommandLine.find(Flag);
		while (Position != std::wstring::npos)
		{
			const bool bStartsAtBoundary =
				Position == 0 || std::iswspace(CommandLine[Position - 1]) != 0;
			const size_t AfterFlag = Position + Flag.size();
			const bool bEndsAtBoundary =
				AfterFlag >= CommandLine.size() || std::iswspace(CommandLine[AfterFlag]) != 0;
			if (bStartsAtBoundary && bEndsAtBoundary)
			{
				return true;
			}
			Position = CommandLine.find(Flag, Position + Flag.size());
		}
		return false;
	}

	bool IsTextureBinaryCacheEnabled()
	{
		static const bool bEnabled =
			!HasCommandLineFlag(GetCommandLineW(), L"--disable-texture-binary-cache");
		return bEnabled;
	}

	struct FTextureBinaryHeader
	{
		char Magic[8] = {};
		uint32 Version = 1;
		uint32 Width = 0;
		uint32 Height = 0;
		uint32 ColorSpace = 0;
		uint64 SourceTimestamp = 0;
		uint64 SourceFileSize = 0;
		uint64 DataSize = 0;
	};

	constexpr char TextureBinaryMagic[8] = { 'K', 'E', 'U', 'T', 'E', 'X', '0', '\0' };

	uint64 HashWideString(const std::wstring& Value)
	{
		uint64 Hash = 0xcbf29ce484222325ULL;
		for (wchar_t Character : Value)
		{
			Hash ^= static_cast<uint64>(Character);
			Hash *= 0x100000001b3ULL;
		}
		return Hash;
	}

	std::filesystem::path ResolveTextureSourcePath(const FString& FilePath)
	{
		std::filesystem::path Path(FPaths::ToWide(FilePath));
		if (!Path.is_absolute())
		{
			Path = std::filesystem::path(FPaths::RootDir()) / Path;
		}
		return Path.lexically_normal();
	}

	bool GetTextureSourceState(
		const std::filesystem::path& SourcePath,
		uint64& OutTimestamp,
		uint64& OutFileSize)
	{
		std::error_code Error;
		if (!std::filesystem::exists(SourcePath, Error) ||
			!std::filesystem::is_regular_file(SourcePath, Error))
		{
			return false;
		}

		OutFileSize = static_cast<uint64>(std::filesystem::file_size(SourcePath, Error));
		if (Error)
		{
			return false;
		}

		const auto WriteTime = std::filesystem::last_write_time(SourcePath, Error);
		if (Error)
		{
			return false;
		}

		OutTimestamp = static_cast<uint64>(WriteTime.time_since_epoch().count());
		return true;
	}

	std::filesystem::path GetTextureBinaryCachePath(
		const FString& FilePath,
		ETextureColorSpace ColorSpace)
	{
		const std::filesystem::path SourcePath = ResolveTextureSourcePath(FilePath);
		const uint64 Hash = HashWideString(SourcePath.generic_wstring());

		char HashBuffer[32] = {};
		std::snprintf(
			HashBuffer,
			sizeof(HashBuffer),
			"%016llX",
			static_cast<unsigned long long>(Hash));

		std::wstring Stem = SourcePath.stem().wstring();
		if (Stem.empty())
		{
			Stem = L"Texture";
		}

		const std::wstring ColorSuffix =
			ColorSpace == ETextureColorSpace::SRGB ? L"_srgb" : L"_linear";
		const std::filesystem::path CacheDir =
			std::filesystem::path(FPaths::RootDir()) / L"Saves" / L"DerivedData" / L"TextureCache";
		return CacheDir / (Stem + L"_" + FPaths::ToWide(HashBuffer) + ColorSuffix + L".utex");
	}

	bool CreateRgba8TextureResource(
		ID3D11Device* Device,
		uint32 InWidth,
		uint32 InHeight,
		const void* Pixels,
		ETextureColorSpace InColorSpace,
		ID3D11ShaderResourceView*& OutSRV,
		uint64& OutTextureMemory)
	{
		if (!Device || !Pixels || InWidth == 0 || InHeight == 0)
		{
			return false;
		}

		D3D11_TEXTURE2D_DESC Desc = {};
		Desc.Width              = InWidth;
		Desc.Height             = InHeight;
		Desc.MipLevels          = 1;
		Desc.ArraySize          = 1;
		Desc.Format             = (InColorSpace == ETextureColorSpace::SRGB)
			? DXGI_FORMAT_R8G8B8A8_UNORM_SRGB
			: DXGI_FORMAT_R8G8B8A8_UNORM;
		Desc.SampleDesc.Count   = 1;
		Desc.SampleDesc.Quality = 0;
		Desc.Usage              = D3D11_USAGE_DEFAULT;
		Desc.BindFlags          = D3D11_BIND_SHADER_RESOURCE;

		D3D11_SUBRESOURCE_DATA InitData = {};
		InitData.pSysMem     = Pixels;
		InitData.SysMemPitch = InWidth * 4u;

		ID3D11Texture2D* Tex2D = nullptr;
		HRESULT hr = Device->CreateTexture2D(&Desc, &InitData, &Tex2D);
		if (FAILED(hr) || !Tex2D)
		{
			return false;
		}

		hr = Device->CreateShaderResourceView(Tex2D, nullptr, &OutSRV);
		if (FAILED(hr))
		{
			Tex2D->Release();
			OutSRV = nullptr;
			return false;
		}

		OutTextureMemory = MemoryStats::CalculateTextureMemory(Tex2D);
		Tex2D->Release();
		return true;
	}

	bool TryLoadTextureBinaryCache(
		const FString& FilePath,
		ID3D11Device* Device,
		ETextureColorSpace InColorSpace,
		uint32& OutWidth,
		uint32& OutHeight,
		ID3D11ShaderResourceView*& OutSRV,
		uint64& OutTextureMemory)
	{
		const std::filesystem::path SourcePath = ResolveTextureSourcePath(FilePath);
		uint64 SourceTimestamp = 0;
		uint64 SourceFileSize = 0;
		if (!GetTextureSourceState(SourcePath, SourceTimestamp, SourceFileSize))
		{
			return false;
		}

		const std::filesystem::path CachePath =
			GetTextureBinaryCachePath(FilePath, InColorSpace);
		std::ifstream File(CachePath, std::ios::binary);
		if (!File.is_open())
		{
			return false;
		}

		FTextureBinaryHeader Header;
		File.read(reinterpret_cast<char*>(&Header), sizeof(Header));
		if (!File ||
			std::memcmp(Header.Magic, TextureBinaryMagic, sizeof(TextureBinaryMagic)) != 0 ||
			Header.Version != 1 ||
			Header.ColorSpace != static_cast<uint32>(InColorSpace) ||
			Header.SourceTimestamp != SourceTimestamp ||
			Header.SourceFileSize != SourceFileSize ||
			Header.Width == 0 ||
			Header.Height == 0 ||
			Header.DataSize != static_cast<uint64>(Header.Width) * Header.Height * 4u)
		{
			return false;
		}

		std::vector<uint8> Pixels(static_cast<size_t>(Header.DataSize));
		File.read(reinterpret_cast<char*>(Pixels.data()), Pixels.size());
		if (!File)
		{
			return false;
		}

		if (!CreateRgba8TextureResource(
				Device,
				Header.Width,
				Header.Height,
				Pixels.data(),
				InColorSpace,
				OutSRV,
				OutTextureMemory))
		{
			return false;
		}

		OutWidth = Header.Width;
		OutHeight = Header.Height;
		return true;
	}

	void SaveTextureBinaryCache(
		const FString& FilePath,
		ETextureColorSpace InColorSpace,
		uint32 InWidth,
		uint32 InHeight,
		const void* Pixels)
	{
		const std::filesystem::path SourcePath = ResolveTextureSourcePath(FilePath);
		uint64 SourceTimestamp = 0;
		uint64 SourceFileSize = 0;
		if (!GetTextureSourceState(SourcePath, SourceTimestamp, SourceFileSize))
		{
			return;
		}

		const std::filesystem::path CachePath =
			GetTextureBinaryCachePath(FilePath, InColorSpace);
		std::error_code Error;
		std::filesystem::create_directories(CachePath.parent_path(), Error);
		if (Error)
		{
			return;
		}

		FTextureBinaryHeader Header;
		std::memcpy(Header.Magic, TextureBinaryMagic, sizeof(TextureBinaryMagic));
		Header.Version = 1;
		Header.Width = InWidth;
		Header.Height = InHeight;
		Header.ColorSpace = static_cast<uint32>(InColorSpace);
		Header.SourceTimestamp = SourceTimestamp;
		Header.SourceFileSize = SourceFileSize;
		Header.DataSize = static_cast<uint64>(InWidth) * InHeight * 4u;

		std::ofstream File(CachePath, std::ios::binary | std::ios::trunc);
		if (!File.is_open())
		{
			return;
		}

		File.write(reinterpret_cast<const char*>(&Header), sizeof(Header));
		File.write(reinterpret_cast<const char*>(Pixels), static_cast<std::streamsize>(Header.DataSize));
	}
}

bool UTexture2D::LoadInternal(const FString& FilePath, ID3D11Device* Device, ETextureColorSpace InColorSpace)
{
	std::wstring WidePath = FPaths::ToWide(FilePath);

	// DDS — DirectXTK의 DDSTextureLoader. WIC와 별도 경로.
	if (IsDdsExtension(FilePath))
	{
		const auto DdsFlags = (InColorSpace == ETextureColorSpace::SRGB)
			? DirectX::DDS_LOADER_FORCE_SRGB
			: DirectX::DDS_LOADER_IGNORE_SRGB;

		ID3D11Resource* Resource = nullptr;
		HRESULT hr = DirectX::CreateDDSTextureFromFileEx(
			Device, WidePath.c_str(),
			0, D3D11_USAGE_DEFAULT, D3D11_BIND_SHADER_RESOURCE,
			0, 0, DdsFlags,
			&Resource, &SRV);

		if (FAILED(hr))
		{
			UE_LOG("Failed to load DDS texture: %s", FilePath.c_str());
			return false;
		}

		if (Resource)
		{
			TrackedTextureMemory = MemoryStats::CalculateTextureMemory(Resource);
			ID3D11Texture2D* Tex2D = nullptr;
			if (SUCCEEDED(Resource->QueryInterface(__uuidof(ID3D11Texture2D), (void**)&Tex2D)))
			{
				D3D11_TEXTURE2D_DESC Desc;
				Tex2D->GetDesc(&Desc);
				Width = Desc.Width;
				Height = Desc.Height;
				Tex2D->Release();
			}
			if (TrackedTextureMemory > 0) MemoryStats::AddTextureMemory(TrackedTextureMemory);
			Resource->Release();
		}

		SourceFilePath = FilePath;
		ColorSpace = InColorSpace;
		return true;
	}

	if (IsTextureBinaryCacheEnabled() &&
		TryLoadTextureBinaryCache(
			FilePath,
			Device,
			InColorSpace,
			Width,
			Height,
			SRV,
			TrackedTextureMemory))
	{
		if (TrackedTextureMemory > 0)
		{
			MemoryStats::AddTextureMemory(TrackedTextureMemory);
		}
		SourceFilePath = FilePath;
		ColorSpace = InColorSpace;
		return true;
	}

	if (LoadInternal_STB(FilePath, Device, InColorSpace, IsTextureBinaryCacheEnabled()))
	{
		return true;
	}

	const auto LoadFlags = (InColorSpace == ETextureColorSpace::SRGB)
		? DirectX::WIC_LOADER_FORCE_SRGB
		: DirectX::WIC_LOADER_IGNORE_SRGB;

	ID3D11Resource* Resource = nullptr;
	HRESULT hr = DirectX::CreateWICTextureFromFileEx(
		Device, WidePath.c_str(),
		0,                                    // maxsize
		D3D11_USAGE_DEFAULT,                  // usage
		D3D11_BIND_SHADER_RESOURCE,           // bindFlags
		0,                                    // cpuAccessFlags
		0,                                    // miscFlags
		LoadFlags,
		&Resource, &SRV);

	if (FAILED(hr))
	{
		UE_LOG("Failed to load texture: %s", FilePath.c_str());
		return false;
	}

	// 텍스처 크기 추출
	if (Resource)
	{
		TrackedTextureMemory = MemoryStats::CalculateTextureMemory(Resource);

		ID3D11Texture2D* Tex2D = nullptr;
		if (SUCCEEDED(Resource->QueryInterface(__uuidof(ID3D11Texture2D), (void**)&Tex2D)))
		{
			D3D11_TEXTURE2D_DESC Desc;
			Tex2D->GetDesc(&Desc);
			Width = Desc.Width;
			Height = Desc.Height;
			Tex2D->Release();
		}

		if (TrackedTextureMemory > 0)
		{
			MemoryStats::AddTextureMemory(TrackedTextureMemory);
		}
		Resource->Release();
	}

	SourceFilePath = FilePath;
	ColorSpace = InColorSpace;
	return true;
}

bool UTexture2D::LoadInternal_STB(
	const FString& FilePath,
	ID3D11Device* Device,
	ETextureColorSpace InColorSpace,
	bool bWriteBinaryCache)
{
	// stbi_load 는 fopen(UTF-8) 기반이라 한글/공백 경로에서 깨질 수 있어
	// wide ifstream 으로 직접 읽고 stbi_load_from_memory 로 우회.
	const std::wstring WidePath = FPaths::ToWide(FilePath);
	std::ifstream File(WidePath, std::ios::binary | std::ios::ate);
	if (!File.is_open())
	{
		UE_LOG("Failed to open texture file: %s", FilePath.c_str());
		return false;
	}

	const std::streamsize FileSize = File.tellg();
	if (FileSize <= 0)
	{
		UE_LOG("Empty texture file: %s", FilePath.c_str());
		return false;
	}
	File.seekg(0, std::ios::beg);

	std::vector<uint8> FileBytes(static_cast<size_t>(FileSize));
	if (!File.read(reinterpret_cast<char*>(FileBytes.data()), FileSize))
	{
		UE_LOG("Failed to read texture file: %s", FilePath.c_str());
		return false;
	}
	File.close();

	int W = 0;
	int H = 0;
	int OrigChannels = 0;
	stbi_uc* Pixels = stbi_load_from_memory(
		FileBytes.data(),
		static_cast<int>(FileBytes.size()),
		&W, &H, &OrigChannels,
		/*desired_channels=*/4);   // 항상 RGBA 4채널로 강제 — D3D11 8/8/8/8 포맷에 맞춤.
	if (!Pixels || W <= 0 || H <= 0)
	{
		UE_LOG("Failed to decode texture '%s': %s", FilePath.c_str(),
			stbi_failure_reason() ? stbi_failure_reason() : "unknown");
		if (Pixels) stbi_image_free(Pixels);
		return false;
	}

	if (!CreateRgba8TextureResource(
			Device,
			static_cast<uint32>(W),
			static_cast<uint32>(H),
			Pixels,
			InColorSpace,
			SRV,
			TrackedTextureMemory))
	{
		stbi_image_free(Pixels);
		UE_LOG("CreateTexture2D failed for '%s'", FilePath.c_str());
		return false;
	}

	if (bWriteBinaryCache)
	{
		SaveTextureBinaryCache(
			FilePath,
			InColorSpace,
			static_cast<uint32>(W),
			static_cast<uint32>(H),
			Pixels);
	}
	stbi_image_free(Pixels);

	if (TrackedTextureMemory > 0)
	{
		MemoryStats::AddTextureMemory(TrackedTextureMemory);
	}

	Width  = static_cast<uint32>(W);
	Height = static_cast<uint32>(H);

	SourceFilePath = FilePath;
	ColorSpace     = InColorSpace;
	return true;
}
