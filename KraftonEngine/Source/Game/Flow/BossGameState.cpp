#include "Game/Flow/BossGameState.h"

#include <algorithm>

ABossGameState::ABossGameState()
{
	bNeedsTick = false;
}

void ABossGameState::ResetCombatState(float InPlayerHP, float InPlayerMaxHP, float InBossHP, float InBossMaxHP, float InUltimateGauge, float InUltimateMaxGauge, int32 InComboCount)
{
	FlowPhase = "Playing";
	SetPlayerHP(InPlayerHP, InPlayerMaxHP);
	SetBossHP(InBossHP, InBossMaxHP);
	SetUltimateGauge(InUltimateGauge, InUltimateMaxGauge);
	SetComboCount(InComboCount);
}

void ABossGameState::SetFlowPhase(const FString& InFlowPhase)
{
	FlowPhase = InFlowPhase.empty() ? "None" : InFlowPhase;
}

void ABossGameState::SetPlayerHP(float Current, float Max)
{
	PlayerMaxHP = std::max(1.0f, Max);
	PlayerHP = std::clamp(Current, 0.0f, PlayerMaxHP);
}

void ABossGameState::SetBossHP(float Current, float Max)
{
	BossMaxHP = std::max(1.0f, Max);
	BossHP = std::clamp(Current, 0.0f, BossMaxHP);
}

void ABossGameState::SetUltimateGauge(float Current, float Max)
{
	UltimateMaxGauge = std::max(1.0f, Max);
	UltimateGauge = std::clamp(Current, 0.0f, UltimateMaxGauge);
}

void ABossGameState::SetComboCount(int32 Count)
{
	ComboCount = std::max(0, Count);
}
