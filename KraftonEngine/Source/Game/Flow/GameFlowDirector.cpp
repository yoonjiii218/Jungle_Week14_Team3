#include "Game/Flow/GameFlowDirector.h"

#include "Core/Logging/Log.h"
#include "Game/Flow/BossGameMode.h"
#include "Game/Flow/BossGameState.h"
#include "GameFramework/GameMode/GameplayStatics.h"
#include "GameFramework/World.h"
#include "Runtime/Engine.h"

#include <algorithm>
#include <cstring>
#ifndef NOMINMAX
#define NOMINMAX
#endif
#include <windows.h>
#ifdef max
#undef max
#endif
#ifdef min
#undef min
#endif

AGameFlowDirector::AGameFlowDirector()
{
	bNeedsTick = true;
}

void AGameFlowDirector::BeginPlay()
{
	AddTag(FName("GameDirector"));
	NormalizeCombatValues();
	ConfigureBossGameMode();
	PushCombatStateToGameState();

	if (bApplyStartPositions)
	{
		ApplyStartPositions();
	}
	if (bStartCombatOnBeginPlay)
	{
		StartCombat();
	}

	// AActor::BeginPlay dispatches component BeginPlay in this engine.
	// GameFlow state must be ready before the Lua component runs.
	AEmptyActor::BeginPlay();
}

void AGameFlowDirector::Tick(float DeltaTime)
{
	(void)DeltaTime;
	AEmptyActor::Tick(DeltaTime);
	EvaluateCombatState();
}

void AGameFlowDirector::PostDuplicate()
{
	AEmptyActor::PostDuplicate();
}

void AGameFlowDirector::StartCombat()
{
	bCombatActive = true;
	bTerminalStateReached = false;
	NormalizeCombatValues();
	ConfigureBossGameMode();
	PushCombatStateToGameState();

	if (bApplyStartPositions)
	{
		ApplyStartPositions();
	}
}

void AGameFlowDirector::EndCombat()
{
	bCombatActive = false;
	if (ABossGameState* State = GetBossGameState())
	{
		State->SetFlowPhase("Ended");
	}
}

void AGameFlowDirector::ApplyStartPositions()
{
	AActor* PlayerActor = GetPlayerActor();
	if (PlayerActor)
	{
		PlayerActor->SetActorLocation(ResolveStartLocation(PlayerStartTag, PlayerStartLocation));
	}

	AActor* BossActor = GetBossActor();
	if (BossActor)
	{
		BossActor->SetActorLocation(ResolveStartLocation(BossStartTag, BossStartLocation));
	}
}

void AGameFlowDirector::EvaluateCombatState()
{
	if (!bCombatActive || bTerminalStateReached)
	{
		return;
	}

	if (ABossGameMode* Mode = GetBossGameMode())
	{
		ConfigureBossGameMode();
		Mode->EvaluateCombatState();
		if (ABossGameState* State = Mode->GetBossGameState())
		{
			const FString Phase = State->GetFlowPhase();
			if (Phase == "GameOver" || Phase == "Clear")
			{
				bTerminalStateReached = true;
				bCombatActive = false;
			}
		}
		return;
	}

	if (bAutoFailWhenPlayerDead && PlayerHP <= 0.0f)
	{
		RequestTerminalScene(GameOverSceneName);
		return;
	}

	if (bAutoClearWhenBossDefeated && BossHP <= 0.0f)
	{
		RequestTerminalScene(ClearSceneName);
		return;
	}
}

void AGameFlowDirector::RequestScene(const FString& SceneName)
{
	if (SceneName.empty())
	{
		UE_LOG("[GameFlowDirector] Empty scene transition request ignored.");
		return;
	}
	if (!GEngine)
	{
		UE_LOG("[GameFlowDirector] Scene transition requested without GEngine: %s", SceneName.c_str());
		return;
	}
	UE_LOG("[GameFlowDirector] RequestScene: %s", SceneName.c_str());
	GEngine->RequestTransitionToScene(SceneName);
}

void AGameFlowDirector::StartTraining()
{
	UE_LOG("[GameFlowDirector] StartTraining -> %s", TrainingSceneName.c_str());
	RequestScene(TrainingSceneName);
}

void AGameFlowDirector::StartStoryBoss()
{
	RequestScene(StoryBossSceneName);
}

void AGameFlowDirector::RestartCombatScene()
{
	RequestScene(RetrySceneName.empty() ? StoryBossSceneName : RetrySceneName);
}

void AGameFlowDirector::RequestMainMenu()
{
	RequestScene(MainMenuSceneName);
}

void AGameFlowDirector::RequestGameOver()
{
	if (ABossGameMode* Mode = GetBossGameMode())
	{
		ConfigureBossGameMode();
		Mode->RequestGameOver();
		bTerminalStateReached = true;
		bCombatActive = false;
		return;
	}
	RequestTerminalScene(GameOverSceneName);
}

void AGameFlowDirector::RequestClear()
{
	if (ABossGameMode* Mode = GetBossGameMode())
	{
		ConfigureBossGameMode();
		Mode->RequestClear();
		bTerminalStateReached = true;
		bCombatActive = false;
		return;
	}
	RequestTerminalScene(ClearSceneName);
}

void AGameFlowDirector::RequestCredits()
{
	RequestScene(CreditsSceneName);
}

void AGameFlowDirector::ExitGame()
{
	PostQuitMessage(0);
}

void AGameFlowDirector::PauseGame()
{
	if (GEngine)
	{
		if (UWorld* World = GEngine->GetWorld())
		{
			World->SetPaused(true);
		}
	}
}

void AGameFlowDirector::ResumeGame()
{
	if (GEngine)
	{
		if (UWorld* World = GEngine->GetWorld())
		{
			World->SetPaused(false);
		}
	}
}

void AGameFlowDirector::TogglePause()
{
	if (!bEnableEscapePause)
	{
		return;
	}
	IsPaused() ? ResumeGame() : PauseGame();
}

bool AGameFlowDirector::IsPaused() const
{
	if (!GEngine)
	{
		return false;
	}
	UWorld* World = GEngine->GetWorld();
	return World ? World->IsPaused() : false;
}

void AGameFlowDirector::SetPlayerHP(float Current, float Max)
{
	PlayerMaxHP = std::max(1.0f, Max);
	PlayerHP = std::clamp(Current, 0.0f, PlayerMaxHP);
	if (ABossGameState* State = GetBossGameState())
	{
		State->SetPlayerHP(PlayerHP, PlayerMaxHP);
	}
	EvaluateCombatState();
}

void AGameFlowDirector::DamagePlayer(float Amount)
{
	SetPlayerHP(GetPlayerHP() - std::max(0.0f, Amount), GetPlayerMaxHP());
}

void AGameFlowDirector::HealPlayer(float Amount)
{
	SetPlayerHP(GetPlayerHP() + std::max(0.0f, Amount), GetPlayerMaxHP());
}

void AGameFlowDirector::SetBossHP(float Current, float Max)
{
	BossMaxHP = std::max(1.0f, Max);
	BossHP = std::clamp(Current, 0.0f, BossMaxHP);
	if (ABossGameState* State = GetBossGameState())
	{
		State->SetBossHP(BossHP, BossMaxHP);
	}
	EvaluateCombatState();
}

void AGameFlowDirector::SetUltimateGauge(float Current, float Max)
{
	UltimateMaxGauge = std::max(1.0f, Max);
	UltimateGauge = std::clamp(Current, 0.0f, UltimateMaxGauge);
	if (ABossGameState* State = GetBossGameState())
	{
		State->SetUltimateGauge(UltimateGauge, UltimateMaxGauge);
	}
}

void AGameFlowDirector::SetComboCount(int32 Count)
{
	ComboCount = std::max(0, Count);
	if (ABossGameState* State = GetBossGameState())
	{
		State->SetComboCount(ComboCount);
	}
}

float AGameFlowDirector::GetPlayerHP() const
{
	if (ABossGameState* State = GetBossGameState())
	{
		return State->GetPlayerHP();
	}
	return PlayerHP;
}

float AGameFlowDirector::GetPlayerMaxHP() const
{
	if (ABossGameState* State = GetBossGameState())
	{
		return State->GetPlayerMaxHP();
	}
	return PlayerMaxHP;
}

float AGameFlowDirector::GetBossHP() const
{
	if (ABossGameState* State = GetBossGameState())
	{
		return State->GetBossHP();
	}
	return BossHP;
}

float AGameFlowDirector::GetBossMaxHP() const
{
	if (ABossGameState* State = GetBossGameState())
	{
		return State->GetBossMaxHP();
	}
	return BossMaxHP;
}

float AGameFlowDirector::GetUltimateGauge() const
{
	if (ABossGameState* State = GetBossGameState())
	{
		return State->GetUltimateGauge();
	}
	return UltimateGauge;
}

float AGameFlowDirector::GetUltimateMaxGauge() const
{
	if (ABossGameState* State = GetBossGameState())
	{
		return State->GetUltimateMaxGauge();
	}
	return UltimateMaxGauge;
}

int32 AGameFlowDirector::GetComboCount() const
{
	if (ABossGameState* State = GetBossGameState())
	{
		return State->GetComboCount();
	}
	return ComboCount;
}

AActor* AGameFlowDirector::GetPlayerActor() const
{
	return FindActorByTagString(PlayerActorTag);
}

AActor* AGameFlowDirector::GetBossActor() const
{
	return FindActorByTagString(BossActorTag);
}

ABossGameMode* AGameFlowDirector::GetBossGameMode() const
{
	if (UWorld* World = GetWorld())
	{
		return Cast<ABossGameMode>(World->GetGameMode());
	}
	return nullptr;
}

ABossGameState* AGameFlowDirector::GetBossGameState() const
{
	if (UWorld* World = GetWorld())
	{
		return Cast<ABossGameState>(World->GetGameState());
	}
	return nullptr;
}

AActor* AGameFlowDirector::FindActorByTagString(const FString& Tag) const
{
	if (Tag.empty())
	{
		return nullptr;
	}
	return FGameplayStatics::FindFirstActorByTag(GetWorld(), FName(Tag));
}

FVector AGameFlowDirector::ResolveStartLocation(const FString& StartTag, const FVector& Fallback) const
{
	if (AActor* Marker = FindActorByTagString(StartTag))
	{
		return Marker->GetActorLocation();
	}
	return Fallback;
}

void AGameFlowDirector::NormalizeCombatValues()
{
	PlayerMaxHP = std::max(1.0f, PlayerMaxHP);
	BossMaxHP = std::max(1.0f, BossMaxHP);
	UltimateMaxGauge = std::max(1.0f, UltimateMaxGauge);
	PlayerHP = std::clamp(PlayerHP, 0.0f, PlayerMaxHP);
	BossHP = std::clamp(BossHP, 0.0f, BossMaxHP);
	UltimateGauge = std::clamp(UltimateGauge, 0.0f, UltimateMaxGauge);
	ComboCount = std::max(0, ComboCount);
}

void AGameFlowDirector::PushCombatStateToGameState()
{
	if (ABossGameState* State = GetBossGameState())
	{
		State->SetPlayerHP(PlayerHP, PlayerMaxHP);
		State->SetBossHP(BossHP, BossMaxHP);
		State->SetUltimateGauge(UltimateGauge, UltimateMaxGauge);
		State->SetComboCount(ComboCount);
		if (bCombatActive)
		{
			State->SetFlowPhase("Playing");
		}
	}
}

void AGameFlowDirector::ConfigureBossGameMode()
{
	if (ABossGameMode* Mode = GetBossGameMode())
	{
		Mode->ConfigureFlowRules(bAutoClearWhenBossDefeated, bAutoFailWhenPlayerDead, GameOverSceneName, ClearSceneName);
	}
}

void AGameFlowDirector::RequestTerminalScene(const FString& SceneName)
{
	bTerminalStateReached = true;
	bCombatActive = false;
	if (ABossGameState* State = GetBossGameState())
	{
		if (SceneName == GameOverSceneName)
		{
			State->SetFlowPhase("GameOver");
		}
		else if (SceneName == ClearSceneName)
		{
			State->SetFlowPhase("Clear");
		}
		else
		{
			State->SetFlowPhase("Ended");
		}
	}
	RequestScene(SceneName);
}

AArenaMarker::AArenaMarker()
{
	bNeedsTick = false;
}

void AArenaMarker::BeginPlay()
{
	SyncMarkerTag();
	AEmptyActor::BeginPlay();
}

void AArenaMarker::PostDuplicate()
{
	AEmptyActor::PostDuplicate();
	SyncMarkerTag();
}

void AArenaMarker::PostEditProperty(const char* PropertyName)
{
	AEmptyActor::PostEditProperty(PropertyName);
	if (!PropertyName || strcmp(PropertyName, "MarkerRole") == 0)
	{
		SyncMarkerTag();
	}
}

void AArenaMarker::SetMarkerRole(const FString& InMarkerRole)
{
	MarkerRole = InMarkerRole.empty() ? "PlayerStart" : InMarkerRole;
	SyncMarkerTag();
}

void AArenaMarker::SyncMarkerTag()
{
	RemoveTag(FName("PlayerStart"));
	RemoveTag(FName("BossStart"));

	if (!MarkerRole.empty())
	{
		AddTag(FName(MarkerRole));
	}
}

APlayerStartMarker::APlayerStartMarker()
{
	SetMarkerRole("PlayerStart");
}

ABossStartMarker::ABossStartMarker()
{
	SetMarkerRole("BossStart");
}
