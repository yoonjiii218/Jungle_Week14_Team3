-- Boss/BossDeathCinematic.lua
-- 보스 사망 시네마틱. "치명타 → 슬로모 → 보스 주위를 부드럽게 도는 궤도샷 → 사망 애니메이션" 연출.
--   ① 킬 임팩트(셰이크/FOV 펀치/비네팅) + 전역 슬로모 진입
--   ② 보스를 중심으로 카메라가 부드럽게 호(arc)를 그리며 궤도 비행 (사망 모션 재생 중)
--   ③ 슬로모 해제 → 살짝 여운 → 플레이어로 카메라 복귀
--
-- 사용법: BossDead 이벤트를 받는 곳(WaveDirector.OnBossDead)에서
--   BossDeathCinematic.Play(bossActor, onComplete) 로 호출.
-- 반드시 사망한 보스가 아닌 "수명이 긴 액터"의 코루틴 풀(Begin/End) 안에서 호출해야 한다.
-- (HandleBossDeath 가 보스 코루틴 풀을 Destroy 하므로 보스 풀에서 돌리면 같이 죽는다.)
--
-- 사망 애니메이션 자체는 CombatContext.HandleBossDeath 가 DeathSignal 로 이미 트리거한다.
-- 이 모듈은 카메라/슬로모/연출만 담당한다.

local CombatContext = require("Combat/CombatContext")

local BossDeathCinematic = {}

-- ───────────────────────── 튜닝 상수 ─────────────────────────
-- 사망 시 보스 루트(액터 위치)는 제자리이고 메시만 쓰러진다. Lua 에서 본 위치를 못 읽으므로
-- 카메라가 메시를 직접 추적할 수 없다. 카메라 높이는 고정하고(상승 X), "바라보는 높이"만
-- 가슴에서 지면으로 내려 쓰러지는 몸을 따라간다.
local ORBIT = {
    Radius        = 22.0,   -- 보스 중심으로부터 카메라 거리 (Intro SHOT 의 fwd 스케일 기준)
    Height        = 0.0,    -- 시작 카메라 높이(보스 발 기준)
    LookHeight    = 0.0,    -- 시작 시선 높이(서 있는 보스 가슴)
    StartDeg      = 150.0,  -- 시작 각도(보스 정면 기준 좌측 3/4 부근). 보스 Forward 에 상대적
    SweepDeg      = -120.0, -- 호를 그리며 도는 양(음수 = 시계방향). 정면을 가로질러 우측으로
    -- 끝: 카메라 높이는 그대로 두고(상승 제거), 시선만 지면으로 내려 쓰러지는 몸을 따라간다.
    RadiusEnd     = 23.0,
    HeightEnd     = 0.0,    -- Height 와 동일 → 카메라가 위로 올라가지 않음
    LookHeightEnd = 0.8,
}

local SLOMO_SCALE     = 0.35   -- 월드 시간 배율(0.35 = 35% 속도). 낮을수록 더 느리게
local ORBIT_TIME      = 1.6    -- 궤도 비행 시간(게임 시간 기준 초; 슬로모로 실제 체감은 더 길다)
local LINGER_TIME     = 0.5    -- 궤도 후 정지 여운(게임 시간)
local RETURN_BLEND    = 0.9    -- 플레이어 카메라로 복귀 블렌드(실시간)
local SLOMO_MAX_REAL_TIME = 12.0  -- 슬로모 자동 만료 방지용 넉넉한 실시간 상한(끝에서 stopSlomo)

-- 킬 임팩트 효과 에셋
local DUST_PARTICLE    = "Content/Data/Smoke.uasset"
local IMPACT_SOUND     = { key = "BossDeathImpact", path = "Player Whoosh/Sword_Cinematic_Impact_Hard_01.WAV", volume = 1.0 }
local RUMBLE_SOUND     = { key = "BossDeathRumble", path = "Boss Whoosh/whoosh_slow_deep_07.wav", volume = 0.9 }

local PITCH_SIGN = 1.0

-- ───────────────────────── 내부 상태 ─────────────────────────
local soundLoaded = false

-- ───────────────────────── 헬퍼 ─────────────────────────
local function isValid(actor)
    return actor ~= nil and (actor.IsValid == nil or actor:IsValid())
end

-- 사망 처리 후엔 "Boss" 태그가 제거되므로, 전달받은 액터 → 등록 컨텍스트 순으로 해석한다.
local function resolveBoss(bossActor)
    if isValid(bossActor) then return bossActor end
    if CombatContext.GetBossContext ~= nil then
        local ctx = CombatContext.GetBossContext()
        if ctx ~= nil and isValid(ctx.Owner) then
            return ctx.Owner
        end
    end
    return nil
end

local function getPlayer()
    return World.FindFirstActorByTag("Player")
end

-- 보스를 바라보는 회전. 엔진 규칙: Rotation = Vector(Roll, Pitch, Yaw) (도 단위)
local function LookAtRotation(camPos, targetPos)
    local dx = targetPos.X - camPos.X
    local dy = targetPos.Y - camPos.Y
    local dz = targetPos.Z - camPos.Z
    local yaw = math.atan2(dy, dx) * 180.0 / math.pi
    local horiz = math.sqrt(dx * dx + dy * dy)
    local pitch = PITCH_SIGN * math.atan2(dz, horiz) * 180.0 / math.pi
    return Vector(0.0, pitch, yaw)
end

local function freezePlayer(frozen)
    local player = getPlayer()
    if not isValid(player) then return end
    if player.GetCharacterMovement ~= nil then
        local move = player:GetCharacterMovement()
        if move ~= nil and move.SetMovementInputEnabled ~= nil then
            move:SetMovementInputEnabled(not frozen)
        end
    end
end

-- 전역 슬로모. 플레이어 ActionComponent.Slomo 를 사용(퍼펙트 회피와 동일 경로).
-- duration 은 넉넉히 주고, 끝에서 StopSlomo 로 명시적으로 복구한다.
local function startSlomo(duration)
    local player = getPlayer()
    if not isValid(player) or player.GetActionComponent == nil then return nil end
    local action = player:GetActionComponent()
    if action ~= nil and action.Slomo ~= nil then
        action:Slomo(duration, SLOMO_SCALE)
    end
    return action
end

local function stopSlomo(action)
    if action ~= nil and action.StopSlomo ~= nil then
        action:StopSlomo()
    end
end

-- 보스 중심 기준 각도/반경/높이로 카메라를 배치하고 보스를 바라보게 한다.
local function placeOrbit(camComp, center, angleDeg, radius, height, lookHeight)
    local rad = angleDeg * math.pi / 180.0
    local pos = Vector(
        center.X + math.cos(rad) * radius,
        center.Y + math.sin(rad) * radius,
        center.Z + height)
    camComp:SetLocation(pos)
    camComp:SetRotation(LookAtRotation(pos, Vector(center.X, center.Y, center.Z + lookHeight)))
end

-- 킬 임팩트: 카메라 셰이크 + FOV 펀치 + 비네팅 펄스 + 먼지/사운드
local function killImpact(boss)
    if CameraManager ~= nil then
        if CameraManager.StartWaveShake ~= nil then
            CameraManager.StartWaveShake(1.4)
        end
        if CameraManager.StartFOVPulse ~= nil then
            CameraManager.StartFOVPulse("bossDeathSlam", -12.0, 0.5, 0.04, 0.3)
        end
        if CameraManager.StartVignettePulse ~= nil then
            CameraManager.StartVignettePulse("bossDeathSlam", 0.9, 0.65, 0.4, 0.7, 0.05, 0.5)
        end
    end

    if isValid(boss) and VFX ~= nil and VFX.SpawnParticleSystem ~= nil then
        local p = boss.Location
        VFX.SpawnParticleSystem(DUST_PARTICLE, Vector(p.X, p.Y, p.Z), Vector(0.0, 0.0, 0.0), Vector(2.5, 2.5, 2.5), 2.0)
    end

    if AudioManager ~= nil and AudioManager.Play ~= nil then
        if not soundLoaded and AudioManager.Load ~= nil then
            AudioManager.Load(IMPACT_SOUND.key, IMPACT_SOUND.path, false)
            AudioManager.Load(RUMBLE_SOUND.key, RUMBLE_SOUND.path, false)
            soundLoaded = true
        end
        AudioManager.Play(IMPACT_SOUND.key, IMPACT_SOUND.volume)
        AudioManager.Play(RUMBLE_SOUND.key, RUMBLE_SOUND.volume)
    end
end

-- ─────────────────── 메인 시퀀스 ───────────────────
-- 수명이 긴 액터(WaveDirector 등)의 코루틴 Begin/End 스코프 안에서 호출되어야 한다.
function BossDeathCinematic.Play(bossActor, onComplete)
    StartCoroutine(function()
        local boss = resolveBoss(bossActor)
        if not isValid(boss) then
            print("[BossDeath] Boss actor unavailable; skipping cinematic.")
            if onComplete then onComplete() end
            return
        end

        print("[BossDeath] Cinematic started.")
        freezePlayer(true)

        -- ① 킬 임팩트 + 슬로모 진입.
        -- ActionComponent.Slomo 는 실시간(RawDeltaTime)으로 만료된다. 궤도/여운은 "게임 시간"
        -- 기준이라 슬로모로 늘어난 실제 길이는 (게임시간 / SLOMO_SCALE)。 자동 만료로 중간에
        -- 풀리지 않도록 넉넉한 고정값을 주고, 마지막에 stopSlomo 로 명시적으로 복구한다.
        killImpact(boss)
        local slomoAction = startSlomo(SLOMO_MAX_REAL_TIME)

        -- 시네마틱 카메라 생성
        local camActor = World.SpawnActor("AActor")
        if not isValid(camActor) or camActor.AddCameraComponent == nil then
            print("[BossDeath] Failed to create cinematic camera; skipping.")
            stopSlomo(slomoAction)
            freezePlayer(false)
            if onComplete then onComplete() end
            return
        end
        local camComp = camActor:AddCameraComponent()
        if camComp == nil then
            print("[BossDeath] AddCameraComponent returned nil; skipping.")
            if camActor.Destroy ~= nil then camActor:Destroy() end
            stopSlomo(slomoAction)
            freezePlayer(false)
            if onComplete then onComplete() end
            return
        end

        -- 궤도 시작 각도를 보스 Forward 에 상대적으로 잡는다(어느 방향을 보든 정면을 가로지르게).
        local f = boss.Forward
        local baseDeg = math.atan2(f.Y, f.X) * 180.0 / math.pi
        local center0 = boss.Location

        -- 즉시 시작 위치로 컷 후 Possess
        placeOrbit(camComp, center0, baseDeg + ORBIT.StartDeg, ORBIT.Radius, ORBIT.Height, ORBIT.LookHeight)
        if CameraManager ~= nil and CameraManager.PossessCamera ~= nil then
            CameraManager.PossessCamera(camComp)
        end

        -- ② 부드러운 궤도 비행 (게임 시간 기준 → 슬로모로 같이 느려져 사망 모션과 싱크)
        local t0 = World.GetGameTime()
        while true do
            if not isValid(boss) then break end
            local elapsed = World.GetGameTime() - t0
            local p = elapsed / ORBIT_TIME
            if p >= 1.0 then break end
            -- ease-in-out 으로 시작/끝을 부드럽게
            local e = p * p * (3.0 - 2.0 * p)
            local angle  = baseDeg + ORBIT.StartDeg + ORBIT.SweepDeg * e
            local radius = ORBIT.Radius + (ORBIT.RadiusEnd - ORBIT.Radius) * e
            local height = ORBIT.Height + (ORBIT.HeightEnd - ORBIT.Height) * e
            -- 시선 높이를 가슴 → 지면으로 내려 쓰러지는 몸을 따라간다(루트는 제자리이므로 근사).
            local lookH  = ORBIT.LookHeight + (ORBIT.LookHeightEnd - ORBIT.LookHeight) * e
            -- 보스 위치를 매 프레임 갱신(쓰러지며 위치가 약간 바뀌어도 따라가도록)
            local center = boss.Location
            placeOrbit(camComp, center, angle, radius, height, lookH)
            WaitFrame()
        end

        -- 마지막 프레임 위치 고정
        if isValid(boss) then
            placeOrbit(camComp, boss.Location, baseDeg + ORBIT.StartDeg + ORBIT.SweepDeg,
                       ORBIT.RadiusEnd, ORBIT.HeightEnd, ORBIT.LookHeightEnd)
        end

        -- ③ 여운 → 슬로모 해제 → 플레이어로 복귀
        Wait(LINGER_TIME)
        stopSlomo(slomoAction)

        local player = getPlayer()
        if isValid(player) and CameraManager ~= nil and CameraManager.ToggleOwnerCamera ~= nil then
            CameraManager.ToggleOwnerCamera(player, RETURN_BLEND)
        end
        Wait(RETURN_BLEND)

        -- 블렌드가 안 먹었을 경우 보장 복귀(즉시 컷)
        if isValid(player) and player.GetCamera ~= nil and CameraManager ~= nil and CameraManager.PossessCamera ~= nil then
            local playerCam = player:GetCamera()
            if playerCam ~= nil then
                CameraManager.PossessCamera(playerCam)
            end
        end

        if isValid(camActor) and camActor.Destroy ~= nil then
            camActor:Destroy()
        end
        freezePlayer(false)
        if onComplete then onComplete() end
    end)
end

return BossDeathCinematic
