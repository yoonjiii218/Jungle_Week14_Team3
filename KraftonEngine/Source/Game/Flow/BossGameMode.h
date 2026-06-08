#pragma once

#include "GameFramework/GameMode/GameModeBase.h"

#include "Source/Game/Flow/BossGameMode.generated.h"

class ABossGameState;

UCLASS()
class ABossGameMode : public AGameModeBase
{
public:
	GENERATED_BODY()

	ABossGameMode();

	void StartMatch() override;
	void EndMatch() override;

	UFUNCTION(Pure, Category="BossGame")
	ABossGameState* GetBossGameState() const;
	UFUNCTION(Callable, Category="BossGame")
	void ConfigureFlowRules(bool bInAutoClearWhenBossDefeated, bool bInAutoFailWhenPlayerDead, const FString& InGameOverSceneName, const FString& InClearSceneName);
	UFUNCTION(Callable, Category="BossGame")
	void EvaluateCombatState();
	UFUNCTION(Callable, Category="BossGame")
	void RequestGameOver();
	UFUNCTION(Callable, Category="BossGame")
	void RequestClear();

private:
	void RequestScene(const FString& SceneName);

private:
	UPROPERTY(Edit, Save, Category="BossGame|Rules", DisplayName="Auto Clear When Boss Dead")
	bool bAutoClearWhenBossDefeated = true;
	UPROPERTY(Edit, Save, Category="BossGame|Rules", DisplayName="Auto Fail When Player Dead")
	bool bAutoFailWhenPlayerDead = true;
	UPROPERTY(Edit, Save, Category="BossGame|Scenes", DisplayName="Game Over Scene")
	FString GameOverSceneName = "GameOver";
	UPROPERTY(Edit, Save, Category="BossGame|Scenes", DisplayName="Clear Scene")
	FString ClearSceneName = "Clear";

	bool bTerminalStateReached = false;
};
