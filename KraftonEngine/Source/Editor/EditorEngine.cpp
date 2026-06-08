#include "Editor/EditorEngine.h"

#include "Profiling/StartupProfiler.h"
#include "Core/Logging/Notification.h"
#include "Engine/Platform/WindowsWindow.h"
#include "Engine/Serialization/SceneSaveManager.h"
#include "Engine/Platform/DirectoryWatcher.h"
#include "Engine/Runtime/EngineInitHooks.h"
#include "Component/Camera/CameraComponent.h"
#include "Component/Debug/GizmoComponent.h"
#include "Component/PrimitiveComponent.h"
#include "Render/Types/MinimalViewInfo.h"
#include "Editor/Viewport/ViewportCameraTransform.h"
#include "GameFramework/World.h"
#include "GameFramework/GameMode/GameModeBase.h"
#include "Viewport/GameViewportClient.h"
#include "UI/UIManager.h"
#include "Editor/Slate/SlateApplication.h"
#include "Editor/EditorRenderPipeline.h"
#include "Editor/UI/Util/EditorFileUtils.h"
#include "Editor/Import/UnrealSceneManifestImporter.h"
#include "Editor/UI/Util/EditorTextureManager.h"
#include "Editor/Viewport/Level/LevelEditorViewportClient.h"
#include "Object/Reflection/ObjectFactory.h"
#include "Mesh/MeshManager.h"
#include "Core/ProjectSettings.h"
#include "Input/InputSystem.h"
#include "GameFramework/AActor.h"
#include "Materials/MaterialManager.h"
#include "Engine/Platform/Paths.h"
#include "Lua/LuaScriptManager.h"
#include "Object/GarbageCollection.h"
#include "SimpleJSON/json.hpp"

#include "Mesh/Skeletal/SkeletalMesh.h"

#include <cwctype>
#include <filesystem>
#include <fstream>

namespace
{
bool GetWorldFocusBounds(UWorld* World, FVector& OutCenter, FVector& OutExtent)
{
	if (!World)
	{
		return false;
	}

	FBoundingBox CombinedBounds;
	bool bHasBounds = false;
	for (AActor* Actor : World->GetActors())
	{
		if (!IsValid(Actor) || !Actor->IsVisible())
		{
			continue;
		}

		for (UActorComponent* Component : Actor->GetComponents())
		{
			UPrimitiveComponent* Primitive = Cast<UPrimitiveComponent>(Component);
			if (!Primitive || !Primitive->IsVisible())
			{
				continue;
			}

			const FBoundingBox Bounds = Primitive->GetWorldBoundingBox();
			if (!Bounds.IsValid())
			{
				continue;
			}

			CombinedBounds.Expand(Bounds.Min);
			CombinedBounds.Expand(Bounds.Max);
			bHasBounds = true;
		}
	}

	if (!bHasBounds)
	{
		return false;
	}

	OutCenter = CombinedBounds.GetCenter();
	OutExtent = CombinedBounds.GetExtent();
	return true;
}

FString BuildScenePathFromStem(const FString& InStem)
{
	std::filesystem::path ScenePath = std::filesystem::path(FSceneSaveManager::GetSceneDirectory())
		/ (FPaths::ToWide(InStem) + FSceneSaveManager::SceneExtension);
	return FPaths::ToUtf8(ScenePath.wstring());
}

FString ResolveSceneFilePath(const FString& InNameOrPath)
{
	std::filesystem::path Input(FPaths::ToWide(InNameOrPath));
	const std::wstring Ext = Input.has_extension() ? Input.extension().wstring() : L"";
	if (Input.is_absolute() && std::filesystem::exists(Input))
	{
		return InNameOrPath;
	}

	std::filesystem::path Resolved = std::filesystem::path(FSceneSaveManager::GetSceneDirectory()) / Input;
	if (Ext.empty())
	{
		Resolved += FSceneSaveManager::SceneExtension;
	}
	return FPaths::ToUtf8(Resolved.wstring());
}

FString ReadCommandLineOption(const std::wstring& CommandLine, const std::wstring& Option)
{
	size_t Position = CommandLine.find(Option);
	while (Position != std::wstring::npos)
	{
		const bool bValidStart =
			Position == 0 || std::iswspace(CommandLine[Position - 1]) != 0;
		const size_t AfterOption = Position + Option.size();
		const bool bValidEnd =
			AfterOption >= CommandLine.size() || std::iswspace(CommandLine[AfterOption]) != 0;
		if (bValidStart && bValidEnd)
		{
			size_t ValueStart = AfterOption;
			while (ValueStart < CommandLine.size() && std::iswspace(CommandLine[ValueStart]) != 0)
			{
				++ValueStart;
			}
			if (ValueStart >= CommandLine.size())
			{
				return {};
			}

			if (CommandLine[ValueStart] == L'"')
			{
				const size_t ValueEnd = CommandLine.find(L'"', ValueStart + 1);
				if (ValueEnd == std::wstring::npos)
				{
					return {};
				}
				return FPaths::ToUtf8(CommandLine.substr(ValueStart + 1, ValueEnd - ValueStart - 1));
			}

			size_t ValueEnd = ValueStart;
			while (ValueEnd < CommandLine.size() && std::iswspace(CommandLine[ValueEnd]) == 0)
			{
				++ValueEnd;
			}
			return FPaths::ToUtf8(CommandLine.substr(ValueStart, ValueEnd - ValueStart));
		}
		Position = CommandLine.find(Option, Position + Option.size());
	}
	return {};
}

bool HasCommandLineFlag(const std::wstring& CommandLine, const std::wstring& Flag)
{
	size_t Position = CommandLine.find(Flag);
	while (Position != std::wstring::npos)
	{
		const bool bValidStart =
			Position == 0 || std::iswspace(CommandLine[Position - 1]) != 0;
		const size_t AfterFlag = Position + Flag.size();
		const bool bValidEnd =
			AfterFlag >= CommandLine.size() || std::iswspace(CommandLine[AfterFlag]) != 0;
		if (bValidStart && bValidEnd)
		{
			return true;
		}
		Position = CommandLine.find(Flag, Position + Flag.size());
	}
	return false;
}

FString GetFileStem(const FString& InPath)
{
	const std::filesystem::path Path(FPaths::ToWide(InPath));
	return FPaths::ToUtf8(Path.stem().wstring());
}
}

void UEditorEngine::Init(FWindowsWindow* InWindow)
{
	// 엔진 공통 초기화 (Renderer, D3D, 싱글턴 등)
	UEngine::Init(InWindow);

	// Game 등 외부 모듈이 static initializer 로 자기 init 함수를 FEngineInitHooks 에
	// 등록해 둔 상태. 여기서 한 번에 실행 — Lua state 등 Engine subsystem 들은 이미
	// UEngine::Init 에서 준비됨. Editor 는 Game 모듈의 함수명도, 헤더도 모름.
	FEngineInitHooks::RunAll();

	{
		SCOPE_STARTUP_STAT("MeshManager::ScanMeshAssets");
		FMeshManager::ScanMeshAssets();
	}

	{
		SCOPE_STARTUP_STAT("MeshManager::ScanFbxSourceFiles");
		FMeshManager::ScanFbxSourceFiles();
	}

	{
		SCOPE_STARTUP_STAT("MaterialManager::ScanAssets");
		FMaterialManager::Get().ScanMaterialAssets();
	}

	// 에디터 전용 초기화
	FEditorSettings::Get().LoadFromFile(FEditorSettings::GetDefaultSettingsPath());
	FProjectSettings::Get().LoadFromFile(FProjectSettings::GetDefaultPath());
	FEditorTextureManager::Get().Initialize(Renderer.GetFD3DDevice().GetDevice());

	{
		SCOPE_STARTUP_STAT("EditorMainPanel::Create");
		MainPanel.Create(Window, Renderer, this);
	}

	// 기본 월드 생성 — 모든 서브시스템 초기화의 기반
	CreateWorldContext(EWorldType::Editor, FName("Default"));
	SetActiveWorld(WorldList[0].ContextHandle);
	GetWorld()->InitWorld();

	// Selection & Gizmo
	SelectionManager.Init();
	SelectionManager.SetWorld(GetWorld());

	// 뷰포트 레이아웃 초기화 + 저장된 설정 복원
	ViewportLayout.Initialize(this, Window, Renderer, &SelectionManager);
	ViewportLayout.LoadFromSettings();

	{
		SCOPE_STARTUP_STAT("Editor::LoadStartLevel");
		LoadStartLevel();
	}
	ApplyTransformSettingsToGizmo();

	// Editor render pipeline
	{
		SCOPE_STARTUP_STAT("EditorRenderPipeline::Create");
		SetRenderPipeline(std::make_unique<FEditorRenderPipeline>(this, Renderer));
	}

	const std::wstring CommandLine = GetCommandLineW();
	UnrealSceneCommandletManifestPath =
		ReadCommandLineOption(CommandLine, L"--import-ue-scene");
	if (!UnrealSceneCommandletManifestPath.empty())
	{
		UnrealSceneCommandletSaveName =
			ReadCommandLineOption(CommandLine, L"--save-scene");
		if (UnrealSceneCommandletSaveName.empty())
		{
			UnrealSceneCommandletSaveName =
				GetFileStem(UnrealSceneCommandletManifestPath) + "_Imported";
		}
		bExitAfterUnrealSceneCommandlet =
			HasCommandLineFlag(CommandLine, L"--exit-after-import");
		bOptimizeUnrealSceneStaticMeshInstances =
			HasCommandLineFlag(CommandLine, L"--optimize-static-mesh-instances");
		bUnrealSceneCommandletQueued = true;
	}
}

void UEditorEngine::Shutdown()
{
	// 에디터 해제 (엔진보다 먼저)
	ViewportLayout.SaveToSettings();
	MainPanel.SaveToSettings();
	FProjectSettings::Get().SaveToFile(FProjectSettings::GetDefaultPath());
	FEditorSettings::Get().SaveToFile(FEditorSettings::GetDefaultSettingsPath());
	CloseScene();
	SelectionManager.Shutdown();
	MainPanel.Release();

	// 뷰포트 레이아웃 해제
	ViewportLayout.Release();
	FEditorTextureManager::Get().Shutdown();

	// 엔진 공통 해제 (Renderer, D3D 등)
	UEngine::Shutdown();
}

void UEditorEngine::OnWindowResized(uint32 Width, uint32 Height)
{
	UEngine::OnWindowResized(Width, Height);
	// 윈도우 리사이즈 시에는 ImGui 패널이 실제 크기를 결정하므로
	// FViewport RT는 SSplitter 레이아웃에서 지연 리사이즈로 처리됨
}

void UEditorEngine::Tick(float DeltaTime)
{
	if (bUnrealSceneCommandletQueued && ProcessQueuedUnrealSceneCommandlet())
	{
		return;
	}

	// --- PIE 요청 처리 (프레임 경계에서 처리되도록 Tick 선두에서 소비) ---
	if (bRequestPIESceneTransitionQueued)
	{
		ProcessQueuedPIESceneTransition();
	}
	if (bRequestEndPlayMapQueued)
	{
		bRequestEndPlayMapQueued = false;
		EndPlayMap();
	}
	if (PlaySessionRequest.has_value())
	{
		StartQueuedPlaySessionRequest();
	}

	ApplyTransformSettingsToGizmo();
	FDirectoryWatcher::Get().ProcessChanges();
	FNotificationManager::Get().Tick(DeltaTime);
	InputSystem::Get().Tick();
	MainPanel.Update();
	InputSystem::Get().RefreshSnapshot();

	FSlateApplication::Get().UpdateInputOwner();

	for (FEditorViewportClient* VC : ViewportLayout.GetAllViewportClients())
	{
		VC->Tick(DeltaTime);
	}

	MainPanel.TickAssetEditors(DeltaTime);

	WorldTick(DeltaTime);
    
    FGarbageCollector::Get().CollectGarbage();
    
	Render(DeltaTime);
	SelectionManager.Tick();
}

bool UEditorEngine::ProcessQueuedUnrealSceneCommandlet()
{
	if (!bUnrealSceneCommandletQueued)
	{
		return false;
	}
	bUnrealSceneCommandletQueued = false;

	const FString ManifestPath = UnrealSceneCommandletManifestPath;
	const FString SaveName = UnrealSceneCommandletSaveName;
	UE_LOG(
		"UE_SCENE_COMMANDLET_BEGIN Manifest=%s SaveName=%s OptimizeStaticMeshInstances=%s",
		ManifestPath.c_str(),
		SaveName.c_str(),
		bOptimizeUnrealSceneStaticMeshInstances ? "true" : "false");

	NewScene();
	FWorldContext* Context = GetWorldContextFromHandle(GetActiveWorldHandle());
	FUnrealSceneImportResult Result;
	if (!Context || !Context->World)
	{
		Result.ErrorMessage = "No active editor world.";
	}
	else
	{
		ID3D11Device* Device = GetRenderer().GetFD3DDevice().GetDevice();
		FUnrealSceneImportOptions ImportOptions;
		ImportOptions.bOptimizeStaticMeshInstances =
			bOptimizeUnrealSceneStaticMeshInstances;
		Result = FUnrealSceneManifestImporter::Import(
			ManifestPath,
			Context->World,
			Device,
			ImportOptions);
	}

	bool bSaved = false;
	bool bReloaded = false;
	int32 LoadedActorCount = 0;
	FString SavedScenePath;
	if (Result.bSuccess)
	{
		bSaved = SaveSceneAs(SaveName);
		SavedScenePath = BuildScenePathFromStem(SaveName);
		if (bSaved)
		{
			bReloaded = LoadSceneFromPath(SavedScenePath);
			if (bReloaded)
			{
				UWorld* ReloadedWorld = GetWorld();
				LoadedActorCount = ReloadedWorld
					? static_cast<int32>(ReloadedWorld->GetActors().size())
					: 0;
			}
		}
	}

	const bool bActorCountMatches =
		Result.bSuccess &&
		bSaved &&
		bReloaded &&
		LoadedActorCount == Result.EngineActorCount;
	const bool bValidationSucceeded =
		bActorCountMatches &&
		Result.FailedMeshCount == 0 &&
		Result.FailedTextureCount == 0 &&
		Result.FailedMaterialCount == 0 &&
		Result.SkippedActorCount == 0;

	json::JSON Report = json::JSON::Make(json::JSON::Class::Object);
	Report["success"] = bValidationSucceeded;
	Report["manifest"] = ManifestPath;
	Report["savedScene"] = SavedScenePath;
	Report["importedActors"] = Result.ActorCount;
	Report["engineActors"] = Result.EngineActorCount;
	Report["loadedActors"] = LoadedActorCount;
	Report["actorCountMatches"] = bActorCountMatches;
	Report["optimizeStaticMeshInstances"] = bOptimizeUnrealSceneStaticMeshInstances;
	Report["instancedGroups"] = Result.InstancedGroupCount;
	Report["instancedPlacements"] = Result.InstancedPlacementCount;
	Report["matrixTransforms"] = Result.MatrixTransformCount;
	Report["correctedMatrixTransforms"] = Result.CorrectedMatrixTransformCount;
	Report["meshes"] = Result.MeshCount;
	Report["textures"] = Result.TextureCount;
	Report["materials"] = Result.MaterialCount;
	Report["materialAssignments"] = Result.MaterialAssignmentCount;
	Report["environmentActors"] = Result.EnvironmentActorCount;
	Report["failedMeshes"] = Result.FailedMeshCount;
	Report["failedTextures"] = Result.FailedTextureCount;
	Report["failedMaterials"] = Result.FailedMaterialCount;
	Report["skippedActors"] = Result.SkippedActorCount;
	Report["negativeScaleActors"] = Result.NegativeScaleCount;
	Report["error"] = Result.ErrorMessage;

	const std::filesystem::path ReportPath =
		std::filesystem::path(FPaths::LogDir()) / L"UnrealSceneImportReport.json";
	std::filesystem::create_directories(ReportPath.parent_path());
	std::ofstream ReportFile(ReportPath);
	if (ReportFile.is_open())
	{
		ReportFile << Report.dump();
	}

	UE_LOG(
		"UE_SCENE_COMMANDLET_END Success=%s ImportedActors=%d EngineActors=%d LoadedActors=%d "
		"InstancedGroups=%d InstancedPlacements=%d MatrixTransforms=%d CorrectedMatrixTransforms=%d "
		"Meshes=%d Textures=%d Materials=%d "
		"Environment=%d FailedMeshes=%d FailedTextures=%d FailedMaterials=%d SkippedActors=%d Report=%s",
		bValidationSucceeded ? "true" : "false",
		Result.ActorCount,
		Result.EngineActorCount,
		LoadedActorCount,
		Result.InstancedGroupCount,
		Result.InstancedPlacementCount,
		Result.MatrixTransformCount,
		Result.CorrectedMatrixTransformCount,
		Result.MeshCount,
		Result.TextureCount,
		Result.MaterialCount,
		Result.EnvironmentActorCount,
		Result.FailedMeshCount,
		Result.FailedTextureCount,
		Result.FailedMaterialCount,
		Result.SkippedActorCount,
		FPaths::ToUtf8(ReportPath.wstring()).c_str());

	if (bExitAfterUnrealSceneCommandlet)
	{
		PostQuitMessage(bValidationSucceeded ? 0 : 1);
		return true;
	}
	return false;
}

bool UEditorEngine::GetActiveViewportPOV(FMinimalViewInfo& OutPOV) const
{
	if (FLevelEditorViewportClient* ActiveVC = ViewportLayout.GetActiveViewport())
	{
		ActiveVC->GetCameraView(OutPOV);
		return true;
	}
	return false;
}

void UEditorEngine::RenderUI(float DeltaTime)
{
	MainPanel.Render(DeltaTime);
}

void UEditorEngine::ToggleCoordSystem()
{
	FGizmoToolSettings& Settings = FEditorSettings::Get().LevelViewportSettings[0].Gizmo;
	Settings.CoordSystem = (Settings.CoordSystem == EEditorCoordSystem::World)
		? EEditorCoordSystem::Local
		: EEditorCoordSystem::World;
	ApplyTransformSettingsToGizmo();
}

void UEditorEngine::ApplyTransformSettingsToGizmo()
{
	UGizmoComponent* Gizmo = GetGizmo();
	if (!Gizmo)
	{
		return;
	}

	const FGizmoToolSettings& Settings = FEditorSettings::Get().LevelViewportSettings[0].Gizmo;
	const bool bForceLocalForScale = Gizmo->GetMode() == EGizmoMode::Scale;
	Gizmo->SetWorldSpace(bForceLocalForScale ? false : (Settings.CoordSystem == EEditorCoordSystem::World));
	// 에디터 설정의 좌표계/스냅 값을 매 프레임 Gizmo 상태와 동기화한다.
	Gizmo->SetSnapSettings(
		Settings.bEnableTranslationSnap, Settings.TranslationSnapSize,
		Settings.bEnableRotationSnap, Settings.RotationSnapSize,
		Settings.bEnableScaleSnap, Settings.ScaleSnapSize);
}

// ─── PIE (Play In Editor) ────────────────────────────────
// UE 패턴 요약: Request는 단일 슬롯(std::optional)에 저장만 하고 즉시 실행하지 않는다.
// 실제 StartPIE는 다음 Tick 선두의 StartQueuedPlaySessionRequest에서 일어난다.
// 이유는 UI 콜백/트랜잭션 도중 같은 불안정한 타이밍을 피하기 위함.

void UEditorEngine::RequestPlaySession(const FRequestPlaySessionParams& InParams)
{
	// 동시 요청은 UE와 동일하게 덮어쓴다 (진짜 큐 아님 — 단일 슬롯).
	PlaySessionRequest = InParams;
}

void UEditorEngine::CancelRequestPlaySession()
{
	PlaySessionRequest.reset();
}

void UEditorEngine::RequestEndPlayMap()
{
	if (!PlayInEditorSessionInfo.has_value())
	{
		return;
	}
	bRequestEndPlayMapQueued = true;
}

void UEditorEngine::RequestTransitionToScene(const FString& InScenePath)
{
	// Queue scene travel until the next editor tick. The Lua click callback may
	// still be on the stack, so do not tear down the PIE world immediately here.
	if (!PlayInEditorSessionInfo.has_value() || InScenePath.empty())
	{
		return;
	}

	QueuedPIESceneTransitionPath = InScenePath;
	QueuedPIESceneTransitionParams = PlayInEditorSessionInfo->OriginalRequestParams;
	bRequestPIESceneTransitionQueued = true;
	bRequestEndPlayMapQueued = false;
}

UWorld* UEditorEngine::GetPlayInEditorWorld() const
{
	for (const FWorldContext& Ctx : WorldList)
	{
		if (Ctx.WorldType == EWorldType::PIE && Ctx.World)
		{
			return Ctx.World;
		}
	}
	return nullptr;
}

void UEditorEngine::ProcessQueuedPIESceneTransition()
{
	if (!bRequestPIESceneTransitionQueued)
	{
		return;
	}

	const FString ScenePath = QueuedPIESceneTransitionPath;
	const FRequestPlaySessionParams Params = QueuedPIESceneTransitionParams;
	bRequestPIESceneTransitionQueued = false;
	QueuedPIESceneTransitionPath.clear();

	if (ScenePath.empty())
	{
		return;
	}

	if (PlayInEditorSessionInfo.has_value())
	{
		EndPlayMap();
	}

	if (!LoadSceneFromPath(ResolveSceneFilePath(ScenePath)))
	{
		return;
	}

	RequestPlaySession(Params);
}

void UEditorEngine::StartQueuedPlaySessionRequest()
{
	if (!PlaySessionRequest.has_value())
	{
		return;
	}

	const FRequestPlaySessionParams Params = *PlaySessionRequest;
	PlaySessionRequest.reset();

	// 이미 PIE 중이면 기존 세션을 정리 후 새로 시작 (단순화).
	if (PlayInEditorSessionInfo.has_value())
	{
		EndPlayMap();
	}

	switch (Params.SessionDestination)
	{
	case EPIESessionDestination::InProcess:
		StartPlayInEditorSession(Params);
		break;
	}
}

void UEditorEngine::StartPlayInEditorSession(const FRequestPlaySessionParams& Params)
{
	InputSystem::Get().ResetAllKeyStates();
	InputSystem::Get().ResetTransientState();

	// 1) 현재 에디터 월드를 복제해 PIE 월드 생성 (UE의 CreatePIEWorldByDuplication 대응).
	UWorld* EditorWorld = GetWorld();
	if (!EditorWorld)
	{
		return;
	}
	// DuplicateAs(PIE)로 복제하면 Actor 복제 전에 WorldType이 설정되어
	// EditorOnly 컴포넌트의 프록시가 아예 생성되지 않음.
	UWorld* PIEWorld = EditorWorld->DuplicateAs(EWorldType::PIE);
	if (!PIEWorld)
	{
		return;
	}

	// 2) PIE WorldContext를 WorldList에 등록.
	FWorldContext Ctx;
	Ctx.WorldType = EWorldType::PIE;
	Ctx.ContextHandle = FName("PIE");
	Ctx.ContextName = "PIE";
	Ctx.World = PIEWorld;
	WorldList.push_back(Ctx);

	// 3) 세션 정보 기록 (이전 활성 핸들 포함 — EndPlayMap에서 복원).
	FPlayInEditorSessionInfo Info;
	Info.OriginalRequestParams = Params;
	Info.PIEStartTime = 0.0;
	Info.PreviousActiveWorldHandle = GetActiveWorldHandle();
	if (FLevelEditorViewportClient* ActiveVC = ViewportLayout.GetActiveViewport())
	{
		ActiveVC->GetCameraView(Info.SavedViewportCamera.POV);
		Info.SavedViewportCamera.bValid = true;
	}
	PlayInEditorSessionInfo = Info;

	// 4) ActiveWorldHandle을 PIE로 전환 — 이후 GetWorld()는 PIE 월드를 반환.
	SetActiveWorld(FName("PIE"));

	// GPU Occlusion readback은 ProxyId 기반이라 월드가 갈리면 stale.
	// 이전 프레임 결과를 무효화해야 wrong-proxy hit 방지.
	if (IRenderPipeline* Pipeline = GetRenderPipeline())
	{
		Pipeline->OnSceneCleared();
	}

	// 5) 활성 뷰포트를 PIE 월드의 IPOVProvider 로 등록 —
	//    PC 가 자기 카메라를 잡기 전까지 LOD fallback 으로 pull.
	if (FLevelEditorViewportClient* ActiveVC = ViewportLayout.GetActiveViewport())
	{
		PIEWorld->SetEditorPOVProvider(ActiveVC);
	}

	// 6) Selection을 PIE 월드 기준으로 재바인딩 — 에디터 액터를 가리킨 채로 두면
	//    픽킹(=PIE 월드) / outliner / outline 렌더가 모두 어긋난다.
	SelectionManager.ClearSelection();
	//SelectionManager.SetGizmoEnabled(false); //PIE가 시작되면 gizmo 비활성화
	SelectionManager.SetWorld(PIEWorld);

	if (!GetGameViewportClient())
	{
		UGameViewportClient* PIEViewportClient = UObjectManager::Get().CreateObject<UGameViewportClient>();
		SetGameViewportClient(PIEViewportClient);
	}
	if (UGameViewportClient* PIEViewportClient = GetGameViewportClient())
	{
		if (Window)
		{
			PIEViewportClient->SetOwnerWindow(Window->GetHWND());
		}
		FViewport* InitialViewport = nullptr;
		if (FLevelEditorViewportClient* ActiveVC = ViewportLayout.GetActiveViewport())
		{
			InitialViewport = ActiveVC->GetViewport();
			PIEViewportClient->SetCursorClipRect(ActiveVC->GetViewportScreenRect());
		}
		PIEViewportClient->BeginGameSession(InitialViewport);
	}
	EnterPIEPossessedMode();
	
	//이 코드와 대응되는 게 아래 EndPlayMap()에 있음.
	//MainPanel.HideEditorWindowsForPIE(); //PIE 중에는 에디터 패널을 숨김.
	//ViewportLayout.DisableWorldAxisForPIE(); //PIE 중에는 월드 축 렌더링을 비활성화.

	// PIE 월드에도 ProjectSettings의 GameMode 클래스 적용.
	// Editor 모듈은 Game-specific 디폴트를 알 수 없으므로, ProjectSettings에
	// 지정된 경우에만 GameMode가 spawn된다. 비어있으면 미생성 (회귀 안전).
	if (UClass* GMClass = AGameModeBase::ResolveClassFromProjectSettings(nullptr))
	{
		PIEWorld->SetGameModeClass(GMClass);
	}

	// 7) BeginPlay 트리거 — 모든 등록/바인딩이 끝난 다음 첫 Tick 이전에 호출.
	//    UWorld::BeginPlay가 bHasBegunPlay를 먼저 세팅하므로 BeginPlay 도중
	//    SpawnActor로 만든 신규 액터도 자동으로 BeginPlay된다.
	PIEWorld->BeginPlay();
}

void UEditorEngine::EndPlayMap()
{
	if (!PlayInEditorSessionInfo.has_value())
	{
		return;
	}

	// 활성 월드를 PIE 시작 전 핸들로 복원.
	const FName PrevHandle = PlayInEditorSessionInfo->PreviousActiveWorldHandle;
	SetActiveWorld(PrevHandle);

	// 복귀한 Editor 월드의 VisibleProxies/캐시된 카메라 상태를 강제 무효화.
	// PIE 중 Editor WorldTick이 skip되어 캐시가 PIE 시작 전 시점 그대로 남아 있고,
	// NeedsVisibleProxyRebuild()가 카메라 변화 기반이라 false를 반환하면 stale
	// VisibleProxies가 그대로 재사용되어 dangling proxy 참조로 크래시가 날 수 있다.
	//
	// 또한 Renderer::PerObjectCBPool은 ProxyId로 인덱싱되는 월드 간 공유 풀이라,
	// PIE 중 PIE 프록시가 덮어쓴 슬롯이 그대로 남아 있으면 Editor 프록시의
	// bPerObjectCBDirty=false 상태로 인해 업로드가 skip되어 PIE 마지막 transform으로
	// 렌더된다. 모든 Editor 프록시를 PerObjectCB dirty로 마킹해 재업로드 강제.
	if (UWorld* EditorWorld = GetWorld())
	{
		EditorWorld->GetScene().MarkAllPerObjectCBDirty();

		// ActiveCamera는 PIE 시작 시 PIE 월드로 옮겨졌고 PIE 월드와 함께 파괴됐다.
		// Editor 월드의 ActiveCamera는 여전히 그 dangling 포인터를 가리킬 수 있으므로
		// 활성 뷰포트의 카메라로 다시 바인딩해 줘야 frustum culling이 정상 동작한다.
		if (FLevelEditorViewportClient* ActiveVC = ViewportLayout.GetActiveViewport())
		{
			// D.3: ViewTransform 에 직접 writeback. NotifyViewTransformChanged 가 mirror Camera 갱신.
			if (PlayInEditorSessionInfo->SavedViewportCamera.bValid)
			{
				const FMinimalViewInfo& SavedPOV = PlayInEditorSessionInfo->SavedViewportCamera.POV;
				FViewportCameraTransform& VT = ActiveVC->GetViewTransform();
				VT.ViewLocation = SavedPOV.Location;
				VT.ViewRotation = SavedPOV.Rotation;
				VT.FOV          = SavedPOV.FOV;
				VT.AspectRatio  = SavedPOV.AspectRatio;
				VT.NearClip     = SavedPOV.NearClip;
				VT.FarClip      = SavedPOV.FarClip;
				VT.OrthoZoom    = SavedPOV.OrthoWidth;
				VT.bIsOrtho     = SavedPOV.bIsOrtho;
				ActiveVC->NotifyViewTransformChanged();
			}

			// Editor world 에 active viewport 를 IPOVProvider 로 등록 (LOD pull 진입점).
			EditorWorld->SetEditorPOVProvider(ActiveVC);
		}
	}

	// Selection을 에디터 월드로 복원 — PIE 액터는 곧 파괴되므로 먼저 비운다.
	SelectionManager.ClearSelection();
	//SelectionManager.SetGizmoEnabled(true); //PIE가 끝나면 gizmo 활성화
	SelectionManager.SetWorld(GetWorld());
	
	//이 코드와 대응되는 게 위의 StartPlayInEditorSession()에 있음.
	//MainPanel.RestoreEditorWindowsAfterPIE();
	//ViewportLayout.RestoreWorldAxisAfterPIE();

	if (UGameViewportClient* PIEViewportClient = GetGameViewportClient())
	{
		PIEViewportClient->EndGameSession();
		UObjectManager::Get().DestroyObject(PIEViewportClient);
		SetGameViewportClient(nullptr);
	}

	UUIManager::Get().ClearViewport();

	// PIE WorldContext 제거 전에 require 캐시/코루틴/registry 의 월드 참조를 먼저 끊는다.
	// DestroyWorldContext 중 Lua EndPlay 가 돌 수 있으므로 stale UObject 를 들고 있는 Lua 전역 상태를 선제 정리한다.
	FLuaScriptManager::FireWorldReset();

	// PIE WorldContext 제거 (DestroyWorldContext가 EndPlay + DestroyObject 수행).
	DestroyWorldContext(FName("PIE"));

	// Destroy 이후 남은 require 캐시의 stale 액터 참조를 한 번 더 정리한다.
	FLuaScriptManager::FireWorldReset();

	// PIE 월드의 프록시가 모두 파괴됐으므로 GPU Occlusion readback 무효화.
	if (IRenderPipeline* Pipeline = GetRenderPipeline())
	{
		Pipeline->OnSceneCleared();
	}

	PlayInEditorSessionInfo.reset();
	PIEControlMode = EPIEControlMode::Possessed;
	InputSystem::Get().ResetCaptureStateForPIEEnd();
}

bool UEditorEngine::TogglePIEControlMode()
{
	if (!IsPlayingInEditor())
	{
		return false;
	}

	if (PIEControlMode == EPIEControlMode::Possessed)
	{
		return EnterPIEEjectedMode();
	}
	return EnterPIEPossessedMode();
}

bool UEditorEngine::EnterPIEPossessedMode()
{
	if (!IsPlayingInEditor())
	{
		return false;
	}

	PIEControlMode = EPIEControlMode::Possessed;
	SyncGameViewportPIEControlState(true);
	InputSystem::Get().SetUseRawMouse(true);
	InputSystem::Get().ResetTransientState();
	return true;
}

bool UEditorEngine::EnterPIEEjectedMode()
{
	if (!IsPlayingInEditor())
	{
		return false;
	}

	PIEControlMode = EPIEControlMode::Ejected;
	SyncGameViewportPIEControlState(false);
	InputSystem::Get().SetUseRawMouse(false);
	InputSystem::Get().ResetTransientState();
	return true;
}

void UEditorEngine::SyncGameViewportPIEControlState(bool bPossessedMode)
{
	UGameViewportClient* PIEViewportClient = GetGameViewportClient();
	if (!PIEViewportClient)
	{
		return;
	}

	PIEViewportClient->SetInputPossessed(bPossessedMode);
	if (!bPossessedMode)
	{
		return;
	}

	if (Window)
	{
		PIEViewportClient->SetOwnerWindow(Window->GetHWND());
	}

	if (FLevelEditorViewportClient* ActiveVC = ViewportLayout.GetActiveViewport())
	{
		PIEViewportClient->SetViewport(ActiveVC->GetViewport());
		PIEViewportClient->SetCursorClipRect(ActiveVC->GetViewportScreenRect());
		return;
	}
}

// ─── 기존 메서드 ──────────────────────────────────────────

void UEditorEngine::ResetViewport()
{
	ViewportLayout.ResetViewport(GetWorld());
}

void UEditorEngine::CloseScene()
{
	ClearScene();
}

void UEditorEngine::NewScene()
{
	StopPlayInEditorImmediate();
	ClearScene();
	FWorldContext& Ctx = CreateWorldContext(EWorldType::Editor, FName("NewScene"), "New Scene");
	Ctx.World->InitWorld();
	SetActiveWorld(Ctx.ContextHandle);
	SelectionManager.SetWorld(GetWorld());

	ResetViewport();
	CurrentLevelFilePath.clear();
}

void UEditorEngine::LoadStartLevel()
{
	const FString& StartLevel = FEditorSettings::Get().EditorStartLevel;
	if (StartLevel.empty())
	{
		return;
	}

	std::filesystem::path ScenePath = std::filesystem::path(FSceneSaveManager::GetSceneDirectory())
		/ (FPaths::ToWide(StartLevel) + FSceneSaveManager::SceneExtension);
	FString FilePath = FPaths::ToUtf8(ScenePath.wstring());

	if (!LoadSceneFromPath(FilePath))
	{
		// 로드 실패 시 빈 씬으로 복구
		NewScene();
	}
}

void UEditorEngine::ClearScene()
{
	StopPlayInEditorImmediate();
	SelectionManager.ClearSelection();
	SelectionManager.SetWorld(nullptr);

	// 씬 프록시 파괴 전 GPU Occlusion 스테이징 데이터 무효화
	if (IRenderPipeline* Pipeline = GetRenderPipeline())
		Pipeline->OnSceneCleared();

	for (auto It = WorldList.begin(); It != WorldList.end();)
	{
		FWorldContext& Ctx = *It;

		if (Ctx.WorldType == EWorldType::EditorPreview)
		{
			++It;
			continue;
		}

		if (Ctx.World)
		{
			Ctx.World->RouteWorldDestroyed();
			UObjectManager::Get().DestroyObject(Ctx.World);
		}

		It = WorldList.erase(It);
	}

	ActiveWorldHandle = FName::None;
	CurrentLevelFilePath.clear();

	ViewportLayout.DestroyAllCameras();
}

// 잔여 정리: SceneSaveManager 가 POV 받게 시그니처화 → 여기도 POV 직접 산출.
bool UEditorEngine::FindSceneViewportPOV(FMinimalViewInfo& OutPOV) const
{
	for (FLevelEditorViewportClient* VC : ViewportLayout.GetLevelViewportClients())
	{
		if (!VC) continue;

		if (VC->GetRenderOptions().ViewportType == ELevelViewportType::Perspective
			|| VC->GetRenderOptions().ViewportType == ELevelViewportType::FreeOrthographic)
		{
			VC->GetCameraView(OutPOV);
			return true;
		}
	}
	return false;
}

void UEditorEngine::RestoreViewportCamera(const FPerspectiveCameraData& CamData)
{
	if (!CamData.bValid)
	{
		return;
	}

	// 잔여 정리: ViewTransform 직접 writeback. 직렬화 컨벤션 FVector(Roll, Pitch, Yaw) → FRotator(Pitch, Yaw, Roll).
	for (FLevelEditorViewportClient* VC : ViewportLayout.GetLevelViewportClients())
	{
		if (!VC) continue;
		const auto VPType = VC->GetRenderOptions().ViewportType;
		if (VPType == ELevelViewportType::Perspective || VPType == ELevelViewportType::FreeOrthographic)
		{
			FViewportCameraTransform& VT = VC->GetViewTransform();
			VT.ViewLocation = CamData.Location;
			VT.ViewRotation = FRotator(CamData.Rotation.Y, CamData.Rotation.Z, CamData.Rotation.X);
			VT.FOV          = CamData.FOV;
			VT.NearClip     = CamData.NearClip;
			VT.FarClip      = CamData.FarClip;
			VC->NotifyViewTransformChanged();
			break;
		}
	}
}

bool UEditorEngine::SaveSceneAs(const FString& InSceneName)
{
	if (InSceneName.empty())
	{
		return false;
	}

	StopPlayInEditorImmediate();
	FWorldContext* Context = GetWorldContextFromHandle(GetActiveWorldHandle());
	if (!Context || !Context->World)
	{
		return false;
	}

	FMinimalViewInfo SavePOV;
	const bool bHasPOV = FindSceneViewportPOV(SavePOV);
	FSceneSaveManager::SaveSceneAsJSON(InSceneName, *Context, bHasPOV ? &SavePOV : nullptr);
	CurrentLevelFilePath = BuildScenePathFromStem(InSceneName);
	return true;
}

bool UEditorEngine::SaveScene()
{
	if (HasCurrentLevelFilePath())
	{
		return SaveSceneAs(GetFileStem(CurrentLevelFilePath));
	}

	return SaveSceneAsWithDialog();
}

bool UEditorEngine::SaveSceneAsWithDialog()
{
	const std::wstring InitialDir = FSceneSaveManager::GetSceneDirectory();
	const std::wstring DefaultFile = HasCurrentLevelFilePath()
		? std::filesystem::path(FPaths::ToWide(CurrentLevelFilePath)).filename().wstring()
		: std::wstring(L"Untitled.Scene");
	const FString SelectedPath = FEditorFileUtils::SaveFileDialog({
		.Filter = L"Scene Files (*.Scene)\0*.Scene\0All Files (*.*)\0*.*\0",
		.Title = L"Save Scene As",
		.DefaultExtension = L"Scene",
		.InitialDirectory = InitialDir.c_str(),
		.DefaultFileName = DefaultFile.c_str(),
		.OwnerWindowHandle = Window ? Window->GetHWND() : nullptr,
		.bFileMustExist = false,
		.bPathMustExist = true,
		.bPromptOverwrite = true,
		.bReturnRelativeToProjectRoot = false,
	});
	if (SelectedPath.empty())
	{
		return false;
	}

	return SaveSceneAs(GetFileStem(SelectedPath));
}

bool UEditorEngine::LoadSceneFromPath(const FString& InScenePath)
{
	if (InScenePath.empty())
	{
		return false;
	}

	StopPlayInEditorImmediate();
	ClearScene();

	FWorldContext LoadContext;
	FPerspectiveCameraData CameraData;
	FSceneSaveManager::LoadSceneFromJSON(InScenePath, LoadContext, CameraData);
	if (!LoadContext.World)
	{
		return false;
	}

	WorldList.push_back(LoadContext);
	SetActiveWorld(LoadContext.ContextHandle);
	SelectionManager.SetWorld(LoadContext.World);
	LoadContext.World->WarmupPickingData();
	ResetViewport();
	RestoreViewportCamera(CameraData);

	CurrentLevelFilePath = InScenePath;
	return true;
}

bool UEditorEngine::LoadSceneWithDialog()
{
	const std::wstring InitialDir = FSceneSaveManager::GetSceneDirectory();
	const FString SelectedPath = FEditorFileUtils::OpenFileDialog({
		.Filter = L"Scene Files (*.Scene)\0*.Scene\0All Files (*.*)\0*.*\0",
		.Title = L"Load Scene",
		.InitialDirectory = InitialDir.c_str(),
		.OwnerWindowHandle = Window ? Window->GetHWND() : nullptr,
		.bFileMustExist = true,
		.bPathMustExist = true,
		.bPromptOverwrite = false,
		.bReturnRelativeToProjectRoot = false,
	});
	if (SelectedPath.empty())
	{
		return false;
	}

	return LoadSceneFromPath(SelectedPath);
}

bool UEditorEngine::ImportUnrealSceneManifestWithDialog(bool bOptimizeStaticMeshInstances)
{
	StopPlayInEditorImmediate();

	FWorldContext* Context = GetWorldContextFromHandle(GetActiveWorldHandle());
	if (!Context || !Context->World)
	{
		FNotificationManager::Get().AddNotification(
			"UE scene import failed: no active world.",
			ENotificationType::Error,
			5.0f);
		return false;
	}

	const FString SelectedPath = FEditorFileUtils::OpenFileDialog({
		.Filter = L"UE Scene Manifest (*.scene.json;*.json)\0*.scene.json;*.json\0JSON Files (*.json)\0*.json\0All Files (*.*)\0*.*\0",
		.Title = L"Import UE Scene Manifest",
		.OwnerWindowHandle = Window ? Window->GetHWND() : nullptr,
		.bFileMustExist = true,
		.bPathMustExist = true,
		.bPromptOverwrite = false,
		.bReturnRelativeToProjectRoot = false,
	});
	if (SelectedPath.empty())
	{
		return false;
	}

	ID3D11Device* Device = GetRenderer().GetFD3DDevice().GetDevice();
	FUnrealSceneImportOptions ImportOptions;
	ImportOptions.bOptimizeStaticMeshInstances = bOptimizeStaticMeshInstances;
	const FUnrealSceneImportResult Result =
		FUnrealSceneManifestImporter::Import(
			SelectedPath,
			Context->World,
			Device,
			ImportOptions);

	if (!Result.bSuccess)
	{
		FNotificationManager::Get().AddNotification(
			"UE scene import failed: " + Result.ErrorMessage,
			ENotificationType::Error,
			7.0f);
		return false;
	}

	RefreshContentBrowser();
	Context->World->WarmupPickingData();
	if (FLevelEditorViewportClient* ActiveViewport = GetActiveViewport())
	{
		FVector SceneCenter;
		FVector SceneExtent;
		if (GetWorldFocusBounds(Context->World, SceneCenter, SceneExtent))
		{
			ActiveViewport->FocusOnBounds(SceneCenter, SceneExtent, true);
		}
	}

	FNotificationManager::Get().AddNotification(
		"UE scene imported: " + std::to_string(Result.ActorCount) +
		" placements, " + std::to_string(Result.EngineActorCount) +
		" engine actors, " + std::to_string(Result.MeshCount) + " meshes, " +
		std::to_string(Result.MaterialCount) + " materials.",
		ENotificationType::Success,
		7.0f);
	return true;
}
