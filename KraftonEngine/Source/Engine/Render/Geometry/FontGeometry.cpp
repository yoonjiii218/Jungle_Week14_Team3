#include "FontGeometry.h"
#include "Resource/ResourceManager.h"

void FFontGeometry::Create(ID3D11Device* InDevice)
{
	Device = InDevice;
	if (!Device) return;
	Device->AddRef();

	WorldVB.Create(InDevice, 1024, sizeof(FTextureVertex));
	WorldIB.Create(InDevice, 1536);
	NoDepthWorldVB.Create(InDevice, 256, sizeof(FTextureVertex));
	NoDepthWorldIB.Create(InDevice, 384);
	ScreenVB.Create(InDevice, 256, sizeof(FTextureVertex));
	ScreenIB.Create(InDevice, 384);

	if (const FFontResource* DefaultFont = FResourceManager::Get().FindFont(FName("Default")))
	{
		if (DefaultFont->Columns > 0 && DefaultFont->Rows > 0)
		{
			BuildCharInfoMap(DefaultFont->Columns, DefaultFont->Rows);
		}
	}
}

void FFontGeometry::Release()
{
	CharInfoMap.clear();
	Clear();
	ClearScreen();

	WorldVB.Release();
	WorldIB.Release();
	NoDepthWorldVB.Release();
	NoDepthWorldIB.Release();
	ScreenVB.Release();
	ScreenIB.Release();

	if (Device) { Device->Release(); Device = nullptr; }
}

void FFontGeometry::BuildCharInfoMap(uint32 Columns, uint32 Rows)
{
	CharInfoMap.clear();
	CachedColumns = Columns;
	CachedRows = Rows;

	const float CellW = 1.0f / static_cast<float>(Columns);
	const float CellH = 1.0f / static_cast<float>(Rows);

	auto AddChar = [&](uint32 Codepoint, uint32 Slot)
	{
		const uint32 Col = Slot % Columns;
		const uint32 Row = Slot / Columns;
		if (Row >= Rows) return;
		CharInfoMap[Codepoint] = { Col * CellW, Row * CellH, CellW, CellH };
	};

	// ASCII 32(' ') ~ 126('~')
	for (uint32 CP = 32; CP <= 126; ++CP)
		AddChar(CP, CP - 32);

	// 한글 완성형 가(U+AC00) ~ 힣(U+D7A3)
	uint32 Slot = 127;
	for (uint32 CP = 0xAC00; CP <= 0xD7A3; ++CP, ++Slot)
		AddChar(CP, Slot - 32);
}

void FFontGeometry::EnsureCharInfoMap(const FFontResource* Resource)
{
	if (!Resource || Resource->Columns == 0 || Resource->Rows == 0) return;
	if (CachedColumns == Resource->Columns && CachedRows == Resource->Rows) return;
	BuildCharInfoMap(Resource->Columns, Resource->Rows);
}

void FFontGeometry::GetCharUV(uint32 Codepoint, FVector2& OutUVMin, FVector2& OutUVMax) const
{
	const auto It = CharInfoMap.find(Codepoint);
	if (It == CharInfoMap.end())
	{
		OutUVMin = FVector2(0, 0);
		OutUVMax = FVector2(0, 0);
		return;
	}
	const FCharacterInfo& Info = It->second;
	OutUVMin = FVector2(Info.U, Info.V);
	OutUVMax = FVector2(Info.U + Info.Width, Info.V + Info.Height);
}

void FFontGeometry::Clear()
{
	WorldVertices.clear();
	WorldIndices.clear();
	NoDepthWorldVertices.clear();
	NoDepthWorldIndices.clear();
}

void FFontGeometry::ClearScreen()
{
	ScreenVertices.clear();
	ScreenIndices.clear();
}

void FFontGeometry::AddWorldText(const FString& Text,
	const FVector& WorldPos,
	const FVector& CamRight,
	const FVector& CamUp,
	const FVector& WorldScale,
	float Scale,
	const FVector4& Color,
	bool bDisableDepthTest)
{
	if (Text.empty()) return;

	TArray<FTextureVertex>& Vertices = bDisableDepthTest ? NoDepthWorldVertices : WorldVertices;
	TArray<uint32>& Indices = bDisableDepthTest ? NoDepthWorldIndices : WorldIndices;

	const float CharW = 0.5f * Scale * WorldScale.Y;
	const float CharH = 0.5f * Scale * WorldScale.Z;
	float CharCursorX = 0.0f;
	const uint32 Base = static_cast<uint32>(Vertices.size());
	const uint32 IdxBase = static_cast<uint32>(Indices.size());
	const size_t CharCount = Text.size();

	Vertices.resize(Base + CharCount * 4);
	Indices.resize(IdxBase + CharCount * 6);
	FTextureVertex* pV = Vertices.data() + Base;
	uint32* pI = Indices.data() + IdxBase;

	const FVector HalfRight = CamRight * (CharW * 0.5f);
	const FVector HalfUp    = CamUp    * (CharH * 0.5f);

	const uint8* Ptr = reinterpret_cast<const uint8*>(Text.c_str());
	const uint8* const End = Ptr + Text.size();
	uint32 CharIdx = 0;

	for (size_t i = 0; i < CharCount && Ptr < End; ++i)
	{
		uint32 CP = 0;
		if      (Ptr[0] < 0x80)                             { CP = Ptr[0];                                                                       Ptr += 1; }
		else if ((Ptr[0] & 0xE0) == 0xC0 && Ptr + 1 < End)  { CP = ((Ptr[0] & 0x1F) << 6)  |  (Ptr[1] & 0x3F);                                   Ptr += 2; }
		else if ((Ptr[0] & 0xF0) == 0xE0 && Ptr + 2 < End)  { CP = ((Ptr[0] & 0x0F) << 12) | ((Ptr[1] & 0x3F) << 6)  |  (Ptr[2] & 0x3F);         Ptr += 3; }
		else if ((Ptr[0] & 0xF8) == 0xF0 && Ptr + 3 < End)  { CP = ((Ptr[0] & 0x07) << 18) | ((Ptr[1] & 0x3F) << 12) | ((Ptr[2] & 0x3F) << 6) | (Ptr[3] & 0x3F); Ptr += 4; }
		else                                                  { ++Ptr; continue; }

		FVector2 UVMin, UVMax;
		GetCharUV(CP, UVMin, UVMax);

		const FVector Center = WorldPos + CamRight * CharCursorX;

		pV[0] = { Center                 + HalfUp, Color, { UVMin.X, UVMin.Y } };
		pV[1] = { Center + HalfRight * 2 + HalfUp, Color, { UVMax.X, UVMin.Y } };
		pV[2] = { Center                 - HalfUp, Color, { UVMin.X, UVMax.Y } };
		pV[3] = { Center + HalfRight * 2 - HalfUp, Color, { UVMax.X, UVMax.Y } };

		const uint32 Vi = Base + CharIdx * 4;
		pI[0] = Vi;     pI[1] = Vi + 1; pI[2] = Vi + 2;
		pI[3] = Vi + 1; pI[4] = Vi + 3; pI[5] = Vi + 2;

		pV += 4;
		pI += 6;
		++CharIdx;
		CharCursorX += CharW;
	}

	Vertices.resize(Base + CharIdx * 4);
	Indices.resize(IdxBase + CharIdx * 6);
}

void FFontGeometry::AddScreenText(const FString& Text,
	float ScreenX, float ScreenY,
	float ViewportWidth, float ViewportHeight,
	float Scale)
{
	if (Text.empty()) return;
	if (ViewportWidth <= 0.0f || ViewportHeight <= 0.0f) return;

	const float CharW = 23.0f * Scale;
	const float CharH = 23.0f * Scale;
	const float LetterSpacing = -0.5f * CharW;

	const uint32 Base = static_cast<uint32>(ScreenVertices.size());
	const uint32 IdxBase = static_cast<uint32>(ScreenIndices.size());
	const size_t CharCount = Text.size();

	ScreenVertices.resize(Base + CharCount * 4);
	ScreenIndices.resize(IdxBase + CharCount * 6);

	FTextureVertex* pV = ScreenVertices.data() + Base;
	uint32* pI = ScreenIndices.data() + IdxBase;

	const uint8* Ptr = reinterpret_cast<const uint8*>(Text.c_str());
	const uint8* const End = Ptr + Text.size();

	uint32 CharIdx = 0;
	float CursorX = ScreenX;

	auto PixelToClipX = [ViewportWidth](float X) -> float
		{
			return (X / ViewportWidth) * 2.0f - 1.0f;
		};

	auto PixelToClipY = [ViewportHeight](float Y) -> float
		{
			return 1.0f - (Y / ViewportHeight) * 2.0f;
		};

	for (size_t i = 0; i < CharCount && Ptr < End; ++i)
	{
		uint32 CP = 0;
		if (Ptr[0] < 0x80) { CP = Ptr[0]; Ptr += 1; }
		else if ((Ptr[0] & 0xE0) == 0xC0 && Ptr + 1 < End) { CP = ((Ptr[0] & 0x1F) << 6) | (Ptr[1] & 0x3F); Ptr += 2; }
		else if ((Ptr[0] & 0xF0) == 0xE0 && Ptr + 2 < End) { CP = ((Ptr[0] & 0x0F) << 12) | ((Ptr[1] & 0x3F) << 6) | (Ptr[2] & 0x3F); Ptr += 3; }
		else if ((Ptr[0] & 0xF8) == 0xF0 && Ptr + 3 < End) { CP = ((Ptr[0] & 0x07) << 18) | ((Ptr[1] & 0x3F) << 12) | ((Ptr[2] & 0x3F) << 6) | (Ptr[3] & 0x3F); Ptr += 4; }
		else { ++Ptr; continue; }

		FVector2 UVMin, UVMax;
		GetCharUV(CP, UVMin, UVMax);

		const float Left = PixelToClipX(CursorX);
		const float Right = PixelToClipX(CursorX + CharW);
		const float Top = PixelToClipY(ScreenY);
		const float Bottom = PixelToClipY(ScreenY + CharH);

		const FVector4 Color = FVector4(0.6f, 1.0f, 1.0f, 1.0f);
		pV[0] = { FVector(Left,  Top,    0.0f), Color, FVector2(UVMin.X, UVMin.Y) };
		pV[1] = { FVector(Right, Top,    0.0f), Color, FVector2(UVMax.X, UVMin.Y) };
		pV[2] = { FVector(Left,  Bottom, 0.0f), Color, FVector2(UVMin.X, UVMax.Y) };
		pV[3] = { FVector(Right, Bottom, 0.0f), Color, FVector2(UVMax.X, UVMax.Y) };

		const uint32 Vi = Base + CharIdx * 4;
		pI[0] = Vi;     pI[1] = Vi + 1; pI[2] = Vi + 2;
		pI[3] = Vi + 1; pI[4] = Vi + 3; pI[5] = Vi + 2;

		pV += 4;
		pI += 6;
		++CharIdx;
		CursorX += CharW + LetterSpacing;
	}

	ScreenVertices.resize(Base + CharIdx * 4);
	ScreenIndices.resize(IdxBase + CharIdx * 6);
}

bool FFontGeometry::UploadWorldBuffers(ID3D11DeviceContext* Context, bool bDisableDepthTest)
{
	TArray<FTextureVertex>& Vertices = bDisableDepthTest ? NoDepthWorldVertices : WorldVertices;
	TArray<uint32>& Indices = bDisableDepthTest ? NoDepthWorldIndices : WorldIndices;
	FDynamicVertexBuffer& VB = bDisableDepthTest ? NoDepthWorldVB : WorldVB;
	FDynamicIndexBuffer& IB = bDisableDepthTest ? NoDepthWorldIB : WorldIB;

	if (Vertices.empty()) return false;

	const uint32 VertCount = static_cast<uint32>(Vertices.size());
	const uint32 IdxCount  = static_cast<uint32>(Indices.size());

	VB.EnsureCapacity(Device, VertCount);
	IB.EnsureCapacity(Device, IdxCount);
	if (!VB.Update(Context, Vertices.data(), VertCount)) return false;
	if (!IB.Update(Context, Indices.data(), IdxCount)) return false;
	return true;
}

bool FFontGeometry::UploadScreenBuffers(ID3D11DeviceContext* Context)
{
	if (ScreenVertices.empty()) return false;

	const uint32 VertCount = static_cast<uint32>(ScreenVertices.size());
	const uint32 IdxCount  = static_cast<uint32>(ScreenIndices.size());

	ScreenVB.EnsureCapacity(Device, VertCount);
	ScreenIB.EnsureCapacity(Device, IdxCount);
	if (!ScreenVB.Update(Context, ScreenVertices.data(), VertCount)) return false;
	if (!ScreenIB.Update(Context, ScreenIndices.data(), IdxCount)) return false;
	return true;
}
