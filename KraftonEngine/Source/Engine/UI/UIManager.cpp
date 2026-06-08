#include "UI/UIManager.h"
#include "Asset/AssetPackage.h"
#include "Object/GarbageCollection.h"

#include "Core/Logging/Log.h"
#include "Input/InputSystem.h"
#include "Object/Object.h"
#include "Platform/Paths.h"
#include "Render/Command/DrawCommandList.h"
#include "Render/Device/D3DDevice.h"
#include "Render/RenderPass/RenderPassBase.h"
#include "Render/Resource/RenderResources.h"
#include "Render/Shader/ShaderManager.h"
#include "Render/Types/FrameContext.h"
#include "UI/RmlUiDocumentAsset.h"
#include "UI/RmlUiDocumentManager.h"
#include "UI/UserWidget.h"
#include "WICTextureLoader.h"

#ifdef GetNextSibling
#undef GetNextSibling
#endif
#ifdef GetFirstChild
#undef GetFirstChild
#endif
#include <RmlUi/Core.h>

#include <algorithm>
#include <array>
#include <chrono>
#include <cmath>
#include <cstdio>
#include <cstdlib>
#include <filesystem>
#include <memory>

namespace
{
	struct FRmlVertexD3D11
	{
		float X, Y;
		float R, G, B, A;
		float U, V;
	};

	struct FRmlGeometryD3D11
	{
		ID3D11Buffer* VertexBuffer = nullptr;
		ID3D11Buffer* IndexBuffer = nullptr;
		UINT IndexCount = 0;
	};

	struct FRmlTextureD3D11
	{
		ID3D11ShaderResourceView* SRV = nullptr;
	};

	struct FRmlPerFrameCB
	{
		float ViewportWidth = 1.0f;
		float ViewportHeight = 1.0f;
		float TranslationX = 0.0f;
		float TranslationY = 0.0f;
		float Transform[16] = {
			1.0f, 0.0f, 0.0f, 0.0f,
			0.0f, 1.0f, 0.0f, 0.0f,
			0.0f, 0.0f, 1.0f, 0.0f,
			0.0f, 0.0f, 0.0f, 1.0f,
		};
	};

	constexpr const char* UIShaderPath = "Shaders/UI/RmlUi.hlsl";

	std::filesystem::path ToProjectPath(const FString& Path)
	{
		std::filesystem::path Result(FPaths::ToWide(Path));
		if (Result.is_relative())
		{
			Result = std::filesystem::path(FPaths::RootDir()) / Result;
		}
		return Result;
	}

	Rml::String ToRmlPath(const std::filesystem::path& Path)
	{
		return FPaths::ToUtf8(Path.generic_wstring());
	}

	bool IsRmlFileUrl(const Rml::String& Source)
	{
		return Source.rfind("file://", 0) == 0;
	}

	std::filesystem::path RmlSourceToPath(const Rml::String& Source)
	{
		Rml::String PathText = Source;
		if (PathText.rfind("file:///", 0) == 0)
		{
			PathText = PathText.substr(8);
		}
		else if (PathText.rfind("file://", 0) == 0)
		{
			PathText = PathText.substr(7);
		}

		if (PathText.size() > 2 && PathText[0] == '/' && PathText[2] == ':')
		{
			PathText.erase(PathText.begin());
		}
		return std::filesystem::path(FPaths::ToWide(PathText));
	}

	Rml::String ToRmlFileUrl(const std::filesystem::path& Path)
	{
		const Rml::String GenericPath = ToRmlPath(Path.lexically_normal());
		return IsRmlFileUrl(GenericPath) ? GenericPath : Rml::String("file:///") + GenericPath;
	}

	std::filesystem::path ResolveRmlTexturePath(const Rml::String& Source)
	{
		std::filesystem::path Path = RmlSourceToPath(Source);
		if (!Path.is_relative())
		{
			return Path;
		}

		const std::filesystem::path Root(FPaths::RootDir());
		std::filesystem::path Candidate = Root / Path;
		if (std::filesystem::exists(Candidate))
		{
			return Candidate;
		}

		Candidate = Root / L"Content" / Path;
		if (std::filesystem::exists(Candidate))
		{
			return Candidate;
		}

		Candidate = Root / L"Content" / L"UI" / L"GameFlow" / Path;
		if (std::filesystem::exists(Candidate))
		{
			return Candidate;
		}

		return Root / Path;
	}

	bool ParseFloatList(const Rml::String& Text, float* OutValues, size_t Count)
	{
		const char* Cursor = Text.c_str();
		char* End = nullptr;
		for (size_t Index = 0; Index < Count; ++Index)
		{
			OutValues[Index] = std::strtof(Cursor, &End);
			if (End == Cursor)
			{
				return false;
			}
			Cursor = End;
			while (*Cursor == ' ' || *Cursor == '\t' || *Cursor == ',')
			{
				++Cursor;
			}
		}
		return true;
	}

	Rml::String PxString(float Value)
	{
		char Buffer[64];
		std::snprintf(Buffer, sizeof(Buffer), "%.0fpx", Value);
		return Buffer;
	}

	void ApplyElementAnchors(Rml::Element* Element, float ViewportWidth, float ViewportHeight)
	{
		if (!Element)
		{
			return;
		}

		const Rml::String AnchorsText = Element->GetAttribute<Rml::String>("data-ue-anchors", Rml::String());
		const Rml::String OffsetsText = Element->GetAttribute<Rml::String>("data-ue-offsets", Rml::String());
		if (!AnchorsText.empty() && !OffsetsText.empty())
		{
			float Anchors[4] = { 0.0f, 0.0f, 0.0f, 0.0f };
			float Offsets[4] = { 0.0f, 0.0f, 0.0f, 0.0f };
			float Alignment[2] = { 0.0f, 0.0f };
			const Rml::String AlignmentText = Element->GetAttribute<Rml::String>("data-ue-alignment", Rml::String("0 0"));

			if (ParseFloatList(AnchorsText, Anchors, 4) &&
				ParseFloatList(OffsetsText, Offsets, 4) &&
				ParseFloatList(AlignmentText, Alignment, 2))
			{
				const bool bStretchX = std::fabs(Anchors[0] - Anchors[2]) > 0.0001f;
				const bool bStretchY = std::fabs(Anchors[1] - Anchors[3]) > 0.0001f;

				float Left = 0.0f;
				float Top = 0.0f;
				float Width = 1.0f;
				float Height = 1.0f;

				if (bStretchX)
				{
					Left = ViewportWidth * Anchors[0] + Offsets[0];
					const float Right = ViewportWidth * Anchors[2] - Offsets[2];
					Width = (std::max)(1.0f, Right - Left);
				}
				else
				{
					Width = (std::max)(1.0f, Offsets[2]);
					Left = ViewportWidth * Anchors[0] + Offsets[0] - Width * Alignment[0];
				}

				if (bStretchY)
				{
					Top = ViewportHeight * Anchors[1] + Offsets[1];
					const float Bottom = ViewportHeight * Anchors[3] - Offsets[3];
					Height = (std::max)(1.0f, Bottom - Top);
				}
				else
				{
					Height = (std::max)(1.0f, Offsets[3]);
					Top = ViewportHeight * Anchors[1] + Offsets[1] - Height * Alignment[1];
				}

				Element->SetProperty("position", "absolute");
				Element->SetProperty("left", PxString(Left));
				Element->SetProperty("top", PxString(Top));
				Element->SetProperty("width", PxString(Width));
				Element->SetProperty("height", PxString(Height));
			}
		}

		const int NumChildren = Element->GetNumChildren();
		for (int Index = 0; Index < NumChildren; ++Index)
		{
			ApplyElementAnchors(Element->GetChild(Index), ViewportWidth, ViewportHeight);
		}
	}
}

double FRmlSystemInterface::GetElapsedTime()
{
	using namespace std::chrono;
	const auto Now = steady_clock::now();
	return duration<double>(Now - StartTime).count();
}

void FRmlSystemInterface::JoinPath(Rml::String& TranslatedPath, const Rml::String& DocumentPath, const Rml::String& Path)
{
	std::filesystem::path ResourcePath = RmlSourceToPath(Path);
	if (IsRmlFileUrl(Path) || !ResourcePath.is_relative())
	{
		TranslatedPath = ToRmlFileUrl(ResourcePath);
		return;
	}

	std::filesystem::path BasePath = RmlSourceToPath(DocumentPath);
	TranslatedPath = ToRmlFileUrl(BasePath.parent_path() / ResourcePath);
}

bool FRmlSystemInterface::LogMessage(Rml::Log::Type Type, const Rml::String& Message)
{
	UE_LOG("[RmlUi] %s", Message.c_str());
	return true;
}

// FRmlFileInterfaceWide — 모든 RmlUi 파일 열기를 wide API 로 우회. 한글 경로의 디렉토리
// 에서 실행될 때 기본 fopen 경로가 ANSI 로 해석되며 깨지는 것을 방지.
Rml::FileHandle FRmlFileInterfaceWide::Open(const Rml::String& Path)
{
	const std::wstring WidePath = RmlSourceToPath(Path).wstring();
	FILE* Fp = nullptr;
	if (_wfopen_s(&Fp, WidePath.c_str(), L"rb") != 0 || !Fp)
	{
		return Rml::FileHandle{};
	}
	return reinterpret_cast<Rml::FileHandle>(Fp);
}

void FRmlFileInterfaceWide::Close(Rml::FileHandle FileHandle)
{
	if (FileHandle)
	{
		fclose(reinterpret_cast<FILE*>(FileHandle));
	}
}

size_t FRmlFileInterfaceWide::Read(void* Buffer, size_t Size, Rml::FileHandle FileHandle)
{
	if (!FileHandle) return 0;
	return fread(Buffer, 1, Size, reinterpret_cast<FILE*>(FileHandle));
}

bool FRmlFileInterfaceWide::Seek(Rml::FileHandle FileHandle, long Offset, int Origin)
{
	if (!FileHandle) return false;
	return fseek(reinterpret_cast<FILE*>(FileHandle), Offset, Origin) == 0;
}

size_t FRmlFileInterfaceWide::Tell(Rml::FileHandle FileHandle)
{
	if (!FileHandle) return 0;
	const long Pos = ftell(reinterpret_cast<FILE*>(FileHandle));
	return Pos < 0 ? 0 : static_cast<size_t>(Pos);
}

FRmlRenderInterfaceD3D11::FRmlRenderInterfaceD3D11(ID3D11Device* InDevice)
	: Device(InDevice)
	, CurrentTransform(Rml::Matrix4f::Identity())
{
	CreateConstantBuffer();
}

FRmlRenderInterfaceD3D11::~FRmlRenderInterfaceD3D11()
{
	ReleaseWhiteTexture();
	if (ScissorRasterizerState)
	{
		ScissorRasterizerState->Release();
		ScissorRasterizerState = nullptr;
	}
	if (PerFrameCB)
	{
		PerFrameCB->Release();
		PerFrameCB = nullptr;
	}
}

void FRmlRenderInterfaceD3D11::BeginFrame(const FPassContext& InCtx)
{
	Ctx = &InCtx;

	ID3D11DeviceContext* DC = Ctx->Device.GetDeviceContext();
	if (!DC)
	{
		return;
	}

	D3D11_VIEWPORT Viewport = {};
	Viewport.TopLeftX = 0.0f;
	Viewport.TopLeftY = 0.0f;
	Viewport.Width = Ctx->Frame.ViewportWidth;
	Viewport.Height = Ctx->Frame.ViewportHeight;
	Viewport.MinDepth = 0.0f;
	Viewport.MaxDepth = 1.0f;
	DC->RSSetViewports(1, &Viewport);
}

void FRmlRenderInterfaceD3D11::EndFrame()
{
	Ctx = nullptr;
}

void FRmlRenderInterfaceD3D11::SetTransform(const Rml::Matrix4f* Transform)
{
	CurrentTransform = Transform ? *Transform : Rml::Matrix4f::Identity();
}

Rml::CompiledGeometryHandle FRmlRenderInterfaceD3D11::CompileGeometry(Rml::Span<const Rml::Vertex> Vertices, Rml::Span<const int> Indices)
{
	if (!Device || Vertices.empty() || Indices.empty())
	{
		return 0;
	}

	TArray<FRmlVertexD3D11> ConvertedVertices;
	ConvertedVertices.reserve(Vertices.size());
	for (const Rml::Vertex& Vertex : Vertices)
	{
		ConvertedVertices.push_back({
			Vertex.position.x,
			Vertex.position.y,
			Vertex.colour.red / 255.0f,
			Vertex.colour.green / 255.0f,
			Vertex.colour.blue / 255.0f,
			Vertex.colour.alpha / 255.0f,
			Vertex.tex_coord.x,
			Vertex.tex_coord.y,
		});
	}

	TArray<uint32> ConvertedIndices;
	ConvertedIndices.reserve(Indices.size());
	for (int Index : Indices)
	{
		ConvertedIndices.push_back(static_cast<uint32>(Index));
	}

	auto* Geometry = new FRmlGeometryD3D11();
	Geometry->IndexCount = static_cast<UINT>(ConvertedIndices.size());

	D3D11_BUFFER_DESC VBDesc = {};
	VBDesc.Usage = D3D11_USAGE_DEFAULT;
	VBDesc.ByteWidth = static_cast<UINT>(sizeof(FRmlVertexD3D11) * ConvertedVertices.size());
	VBDesc.BindFlags = D3D11_BIND_VERTEX_BUFFER;

	D3D11_SUBRESOURCE_DATA VBData = {};
	VBData.pSysMem = ConvertedVertices.data();
	if (FAILED(Device->CreateBuffer(&VBDesc, &VBData, &Geometry->VertexBuffer)))
	{
		delete Geometry;
		return 0;
	}
	Geometry->VertexBuffer->SetPrivateData(WKPDID_D3DDebugObjectName, static_cast<UINT>(strlen("RmlGeometryVertexBuffer")), "RmlGeometryVertexBuffer");

	D3D11_BUFFER_DESC IBDesc = {};
	IBDesc.Usage = D3D11_USAGE_DEFAULT;
	IBDesc.ByteWidth = static_cast<UINT>(sizeof(uint32) * ConvertedIndices.size());
	IBDesc.BindFlags = D3D11_BIND_INDEX_BUFFER;

	D3D11_SUBRESOURCE_DATA IBData = {};
	IBData.pSysMem = ConvertedIndices.data();
	if (FAILED(Device->CreateBuffer(&IBDesc, &IBData, &Geometry->IndexBuffer)))
	{
		ReleaseGeometry(reinterpret_cast<Rml::CompiledGeometryHandle>(Geometry));
		return 0;
	}
	Geometry->IndexBuffer->SetPrivateData(WKPDID_D3DDebugObjectName, static_cast<UINT>(strlen("RmlGeometryIndexBuffer")), "RmlGeometryIndexBuffer");

	return reinterpret_cast<Rml::CompiledGeometryHandle>(Geometry);
}

void FRmlRenderInterfaceD3D11::RenderGeometry(Rml::CompiledGeometryHandle GeometryHandle, Rml::Vector2f Translation, Rml::TextureHandle Texture)
{
	if (!Ctx || !GeometryHandle)
	{
		return;
	}

	auto* Geometry = reinterpret_cast<FRmlGeometryD3D11*>(GeometryHandle);
	ID3D11DeviceContext* DC = Ctx->Device.GetDeviceContext();
	if (!DC || !Geometry->VertexBuffer || !Geometry->IndexBuffer)
	{
		return;
	}

	FShader* Shader = FShaderManager::Get().GetOrCreate(UIShaderPath);
	if (!Shader || !Shader->IsValid())
	{
		return;
	}

	Ctx->Resources.SetDepthStencilState(Ctx->Device, EDepthStencilState::NoDepth);
	Ctx->Resources.SetBlendState(Ctx->Device, EBlendState::AlphaBlend);
	Ctx->Resources.SetRasterizerState(Ctx->Device, ERasterizerState::SolidNoCull);

	DC->OMSetRenderTargets(1, &Ctx->Cache.RTV, Ctx->Cache.DSV);
	DC->IASetPrimitiveTopology(D3D11_PRIMITIVE_TOPOLOGY_TRIANGLELIST);
	Shader->Bind(DC);

	FRmlPerFrameCB CBData;
	CBData.ViewportWidth = Ctx->Frame.ViewportWidth;
	CBData.ViewportHeight = Ctx->Frame.ViewportHeight;
	CBData.TranslationX = Translation.x;
	CBData.TranslationY = Translation.y;
	const float* TransformData = CurrentTransform.data();
	std::copy(TransformData, TransformData + 16, CBData.Transform);
	DC->UpdateSubresource(PerFrameCB, 0, nullptr, &CBData, 0, 0);
	DC->VSSetConstantBuffers(0, 1, &PerFrameCB);

	ID3D11ShaderResourceView* SRV = WhiteTextureSRV;
	if (Texture)
	{
		auto* TextureResource = reinterpret_cast<FRmlTextureD3D11*>(Texture);
		SRV = TextureResource ? TextureResource->SRV : nullptr;
	}
	DC->PSSetShaderResources(0, 1, &SRV);

	UINT Stride = sizeof(FRmlVertexD3D11);
	UINT Offset = 0;
	DC->IASetVertexBuffers(0, 1, &Geometry->VertexBuffer, &Stride, &Offset);
	DC->IASetIndexBuffer(Geometry->IndexBuffer, DXGI_FORMAT_R32_UINT, 0);
	DC->DrawIndexed(Geometry->IndexCount, 0, 0);
}

void FRmlRenderInterfaceD3D11::ReleaseGeometry(Rml::CompiledGeometryHandle GeometryHandle)
{
	auto* Geometry = reinterpret_cast<FRmlGeometryD3D11*>(GeometryHandle);
	if (!Geometry)
	{
		return;
	}

	if (Geometry->VertexBuffer)
	{
		Geometry->VertexBuffer->Release();
	}
	if (Geometry->IndexBuffer)
	{
		Geometry->IndexBuffer->Release();
	}
	delete Geometry;
}

Rml::TextureHandle FRmlRenderInterfaceD3D11::LoadTexture(Rml::Vector2i& TextureDimensions, const Rml::String& Source)
{
	TextureDimensions = { 0, 0 };

	if (!Device || Source.empty())
	{
		return 0;
	}

	const std::filesystem::path ResolvedPath = ResolveRmlTexturePath(Source);
	const std::wstring WidePath = ResolvedPath.wstring();

	ID3D11Resource* Resource = nullptr;
	ID3D11ShaderResourceView* SRV = nullptr;
	const HRESULT HR = DirectX::CreateWICTextureFromFileEx(
		Device,
		WidePath.c_str(),
		0,
		D3D11_USAGE_DEFAULT,
		D3D11_BIND_SHADER_RESOURCE,
		0,
		0,
		DirectX::WIC_LOADER_IGNORE_SRGB,
		&Resource,
		&SRV);

	if (FAILED(HR) || !SRV)
	{
		if (Resource)
		{
			Resource->Release();
		}
		UE_LOG("[RmlUi] Failed to load texture: %s -> %s", Source.c_str(), ToRmlPath(ResolvedPath).c_str());
		return 0;
	}

	if (Resource)
	{
		ID3D11Texture2D* Texture2D = nullptr;
		if (SUCCEEDED(Resource->QueryInterface(__uuidof(ID3D11Texture2D), reinterpret_cast<void**>(&Texture2D))) && Texture2D)
		{
			D3D11_TEXTURE2D_DESC Desc = {};
			Texture2D->GetDesc(&Desc);
			TextureDimensions = {
				static_cast<int>(Desc.Width),
				static_cast<int>(Desc.Height)
			};
			Texture2D->Release();
		}
		Resource->Release();
	}

	auto* TextureResource = new FRmlTextureD3D11();
	TextureResource->SRV = SRV;
	return reinterpret_cast<Rml::TextureHandle>(TextureResource);
}

Rml::TextureHandle FRmlRenderInterfaceD3D11::GenerateTexture(Rml::Span<const Rml::byte> Source, Rml::Vector2i SourceDimensions)
{
	if (!Device || Source.empty() || SourceDimensions.x <= 0 || SourceDimensions.y <= 0)
	{
		return 0;
	}

	D3D11_TEXTURE2D_DESC TextureDesc = {};
	TextureDesc.Width = static_cast<UINT>(SourceDimensions.x);
	TextureDesc.Height = static_cast<UINT>(SourceDimensions.y);
	TextureDesc.MipLevels = 1;
	TextureDesc.ArraySize = 1;
	TextureDesc.Format = DXGI_FORMAT_R8G8B8A8_UNORM;
	TextureDesc.SampleDesc.Count = 1;
	TextureDesc.Usage = D3D11_USAGE_DEFAULT;
	TextureDesc.BindFlags = D3D11_BIND_SHADER_RESOURCE;

	D3D11_SUBRESOURCE_DATA InitialData = {};
	InitialData.pSysMem = Source.data();
	InitialData.SysMemPitch = static_cast<UINT>(SourceDimensions.x * 4);

	ID3D11Texture2D* Texture = nullptr;
	if (FAILED(Device->CreateTexture2D(&TextureDesc, &InitialData, &Texture)))
	{
		return 0;
	}

	ID3D11ShaderResourceView* SRV = nullptr;
	HRESULT HR = Device->CreateShaderResourceView(Texture, nullptr, &SRV);
	Texture->Release();
	if (FAILED(HR))
	{
		return 0;
	}

	auto* TextureResource = new FRmlTextureD3D11();
	TextureResource->SRV = SRV;
	return reinterpret_cast<Rml::TextureHandle>(TextureResource);
}

void FRmlRenderInterfaceD3D11::ReleaseTexture(Rml::TextureHandle Texture)
{
	auto* TextureResource = reinterpret_cast<FRmlTextureD3D11*>(Texture);
	if (!TextureResource)
	{
		return;
	}
	if (TextureResource->SRV)
	{
		TextureResource->SRV->Release();
	}
	delete TextureResource;
}

void FRmlRenderInterfaceD3D11::EnableScissorRegion(bool Enable)
{
	if (!Ctx)
	{
		return;
	}

	ID3D11DeviceContext* DC = Ctx->Device.GetDeviceContext();
	if (Enable && ScissorRasterizerState)
	{
		DC->RSSetState(ScissorRasterizerState);
	}
	else
	{
		Ctx->Resources.SetRasterizerState(Ctx->Device, ERasterizerState::SolidNoCull);
	}

	if (!Enable)
	{
		DC->RSSetScissorRects(0, nullptr);
	}
}

void FRmlRenderInterfaceD3D11::SetScissorRegion(Rml::Rectanglei Region)
{
	if (!Ctx)
	{
		return;
	}

	D3D11_RECT Rect = {};
	Rect.left = Region.Left();
	Rect.top = Region.Top();
	Rect.right = Region.Right();
	Rect.bottom = Region.Bottom();
	Ctx->Device.GetDeviceContext()->RSSetScissorRects(1, &Rect);
}

void FRmlRenderInterfaceD3D11::CreateConstantBuffer()
{
	if (!Device)
	{
		return;
	}

	D3D11_BUFFER_DESC Desc = {};
	Desc.Usage = D3D11_USAGE_DEFAULT;
	Desc.ByteWidth = sizeof(FRmlPerFrameCB);
	Desc.BindFlags = D3D11_BIND_CONSTANT_BUFFER;
	Device->CreateBuffer(&Desc, nullptr, &PerFrameCB);
	PerFrameCB->SetPrivateData(WKPDID_D3DDebugObjectName, static_cast<UINT>(strlen("RmlPerFrameCB")), "RmlPerFrameCB");

	CreateWhiteTexture();

	D3D11_RASTERIZER_DESC RasterDesc = {};
	RasterDesc.FillMode = D3D11_FILL_SOLID;
	RasterDesc.CullMode = D3D11_CULL_NONE;
	RasterDesc.ScissorEnable = TRUE;
	Device->CreateRasterizerState(&RasterDesc, &ScissorRasterizerState);
}

void FRmlRenderInterfaceD3D11::CreateWhiteTexture()
{
	const uint32 WhitePixel = 0xffffffff;

	D3D11_TEXTURE2D_DESC TextureDesc = {};
	TextureDesc.Width = 1;
	TextureDesc.Height = 1;
	TextureDesc.MipLevels = 1;
	TextureDesc.ArraySize = 1;
	TextureDesc.Format = DXGI_FORMAT_R8G8B8A8_UNORM;
	TextureDesc.SampleDesc.Count = 1;
	TextureDesc.Usage = D3D11_USAGE_DEFAULT;
	TextureDesc.BindFlags = D3D11_BIND_SHADER_RESOURCE;

	D3D11_SUBRESOURCE_DATA InitialData = {};
	InitialData.pSysMem = &WhitePixel;
	InitialData.SysMemPitch = sizeof(uint32);

	ID3D11Texture2D* Texture = nullptr;
	if (SUCCEEDED(Device->CreateTexture2D(&TextureDesc, &InitialData, &Texture)))
	{
		Device->CreateShaderResourceView(Texture, nullptr, &WhiteTextureSRV);
		Texture->SetPrivateData(WKPDID_D3DDebugObjectName, static_cast<UINT>(strlen("RmlWhiteTexture")), "RmlWhiteTexture");
		WhiteTextureSRV->SetPrivateData(WKPDID_D3DDebugObjectName, static_cast<UINT>(strlen("RmlWhiteTextureSRV")), "RmlWhiteTextureSRV");
		Texture->Release();
	}
}

void FRmlRenderInterfaceD3D11::ReleaseWhiteTexture()
{
	if (WhiteTextureSRV)
	{
		WhiteTextureSRV->Release();
		WhiteTextureSRV = nullptr;
	}
}

void UUIManager::Initialize(ID3D11Device* InDevice)
{
	CachedDevice = InDevice;

	if (bRmlInitialized || !CachedDevice)
	{
		return;
	}

	SystemInterface = new FRmlSystemInterface();
	FileInterface = new FRmlFileInterfaceWide();
	RenderInterface = new FRmlRenderInterfaceD3D11(CachedDevice);

	Rml::SetSystemInterface(SystemInterface);
	// Initialise 전에 등록해야 RmlUi 가 default file 인터페이스 대신 우리 wide 버전을 쓴다.
	Rml::SetFileInterface(FileInterface);
	Rml::SetRenderInterface(RenderInterface);
	bRmlInitialized = Rml::Initialise();
	if (!bRmlInitialized)
	{
		UE_LOG("[RmlUi] Initialise failed.");
		return;
	}

	RmlContext = Rml::CreateContext("GameViewport", Rml::Vector2i(1, 1));
	if (!RmlContext)
	{
		UE_LOG("[RmlUi] Failed to create GameViewport context.");
	}

	const std::filesystem::path FontPath = ToProjectPath("Content/Font/Maplestory Bold.ttf");
	if (!Rml::LoadFontFace(ToRmlPath(FontPath), "Maplestory", Rml::Style::FontStyle::Normal, Rml::Style::FontWeight::Bold))
	{
		UE_LOG("[RmlUi] Failed to load font: Content/Font/Maplestory Bold.ttf");
	}
}

void UUIManager::Shutdown()
{
	DestroyAllWidgets();

	if (RmlContext)
	{
		Rml::RemoveContext("GameViewport");
		RmlContext = nullptr;
	}

	if (bRmlInitialized)
	{
		Rml::Shutdown();
		bRmlInitialized = false;
	}

	delete RenderInterface;
	RenderInterface = nullptr;
	delete FileInterface;
	FileInterface = nullptr;
	delete SystemInterface;
	SystemInterface = nullptr;
	CachedDevice = nullptr;
}

UUserWidget* UUIManager::CreateWidget(APlayerController* OwningPlayer, const FString& DocumentPath)
{
	UUserWidget* Widget = UObjectManager::Get().CreateObject<UUserWidget>();
	Widget->Initialize(OwningPlayer, DocumentPath);
	CreatedWidgets.push_back(Widget);
	return Widget;
}

bool UUIManager::AnyViewportWidgetWantsMouse() const
{
	for (const UUserWidget* Widget : ViewportWidgets)
	{
        if (IsValid(Widget) && Widget->WantsMouse())
		{
			return true;
		}
	}
	return false;
}

void UUIManager::AddReferencedObjects(FReferenceCollector& Collector)
{
    for (UUserWidget* Widget : ViewportWidgets)
    {
        Collector.AddReferencedObject(Widget);
    }

    for (UUserWidget* Widget : CreatedWidgets)
    {
        Collector.AddReferencedObject(Widget);
    }

    for (UUserWidget* Widget : PendingRemoveWidgets)
    {
        Collector.AddReferencedObject(Widget);
    }
}

void UUIManager::AddToViewport(UUserWidget* Widget, int32 /*ZOrder*/)
{
    if (!IsValid(Widget))
	{
		return;
	}

	if (!LoadDocument(Widget))
	{
		return;
	}

	auto It = std::find(ViewportWidgets.begin(), ViewportWidgets.end(), Widget);
	if (It == ViewportWidgets.end())
	{
		ViewportWidgets.push_back(Widget);
		bAnchorLayoutDirty = true;
	}

	std::sort(ViewportWidgets.begin(), ViewportWidgets.end(),
		[](const UUserWidget* A, const UUserWidget* B)
		{
			return A->GetZOrder() < B->GetZOrder();
		});
}

void UUIManager::RemoveFromViewport(UUserWidget* Widget)
{
	if (bDispatchingRmlEvents)
	{
        if (IsValid(Widget) && std::find(PendingRemoveWidgets.begin(), PendingRemoveWidgets.end(), Widget) ==
            PendingRemoveWidgets.end())
		{
			PendingRemoveWidgets.push_back(Widget);
			Widget->MarkRemovedFromViewport();
		}
		return;
	}

	RemoveFromViewportImmediate(Widget);
}

void UUIManager::RemoveFromViewportImmediate(UUserWidget* Widget)
{
	ViewportWidgets.erase(std::remove(ViewportWidgets.begin(), ViewportWidgets.end(), Widget), ViewportWidgets.end());
	CloseDocument(Widget);
    if (IsAliveObject(Widget))
	{
		Widget->MarkRemovedFromViewport();
	}
}

void UUIManager::ClearViewport()
{
	// 위젯을 viewport 에서만 떼고 UObject 자체는 유지. UUIManager 는 widgets 의 owner —
	// 같은 Lua VM 안의 widgets[] 테이블이 그대로 살아있고, PIE 재시작 / TransitionToScene
	// 후 UIManager.Init re-entry 경로가 동일 위젯을 재사용한다 (위젯 destroy 시 Lua 측
	// 캐시가 dangling 이 되어 RemoveFromParent → CloseDocument 가 stale Rml::Document 를
	// 참조해 크래시). UObject 까지 파괴하는 건 Shutdown 만의 책임.
	PendingRemoveWidgets.clear();

	for (UUserWidget* Widget : ViewportWidgets)
	{
		CloseDocument(Widget);
        if (IsAliveObject(Widget))
		{
			Widget->MarkRemovedFromViewport();
		}
	}
	ViewportWidgets.clear();
	bAnchorLayoutDirty = true;

	if (RmlContext)
	{
		RmlContext->Update();
	}
}

void UUIManager::DestroyAllWidgets()
{
	ClearViewport();

	for (UUserWidget* Widget : CreatedWidgets)
	{
		if (IsAliveObject(Widget))
		{
			UObjectManager::Get().DestroyObject(Widget);
		}
	}
	CreatedWidgets.clear();
}

bool UUIManager::LoadDocument(UUserWidget* Widget)
{
	if (!Widget)
	{
		return false;
	}
	if (Widget->IsDocumentLoaded())
	{
		return true;
	}
	if (!RmlContext)
	{
		return false;
	}

	const FString& DocumentPath = Widget->GetDocumentPath();
	const std::filesystem::path Path = ToProjectPath(DocumentPath);
	if (!std::filesystem::exists(Path))
	{
		UE_LOG("[RmlUi] Document not found: %s", DocumentPath.c_str());
		return false;
	}

	Rml::ElementDocument* Document = nullptr;
	if (FAssetPackage::IsAssetPackagePath(DocumentPath))
	{
		EAssetPackageType PackageType = EAssetPackageType::Unknown;
		if (!FAssetPackage::GetPackageType(DocumentPath, PackageType) || PackageType != EAssetPackageType::RmlUiDocument)
		{
			UE_LOG("[RmlUi] Unsupported UI asset package: %s", DocumentPath.c_str());
			return false;
		}

		// UI assets are commonly edited while the editor stays open; reload the
		// package before creating a new Rml document so PIE does not reuse stale RML.
		URmlUiDocumentAsset* Asset = FRmlUiDocumentManager::Get().Reload(DocumentPath);
		if (!Asset || Asset->GetDocumentSource().empty())
		{
			UE_LOG("[RmlUi] Failed to load UI widget asset: %s", DocumentPath.c_str());
			return false;
		}

		Document = RmlContext->LoadDocumentFromMemory(Asset->GetDocumentSource(), ToRmlFileUrl(Path));
	}
	else
	{
		Document = RmlContext->LoadDocument(ToRmlPath(Path));
	}
	if (!Document)
	{
		UE_LOG("[RmlUi] Failed to load document: %s", DocumentPath.c_str());
		return false;
	}

	Document->Show();
	Widget->MarkDocumentLoaded(Document);
	Widget->RegisterEventListeners();
	bAnchorLayoutDirty = true;
	return true;
}

void UUIManager::ApplyDocumentAnchors(float ViewportWidth, float ViewportHeight)
{
	for (UUserWidget* Widget : ViewportWidgets)
	{
		if (!IsValid(Widget) || !Widget->GetDocument())
		{
			continue;
		}

		ApplyElementAnchors(Widget->GetDocument(), ViewportWidth, ViewportHeight);
	}
}

void UUIManager::CloseDocument(UUserWidget* Widget)
{
	if (!Widget || !Widget->GetDocument())
	{
		return;
	}

	Widget->ClearEventListeners();
	Widget->GetDocument()->Close();
	Widget->ClearDocument();
}

void UUIManager::Render(const FPassContext& Ctx)
{
	if (!RmlContext || !RenderInterface || ViewportWidgets.empty() || Ctx.Frame.ViewportWidth <= 0.0f || Ctx.Frame.ViewportHeight <= 0.0f)
	{
		return;
	}

	RmlContext->SetDimensions({
		static_cast<int>(Ctx.Frame.ViewportWidth),
		static_cast<int>(Ctx.Frame.ViewportHeight)
	});
	if (bAnchorLayoutDirty ||
		std::fabs(LastAnchorLayoutViewportWidth - Ctx.Frame.ViewportWidth) > 0.5f ||
		std::fabs(LastAnchorLayoutViewportHeight - Ctx.Frame.ViewportHeight) > 0.5f)
	{
		ApplyDocumentAnchors(Ctx.Frame.ViewportWidth, Ctx.Frame.ViewportHeight);
		LastAnchorLayoutViewportWidth = Ctx.Frame.ViewportWidth;
		LastAnchorLayoutViewportHeight = Ctx.Frame.ViewportHeight;
		bAnchorLayoutDirty = false;
	}

	ProcessInput(Ctx.Frame);
	FlushDeferredViewportRemovals();
	if (ViewportWidgets.empty())
	{
		return;
	}

	RmlContext->Update();
	RenderInterface->BeginFrame(Ctx);
	RmlContext->Render();
	RenderInterface->EndFrame();
}

void UUIManager::ProcessInput(const FFrameContext& Frame)
{
	if (!RmlContext)
	{
		return;
	}

	InputSystem& Input = InputSystem::Get();
	const int KeyModifierState = 0;

	int MouseX = 0;
	int MouseY = 0;
	if (Frame.CursorViewportX != UINT32_MAX && Frame.CursorViewportY != UINT32_MAX)
	{
		MouseX = static_cast<int>(Frame.CursorViewportX);
		MouseY = static_cast<int>(Frame.CursorViewportY);
	}
	else
	{
		const POINT MousePos = Input.GetMouseClientPos();
		MouseX = MousePos.x;
		MouseY = MousePos.y;
	}

	bDispatchingRmlEvents = true;
	RmlContext->ProcessMouseMove(MouseX, MouseY, KeyModifierState);
	if (Input.GetKeyDown(VK_LBUTTON))
	{
		RmlContext->ProcessMouseButtonDown(0, KeyModifierState);
	}
	if (Input.GetKeyUp(VK_LBUTTON))
	{
		RmlContext->ProcessMouseButtonUp(0, KeyModifierState);
	}
	bDispatchingRmlEvents = false;
}

void UUIManager::FlushDeferredViewportRemovals()
{
	if (PendingRemoveWidgets.empty())
	{
		return;
	}

	TArray<UUserWidget*> WidgetsToRemove = PendingRemoveWidgets;
	PendingRemoveWidgets.clear();

	for (UUserWidget* Widget : WidgetsToRemove)
	{
		RemoveFromViewportImmediate(Widget);
	}
}
