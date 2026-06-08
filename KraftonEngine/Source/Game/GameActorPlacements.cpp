#include "Game/GameActorPlacements.h"

#include "Engine/Runtime/ActorPlacementRegistry.h"
#include "Engine/Runtime/EngineInitHooks.h"
#include "Game/Flow/GameFlowDirector.h"
#include "GameFramework/World.h"

// ============================================================
// 게임-특화 액터를 Editor 의 "Place Actor" 메뉴에 등록 — 현재는 비어 있음.
//
// game-specific actor (전용 Pawn / NPC / spawner 등) 도입 시 여기에 RegisterEntry
// 항목을 추가한다. Engine 측은 이 함수의 이름만 알고 호출 — 새 액터 클래스 헤더는
// 이 cpp 안에서만 include 하면 됨.
// ============================================================
void RegisterGameActorPlacements()
{
	FActorPlacementRegistry::Get().RegisterEntry("Game Flow Director", [](UWorld* World, const FVector& Location) -> AActor*
	{
		if (!World)
		{
			return nullptr;
		}

		AGameFlowDirector* Director = World->SpawnActor<AGameFlowDirector>();
		if (!Director)
		{
			return nullptr;
		}

		Director->InitDefaultComponents();
		Director->SetActorLocation(Location);
		Director->AddTag(FName("GameDirector"));
		return Director;
	});

	FActorPlacementRegistry::Get().RegisterEntry("Player Start Marker", [](UWorld* World, const FVector& Location) -> AActor*
	{
		if (!World)
		{
			return nullptr;
		}

		APlayerStartMarker* Marker = World->SpawnActor<APlayerStartMarker>();
		if (!Marker)
		{
			return nullptr;
		}

		Marker->InitDefaultComponents();
		Marker->SetActorLocation(Location);
		return Marker;
	});

	FActorPlacementRegistry::Get().RegisterEntry("Boss Start Marker", [](UWorld* World, const FVector& Location) -> AActor*
	{
		if (!World)
		{
			return nullptr;
		}

		ABossStartMarker* Marker = World->SpawnActor<ABossStartMarker>();
		if (!Marker)
		{
			return nullptr;
		}

		Marker->InitDefaultComponents();
		Marker->SetActorLocation(Location);
		return Marker;
	});

	FActorPlacementRegistry::Get().RegisterEntry("Arena Marker", [](UWorld* World, const FVector& Location) -> AActor*
	{
		if (!World)
		{
			return nullptr;
		}

		AArenaMarker* Marker = World->SpawnActor<AArenaMarker>();
		if (!Marker)
		{
			return nullptr;
		}

		Marker->InitDefaultComponents();
		Marker->SetActorLocation(Location);
		Marker->SetMarkerRole("PlayerStart");
		return Marker;
	});
}

// 자기-등록 — Editor / Game 측이 함수명을 모르고도 FEngineInitHooks::RunAll() 로 호출됨.
namespace
{
	struct GameActorPlacementsAutoReg
	{
		GameActorPlacementsAutoReg() { FEngineInitHooks::Register(&RegisterGameActorPlacements); }
	};

	static GameActorPlacementsAutoReg gAutoReg;
}
