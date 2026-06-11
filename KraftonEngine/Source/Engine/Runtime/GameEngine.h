#pragma once

#include "Engine/Runtime/Engine.h"
#include "Serialization/SceneSaveManager.h"


#include "Source/Engine/Runtime/GameEngine.generated.h"

class USkinnedMeshComponent;
class UStaticMeshComponent;

UCLASS()
class UGameEngine : public UEngine
{
public:
	GENERATED_BODY()
	UGameEngine() = default;
	~UGameEngine() override;

	void Init(FWindowsWindow* InWindow) override;
	void Shutdown() override;
	void Tick(float DeltaTime) override;
	void OnWindowResized(uint32 Width, uint32 Height) override;
	void AddReferencedObjects(FReferenceCollector& Collector) override;

	FViewport* GetStandaloneViewport() const { return StandaloneViewport; }

	// 다음 frame Tick 끝에서 active world 를 destroy 하고 InScenePath 의 scene 으로 교체.
	// 호출은 Lua / GameMode 어디서든 안전 — 실제 destroy/load 는 World->Tick 바깥에서 일어나
	// 호출 stack 위의 액터/컴포넌트가 destroy 되어 use-after-free 가 나지 않는다.
	// "Go To Intro" / 매치 재시작 등 동적 상태 전체 리셋이 필요한 경우 사용.
	void RequestTransitionToScene(const FString& InScenePath) override;
	bool RequestAsyncTransitionToScene(const FString& InScenePath) override;
	bool IsAsyncSceneTransitionPending() const override;
	bool IsAsyncSceneTransitionReady() const override;
	float GetAsyncSceneTransitionProgress() const override;
	bool CommitAsyncSceneTransition() override;

private:
	void LoadStartLevel();
	bool LoadSceneFromPath(const FString& FilePath);
	void ConfigureGameWorld(FWorldContext& LoadContext);

	// "Map" 같은 이름이나 Scene/.Scene 풀 경로 양쪽 다 받아 풀 파일 경로로 정규화.
	FString ResolveSceneFilePath(const FString& InNameOrPath) const;

	// UGameEngine::Tick 끝에서 호출 — 펜딩 요청이 있으면 이 시점에 destroy + load + BeginPlay 실행.
	void ProcessPendingTransition();
	void TickAsyncSceneTransition();
	void ProcessAsyncSceneTransitionCommit();
	void QueueDeferredMeshResolves(UWorld* World);
	bool HasDeferredMeshResolves() const;
	void TickDeferredMeshResolves();
	void ResetAsyncSceneTransition(bool bDestroyLoadedWorld);
	void BeginPlayForActiveGameWorld();

private:
	FViewport* StandaloneViewport = nullptr;

	bool bPendingSceneTransition = false;
	FString PendingScenePath;

	bool bAsyncSceneTransitionPending = false;
	bool bAsyncSceneTransitionReady = false;
	bool bAsyncSceneTransitionFailed = false;
	bool bAsyncSceneTransitionCommitRequested = false;
	bool bAsyncSceneTransitionResolvingAssets = false;
	int32 AsyncLoadedActorCount = 0;
	int32 AsyncTotalActorCount = 0;
	FString AsyncScenePath;
	FString AsyncResolvedScenePath;
	FWorldContext AsyncLoadedContext;
	FPerspectiveCameraData AsyncLoadedCamera;
	FSceneSaveManager::FSceneAsyncLoadState* AsyncLoadState = nullptr;
	TArray<UStaticMeshComponent*> DeferredStaticMeshResolveComponents;
	TArray<USkinnedMeshComponent*> DeferredSkinnedMeshResolveComponents;
};
