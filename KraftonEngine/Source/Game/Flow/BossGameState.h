#pragma once

#include "GameFramework/GameMode/GameStateBase.h"

#include "Source/Game/Flow/BossGameState.generated.h"

UCLASS()
class ABossGameState : public AGameStateBase
{
public:
	GENERATED_BODY()

	ABossGameState();

	UFUNCTION(Callable, Category="BossGame|State")
	void ResetCombatState(float InPlayerHP, float InPlayerMaxHP, float InBossHP, float InBossMaxHP, float InUltimateGauge, float InUltimateMaxGauge, int32 InComboCount);
	UFUNCTION(Callable, Category="BossGame|State")
	void SetFlowPhase(const FString& InFlowPhase);
	UFUNCTION(Pure, Category="BossGame|State")
	FString GetFlowPhase() const { return FlowPhase; }

	UFUNCTION(Callable, Category="BossGame|Combat")
	void SetPlayerHP(float Current, float Max);
	UFUNCTION(Callable, Category="BossGame|Combat")
	void SetBossHP(float Current, float Max);
	UFUNCTION(Callable, Category="BossGame|Combat")
	void SetUltimateGauge(float Current, float Max);
	UFUNCTION(Callable, Category="BossGame|Combat")
	void SetComboCount(int32 Count);

	UFUNCTION(Pure, Category="BossGame|Combat")
	float GetPlayerHP() const { return PlayerHP; }
	UFUNCTION(Pure, Category="BossGame|Combat")
	float GetPlayerMaxHP() const { return PlayerMaxHP; }
	UFUNCTION(Pure, Category="BossGame|Combat")
	float GetBossHP() const { return BossHP; }
	UFUNCTION(Pure, Category="BossGame|Combat")
	float GetBossMaxHP() const { return BossMaxHP; }
	UFUNCTION(Pure, Category="BossGame|Combat")
	float GetUltimateGauge() const { return UltimateGauge; }
	UFUNCTION(Pure, Category="BossGame|Combat")
	float GetUltimateMaxGauge() const { return UltimateMaxGauge; }
	UFUNCTION(Pure, Category="BossGame|Combat")
	int32 GetComboCount() const { return ComboCount; }
	UFUNCTION(Pure, Category="BossGame|Combat")
	bool IsPlayerDead() const { return PlayerHP <= 0.0f; }
	UFUNCTION(Pure, Category="BossGame|Combat")
	bool IsBossDefeated() const { return BossHP <= 0.0f; }

private:
	UPROPERTY(Edit, Save, Category="BossGame|State", DisplayName="Flow Phase")
	FString FlowPhase = "WaitingToStart";

	UPROPERTY(Edit, Save, Category="BossGame|Combat", DisplayName="Player HP")
	float PlayerHP = 100.0f;
	UPROPERTY(Edit, Save, Category="BossGame|Combat", DisplayName="Player Max HP")
	float PlayerMaxHP = 100.0f;
	UPROPERTY(Edit, Save, Category="BossGame|Combat", DisplayName="Boss HP")
	float BossHP = 100.0f;
	UPROPERTY(Edit, Save, Category="BossGame|Combat", DisplayName="Boss Max HP")
	float BossMaxHP = 100.0f;
	UPROPERTY(Edit, Save, Category="BossGame|Combat", DisplayName="Ultimate Gauge")
	float UltimateGauge = 0.0f;
	UPROPERTY(Edit, Save, Category="BossGame|Combat", DisplayName="Ultimate Max Gauge")
	float UltimateMaxGauge = 100.0f;
	UPROPERTY(Edit, Save, Category="BossGame|Combat", DisplayName="Combo Count")
	int32 ComboCount = 0;
};
