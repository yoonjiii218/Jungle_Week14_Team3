#include "Game/Lua/GameLuaBindings.h"

#include "sol/sol.hpp"

#include "Engine/Runtime/Engine.h"
#include "Engine/Runtime/EngineInitHooks.h"
#include "Game/Flow/BossGameMode.h"
#include "Game/Flow/BossGameState.h"
#include "Game/Flow/GameFlowDirector.h"
#include "GameFramework/GameMode/GameModeBase.h"
#include "GameFramework/GameMode/GameStateBase.h"
#include "Animation/AnimationMode.h"
#include "Component/Input/ActionComponent.h"
#include "Component/Primitive/SkeletalMeshComponent.h"
#include "Component/Shape/CapsuleComponent.h"
#include "GameFramework/Pawn/LuaCharacter.h"
#include "Materials/MaterialManager.h"
#include "Mesh/MeshManager.h"
#include "Object/Reflection/ObjectFactory.h"
#include "GameFramework/World.h"
#include "Lua/LuaScriptManager.h"
#include "Object/Object.h"
#include "Object/Reflection/UClass.h"

namespace
{
	struct FTutorialCharacterSpawnSpec
	{
		FString MeshPath;
		FString ScriptFile;
		FString LuaAnimScriptFile;
		FVector MeshRelativeLocation = FVector::ZeroVector;
		FVector MeshRelativeScale = FVector(1.0f, 1.0f, 1.0f);
		float CapsuleRadius = 3.0f;
		float CapsuleHalfHeight = 5.0f;
		TArray<FString> MaterialPaths;
		TArray<FString> Tags;
	};

	void ApplySkeletalMaterialPaths(USkeletalMeshComponent* Mesh, const TArray<FString>& MaterialPaths)
	{
		if (!Mesh)
		{
			return;
		}

		for (int32 Index = 0; Index < static_cast<int32>(MaterialPaths.size()); ++Index)
		{
			const FString& MatPath = MaterialPaths[Index];
			UMaterial* Material = (MatPath.empty() || MatPath == "None")
				? nullptr
				: FMaterialManager::Get().GetOrCreateMaterial(MatPath);
			Mesh->SetMaterial(Index, Material);
		}
	}

	ALuaCharacter* SpawnTutorialLuaCharacter(const FTutorialCharacterSpawnSpec& Spec, const FVector& Location, float YawDegrees)
	{
		if (!GEngine)
		{
			return nullptr;
		}

		UWorld* World = GEngine->GetWorld();
		if (!World)
		{
			return nullptr;
		}

		UObject* Created = FObjectFactory::Get().Create("ALuaCharacter", World);
		ALuaCharacter* Actor = Cast<ALuaCharacter>(Created);
		if (!Actor)
		{
			return nullptr;
		}

		Actor->InitDefaultComponents(Spec.MeshPath, Spec.ScriptFile);
		Actor->SetActorLocation(Location);
		Actor->SetActorRotation(FRotator(0.0f, YawDegrees, 0.0f));
		Actor->SetActorScale(FVector(1.0f, 1.0f, 1.0f));
		Actor->bAutoInputMouseLook = false;

		if (UCapsuleComponent* Capsule = Actor->GetCapsuleComponent())
		{
			Capsule->SetCapsuleSize(Spec.CapsuleRadius, Spec.CapsuleHalfHeight);
			Capsule->SetSimulatePhysics(false);

			// SpringArm camera collision test에서는 적 캡슐을 무시
			Capsule->SetCollisionResponseToChannel(
				ECollisionChannel::Camera,
				ECollisionResponse::Ignore
			);
		}

		if (USkeletalMeshComponent* Mesh = Actor->GetMesh())
		{
			Mesh->SetRelativeLocation(Spec.MeshRelativeLocation);
			Mesh->SetRelativeScale(Spec.MeshRelativeScale);
			Mesh->SetAnimationMode(EAnimationMode::AnimationCustom);
			Mesh->SetAnimInstanceClass(UClass::FindByName("ULuaAnimInstance"));
			Mesh->SetLuaAnimScriptFile(Spec.LuaAnimScriptFile);
			ApplySkeletalMaterialPaths(Mesh, Spec.MaterialPaths);
			Mesh->InitializeAnimation();
		}

		if (!Actor->GetComponentByClass<UActionComponent>())
		{
			Actor->AddComponent<UActionComponent>();
		}

		for (const FString& Tag : Spec.Tags)
		{
			if (!Tag.empty())
			{
				Actor->AddTag(FName(Tag));
			}
		}

		World->AddActor(Actor);
		return Actor;
	}

	FTutorialCharacterSpawnSpec MakeTutorialMobSpec()
	{
		FTutorialCharacterSpawnSpec Spec;
		Spec.MeshPath = "Content/Mesh/Trooper1/SK_SciFITrooper-01_SkeletalMesh.uasset";
		Spec.ScriptFile = "Mob/MobCharacter.lua";
		Spec.LuaAnimScriptFile = "Anim/MobAnimation.lua";
		Spec.MeshRelativeLocation = FVector(0.0f, 0.0f, -5.149981f);
		Spec.MeshRelativeScale = FVector(5.0f, 5.0f, 5.0f);
		Spec.CapsuleRadius = 3.0f;
		Spec.CapsuleHalfHeight = 5.0f;
		Spec.MaterialPaths = {
			"Content/Material/Auto/M_SciFITrooper-01_Top.mat",
			"Content/Material/Auto/M_SciFITrooper-01_Bottom.mat"
		};
		Spec.Tags = { "Mob", "Enemy", "HitTarget", "TutorialEnemy", "TutorialMob" };
		return Spec;
	}

	FTutorialCharacterSpawnSpec MakeTutorialBossSpec()
	{
		FTutorialCharacterSpawnSpec Spec;
		Spec.MeshPath = "Content/Mesh/Boss/BossModel_SkeletalMesh.uasset";
		Spec.ScriptFile = "Boss/BossCharacter.lua";
		Spec.LuaAnimScriptFile = "Anim/BossAnimation.lua";
		Spec.MeshRelativeLocation = FVector(0.0f, 0.0f, -9.271478f);
		Spec.MeshRelativeScale = FVector(10.0f, 10.0f, 10.0f);
		Spec.CapsuleRadius = 4.0f;
		Spec.CapsuleHalfHeight = 9.0f;
		Spec.MaterialPaths = {
			"Content/Material/Auto/M_Sci_Fi_Character_Details_3.mat",
			"Content/Material/Auto/M_Sci_Fi_Character_Body_3.mat"
		};
		Spec.Tags = { "Boss", "Enemy", "HitTarget", "TutorialEnemy", "TutorialBoss" };
		return Spec;
	}

	AGameFlowDirector* FindGameFlowDirector()
	{
		if (!GEngine)
		{
			return nullptr;
		}

		UWorld* World = GEngine->GetWorld();
		if (!World)
		{
			return nullptr;
		}

		AGameFlowDirector* FirstDirector = nullptr;
		for (AActor* Actor : World->GetActors())
		{
			if (!IsValid(Actor))
			{
				continue;
			}
			if (AGameFlowDirector* Director = Cast<AGameFlowDirector>(Actor))
			{
				if (Director->HasTag(FName("GameDirector")))
				{
					return Director;
				}
				if (!FirstDirector)
				{
					FirstDirector = Director;
				}
			}
		}
		return FirstDirector;
	}

	ABossGameMode* GetBossGameMode()
	{
		if (!GEngine)
		{
			return nullptr;
		}
		UWorld* World = GEngine->GetWorld();
		return World ? Cast<ABossGameMode>(World->GetGameMode()) : nullptr;
	}

	ABossGameState* GetBossGameState()
	{
		if (!GEngine)
		{
			return nullptr;
		}
		UWorld* World = GEngine->GetWorld();
		return World ? Cast<ABossGameState>(World->GetGameState()) : nullptr;
	}
}

// ============================================================
// 게임-특화 Lua 바인딩 등록 위치 — 현재는 비어 있음.
//
// Engine 의 FLuaScriptManager 가 등록하는 일반 binding (AActor / APawn / FVector /
// UWorld / Anim 등) 만으로 동작하지 않는 game-specific usertype (ACarPawn /
// AGameStateXxx / 전용 enum 등) 이 도입되면 여기에 new_usertype 으로 추가한다.
//
// 호출 시점: UEngine::Init() 이 FLuaScriptManager::Initialize() 를 끝낸 직후.
// 등록은 EngineInitHooks 에 자동으로 걸려 GameEngine / EditorEngine 두 엔트리 모두
// 같은 바인딩이 적용된다 (PIE 호환).
// ============================================================
void RegisterGameLuaBindings(sol::state& Lua)
{
	Lua.new_usertype<ABossGameState>("BossGameState",
		sol::base_classes,
		sol::bases<AGameStateBase, AActor, UObject>(),
		"ResetCombatState", &ABossGameState::ResetCombatState,
		"SetFlowPhase", &ABossGameState::SetFlowPhase,
		"GetFlowPhase", &ABossGameState::GetFlowPhase,
		"SetPlayerHP", &ABossGameState::SetPlayerHP,
		"SetBossHP", &ABossGameState::SetBossHP,
		"SetUltimateGauge", &ABossGameState::SetUltimateGauge,
		"SetComboCount", &ABossGameState::SetComboCount,
		"GetPlayerHP", &ABossGameState::GetPlayerHP,
		"GetPlayerMaxHP", &ABossGameState::GetPlayerMaxHP,
		"GetBossHP", &ABossGameState::GetBossHP,
		"GetBossMaxHP", &ABossGameState::GetBossMaxHP,
		"GetUltimateGauge", &ABossGameState::GetUltimateGauge,
		"GetUltimateMaxGauge", &ABossGameState::GetUltimateMaxGauge,
		"GetComboCount", &ABossGameState::GetComboCount,
		"IsPlayerDead", &ABossGameState::IsPlayerDead,
		"IsBossDefeated", &ABossGameState::IsBossDefeated);

	Lua.new_usertype<ABossGameMode>("BossGameMode",
		sol::base_classes,
		sol::bases<AGameModeBase, AActor, UObject>(),
		"GetBossGameState", &ABossGameMode::GetBossGameState,
		"ConfigureFlowRules", &ABossGameMode::ConfigureFlowRules,
		"EvaluateCombatState", &ABossGameMode::EvaluateCombatState,
		"RequestGameOver", &ABossGameMode::RequestGameOver,
		"RequestClear", &ABossGameMode::RequestClear);

	Lua.new_usertype<AGameFlowDirector>("GameFlowDirector",
		sol::base_classes,
		sol::bases<AEmptyActor, AActor, UObject>(),
		"StartCombat", &AGameFlowDirector::StartCombat,
		"EndCombat", &AGameFlowDirector::EndCombat,
		"ApplyStartPositions", &AGameFlowDirector::ApplyStartPositions,
		"EvaluateCombatState", &AGameFlowDirector::EvaluateCombatState,
		"RequestScene", &AGameFlowDirector::RequestScene,
		"StartTraining", &AGameFlowDirector::StartTraining,
		"StartStoryBoss", &AGameFlowDirector::StartStoryBoss,
		"RestartCombatScene", &AGameFlowDirector::RestartCombatScene,
		"RequestMainMenu", &AGameFlowDirector::RequestMainMenu,
		"RequestGameOver", &AGameFlowDirector::RequestGameOver,
		"RequestClear", &AGameFlowDirector::RequestClear,
		"RequestCredits", &AGameFlowDirector::RequestCredits,
		"ExitGame", &AGameFlowDirector::ExitGame,
		"PauseGame", &AGameFlowDirector::PauseGame,
		"ResumeGame", &AGameFlowDirector::ResumeGame,
		"TogglePause", &AGameFlowDirector::TogglePause,
		"IsPaused", &AGameFlowDirector::IsPaused,
		"SetPlayerHP", &AGameFlowDirector::SetPlayerHP,
		"DamagePlayer", &AGameFlowDirector::DamagePlayer,
		"HealPlayer", &AGameFlowDirector::HealPlayer,
		"SetBossHP", &AGameFlowDirector::SetBossHP,
		"SetUltimateGauge", &AGameFlowDirector::SetUltimateGauge,
		"SetComboCount", &AGameFlowDirector::SetComboCount,
		"GetPlayerHP", &AGameFlowDirector::GetPlayerHP,
		"GetPlayerMaxHP", &AGameFlowDirector::GetPlayerMaxHP,
		"GetBossHP", &AGameFlowDirector::GetBossHP,
		"GetBossMaxHP", &AGameFlowDirector::GetBossMaxHP,
		"GetUltimateGauge", &AGameFlowDirector::GetUltimateGauge,
		"GetUltimateMaxGauge", &AGameFlowDirector::GetUltimateMaxGauge,
		"GetComboCount", &AGameFlowDirector::GetComboCount,
		"IsCombatActive", &AGameFlowDirector::IsCombatActive,
		"HasReachedTerminalState", &AGameFlowDirector::HasReachedTerminalState,
		"GetStartupScreen", &AGameFlowDirector::GetStartupScreen,
		"GetStartMenuWidgetPath", &AGameFlowDirector::GetStartMenuWidgetPath,
		"GetHudWidgetPath", &AGameFlowDirector::GetHudWidgetPath,
		"GetCountdownWidgetPath", &AGameFlowDirector::GetCountdownWidgetPath,
		"GetTutorialHudWidgetPath", &AGameFlowDirector::GetTutorialHudWidgetPath,
		"GetPauseMenuWidgetPath", &AGameFlowDirector::GetPauseMenuWidgetPath,
		"GetGameOverWidgetPath", &AGameFlowDirector::GetGameOverWidgetPath,
		"GetClearWidgetPath", &AGameFlowDirector::GetClearWidgetPath,
		"GetCreditsWidgetPath", &AGameFlowDirector::GetCreditsWidgetPath,
		"GetTrainingSceneName", &AGameFlowDirector::GetTrainingSceneName,
		"GetStoryBossSceneName", &AGameFlowDirector::GetStoryBossSceneName,
		"GetRetrySceneName", &AGameFlowDirector::GetRetrySceneName,
		"GetMainMenuSceneName", &AGameFlowDirector::GetMainMenuSceneName,
		"GetGameOverSceneName", &AGameFlowDirector::GetGameOverSceneName,
		"GetClearSceneName", &AGameFlowDirector::GetClearSceneName,
		"GetCreditsSceneName", &AGameFlowDirector::GetCreditsSceneName,
		"GetPlayerActor", &AGameFlowDirector::GetPlayerActor,
		"GetBossActor", &AGameFlowDirector::GetBossActor,
		"GetBossGameMode", &AGameFlowDirector::GetBossGameMode,
		"GetBossGameState", &AGameFlowDirector::GetBossGameState);

	Lua.new_usertype<AArenaMarker>("ArenaMarker",
		sol::base_classes,
		sol::bases<AEmptyActor, AActor, UObject>(),
		"GetMarkerRole", &AArenaMarker::GetMarkerRole,
		"SetMarkerRole", &AArenaMarker::SetMarkerRole);

	sol::table GameFlow = Lua.create_named_table("GameFlow");
	GameFlow.set_function("GetDirector", &FindGameFlowDirector);
	GameFlow.set_function("GetGameMode", &GetBossGameMode);
	GameFlow.set_function("GetGameState", &GetBossGameState);
	GameFlow.set_function("OpenScene", [](const FString& SceneName)
	{
		if (GEngine)
		{
			GEngine->RequestTransitionToScene(SceneName);
		}
	});
	GameFlow.set_function("BeginAsyncOpenScene", [](const FString& SceneName) -> bool
	{
		return GEngine ? GEngine->RequestAsyncTransitionToScene(SceneName) : false;
	});
	GameFlow.set_function("IsAsyncOpenSceneReady", []() -> bool
	{
		return GEngine ? GEngine->IsAsyncSceneTransitionReady() : true;
	});
	GameFlow.set_function("GetAsyncOpenSceneProgress", []() -> float
	{
		return GEngine ? GEngine->GetAsyncSceneTransitionProgress() : 1.0f;
	});
	GameFlow.set_function("CommitAsyncOpenScene", []() -> bool
	{
		return GEngine ? GEngine->CommitAsyncSceneTransition() : false;
	});

	// Tutorial spawns are runtime-created ALuaCharacter actors configured from
	// MobTest.Scene / BossTest.Scene actor settings. The helper initializes
	// default components before AddActor(), so BeginPlay observes a complete
	// character instead of a bare ALuaCharacter.
	GameFlow.set_function("SpawnTutorialMob", [](const FVector& Location, sol::optional<float> YawDegrees) -> AActor*
	{
		return SpawnTutorialLuaCharacter(MakeTutorialMobSpec(), Location, YawDegrees.value_or(0.0f));
	});

	GameFlow.set_function("SpawnTutorialBoss", [](const FVector& Location, sol::optional<float> YawDegrees) -> AActor*
	{
		return SpawnTutorialLuaCharacter(MakeTutorialBossSpec(), Location, YawDegrees.value_or(0.0f));
	});
}

// 자기-등록 — Editor / Game 측이 RegisterGameLuaBindings 함수명을 모르고도
// FEngineInitHooks::RunAll() 한 번이면 호출되도록 static initializer 로 등록.
namespace
{
	void RunRegisterGameLuaBindings()
	{
		RegisterGameLuaBindings(FLuaScriptManager::GetState());
	}

	struct GameLuaBindingsAutoReg
	{
		GameLuaBindingsAutoReg() { FEngineInitHooks::Register(&RunRegisterGameLuaBindings); }
	};

	static GameLuaBindingsAutoReg gAutoReg;
}
