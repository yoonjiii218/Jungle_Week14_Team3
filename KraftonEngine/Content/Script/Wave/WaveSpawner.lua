-- Wave/WaveSpawner.lua
-- 몹/보스 액터 생성 담당. 생성한 액터를 추적해 일괄 정리(ClearAll)까지 책임진다.
-- 스폰 바인딩/좌표 규약은 검증된 TutorialSpawner 와 동일하게 맞춘다.
-- (WaveDirector 가 require 해서 사용하는 순수 모듈. 코루틴은 호출자의 Begin/End 스코프에서 구동된다.)

local WaveSpawner = {}

-- 추적 테이블 (TutorialSpawner 의 모듈 레벨 상태 패턴과 동일. 웨이브 시스템은 단일 인스턴스)
local spawnedEntities = {}

-- TutorialSpawner 와 동일한 씬 기준 Z 오프셋
local MOB_Z_OFFSET = -1.33849
local BOSS_Z_OFFSET = 5.513673
local DEFAULT_DISTANCE = 15.0

local function IsValidActor(actor)
    return actor ~= nil and actor.IsValid ~= nil and actor:IsValid()
end

local function GetPlayerActor()
    local player = World.FindFirstActorByTag("Player")
    if IsValidActor(player) then
        return player
    end
    return World.FindActorByName("PlayerCharacter")
end

-- waveData 안의 모든 적 그룹 수 합산 (Director 의 AliveCount 사전 계산용).
-- enemies 배열이 없으면 waveData 자체를 단일 그룹으로 간주(구버전 포맷 호환).
function WaveSpawner.GetSpawnCount(waveData)
    local groups = waveData.enemies or { waveData }
    local total = 0
    for _, group in ipairs(groups) do
        total = total + (group.count or 1)
    end
    return total
end

-- 플레이어를 중심으로 한 원 테두리 위 임의 지점 + 플레이어를 바라보는 Yaw.
local function ComputeSpawnTransform(enemyData)
    local player = GetPlayerActor()
    if not IsValidActor(player) then
        return nil
    end

    local origin = player.Location
    local dist = enemyData.distance or DEFAULT_DISTANCE
    local angle = math.random() * math.pi * 2.0

    local zOffset = MOB_Z_OFFSET
    if enemyData.spawnType == "Boss" then
        zOffset = BOSS_Z_OFFSET
    end

    local loc = Vector(
        origin.X + math.cos(angle) * dist,
        origin.Y + math.sin(angle) * dist,
        origin.Z + zOffset
    )

    local yaw = math.deg(math.atan2(origin.Y - loc.Y, origin.X - loc.X))
    return loc, yaw
end

-- 단일 적 생성. 성공 시 true. enemyData 는 enemies 배열의 한 그룹.
function WaveSpawner.SpawnSingleEntity(enemyData)
    if GameFlow == nil then
        return false
    end

    local loc, yaw = ComputeSpawnTransform(enemyData)
    if loc == nil then
        print("[WaveSpawner] player not found; skip spawn")
        return false
    end

    -- 검증된 C++ 바인딩 재사용. (Elite 등 신규 종류는 전용 바인딩 추가 후 분기에 끼우면 됨)
    local spawnedActor = nil
    if enemyData.spawnType == "Boss" then
        if GameFlow.SpawnTutorialBoss ~= nil then
            spawnedActor = GameFlow.SpawnTutorialBoss(loc, yaw)
        end
    else
        if GameFlow.SpawnTutorialMob ~= nil then
            spawnedActor = GameFlow.SpawnTutorialMob(loc, yaw)
        end
    end

    if IsValidActor(spawnedActor) then
        spawnedActor:AddTag("WaveEnemy")
        table.insert(spawnedEntities, spawnedActor)
        return true
    end

    print("[WaveSpawner] failed to spawn " .. tostring(enemyData.spawnType))
    return false
end

-- waveData 의 모든 그룹을 spawnDelay 간격으로 스폰. 완료 시 실제 스폰 수를 콜백으로 보고.
-- 전역 StartCoroutine/Wait 사용 → 호출자(WaveDirector.Tick)의 Begin/End 스코프 안에서만 호출할 것.
function WaveSpawner.SpawnWave(waveData, onSpawnComplete)
    local groups = waveData.enemies or { waveData }
    local totalCount = WaveSpawner.GetSpawnCount(waveData)

    StartCoroutine(function()
        local spawnedCount = 0
        local spawnIndex = 0

        for _, group in ipairs(groups) do
            for _ = 1, (group.count or 1) do
                spawnIndex = spawnIndex + 1

                if WaveSpawner.SpawnSingleEntity(group) then
                    spawnedCount = spawnedCount + 1
                end

                -- 마지막 1마리 뒤에는 대기 생략 (불필요한 지연 방지)
                local delay = group.spawnDelay or 0
                if spawnIndex < totalCount and delay > 0 then
                    Wait(delay)
                end
            end
        end

        if onSpawnComplete then
            onSpawnComplete(spawnedCount)
        end
    end)
end

-- 맵 밖(허공)으로 떨어진 적을 회수한다. killZ 아래로 내려간 액터는 destroy 하고 목록에서 제거,
-- 회수된 액터는 onReap(actor) 로 알린다(Director 가 사망으로 처리해 웨이브 softlock 을 막음).
-- 이미 파괴된(IsValid=false) 항목도 목록에서 정리한다.
function WaveSpawner.ReapFallen(killZ, onReap)
    for i = #spawnedEntities, 1, -1 do
        local actor = spawnedEntities[i]
        if not IsValidActor(actor) then
            table.remove(spawnedEntities, i)
        elseif actor.Location ~= nil and actor.Location.Z < killZ then
            if onReap then onReap(actor) end
            actor:Destroy()
            table.remove(spawnedEntities, i)
        end
    end
end

-- 추적 중인 모든 스폰 액터 제거. StopWaveSystem / Stage Reset 에서 호출.
function WaveSpawner.ClearAll()
    for _, actor in ipairs(spawnedEntities) do
        if IsValidActor(actor) then
            actor:Destroy()
        end
    end
    spawnedEntities = {}
end

return WaveSpawner
