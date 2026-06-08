#include "Game/Flow/BossGameMode.h"

#include "Game/Flow/BossGameState.h"
#include "Runtime/Engine.h"

ABossGameMode::ABossGameMode()
{
	GameStateClass = ABossGameState::StaticClass();
}

void ABossGameMode::StartMatch()
{
	bTerminalStateReached = false;
	AGameModeBase::StartMatch();

	if (ABossGameState* State = GetBossGameState())
	{
		if (State->GetFlowPhase() != "Playing")
		{
			State->SetFlowPhase("WaitingToStart");
		}
	}
}

void ABossGameMode::EndMatch()
{
	if (ABossGameState* State = GetBossGameState())
	{
		const FString Phase = State->GetFlowPhase();
		if (Phase != "GameOver" && Phase != "Clear")
		{
			State->SetFlowPhase("Ended");
		}
	}

	AGameModeBase::EndMatch();
}

ABossGameState* ABossGameMode::GetBossGameState() const
{
	return Cast<ABossGameState>(GetGameState());
}

void ABossGameMode::ConfigureFlowRules(bool bInAutoClearWhenBossDefeated, bool bInAutoFailWhenPlayerDead, const FString& InGameOverSceneName, const FString& InClearSceneName)
{
	bAutoClearWhenBossDefeated = bInAutoClearWhenBossDefeated;
	bAutoFailWhenPlayerDead = bInAutoFailWhenPlayerDead;
	if (!InGameOverSceneName.empty())
	{
		GameOverSceneName = InGameOverSceneName;
	}
	if (!InClearSceneName.empty())
	{
		ClearSceneName = InClearSceneName;
	}
}

void ABossGameMode::EvaluateCombatState()
{
	if (bTerminalStateReached)
	{
		return;
	}

	ABossGameState* State = GetBossGameState();
	if (!State || State->GetFlowPhase() != "Playing")
	{
		return;
	}

	if (bAutoFailWhenPlayerDead && State->IsPlayerDead())
	{
		RequestGameOver();
		return;
	}

	if (bAutoClearWhenBossDefeated && State->IsBossDefeated())
	{
		RequestClear();
	}
}

void ABossGameMode::RequestGameOver()
{
	bTerminalStateReached = true;
	if (ABossGameState* State = GetBossGameState())
	{
		State->SetFlowPhase("GameOver");
	}
	EndMatch();
	RequestScene(GameOverSceneName);
}

void ABossGameMode::RequestClear()
{
	bTerminalStateReached = true;
	if (ABossGameState* State = GetBossGameState())
	{
		State->SetFlowPhase("Clear");
	}
	EndMatch();
	RequestScene(ClearSceneName);
}

void ABossGameMode::RequestScene(const FString& SceneName)
{
	if (!GEngine || SceneName.empty())
	{
		return;
	}
	GEngine->RequestTransitionToScene(SceneName);
}
