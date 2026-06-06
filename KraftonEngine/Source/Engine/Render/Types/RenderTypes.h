#pragma once

//	Windows API Include
#define NOMINMAX
#include <Windows.h>
#include <windowsx.h>

//	D3D API Include
#pragma comment(lib, "user32")
#pragma comment(lib, "d3d11")
#pragma comment(lib, "d3dcompiler")

#include <d3d11.h>
#include <d3dcompiler.h>
#include <dxgi1_5.h>

#pragma comment(lib, "dxgi")
#include "Core/Types/CoreTypes.h"
#include "Render/Types/RenderStateTypes.h"

//	Mesh Shape Enum — MeshBufferManager 조회용 (순수 기하 형상)
enum class EMeshShape
{
	Cube,
	Sphere,
	Plane,
	Quad,
	TexturedQuad,
	TransGizmo,
	RotGizmo,
	ScaleGizmo,
};

enum class ERenderPass : uint32
{
	PreDepth,		// Depth-only 프리패스 (color write 없음, Early-Z용)
	LightCulling,	// 라이트 컬링 CS 디스패치 (Tile/Cluster)
	ShadowMap,		// 라이트별 Shadow Depth 렌더링
	Opaque,			// 불투명 지오메트리 (StaticMesh 등)
	Decal,			// 데칼 (DepthReadOnly)
	AdditiveDecal,	// Additive 빌보드 등
	Fog,			// Fullscreen HeightFog (불투명 이후, AlphaBlend 이전)
	AlphaBlend,		// 반투명 지오메트리 (Font, SubUV, Billboard, Translucent)
	SelectionMask,	// 선택 스텐실 마스크
	PostProcess,	// SceneDepth, WorldNormal, LightCulling 등 scene 기반 post-process
	DOFSetup,		// Depth of Field setup — CoC 생성
	DOFGather,		// Depth of Field gather — blur 생성
	DOFRecombine,	// Depth of Field recombine — 원본과 blur 합성
	PostProcessOverlay, // Outline, Fade, Vignette, Letterbox 등 DOF 뒤 overlay 계열
	EditorLines,	// 디버그 라인 + 그리드 (LINELIST)
	FXAA,			// FXAA 안티앨리어싱 (SceneColor 복사 후 실행)
	GizmoOuter,		// 기즈모 외곽 (깊이 테스트 O)
	GizmoInner,		// 기즈모 내부 (깊이 무시)
	BloomExtract,	// HDR SceneColor 밝은 영역 추출 + 반해상도 가로 블러
	GammaCorrection,// Bloom 합성 + 톤매핑 + 디스플레이 감마 변환
	OverlayFont,	// 톤매핑 뒤 스크린 공간 LDR 텍스트
	UI,				// 톤매핑 뒤 RmlUi 기반 LDR 게임 UI
	MAX
};

inline const char* GetRenderPassName(ERenderPass Pass)
{
	static const char* Names[] = {
		"RenderPass::PreDepth",
		"RenderPass::LightCulling",
		"RenderPass::ShadowMap",
		"RenderPass::Opaque",
		"RenderPass::Decal",
		"RenderPass::AdditiveDecal",
		"RenderPass::Fog",
		"RenderPass::AlphaBlend",
		"RenderPass::SelectionMask",
		"RenderPass::PostProcess",
		"RenderPass::DOFSetup",
		"RenderPass::DOFGather",
		"RenderPass::DOFRecombine",
		"RenderPass::PostProcessOverlay",
		"RenderPass::EditorLines",
		"RenderPass::FXAA",
		"RenderPass::GizmoOuter",
		"RenderPass::GizmoInner",
		"RenderPass::BloomExtract",
		"RenderPass::GammaCorrection",
		"RenderPass::OverlayFont",
		"RenderPass::UI",
	};
	static_assert(ARRAYSIZE(Names) == (uint32)ERenderPass::MAX, "Names must match ERenderPass entries");
	return Names[(uint32)Pass];
}

namespace RenderStateStrings
{
	inline constexpr FEnumEntry RenderPassMap[] =
	{
		{ "PreDepth",      (int)ERenderPass::PreDepth },
		{ "LightCulling",  (int)ERenderPass::LightCulling },
		{ "ShadowMap",     (int)ERenderPass::ShadowMap },
		{ "Opaque",        (int)ERenderPass::Opaque },
		{ "Decal",         (int)ERenderPass::Decal },
		{ "AdditiveDecal", (int)ERenderPass::AdditiveDecal },
		{ "Fog",           (int)ERenderPass::Fog },
		{ "AlphaBlend",    (int)ERenderPass::AlphaBlend },
		{ "SelectionMask", (int)ERenderPass::SelectionMask },
		{ "PostProcess",   (int)ERenderPass::PostProcess },
		{ "DOFSetup",      (int)ERenderPass::DOFSetup },
		{ "DOFGather",     (int)ERenderPass::DOFGather },
		{ "DOFRecombine",  (int)ERenderPass::DOFRecombine },
		{ "PostProcessOverlay", (int)ERenderPass::PostProcessOverlay },
		{ "EditorLines",   (int)ERenderPass::EditorLines },
		{ "FXAA",          (int)ERenderPass::FXAA },
		{ "GizmoOuter",    (int)ERenderPass::GizmoOuter },
		{ "GizmoInner",    (int)ERenderPass::GizmoInner },
		{ "BloomExtract",   (int)ERenderPass::BloomExtract },
		{ "GammaCorrection",(int)ERenderPass::GammaCorrection },
		{ "OverlayFont",   (int)ERenderPass::OverlayFont },
		{ "UI",            (int)ERenderPass::UI },
	};

	static_assert(ARRAYSIZE(RenderPassMap) == (int)ERenderPass::MAX, "RenderPassMap must match ERenderPass entries");
}
