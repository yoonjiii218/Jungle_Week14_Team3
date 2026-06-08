#include "Game/Lua/GameLuaBindings.h"

#include "sol/sol.hpp"

#include "Engine/Runtime/Engine.h"
#include "Engine/Runtime/EngineInitHooks.h"
#include "Game/Flow/BossGameMode.h"
#include "Game/Flow/BossGameState.h"
#include "Game/Flow/GameFlowDirector.h"
#include "GameFramework/GameMode/GameModeBase.h"
#include "GameFramework/GameMode/GameStateBase.h"
#include "GameFramework/World.h"
#include "Lua/LuaScriptManager.h"
#include "Object/Object.h"
#include "Object/Reflection/UClass.h"

namespace
{
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
