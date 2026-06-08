#pragma once

#include "Core/Types/CoreTypes.h"
#include "Core/Types/EngineTypes.h"
#include "Core/Types/ResourceTypes.h"
#include "Math/Vector.h"
#include "Render/Types/VertexTypes.h"
#include "Render/Resource/Buffer.h"

// Texture Atlas UV 정보
struct FCharacterInfo
{
	float U;
	float V;
	float Width;
	float Height;
};

// FFontGeometry — 동적 VB/IB와 문자 지오메트리 생성을 직접 소유.
class FFontGeometry
{
public:
	void Create(ID3D11Device* InDevice);
	void Release();

	// 월드 좌표 빌보드 텍스트
	void AddWorldText(const FString& Text,
		const FVector& WorldPos,
		const FVector& CamRight,
		const FVector& CamUp,
		const FVector& WorldScale,
		float Scale = 1.0f,
		const FVector4& Color = FVector4(1.0f, 1.0f, 1.0f, 1.0f),
		bool bDisableDepthTest = false);

	// 스크린 공간 오버레이 텍스트
	void AddScreenText(const FString& Text,
		float ScreenX, float ScreenY,
		float ViewportWidth, float ViewportHeight,
		float Scale = 1.0f);

	void Clear();
	void ClearScreen();

	void EnsureCharInfoMap(const FFontResource* Resource);

	bool UploadWorldBuffers(ID3D11DeviceContext* Context, bool bDisableDepthTest = false);
	bool UploadScreenBuffers(ID3D11DeviceContext* Context);

	ID3D11Buffer* GetWorldVBBuffer(bool bDisableDepthTest = false) const { return bDisableDepthTest ? NoDepthWorldVB.GetBuffer() : WorldVB.GetBuffer(); }
	uint32 GetWorldVBStride(bool bDisableDepthTest = false) const { return bDisableDepthTest ? NoDepthWorldVB.GetStride() : WorldVB.GetStride(); }
	ID3D11Buffer* GetWorldIBBuffer(bool bDisableDepthTest = false) const { return bDisableDepthTest ? NoDepthWorldIB.GetBuffer() : WorldIB.GetBuffer(); }
	uint32 GetWorldIndexCount(bool bDisableDepthTest = false) const { return static_cast<uint32>((bDisableDepthTest ? NoDepthWorldIndices : WorldIndices).size()); }

	ID3D11Buffer* GetScreenVBBuffer() const { return ScreenVB.GetBuffer(); }
	uint32 GetScreenVBStride() const { return ScreenVB.GetStride(); }
	ID3D11Buffer* GetScreenIBBuffer() const { return ScreenIB.GetBuffer(); }
	uint32 GetScreenIndexCount() const { return static_cast<uint32>(ScreenIndices.size()); }

	uint32 GetWorldQuadCount(bool bDisableDepthTest = false) const { return static_cast<uint32>((bDisableDepthTest ? NoDepthWorldVertices : WorldVertices).size() / 4); }
	uint32 GetScreenQuadCount() const { return static_cast<uint32>(ScreenVertices.size() / 4); }

private:
	void BuildCharInfoMap(uint32 Columns, uint32 Rows);
	void GetCharUV(uint32 Codepoint, FVector2& OutUVMin, FVector2& OutUVMax) const;

	// CPU 누적 배열
	TArray<FTextureVertex> WorldVertices;
	TArray<uint32>         WorldIndices;
	TArray<FTextureVertex> NoDepthWorldVertices;
	TArray<uint32>         NoDepthWorldIndices;
	TArray<FTextureVertex> ScreenVertices;
	TArray<uint32>         ScreenIndices;

	// GPU Dynamic Buffers
	FDynamicVertexBuffer WorldVB;
	FDynamicIndexBuffer  WorldIB;
	FDynamicVertexBuffer NoDepthWorldVB;
	FDynamicIndexBuffer  NoDepthWorldIB;
	FDynamicVertexBuffer ScreenVB;
	FDynamicIndexBuffer  ScreenIB;

	// Device
	ID3D11Device* Device = nullptr;

	// CharInfoMap
	TMap<uint32, FCharacterInfo> CharInfoMap;
	uint32 CachedColumns = 0;
	uint32 CachedRows    = 0;
};
