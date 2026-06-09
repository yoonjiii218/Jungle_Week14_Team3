-- Wave/WaveDirector.lua
-- 더미 액터에 부착하는 웨이브 진행/클리어 관리 스크립트 컴포넌트.
-- MobCharacter/BossCharacter 와 동일하게 전역 BeginPlay/Tick/EndPlay 진입점을 쓰고,
-- obj.UUID 로 자기 코루틴 풀을 구동한다. (이 파일만 액터에 붙이면 됨)

local CoroutineManager = require("CoroutineManager")
local GameplayEventBus = require("Core/GameplayEventBus")
local WaveConfig = require("Wave/WaveConfig")
local WaveSpawner = require("Wave/WaveSpawner")

-- 웨이브 진행 상태
local WaveState = {
    Idle      = "Idle",       -- 대기(시스템 비활성)
    Waiting   = "Waiting",    -- 다음 웨이브 시작 전 인터벌
    Spawning  = "Spawning",   -- 적 스폰 진행 중
    Fighting  = "Fighting",   -- 스폰 완료, 전투 중
    Completed = "Completed",  -- 현재 웨이브 클리어(전이 표시용)
    Finished  = "Finished",   -- 모든 웨이브 종료
}

local FIRST_WAVE_DELAY = 2.0    -- 씬 로딩 후 첫 웨이브까지
local INTER_WAVE_DELAY = 3.0    -- 웨이브 사이 휴식
local FALL_KILL_DELTA  = 50.0   -- 플레이어보다 이만큼 아래로 떨어지면 추락(맵 밖)으로 간주

-- 웨이브 시스템 상태 (단일 액터이므로 모듈 레벨 상태로 보유)
local state = {
    CurrentWaveIndex = 0,
    AliveCount = 0,
    IsActive = false,
    State = WaveState.Idle,
    SpawnComplete = false,
    WaitTimer = 0.0,
}

local mobDeadHandle = nil
local bossDeadHandle = nil

-- 이미 사망/추락 처리한 액터 키 집합. 사망 이벤트와 추락 회수가 같은 적을 중복 차감하지 않게 한다.
-- 액터 UUID 는 고유하므로 웨이브 간 초기화하지 않는다(이전 시체가 떨어져도 재차감되지 않음).
local resolved = {}

local function ActorKey(actor)
    if actor == nil then return nil end
    return actor.UUID or tostring(actor)
end

local function GetPlayerZ()
    local p = World.FindFirstActorByTag("Player")
    if p ~= nil and p.IsValid ~= nil and p:IsValid() and p.Location ~= nil then
        return p.Location.Z
    end
    return nil
end

local function SetState(newState)
    if state.State == newState then return end
    print("[WaveDirector] State: " .. tostring(state.State) .. " -> " .. tostring(newState))
    state.State = newState
end

local function StartNextWave()
    state.CurrentWaveIndex = state.CurrentWaveIndex + 1
    local waveData = WaveConfig[state.CurrentWaveIndex]

    -- 더 이상 설정된 웨이브가 없으면 최종 클리어
    if not waveData then
        state.IsActive = false
        SetState(WaveState.Finished)
        print("[WaveDirector] All Waves Cleared! Stage Complete.")
        GameplayEventBus.Publish({
            Type = "WavesFinished",
            WaveIndex = state.CurrentWaveIndex - 1,
        })
        return
    end

    -- ① AliveCount 를 Config 기준으로 '미리' 확정 (스폰 콜백이 아니라 시작 시점에).
    --    아직 안 나온 적은 죽을 수 없으므로 스폰 도중 적이 죽어도 카운트가 꼬이지 않는다.
    state.AliveCount = WaveSpawner.GetSpawnCount(waveData)
    state.SpawnComplete = false
    SetState(WaveState.Spawning)
    print("[WaveDirector] Starting Wave " .. state.CurrentWaveIndex .. " (Target: " .. state.AliveCount .. ")")

    WaveSpawner.SpawnWave(waveData, function(spawnedCount)
        -- 스폰 실패 보정: 계획보다 적게 났으면 그만큼 차감해야 카운트가 0에 도달함.
        local failed = WaveSpawner.GetSpawnCount(waveData) - spawnedCount
        if failed > 0 then
            state.AliveCount = state.AliveCount - failed
            print("[WaveDirector] Spawn shortfall: " .. failed .. " (Alive=" .. state.AliveCount .. ")")
        end
        state.SpawnComplete = true
        SetState(WaveState.Fighting)
    end)
end

-- 적 1마리를 '해결'(사망 or 추락)로 처리. 액터 키로 중복을 막아 한 번만 차감한다.
local function ResolveEnemy(actor)
    local key = ActorKey(actor)
    if key ~= nil then
        if resolved[key] then return end
        resolved[key] = true
    end

    state.AliveCount = state.AliveCount - 1
    print("[WaveDirector] Enemy Down! Remaining: " .. state.AliveCount)
end

-- 사망 이벤트는 '다른 액터의 Tick 도중'(전투 해결 중) 동기 호출된다.
-- 그 시점엔 이 액터의 코루틴 풀이 current 가 아니므로, 여기서는 카운트만 줄이고
-- 실제 상태 전이/타이머는 이 액터의 Tick 에서 처리한다.
local function HandleEnemyDeath(eventData)
    if not state.IsActive then return end
    -- 스폰/전투 단계에서만 카운트. 인터벌·종료 후 들어오는 잔여 사망 신호는 무시.
    if state.State ~= WaveState.Spawning and state.State ~= WaveState.Fighting then
        return
    end

    ResolveEnemy(eventData and eventData.Owner or nil)
end

local function OnMobDead(eventData)
    HandleEnemyDeath(eventData)
end

local function OnBossDead(eventData)
    HandleEnemyDeath(eventData)
end

-- 맵 밖으로 추락한 적을 회수해 사망으로 처리한다(추락한 보스 때문에 웨이브가 영원히
-- 클리어되지 않는 softlock 방지). 회수된 액터도 ResolveEnemy 로 중복 없이 1회만 차감.
local function ReapFallenEnemies()
    local playerZ = GetPlayerZ()
    if playerZ == nil then return end

    WaveSpawner.ReapFallen(playerZ - FALL_KILL_DELTA, function(actor)
        print("[WaveDirector] Enemy fell out of world; reclaiming.")
        ResolveEnemy(actor)
    end)
end

local function StopWaveSystem()
    state.IsActive = false
    SetState(WaveState.Idle)

    if mobDeadHandle then
        GameplayEventBus.Unsubscribe(mobDeadHandle)
        mobDeadHandle = nil
    end
    if bossDeadHandle then
        GameplayEventBus.Unsubscribe(bossDeadHandle)
        bossDeadHandle = nil
    end

    WaveSpawner.ClearAll()
    resolved = {}
    state.AliveCount = 0
    state.SpawnComplete = false
end

-- =========================================================
-- 스크립트 컴포넌트 진입점 (전역 BeginPlay/Tick/EndPlay)
-- =========================================================

function BeginPlay()
    state.CurrentWaveIndex = 0
    state.AliveCount = 0
    state.SpawnComplete = false
    state.IsActive = true

    -- 몹/보스 사망 이벤트 구독 (CombatContext 에서 각각 Publish)
    mobDeadHandle  = GameplayEventBus.Subscribe("MobDead", obj, OnMobDead)
    bossDeadHandle = GameplayEventBus.Subscribe("BossDead", obj, OnBossDead)

    -- 씬 로딩 후 잠시 대기했다가 첫 웨이브 시작 (타이머는 Tick 이 소모)
    state.WaitTimer = FIRST_WAVE_DELAY
    SetState(WaveState.Waiting)
    print("[WaveDirector] BeginPlay - first wave in " .. FIRST_WAVE_DELAY .. "s")
end

function Tick(dt)
    if not state.IsActive then
        return
    end

    -- 이 액터 전용 코루틴 풀 구동 (스폰 페이싱 코루틴이 여기서 진행됨)
    CoroutineManager.Begin(obj.UUID)

    -- 스폰/전투 중인 적이 맵 밖으로 추락했는지 점검해 회수(softlock 방지)
    if state.State == WaveState.Spawning or state.State == WaveState.Fighting then
        ReapFallenEnemies()
    end

    if state.State == WaveState.Waiting then
        state.WaitTimer = state.WaitTimer - dt
        if state.WaitTimer <= 0.0 then
            StartNextWave()
        end
    elseif state.State == WaveState.Fighting then
        -- 스폰이 끝났고 생존자가 0 → 웨이브 클리어 (스폰 도중 조기 클리어 방지)
        if state.SpawnComplete and state.AliveCount <= 0 then
            SetState(WaveState.Completed)
            print("[WaveDirector] Wave " .. state.CurrentWaveIndex .. " Cleared!")
            state.WaitTimer = INTER_WAVE_DELAY
            SetState(WaveState.Waiting)
        end
    end

    UpdateCoroutines(dt)
    CoroutineManager.End()
end

function EndPlay()
    StopWaveSystem()
    if obj ~= nil then
        CoroutineManager.Destroy(obj.UUID)
    end
end
