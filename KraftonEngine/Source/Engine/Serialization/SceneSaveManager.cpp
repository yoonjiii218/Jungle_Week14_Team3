#include "SceneSaveManager.h"

#include <iostream>
#include <fstream>
#include <chrono>
#include <cstring>
#include <algorithm>
#include <future>
#include <memory>
#include <utility>
#include "SimpleJSON/json.hpp"
#include "GameFramework/World.h"
#include "GameFramework/AActor.h"
#include "Component/SceneComponent.h"
#include "Component/ActorComponent.h"
#include "Render/Types/MinimalViewInfo.h"
#include "Component/Primitive/SkeletalMeshComponent.h"
#include "Component/Primitive/SkinnedMeshComponent.h"
#include "Component/Primitive/StaticMeshComponent.h"
#include "Component/Primitive/DecalComponent.h"
#include "Component/Primitive/HeightFogComponent.h"
#include "Component/Light/LightComponentBase.h"
#include "Object/Object.h"
#include "Object/Reflection/ObjectFactory.h"
#include "Core/Types/PropertyTypes.h"
#include "Object/FName.h"
#include "Serialization/JsonArchive.h"
#include "Profiling/Time/PlatformTime.h"

// ---- JSON vector helpers ---------------------------------------------------

static void WriteVec3(json::JSON& Obj, const char* Key, const FVector& V)
{
	json::JSON arr = json::Array();
	arr.append(static_cast<double>(V.X));
	arr.append(static_cast<double>(V.Y));
	arr.append(static_cast<double>(V.Z));
	Obj[Key] = arr;
}

static FVector ReadVec3(json::JSON& Arr)
{
	FVector out(0, 0, 0);
	int i = 0;
	for (auto& e : Arr.ArrayRange()) {
		if (i == 0) out.X = static_cast<float>(e.ToFloat());
		else if (i == 1) out.Y = static_cast<float>(e.ToFloat());
		else if (i == 2) out.Z = static_cast<float>(e.ToFloat());
		++i;
	}
	return out;
}

// ---------------------------------------------------------------------------

namespace SceneKeys
{
	static constexpr const char* Version = "Version";
	static constexpr const char* Name = "Name";
	static constexpr const char* ClassName = "ClassName";
	static constexpr const char* WorldType = "WorldType";
	static constexpr const char* ContextName = "ContextName";
	static constexpr const char* ContextHandle = "ContextHandle";
	static constexpr const char* WorldSettings = "WorldSettings";
	static constexpr const char* GameMode = "GameMode";  // legacy / WorldSettings 내부 키
	static constexpr const char* Actors = "Actors";
	static constexpr const char* RootComponent = "RootComponent";
	static constexpr const char* NonSceneComponents = "NonSceneComponents";
	static constexpr const char* Properties = "Properties";
	static constexpr const char* Children = "Children";
	static constexpr const char* AttachSocket = "AttachSocket";
	static constexpr const char* HiddenInComponentTree = "bHiddenInComponentTree";
	static constexpr const char* ObjectId = "ObjectId";
}

class FSceneJsonSaveArchive : public FJsonArchive
{
public:
	FSceneJsonSaveArchive(json::JSON& Root, const FSceneSaveManager::FSceneSaveContext& InContext)
		: FJsonArchive(Root, /*bInIsSaving=*/true)
		, Context(InContext)
	{
	}

protected:
	uint32 ResolveJsonObjectId(const UObject* Object) const override
	{
		return Context.FindObjectId(Object);
	}

private:
	const FSceneSaveManager::FSceneSaveContext& Context;
};

class FSceneJsonLoadArchive : public FJsonArchive
{
public:
	FSceneJsonLoadArchive(json::JSON& Root, const FSceneSaveManager::FSceneLoadContext& InContext)
		: FJsonArchive(Root, /*bInIsSaving=*/false)
		, Context(InContext)
	{
	}

protected:
	UObject* ResolveJsonObjectReference(uint32 ObjectId) const override
	{
		return ObjectId != 0 ? Context.FindObjectById(ObjectId) : nullptr;
	}

private:
	const FSceneSaveManager::FSceneLoadContext& Context;
};

uint32 FSceneSaveManager::FSceneSaveContext::RegisterSceneObject(const UObject* Object)
{
	if (!Object)
	{
		return 0;
	}

	auto It = ObjectToId.find(Object);
	if (It != ObjectToId.end())
	{
		return It->second;
	}

	const uint32 ObjectId = NextObjectId++;
	ObjectToId.emplace(Object, ObjectId);
	return ObjectId;
}

uint32 FSceneSaveManager::FSceneSaveContext::FindObjectId(const UObject* Object) const
{
	if (!Object)
	{
		return 0;
	}

	auto It = ObjectToId.find(Object);
	return It != ObjectToId.end() ? It->second : 0;
}

void FSceneSaveManager::FSceneLoadContext::RegisterLoadedObject(json::JSON& Node, UObject* Object)
{
	if (!Object || !Node.hasKey(SceneKeys::ObjectId))
	{
		return;
	}

	const uint32 ObjectId = static_cast<uint32>(Node[SceneKeys::ObjectId].ToInt());
	if (ObjectId != 0)
	{
		ObjectById[ObjectId] = Object;
	}
}

UObject* FSceneSaveManager::FSceneLoadContext::FindObjectById(uint32 ObjectId) const
{
	auto It = ObjectById.find(ObjectId);
	return It != ObjectById.end() ? It->second : nullptr;
}

void FSceneSaveManager::FSceneLoadContext::QueueProperties(UObject* Object, json::JSON& Properties)
{
	if (!Object)
	{
		return;
	}

	PendingProperties.push_back({ Object, &Properties });
}

struct FSceneSaveManager::FSceneAsyncLoadState
{
	enum class EPhase
	{
		LoadRoot,
		InitWorld,
		Actors,
		Properties,
		PostLoad,
		Octree,
		Finished,
		Failed
	};

	struct FRootLoadResult
	{
		bool bSucceeded = false;
		std::shared_ptr<json::JSON> Root;
	};

	std::shared_ptr<json::JSON> Root;
	std::future<FRootLoadResult> RootFuture;
	FWorldContext* OutWorldContext = nullptr;
	FPerspectiveCameraData* OutCam = nullptr;
	FSceneLoadContext LoadContextState;
	UWorld* World = nullptr;
	json::JSON* ActorsJSON = nullptr;
	bool bHasOverrideWorldType = false;
	EWorldType OverrideWorldType = EWorldType::Editor;
	EWorldType WorldType = EWorldType::Editor;
	FString ContextName;
	FName ContextHandle;
	TArray<UObject*> PostLoadObjects;
	TArray<AActor*> OctreeActors;
	int32 TotalActorCount = 0;
	int32 NextActorIndex = 0;
	int32 NextPropertyIndex = 0;
	int32 NextPostLoadIndex = 0;
	int32 NextOctreeActorIndex = 0;
	EPhase Phase = EPhase::Failed;
};

static void SerializeComponentEditorMetadata(json::JSON& Node, const UActorComponent* Comp)
{
	if (!Comp)
	{
		return;
	}

	if (Comp->IsHiddenInComponentTree())
	{
		Node[SceneKeys::HiddenInComponentTree] = true;
	}
}

static void DeserializeComponentEditorMetadata(UActorComponent* Comp, json::JSON& Node)
{
	if (!Comp)
	{
		return;
	}

	if (Node.hasKey(SceneKeys::HiddenInComponentTree))
	{
		Comp->SetHiddenInComponentTree(Node[SceneKeys::HiddenInComponentTree].ToBool());
	}
}

static void EnsureEditorBillboardMetadata(UActorComponent* Comp)
{
	if (ULightComponentBase* LightComponent = Cast<ULightComponentBase>(Comp))
	{
		LightComponent->EnsureEditorBillboard();
	}
	else if (UDecalComponent* DecalComponent = Cast<UDecalComponent>(Comp))
	{
		DecalComponent->EnsureEditorBillboard();
	}
	else if (UHeightFogComponent* HeightFogComponent = Cast<UHeightFogComponent>(Comp))
	{
		HeightFogComponent->EnsureEditorBillboard();
	}
}

static const char* WorldTypeToString(EWorldType Type)
{
	switch (Type) {
	case EWorldType::Game: return "Game";
	case EWorldType::PIE:  return "PIE";
	default:               return "Editor";
	}
}

static EWorldType StringToWorldType(const string& Str)
{
	if (Str == "Game") return EWorldType::Game;
	if (Str == "PIE")  return EWorldType::PIE;
	return EWorldType::Editor;
}

// ============================================================
// Save
// ============================================================

void FSceneSaveManager::SaveSceneAsJSON(const string& InSceneName, FWorldContext& WorldContext, const FMinimalViewInfo* PerspectivePOV)
{
	using namespace json;

	if (!WorldContext.World) return;

	string FinalName = InSceneName.empty()
		? "Save_" + GetCurrentTimeStamp()
		: InSceneName;

	std::wstring SceneDir = GetSceneDirectory();
	std::filesystem::path FileDestination = std::filesystem::path(SceneDir) / (FPaths::ToWide(FinalName) + SceneExtension);
	std::filesystem::create_directories(SceneDir);

	FSceneSaveContext SaveContext;
	CollectWorldObjectIds(WorldContext.World, SaveContext);

	JSON Root = SerializeWorld(WorldContext.World, WorldContext, PerspectivePOV, SaveContext);
	Root[SceneKeys::Version] = 2;
	Root[SceneKeys::Name] = FinalName;

	std::ofstream File(FileDestination);
	if (File.is_open()) {
		File << Root.dump();
		File.flush();
		File.close();
	}
}

void FSceneSaveManager::CollectWorldObjectIds(UWorld* World, FSceneSaveContext& Context)
{
	if (!World)
	{
		return;
	}

	Context.RegisterSceneObject(World);
	for (AActor* Actor : World->GetActors())
	{
		CollectActorObjectIds(Actor, Context);
	}
}

void FSceneSaveManager::CollectActorObjectIds(AActor* Actor, FSceneSaveContext& Context)
{
	if (!Actor)
	{
		return;
	}

	Context.RegisterSceneObject(Actor);
	if (Actor->GetRootComponent())
	{
		CollectSceneComponentObjectIds(Actor->GetRootComponent(), Context);
	}

	for (UActorComponent* Comp : Actor->GetComponents())
	{
		if (!Comp)
		{
			continue;
		}

		Context.RegisterSceneObject(Comp);
	}
}

void FSceneSaveManager::CollectSceneComponentObjectIds(USceneComponent* Comp, FSceneSaveContext& Context)
{
	if (!Comp)
	{
		return;
	}

	Context.RegisterSceneObject(Comp);
	for (USceneComponent* Child : Comp->GetChildren())
	{
		CollectSceneComponentObjectIds(Child, Context);
	}
}

json::JSON FSceneSaveManager::SerializeWorld(UWorld* World, const FWorldContext& Ctx, const FMinimalViewInfo* PerspectivePOV, FSceneSaveContext& Context)
{
	using namespace json;
	JSON w = json::Object();
	w[SceneKeys::ClassName] = World->GetClass()->GetName();
	w[SceneKeys::ObjectId] = static_cast<int>(Context.RegisterSceneObject(World));
	w[SceneKeys::WorldType] = WorldTypeToString(Ctx.WorldType);
	w[SceneKeys::ContextName] = Ctx.ContextName;
	w[SceneKeys::ContextHandle] = Ctx.ContextHandle.ToString();

	// ---- WorldSettings (씬 단위 게임 설정) ----
	{
		const FWorldSettings& WS = World->GetWorldSettings();
		JSON WSObj = json::Object();
		WSObj[SceneKeys::GameMode] = WS.GameModeClassName;
		w[SceneKeys::WorldSettings] = WSObj;
	}

	// ---- Actors ----
	JSON Actors = json::Array();
	for (AActor* Actor : World->GetActors()) {
		if (!Actor) continue;
		Actors.append(SerializeActor(Actor, Context));
	}
	w[SceneKeys::Actors] = Actors;

	// ---- Perspective camera ----
	JSON cam = SerializeCamera(PerspectivePOV);
	if (cam.size() > 0) {
		w["PerspectiveCamera"] = cam;
	}

	return w;
}

json::JSON FSceneSaveManager::SerializeActor(AActor* Actor, FSceneSaveContext& Context)
{
	using namespace json;
	JSON a = json::Object();
	a[SceneKeys::ClassName] = Actor->GetClass()->GetName();
	a[SceneKeys::ObjectId] = static_cast<int>(Context.RegisterSceneObject(Actor));
	a[SceneKeys::Name] = Actor->GetFName().ToString();
	a[SceneKeys::Properties] = SerializeProperties(Actor, Context);

	// RootComponent 트리 직렬화
	if (Actor->GetRootComponent()) {
		a[SceneKeys::RootComponent] = SerializeSceneComponentTree(Actor->GetRootComponent(), Context);
	}

	// Non-scene components
	JSON NonScene = json::Array();
	for (UActorComponent* Comp : Actor->GetComponents()) {
		if (!Comp) continue;
		if (Comp->IsA<USceneComponent>()) continue;

		JSON c = json::Object();
		c[SceneKeys::ClassName] = Comp->GetClass()->GetName();
		c[SceneKeys::ObjectId] = static_cast<int>(Context.RegisterSceneObject(Comp));
		c[SceneKeys::Properties] = SerializeProperties(Comp, Context);
		SerializeComponentEditorMetadata(c, Comp);
		NonScene.append(c);
	}
	a[SceneKeys::NonSceneComponents] = NonScene;

	return a;
}

json::JSON FSceneSaveManager::SerializeSceneComponentTree(USceneComponent* Comp, FSceneSaveContext& Context)
{
	using namespace json;
	JSON c = json::Object();
	c[SceneKeys::ClassName] = Comp->GetClass()->GetName();
	c[SceneKeys::ObjectId] = static_cast<int>(Context.RegisterSceneObject(Comp));
	c[SceneKeys::Properties] = SerializeProperties(Comp, Context);
	SerializeComponentEditorMetadata(c, Comp);
	if (Comp->GetAttachSocketName() != FName::None)
	{
		c[SceneKeys::AttachSocket] = Comp->GetAttachSocketName().ToString();
	}

	JSON Children = json::Array();
	for (USceneComponent* Child : Comp->GetChildren()) {
		if (!Child) continue;
		Children.append(SerializeSceneComponentTree(Child, Context));
	}
	c[SceneKeys::Children] = Children;

	return c;
}

json::JSON FSceneSaveManager::SerializeProperties(UObject* Obj, FSceneSaveContext& Context)
{
	using namespace json;
	JSON Props = json::Object();
	if (!Obj) return Props;

	FSceneJsonSaveArchive Ar(Props, Context);
	Obj->PreSave();
	Obj->SerializeProperties(Ar, PF_Save);
	return Props;
}

// ---- Camera helpers ----

json::JSON FSceneSaveManager::SerializeCamera(const FMinimalViewInfo* POV)
{
	using namespace json;
	JSON cam = json::Object();
	if (!POV) return cam;

	WriteVec3(cam, "Location", POV->Location);
	// FRotator(Pitch, Yaw, Roll) → 직렬화 컨벤션 FVector(Roll, Pitch, Yaw)
	WriteVec3(cam, "Rotation", FVector(POV->Rotation.Roll, POV->Rotation.Pitch, POV->Rotation.Yaw));

	cam["FOV"] = static_cast<double>(POV->FOV);
	cam["NearClip"] = static_cast<double>(POV->NearClip);
	cam["FarClip"] = static_cast<double>(POV->FarClip);

	return cam;
}

void FSceneSaveManager::DeserializeCamera(json::JSON& CameraJSON, FPerspectiveCameraData& OutCam)
{
	using namespace json;
	if (CameraJSON.JSONType() == JSON::Class::Null) return;

	if (CameraJSON.hasKey("Location")) OutCam.Location = ReadVec3(CameraJSON["Location"]);
	if (CameraJSON.hasKey("Rotation")) OutCam.Rotation = ReadVec3(CameraJSON["Rotation"]);
	if (CameraJSON.hasKey("FOV")) {
		auto& Val = CameraJSON["FOV"];
		float fov = static_cast<float>(Val.JSONType() == JSON::Class::Array ? Val[0].ToFloat() : Val.ToFloat());
		// 엔진 내부는 라디안 — π(~3.14)를 넘으면 degree로 간주하고 변환
		if (fov > 3.14159265f) fov *= (3.14159265f / 180.0f);
		OutCam.FOV = fov;
	}
	if (CameraJSON.hasKey("NearClip")) {
		auto& Val = CameraJSON["NearClip"];
		OutCam.NearClip = static_cast<float>(Val.JSONType() == JSON::Class::Array ? Val[0].ToFloat() : Val.ToFloat());
	}
	if (CameraJSON.hasKey("FarClip")) {
		auto& Val = CameraJSON["FarClip"];
		OutCam.FarClip = static_cast<float>(Val.JSONType() == JSON::Class::Array ? Val[0].ToFloat() : Val.ToFloat());
	}
	OutCam.bValid = true;
}

bool FSceneSaveManager::DeserializeActor(json::JSON& ActorJSON, UWorld* World, FSceneLoadContext& LoadContextState)
{
	if (!World)
	{
		return false;
	}

	string ActorClass = ActorJSON[SceneKeys::ClassName].ToString();

	UObject* ActorObj = FObjectFactory::Get().Create(ActorClass, World);
	if (!ActorObj || !ActorObj->IsA<AActor>())
	{
		return false;
	}

	AActor* Actor = static_cast<AActor*>(ActorObj);
	LoadContextState.RegisterLoadedObject(ActorJSON, Actor);
	World->AddActor(Actor);

	if (ActorJSON.hasKey(SceneKeys::Name))
	{
		Actor->SetFName(FName(ActorJSON[SceneKeys::Name].ToString()));
	}

	if (ActorJSON.hasKey(SceneKeys::RootComponent))
	{
		json::JSON& RootJSON = ActorJSON[SceneKeys::RootComponent];
		USceneComponent* Root = DeserializeSceneComponentTree(RootJSON, Actor, LoadContextState);
		if (Root)
		{
			Actor->SetRootComponent(Root);
		}
	}

	if (ActorJSON.hasKey(SceneKeys::Properties))
	{
		LoadContextState.QueueProperties(Actor, ActorJSON[SceneKeys::Properties]);
	}

	if (ActorJSON.hasKey(SceneKeys::NonSceneComponents))
	{
		for (auto& CompJSON : ActorJSON[SceneKeys::NonSceneComponents].ArrayRange())
		{
			string CompClass = CompJSON[SceneKeys::ClassName].ToString();
			UObject* CompObj = FObjectFactory::Get().Create(CompClass, Actor);
			if (!CompObj || !CompObj->IsA<UActorComponent>())
			{
				continue;
			}

			UActorComponent* Comp = static_cast<UActorComponent*>(CompObj);
			LoadContextState.RegisterLoadedObject(CompJSON, Comp);
			Actor->RegisterComponent(Comp);

			if (CompJSON.hasKey(SceneKeys::Properties))
			{
				json::JSON& PropsJSON = CompJSON[SceneKeys::Properties];
				LoadContextState.QueueProperties(Comp, PropsJSON);
			}
			DeserializeComponentEditorMetadata(Comp, CompJSON);
		}
	}

	return true;
}

// ============================================================
// Load
// ============================================================

void FSceneSaveManager::LoadSceneFromJSON(const string& filepath, FWorldContext& OutWorldContext, FPerspectiveCameraData& OutCam, const EWorldType* OverrideWorldType)
{
	using json::JSON;
	std::ifstream File(std::filesystem::path(FPaths::ToWide(filepath)));
	if (!File.is_open()) {
		std::cerr << "Failed to open file at target destination" << std::endl;
		return;
	}

	string FileContent((std::istreambuf_iterator<char>(File)),
		std::istreambuf_iterator<char>());

	JSON root = JSON::Load(FileContent);

	string ClassName = root[SceneKeys::ClassName].ToString();
	ClassName = ClassName.empty() ? "UWorld" : ClassName; // Default to "World" if ClassName is missing
	UObject* WorldObj = FObjectFactory::Get().Create(ClassName);
	if (!WorldObj || !WorldObj->IsA<UWorld>()) return;

	UWorld* World = static_cast<UWorld*>(WorldObj);
	FSceneLoadContext LoadContextState;
	LoadContextState.RegisterLoadedObject(root, World);

	EWorldType WorldType = OverrideWorldType
		? *OverrideWorldType
		: (root.hasKey(SceneKeys::WorldType)
			? StringToWorldType(root[SceneKeys::WorldType].ToString())
			: EWorldType::Editor);

	// World 의 WorldType 을 actor deserialize 전에 적용. Default 가 Editor 라 actor 추가
	// 시 CreateRenderState 의 "EditorOnly && WorldType != Editor" 체크가 잘못 통과돼 Game
	// 빌드에서도 editor billboard SceneProxy 가 만들어지는 버그를 막기 위해.
	World->SetWorldType(WorldType);
	FString ContextName = root.hasKey(SceneKeys::ContextName)
		? root[SceneKeys::ContextName].ToString()
		: "Loaded Scene";
	FString ContextHandle = root.hasKey(SceneKeys::ContextHandle)
		? root[SceneKeys::ContextHandle].ToString()
		: ContextName;

	// WorldSettings — scene 단위 게임 설정. 신규 포맷은 root["WorldSettings"] 객체.
	// 구버전 호환: root["GameMode"] (top-level) 도 fallback 으로 읽음.
	FWorldSettings WorldSettings;
	if (root.hasKey(SceneKeys::WorldSettings))
	{
		JSON& WSObj = root[SceneKeys::WorldSettings];
		if (WSObj.hasKey(SceneKeys::GameMode))
		{
			WorldSettings.GameModeClassName = WSObj[SceneKeys::GameMode].ToString();
		}
	}
	else if (root.hasKey(SceneKeys::GameMode))
	{
		WorldSettings.GameModeClassName = root[SceneKeys::GameMode].ToString();
	}
	World->GetWorldSettings() = WorldSettings;

	World->InitWorld();

	// "PerspectiveCamera" 우선, 구버전 "Camera" 키도 지원
	const char* CamKey = root.hasKey("PerspectiveCamera") ? "PerspectiveCamera"
		: root.hasKey("Camera") ? "Camera"
		: nullptr;
	if (CamKey) {
		JSON& Cam = root[CamKey];
		DeserializeCamera(Cam, OutCam);
	}

	// Deserialize Actors
	if (root.hasKey(SceneKeys::Actors))
	{
		for (auto& ActorJSON : root[SceneKeys::Actors].ArrayRange())
		{
			DeserializeActor(ActorJSON, World, LoadContextState);
		}
	}

	for (FPendingPropertyLoad& Pending : LoadContextState.PendingProperties)
	{
		if (Pending.Object && Pending.Properties)
		{
			DeserializeProperties(Pending.Object, *Pending.Properties, LoadContextState);
		}
	}

	for (auto& It : LoadContextState.ObjectById)
	{
		if (It.second)
		{
			It.second->PostLoad();
		}
	}

	for (AActor* Actor : World->GetActors())
	{
		if (!Actor)
		{
			continue;
		}

		World->RemoveActorToOctree(Actor);
		World->InsertActorToOctree(Actor);
	}

	OutWorldContext.WorldType = WorldType;
	OutWorldContext.World = World;
	OutWorldContext.ContextName = ContextName;
	OutWorldContext.ContextHandle = FName(ContextHandle);
}

FSceneSaveManager::FSceneAsyncLoadState* FSceneSaveManager::BeginLoadSceneFromJSONAsync(
	const string& filepath,
	FWorldContext& OutWorldContext,
	FPerspectiveCameraData& OutCam,
	const EWorldType* OverrideWorldType)
{
	using json::JSON;

	FSceneAsyncLoadState* State = new FSceneAsyncLoadState();
	State->OutWorldContext = &OutWorldContext;
	State->OutCam = &OutCam;
	State->LoadContextState.bDeferExpensiveAssetPostEdit = true;
	State->bHasOverrideWorldType = OverrideWorldType != nullptr;
	if (OverrideWorldType)
	{
		State->OverrideWorldType = *OverrideWorldType;
	}
	OutWorldContext = FWorldContext();

	const std::filesystem::path FilePath(FPaths::ToWide(filepath));
	State->RootFuture = std::async(std::launch::async, [FilePath]() -> FSceneAsyncLoadState::FRootLoadResult
	{
		FSceneAsyncLoadState::FRootLoadResult Result;
		std::ifstream File(FilePath);
		if (!File.is_open())
		{
			std::cerr << "Failed to open file at target destination" << std::endl;
			return Result;
		}

		const string FileContent((std::istreambuf_iterator<char>(File)),
			std::istreambuf_iterator<char>());
		Result.Root = std::make_shared<JSON>(JSON::Load(FileContent));
		Result.bSucceeded = true;
		return Result;
	});

	State->Phase = FSceneAsyncLoadState::EPhase::LoadRoot;
	return State;
}

FSceneSaveManager::FSceneAsyncLoadStatus FSceneSaveManager::TickLoadSceneFromJSONAsync(
	FSceneAsyncLoadState& State,
	int32 WorkBudget,
	double MaxWorkMilliseconds)
{
	FSceneAsyncLoadStatus Status;
	Status.LoadedActorCount = State.NextActorIndex;
	Status.TotalActorCount = State.TotalActorCount;

	if (State.Phase == FSceneAsyncLoadState::EPhase::Finished)
	{
		Status.bFinished = true;
		Status.bSucceeded = true;
		return Status;
	}
	if (State.Phase == FSceneAsyncLoadState::EPhase::Failed)
	{
		Status.bFinished = true;
		Status.bSucceeded = false;
		return Status;
	}

	int32 RemainingBudget = (std::max)(1, WorkBudget);
	int32 CompletedWorkItems = 0;
	const uint64 WorkStartCycles = FPlatformTime::Cycles64();
	auto IsTimeBudgetExhausted = [&]() -> bool
	{
		if (CompletedWorkItems <= 0 || MaxWorkMilliseconds <= 0.0)
		{
			return false;
		}
		return FPlatformTime::ToMilliseconds(FPlatformTime::Cycles64() - WorkStartCycles) >= MaxWorkMilliseconds;
	};

	while (RemainingBudget > 0 && !IsTimeBudgetExhausted())
	{
		switch (State.Phase)
		{
		case FSceneAsyncLoadState::EPhase::LoadRoot:
		{
			if (!State.RootFuture.valid())
			{
				State.Phase = FSceneAsyncLoadState::EPhase::Failed;
				break;
			}

			if (State.RootFuture.wait_for(std::chrono::seconds(0)) != std::future_status::ready)
			{
				Status.LoadedActorCount = State.NextActorIndex;
				Status.TotalActorCount = State.TotalActorCount;
				return Status;
			}

			FSceneAsyncLoadState::FRootLoadResult Result = State.RootFuture.get();
			if (!Result.bSucceeded || !Result.Root)
			{
				State.Phase = FSceneAsyncLoadState::EPhase::Failed;
				break;
			}

			State.Root = std::move(Result.Root);
			State.Phase = FSceneAsyncLoadState::EPhase::InitWorld;
			--RemainingBudget;
			++CompletedWorkItems;
			break;
		}

		case FSceneAsyncLoadState::EPhase::InitWorld:
		{
			if (!State.Root)
			{
				State.Phase = FSceneAsyncLoadState::EPhase::Failed;
				break;
			}

			json::JSON& Root = *State.Root;
			string ClassName = Root[SceneKeys::ClassName].ToString();
			ClassName = ClassName.empty() ? "UWorld" : ClassName;
			UObject* WorldObj = FObjectFactory::Get().Create(ClassName);
			if (!WorldObj || !WorldObj->IsA<UWorld>())
			{
				if (WorldObj)
				{
					UObjectManager::Get().DestroyObject(WorldObj);
				}
				State.Phase = FSceneAsyncLoadState::EPhase::Failed;
				break;
			}

			State.World = static_cast<UWorld*>(WorldObj);
			State.LoadContextState.RegisterLoadedObject(Root, State.World);

			State.WorldType = State.bHasOverrideWorldType
				? State.OverrideWorldType
				: (Root.hasKey(SceneKeys::WorldType)
					? StringToWorldType(Root[SceneKeys::WorldType].ToString())
					: EWorldType::Editor);

			State.World->SetWorldType(State.WorldType);
			State.ContextName = Root.hasKey(SceneKeys::ContextName)
				? Root[SceneKeys::ContextName].ToString()
				: "Loaded Scene";
			const FString ContextHandle = Root.hasKey(SceneKeys::ContextHandle)
				? Root[SceneKeys::ContextHandle].ToString()
				: State.ContextName;
			State.ContextHandle = FName(ContextHandle);

			FWorldSettings WorldSettings;
			if (Root.hasKey(SceneKeys::WorldSettings))
			{
				json::JSON& WSObj = Root[SceneKeys::WorldSettings];
				if (WSObj.hasKey(SceneKeys::GameMode))
				{
					WorldSettings.GameModeClassName = WSObj[SceneKeys::GameMode].ToString();
				}
			}
			else if (Root.hasKey(SceneKeys::GameMode))
			{
				WorldSettings.GameModeClassName = Root[SceneKeys::GameMode].ToString();
			}
			State.World->GetWorldSettings() = WorldSettings;
			State.World->InitWorld();

			const char* CamKey = Root.hasKey("PerspectiveCamera") ? "PerspectiveCamera"
				: Root.hasKey("Camera") ? "Camera"
				: nullptr;
			if (CamKey && State.OutCam)
			{
				json::JSON& Cam = Root[CamKey];
				DeserializeCamera(Cam, *State.OutCam);
			}

			if (Root.hasKey(SceneKeys::Actors))
			{
				State.ActorsJSON = &Root[SceneKeys::Actors];
				for (auto& ActorJSON : State.ActorsJSON->ArrayRange())
				{
					(void)ActorJSON;
					++State.TotalActorCount;
				}
			}

			if (State.OutWorldContext)
			{
				State.OutWorldContext->WorldType = State.WorldType;
				State.OutWorldContext->World = State.World;
				State.OutWorldContext->ContextName = State.ContextName;
				State.OutWorldContext->ContextHandle = State.ContextHandle;
			}

			State.Phase = FSceneAsyncLoadState::EPhase::Actors;
			--RemainingBudget;
			++CompletedWorkItems;
			break;
		}

		case FSceneAsyncLoadState::EPhase::Actors:
			if (!State.ActorsJSON || State.NextActorIndex >= State.TotalActorCount)
			{
				State.Phase = FSceneAsyncLoadState::EPhase::Properties;
				break;
			}

			DeserializeActor(State.ActorsJSON->at(static_cast<unsigned>(State.NextActorIndex)), State.World, State.LoadContextState);
			++State.NextActorIndex;
			--RemainingBudget;
			++CompletedWorkItems;
			break;

		case FSceneAsyncLoadState::EPhase::Properties:
			if (State.NextPropertyIndex >= static_cast<int32>(State.LoadContextState.PendingProperties.size()))
			{
				for (auto& It : State.LoadContextState.ObjectById)
				{
					if (It.second)
					{
						State.PostLoadObjects.push_back(It.second);
					}
				}
				State.Phase = FSceneAsyncLoadState::EPhase::PostLoad;
				break;
			}
			else
			{
				FPendingPropertyLoad& Pending = State.LoadContextState.PendingProperties[State.NextPropertyIndex];
				if (Pending.Object && Pending.Properties)
				{
					DeserializeProperties(Pending.Object, *Pending.Properties, State.LoadContextState);
				}
				++State.NextPropertyIndex;
				--RemainingBudget;
				++CompletedWorkItems;
			}
			break;

		case FSceneAsyncLoadState::EPhase::PostLoad:
			if (State.NextPostLoadIndex >= static_cast<int32>(State.PostLoadObjects.size()))
			{
				for (AActor* Actor : State.World->GetActors())
				{
					if (Actor)
					{
						State.OctreeActors.push_back(Actor);
					}
				}
				State.Phase = FSceneAsyncLoadState::EPhase::Octree;
				break;
			}
			else
			{
				UObject* Object = State.PostLoadObjects[State.NextPostLoadIndex];
				if (Object)
				{
					Object->PostLoad();
				}
				++State.NextPostLoadIndex;
				--RemainingBudget;
				++CompletedWorkItems;
			}
			break;

		case FSceneAsyncLoadState::EPhase::Octree:
			if (State.NextOctreeActorIndex >= static_cast<int32>(State.OctreeActors.size()))
			{
				if (State.OutWorldContext)
				{
					State.OutWorldContext->WorldType = State.WorldType;
					State.OutWorldContext->World = State.World;
					State.OutWorldContext->ContextName = State.ContextName;
					State.OutWorldContext->ContextHandle = State.ContextHandle;
				}
				State.Phase = FSceneAsyncLoadState::EPhase::Finished;
				Status.bFinished = true;
				Status.bSucceeded = true;
				Status.LoadedActorCount = State.NextActorIndex;
				Status.TotalActorCount = State.TotalActorCount;
				return Status;
			}
			else
			{
				AActor* Actor = State.OctreeActors[State.NextOctreeActorIndex];
				if (Actor)
				{
					State.World->RemoveActorToOctree(Actor);
					State.World->InsertActorToOctree(Actor);
				}
				++State.NextOctreeActorIndex;
				--RemainingBudget;
				++CompletedWorkItems;
			}
			break;

		case FSceneAsyncLoadState::EPhase::Finished:
			Status.bFinished = true;
			Status.bSucceeded = true;
			return Status;

		case FSceneAsyncLoadState::EPhase::Failed:
		default:
			Status.bFinished = true;
			Status.bSucceeded = false;
			return Status;
		}
	}

	Status.LoadedActorCount = State.NextActorIndex;
	Status.TotalActorCount = State.TotalActorCount;
	return Status;
}

void FSceneSaveManager::DestroySceneAsyncLoadState(FSceneAsyncLoadState* State)
{
	delete State;
}

USceneComponent* FSceneSaveManager::DeserializeSceneComponentTree(json::JSON& Node, AActor* Owner, FSceneLoadContext& Context)
{
	string ClassName = Node[SceneKeys::ClassName].ToString();
	UObject* Obj = FObjectFactory::Get().Create(ClassName, Owner);
	if (!Obj || !Obj->IsA<USceneComponent>()) return nullptr;

	USceneComponent* Comp = static_cast<USceneComponent*>(Obj);
	Context.RegisterLoadedObject(Node, Comp);
	Owner->RegisterComponent(Comp);

	// Restore properties
	if (Node.hasKey(SceneKeys::Properties)) {
		json::JSON& PropsJSON = Node[SceneKeys::Properties];
		Context.QueueProperties(Comp, PropsJSON);
	}
	DeserializeComponentEditorMetadata(Comp, Node);
	Comp->MarkTransformDirty();

	// Restore children recursively
	if (Node.hasKey(SceneKeys::Children)) {
		for (auto& ChildJSON : Node[SceneKeys::Children].ArrayRange()) {
			USceneComponent* Child = DeserializeSceneComponentTree(ChildJSON, Owner, Context);
			if (Child) {
				FName AttachSocketName = FName::None;
				if (ChildJSON.hasKey(SceneKeys::AttachSocket))
				{
					AttachSocketName = FName(ChildJSON[SceneKeys::AttachSocket].ToString());
				}
				Child->AttachToComponent(Comp, AttachSocketName);
			}
		}
	}

	EnsureEditorBillboardMetadata(Comp);

	return Comp;
}

static bool ShouldDeferSceneLoadPostEdit(UObject* Obj, const FProperty* Property)
{
	if (!Obj || !Property)
	{
		return false;
	}

	const char* Name = Property->Name ? Property->Name : "";
	const char* DisplayName = Property->DisplayName ? Property->DisplayName : "";

	if (Obj->IsA<UStaticMeshComponent>())
	{
		return std::strcmp(Name, "StaticMeshPath") == 0
			|| std::strcmp(DisplayName, "Static Mesh") == 0
			|| std::strcmp(Name, "MaterialSlots") == 0
			|| std::strcmp(DisplayName, "Materials") == 0
			|| std::strncmp(DisplayName, "Element ", 8) == 0;
	}

	if (Obj->IsA<USkinnedMeshComponent>())
	{
		if (std::strcmp(Name, "SkeletalMeshPath") == 0
			|| std::strcmp(DisplayName, "Skeletal Mesh") == 0
			|| std::strcmp(Name, "MaterialSlots") == 0
			|| std::strcmp(DisplayName, "Materials") == 0
			|| std::strncmp(DisplayName, "Element ", 8) == 0)
		{
			return true;
		}
	}

	if (Obj->IsA<USkeletalMeshComponent>())
	{
		return std::strcmp(Name, "AnimationMode") == 0
			|| std::strcmp(DisplayName, "Animation Mode") == 0
			|| std::strcmp(Name, "AnimationData") == 0
			|| std::strcmp(DisplayName, "Animation Data") == 0
			|| std::strcmp(Name, "AnimInstanceClass") == 0
			|| std::strcmp(DisplayName, "Anim Instance Class") == 0
			|| std::strcmp(Name, "AnimToPlayPath") == 0
			|| std::strcmp(Name, "LuaAnimScriptFile") == 0
			|| std::strcmp(DisplayName, "Lua Anim Script") == 0;
	}

	return false;
}

void FSceneSaveManager::DeserializeProperties(UObject* Obj, json::JSON& PropsJSON, FSceneLoadContext& Context)
{
	if (!Obj) return;

	TArray<const FProperty*> Properties;
	Obj->GetClass()->GetPropertyRefs(Properties);
	for (const FProperty* Property : Properties)
	{
		if(!Property || (Property->Flags & PF_Save) == 0)
		{
			continue;
		}

		const char* PropertyKey = Property->Name;
		if (!PropsJSON.hasKey(PropertyKey) && Property->DisplayName && PropsJSON.hasKey(Property->DisplayName))
		{
			PropertyKey = Property->DisplayName;
		}

		if (!PropsJSON.hasKey(PropertyKey))
		{
			continue;
		}

		if (PropertyKey != Property->Name)
		{
			PropsJSON[Property->Name] = PropsJSON[PropertyKey];
		}
	}

	for (const FProperty* Property : Properties)
	{
		if(!Property || (Property->Flags & PF_Save) == 0)
		{
			continue;
		}

		const char* PropertyKey = Property->Name;
		if (!PropsJSON.hasKey(PropertyKey))
		{
			continue;
		}

		if(!Property->GetValuePtrFor(Obj))
		{
			continue;
		}

		FSceneJsonLoadArchive Ar(PropsJSON[PropertyKey], Context);
		Property->Serialize(Obj, Ar);

		if (Context.bDeferExpensiveAssetPostEdit && ShouldDeferSceneLoadPostEdit(Obj, Property))
		{
			continue;
		}

		FPropertyChangedEvent Event;
		Event.Object = Obj;
		Event.Property = Property;
		Event.PropertyName = Property->Name;
		Event.DisplayName = Property->DisplayName ? Property->DisplayName : Property->Name;
		Event.PropertyPath = Property->Name;
		Event.Type = Property->GetType();
		Event.ChangeType = EPropertyChangeType::Load;
		Obj->PostEditChangeProperty(Event);
	}

}

// ============================================================
// Utility
// ============================================================

string FSceneSaveManager::GetCurrentTimeStamp()
{
	std::time_t t = std::time(nullptr);
	std::tm tm{};
	localtime_s(&tm, &t);

	char buf[20];
	std::strftime(buf, sizeof(buf), "%Y%m%d_%H%M%S", &tm);
	return buf;
}

TArray<FString> FSceneSaveManager::GetSceneFileList()
{
	TArray<FString> Result;
	std::wstring SceneDir = GetSceneDirectory();
	if (!std::filesystem::exists(SceneDir))
	{
		return Result;
	}

	for (auto& Entry : std::filesystem::directory_iterator(SceneDir))
	{
		if (Entry.is_regular_file() && Entry.path().extension() == SceneExtension)
		{
			Result.push_back(FPaths::ToUtf8(Entry.path().stem().wstring()));
		}
	}
	return Result;
}
