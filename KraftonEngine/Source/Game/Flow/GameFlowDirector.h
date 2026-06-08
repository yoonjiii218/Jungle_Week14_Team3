#pragma once

#include "GameFramework/Actor/EmptyActor.h"

#include "Source/Game/Flow/GameFlowDirector.generated.h"

class AActor;
class ABossGameMode;
class ABossGameState;

UCLASS()
class AGameFlowDirector : public AEmptyActor
{
public:
	GENERATED_BODY()

	AGameFlowDirector();

	void BeginPlay() override;
	void Tick(float DeltaTime) override;
	void PostDuplicate() override;

	UFUNCTION(Callable, Category="GameFlow")
	void StartCombat();
	UFUNCTION(Callable, Category="GameFlow")
	void EndCombat();
	UFUNCTION(Callable, Category="GameFlow")
	void ApplyStartPositions();
	UFUNCTION(Callable, Category="GameFlow")
	void EvaluateCombatState();

	UFUNCTION(Callable, Category="GameFlow|Scene")
	void RequestScene(const FString& SceneName);
	UFUNCTION(Callable, Category="GameFlow|Scene")
	void StartTraining();
	UFUNCTION(Callable, Category="GameFlow|Scene")
	void StartStoryBoss();
	UFUNCTION(Callable, Category="GameFlow|Scene")
	void RestartCombatScene();
	UFUNCTION(Callable, Category="GameFlow|Scene")
	void RequestMainMenu();
	UFUNCTION(Callable, Category="GameFlow|Scene")
	void RequestGameOver();
	UFUNCTION(Callable, Category="GameFlow|Scene")
	void RequestClear();
	UFUNCTION(Callable, Category="GameFlow|Scene")
	void RequestCredits();
	UFUNCTION(Callable, Category="GameFlow|Scene")
	void ExitGame();

	UFUNCTION(Callable, Category="GameFlow|Pause")
	void PauseGame();
	UFUNCTION(Callable, Category="GameFlow|Pause")
	void ResumeGame();
	UFUNCTION(Callable, Category="GameFlow|Pause")
	void TogglePause();
	UFUNCTION(Pure, Category="GameFlow|Pause")
	bool IsPaused() const;

	UFUNCTION(Callable, Category="GameFlow|Combat")
	void SetPlayerHP(float Current, float Max);
	UFUNCTION(Callable, Category="GameFlow|Combat")
	void DamagePlayer(float Amount);
	UFUNCTION(Callable, Category="GameFlow|Combat")
	void HealPlayer(float Amount);
	UFUNCTION(Callable, Category="GameFlow|Combat")
	void SetBossHP(float Current, float Max);
	UFUNCTION(Callable, Category="GameFlow|Combat")
	void SetUltimateGauge(float Current, float Max);
	UFUNCTION(Callable, Category="GameFlow|Combat")
	void SetComboCount(int32 Count);

	UFUNCTION(Pure, Category="GameFlow|Combat")
	float GetPlayerHP() const;
	UFUNCTION(Pure, Category="GameFlow|Combat")
	float GetPlayerMaxHP() const;
	UFUNCTION(Pure, Category="GameFlow|Combat")
	float GetBossHP() const;
	UFUNCTION(Pure, Category="GameFlow|Combat")
	float GetBossMaxHP() const;
	UFUNCTION(Pure, Category="GameFlow|Combat")
	float GetUltimateGauge() const;
	UFUNCTION(Pure, Category="GameFlow|Combat")
	float GetUltimateMaxGauge() const;
	UFUNCTION(Pure, Category="GameFlow|Combat")
	int32 GetComboCount() const;
	UFUNCTION(Pure, Category="GameFlow|Combat")
	bool IsCombatActive() const { return bCombatActive; }
	UFUNCTION(Pure, Category="GameFlow|Combat")
	bool HasReachedTerminalState() const { return bTerminalStateReached; }

	UFUNCTION(Pure, Category="GameFlow|UI")
	FString GetStartupScreen() const { return StartupScreen; }
	UFUNCTION(Pure, Category="GameFlow|UI")
	FString GetStartMenuWidgetPath() const { return StartMenuWidgetPath; }
	UFUNCTION(Pure, Category="GameFlow|UI")
	FString GetHudWidgetPath() const { return HudWidgetPath; }
	UFUNCTION(Pure, Category="GameFlow|UI")
	FString GetPauseMenuWidgetPath() const { return PauseMenuWidgetPath; }
	UFUNCTION(Pure, Category="GameFlow|UI")
	FString GetGameOverWidgetPath() const { return GameOverWidgetPath; }
	UFUNCTION(Pure, Category="GameFlow|UI")
	FString GetClearWidgetPath() const { return ClearWidgetPath; }
	UFUNCTION(Pure, Category="GameFlow|UI")
	FString GetCreditsWidgetPath() const { return CreditsWidgetPath; }

	UFUNCTION(Pure, Category="GameFlow|Scene")
	FString GetTrainingSceneName() const { return TrainingSceneName; }
	UFUNCTION(Pure, Category="GameFlow|Scene")
	FString GetStoryBossSceneName() const { return StoryBossSceneName; }
	UFUNCTION(Pure, Category="GameFlow|Scene")
	FString GetRetrySceneName() const { return RetrySceneName; }
	UFUNCTION(Pure, Category="GameFlow|Scene")
	FString GetMainMenuSceneName() const { return MainMenuSceneName; }
	UFUNCTION(Pure, Category="GameFlow|Scene")
	FString GetGameOverSceneName() const { return GameOverSceneName; }
	UFUNCTION(Pure, Category="GameFlow|Scene")
	FString GetClearSceneName() const { return ClearSceneName; }
	UFUNCTION(Pure, Category="GameFlow|Scene")
	FString GetCreditsSceneName() const { return CreditsSceneName; }

	UFUNCTION(Pure, Category="GameFlow|Actors")
	AActor* GetPlayerActor() const;
	UFUNCTION(Pure, Category="GameFlow|Actors")
	AActor* GetBossActor() const;
	UFUNCTION(Pure, Category="GameFlow|GameMode")
	ABossGameMode* GetBossGameMode() const;
	UFUNCTION(Pure, Category="GameFlow|GameMode")
	ABossGameState* GetBossGameState() const;

private:
	AActor* FindActorByTagString(const FString& Tag) const;
	FVector ResolveStartLocation(const FString& StartTag, const FVector& Fallback) const;
	void NormalizeCombatValues();
	void PushCombatStateToGameState();
	void ConfigureBossGameMode();
	void RequestTerminalScene(const FString& SceneName);

private:
	UPROPERTY(Edit, Save, Category="GameFlow|UI", DisplayName="Startup Screen")
	FString StartupScreen = "StartMenu";

	UPROPERTY(Edit, Save, Category="GameFlow|UI", DisplayName="Start Menu Widget", AssetType="RmlUiDocument")
	FString StartMenuWidgetPath = "Content/UI/GameFlow/StartMenu.uasset";
	UPROPERTY(Edit, Save, Category="GameFlow|UI", DisplayName="HUD Widget", AssetType="RmlUiDocument")
	FString HudWidgetPath = "Content/UI/GameFlow/BossHUD.uasset";
	UPROPERTY(Edit, Save, Category="GameFlow|UI", DisplayName="Pause Menu Widget", AssetType="RmlUiDocument")
	FString PauseMenuWidgetPath = "Content/UI/GameFlow/PauseMenu.uasset";
	UPROPERTY(Edit, Save, Category="GameFlow|UI", DisplayName="Game Over Widget", AssetType="RmlUiDocument")
	FString GameOverWidgetPath = "Content/UI/GameFlow/GameOver.uasset";
	UPROPERTY(Edit, Save, Category="GameFlow|UI", DisplayName="Clear Widget", AssetType="RmlUiDocument")
	FString ClearWidgetPath = "Content/UI/GameFlow/Clear.uasset";
	UPROPERTY(Edit, Save, Category="GameFlow|UI", DisplayName="Credits Widget", AssetType="RmlUiDocument")
	FString CreditsWidgetPath = "Content/UI/GameFlow/Credits.uasset";

	UPROPERTY(Edit, Save, Category="GameFlow|Scenes", DisplayName="Main Menu Scene")
	FString MainMenuSceneName = "StartMenu";
	UPROPERTY(Edit, Save, Category="GameFlow|Scenes", DisplayName="Training Scene")
	FString TrainingSceneName = "TrainingMap";
	UPROPERTY(Edit, Save, Category="GameFlow|Scenes", DisplayName="Story Boss Scene")
	FString StoryBossSceneName = "StoryBoss";
	UPROPERTY(Edit, Save, Category="GameFlow|Scenes", DisplayName="Retry Scene")
	FString RetrySceneName = "StoryBoss";
	UPROPERTY(Edit, Save, Category="GameFlow|Scenes", DisplayName="Game Over Scene")
	FString GameOverSceneName = "GameOver";
	UPROPERTY(Edit, Save, Category="GameFlow|Scenes", DisplayName="Clear Scene")
	FString ClearSceneName = "Clear";
	UPROPERTY(Edit, Save, Category="GameFlow|Scenes", DisplayName="Credits Scene")
	FString CreditsSceneName = "Credits";

	UPROPERTY(Edit, Save, Category="GameFlow|Actors", DisplayName="Player Actor Tag")
	FString PlayerActorTag = "Player";
	UPROPERTY(Edit, Save, Category="GameFlow|Actors", DisplayName="Boss Actor Tag")
	FString BossActorTag = "Boss";
	UPROPERTY(Edit, Save, Category="GameFlow|Actors", DisplayName="Player Start Tag")
	FString PlayerStartTag = "PlayerStart";
	UPROPERTY(Edit, Save, Category="GameFlow|Actors", DisplayName="Boss Start Tag")
	FString BossStartTag = "BossStart";

	UPROPERTY(Edit, Save, Category="GameFlow|Stage", DisplayName="Apply Start Positions")
	bool bApplyStartPositions = true;
	UPROPERTY(Edit, Save, Category="GameFlow|Stage", DisplayName="Player Start Location")
	FVector PlayerStartLocation = FVector(-5.0f, 0.0f, 1.0f);
	UPROPERTY(Edit, Save, Category="GameFlow|Stage", DisplayName="Boss Start Location")
	FVector BossStartLocation = FVector(5.0f, 0.0f, 1.0f);

	UPROPERTY(Edit, Save, Category="GameFlow|Rules", DisplayName="Start Combat On BeginPlay")
	bool bStartCombatOnBeginPlay = false;
	UPROPERTY(Edit, Save, Category="GameFlow|Rules", DisplayName="Auto Clear When Boss Dead")
	bool bAutoClearWhenBossDefeated = true;
	UPROPERTY(Edit, Save, Category="GameFlow|Rules", DisplayName="Auto Fail When Player Dead")
	bool bAutoFailWhenPlayerDead = true;
	UPROPERTY(Edit, Save, Category="GameFlow|Rules", DisplayName="Enable Escape Pause")
	bool bEnableEscapePause = true;

	UPROPERTY(Edit, Save, Category="GameFlow|Combat", DisplayName="Player HP")
	float PlayerHP = 100.0f;
	UPROPERTY(Edit, Save, Category="GameFlow|Combat", DisplayName="Player Max HP")
	float PlayerMaxHP = 100.0f;
	UPROPERTY(Edit, Save, Category="GameFlow|Combat", DisplayName="Boss HP")
	float BossHP = 100.0f;
	UPROPERTY(Edit, Save, Category="GameFlow|Combat", DisplayName="Boss Max HP")
	float BossMaxHP = 100.0f;
	UPROPERTY(Edit, Save, Category="GameFlow|Combat", DisplayName="Ultimate Gauge")
	float UltimateGauge = 0.0f;
	UPROPERTY(Edit, Save, Category="GameFlow|Combat", DisplayName="Ultimate Max Gauge")
	float UltimateMaxGauge = 100.0f;
	UPROPERTY(Edit, Save, Category="GameFlow|Combat", DisplayName="Combo Count")
	int32 ComboCount = 0;

	bool bCombatActive = false;
	bool bTerminalStateReached = false;
};

UCLASS()
class AArenaMarker : public AEmptyActor
{
public:
	GENERATED_BODY()

	AArenaMarker();
	void BeginPlay() override;
	void PostDuplicate() override;
	void PostEditProperty(const char* PropertyName) override;

	UFUNCTION(Pure, Category="Arena")
	FString GetMarkerRole() const { return MarkerRole; }
	UFUNCTION(Callable, Category="Arena")
	void SetMarkerRole(const FString& InMarkerRole);

private:
	void SyncMarkerTag();

private:
	UPROPERTY(Edit, Save, Category="Arena", DisplayName="Marker Role")
	FString MarkerRole = "PlayerStart";
};

UCLASS()
class APlayerStartMarker : public AArenaMarker
{
public:
	GENERATED_BODY()

	APlayerStartMarker();
};

UCLASS()
class ABossStartMarker : public AArenaMarker
{
public:
	GENERATED_BODY()

	ABossStartMarker();
};
