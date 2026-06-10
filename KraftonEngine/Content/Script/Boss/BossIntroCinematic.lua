-- Boss/BossIntroCinematic.lua
-- 보스 등장 시네마틱. 만화풍 악당 등장 연출:
--   ① 보스를 아래에서 위로(로우앵글) 천천히 올려다봄
--   ② 좌측 3/4 하드컷 → ③ 우측 3/4 하드컷
--   ④ 보스가 DashSlash 한 방 → 임팩트(땅 흔들림/먼지/사운드)
--   ⑤ 몇 초 여운 → ⑥ 플레이어로 카메라 복귀 → 전투 시작
--
-- 사용법: WaveDirector 의 보스 웨이브 스폰 완료 시 BossIntroCinematic.Play(onComplete) 호출.
-- 카메라는 임시 액터 + 카메라 컴포넌트를 직접 구동한다(액터 root 의존을 피하려고 컴포넌트를 직접 이동).
--
-- 임팩트(땅 흔들림)는 DashSlash 시퀀스에 찍은 AnimNotify_LuaFunction 이 전역
-- on_boss_intro_slam() 을 호출해 발동한다. notify 가 아직 없을 때를 대비해 코루틴이
-- 타이머 폴백으로도 호출하며, slamFired 가드로 중복 발동을 막는다.

local CombatContext = require("Combat/CombatContext")

local BossIntroCinematic = {}

-- ───────────────────────── 튜닝 상수 ─────────────────────────
-- 카메라를 보스 기준 (전방, 측면, 높이) 오프셋으로 배치한다. 월드 스케일에 맞춰 조정할 것.
-- (참고: 보스 스폰이 player.Location + Vector(10,0,0) 스케일이므로 아래 값은 그 기준.)
local SHOT = {
    -- ① 로우앵글: 카메라는 낮게(바닥 위), 보스 머리쪽(look 높게)을 올려다봄
    Low      = { fwd = 10,  side = 0.0,  up = 0.3,  look = 0.2 },
    LowRise  = 1.0,    -- 로우앵글에서 위로 상승하는 양(초당), 1.3초간 상승
    LowTime  = 1.3,
    -- ② 좌측 3/4
    Left     = { fwd = 15,  side = -2.8, up = 1.5,  look = 0.8 },
    LeftHold = 0.7,
    -- ③ 우측 3/4
    Right    = { fwd = 20,  side = 2.8,  up = 1.5,  look = 1.8 },
    RightHold= 0.7,
    -- ④ 공격 직전: 정면에서 살짝 로우로 빠짐
    Attack   = { fwd = 30,  side = 0.0,  up = 1.0,  look = 1.5 },
}

local PITCH_SIGN       = 1.0     -- 위를 올려다보는 pitch 부호. 카메라가 거꾸로 보이면 -1.0 로 바꾼다.
local DASH_TRIGGER_DELAY = 0.25  -- 공격 컷 진입 후 DashSlash 트리거까지 대기
local SLAM_FALLBACK_DELAY = 0.9  -- DashSlash 트리거 후 임팩트 폴백까지(노티파이 없을 때 대비)
local LINGER_TIME      = 2.0     -- 임팩트 후 여운
local RETURN_BLEND     = 0.8     -- 플레이어로 복귀하는 블렌드 시간

-- 임팩트 효과 에셋
local DUST_PARTICLE    = "Content/Data/Smoke.uasset"
local GROUND_CRACK_MAT = "Content/Material/VFX/M_GroundCrack.mat"
local IMPACT_SOUND     = { key = "BossIntroImpact", path = "Player Whoosh/Sword_Cinematic_Impact_Hard_01.WAV", volume = 1.0 }
local RUMBLE_SOUND     = { key = "BossIntroRumble", path = "Boss Whoosh/whoosh_slow_deep_07.wav", volume = 0.9 }

-- ───────────────────────── 내부 상태 ─────────────────────────
local slamFired = false          -- 임팩트 중복 발동 방지(notify + 타이머 폴백)
local soundLoaded = false

-- ───────────────────────── 헬퍼 ─────────────────────────
local function isValid(actor)
    return actor ~= nil and (actor.IsValid == nil or actor:IsValid())
end

-- 보스 액터를 가장 확실한 순서로 해석한다.
--   ① CombatContext.GetBossContext().Owner (등록된 보스 — 태그보다 빠르고 정확)
--   ② "Boss" 태그 (BossCharacter.BeginPlay 가 붙임 — 스폰 다음 프레임)
local function resolveBoss()
    if CombatContext.GetBossContext ~= nil then
        local ctx = CombatContext.GetBossContext()
        if ctx ~= nil and isValid(ctx.Owner) then
            return ctx.Owner
        end
    end
    local tagged = World.FindFirstActorByTag("Boss")
    if isValid(tagged) then
        return tagged
    end
    return nil
end

-- 보스를 바라보는 회전 계산. 엔진 규칙: Rotation = Vector(Roll, Pitch, Yaw) (도 단위)
local function LookAtRotation(camPos, targetPos)
    local dx = targetPos.X - camPos.X
    local dy = targetPos.Y - camPos.Y
    local dz = targetPos.Z - camPos.Z
    local yaw = math.atan2(dy, dx) * 180.0 / math.pi
    local horiz = math.sqrt(dx * dx + dy * dy)
    local pitch = PITCH_SIGN * math.atan2(dz, horiz) * 180.0 / math.pi
    return Vector(0.0, pitch, yaw)
end

-- 보스 기준 오프셋으로 카메라를 배치하고 보스를 바라보게 한다.
-- 런타임 생성 카메라 액터는 RootComponent 가 없어 SetActorLocation 이 무효이므로,
-- 카메라 컴포넌트의 월드 트랜스폼을 직접 구동한다(GetCameraView 가 컴포넌트 월드 트랜스폼 사용).
local function placeShot(camComp, boss, shot, upOverride)
    local bp = boss.Location
    local f = boss.Forward
    local r = boss.Right
    local up = upOverride or shot.up
    local pos = Vector(
        bp.X + f.X * shot.fwd + r.X * shot.side,
        bp.Y + f.Y * shot.fwd + r.Y * shot.side,
        bp.Z + up)
    camComp:SetLocation(pos)   -- SetWorldLocation
    camComp:SetRotation(LookAtRotation(pos, Vector(bp.X, bp.Y, bp.Z + shot.look)))   -- 무부모이므로 relative==world
end

local function freezePlayer(frozen)
    local player = World.FindFirstActorByTag("Player")
    if not isValid(player) then return end
    if player.GetCharacterMovement ~= nil then
        local move = player:GetCharacterMovement()
        if move ~= nil and move.SetMovementInputEnabled ~= nil then
            move:SetMovementInputEnabled(not frozen)
        end
    end
end

-- ─────────────────── 임팩트(땅 흔들림) — DashSlash notify 가 호출 ───────────────────
function on_boss_intro_slam()
    if slamFired then return end
    slamFired = true

    -- 카메라 셰이크 + FOV 펀치 + 비네팅 펄스
    if CameraManager ~= nil then
        if CameraManager.StartWaveShake ~= nil then
            CameraManager.StartWaveShake(1.6)
        end
        if CameraManager.StartFOVPulse ~= nil then
            CameraManager.StartFOVPulse("bossIntroSlam", -10.0, 0.45, 0.04, 0.25)
        end
        if CameraManager.StartVignettePulse ~= nil then
            CameraManager.StartVignettePulse("bossIntroSlam", 0.85, 0.7, 0.4, 0.6, 0.05, 0.4)
        end
    end

    -- 보스 발치 먼지 + 갈라진 바닥
    local boss = resolveBoss()
    if isValid(boss) and VFX ~= nil then
        local p = boss.Location
        local foot = Vector(p.X, p.Y, p.Z)
        if VFX.SpawnParticleSystem ~= nil then
            VFX.SpawnParticleSystem(DUST_PARTICLE, foot, Vector(0.0, 0.0, 0.0), Vector(2.5, 2.5, 2.5), 2.0)
        end
        if VFX.SpawnGroundCrackDecal ~= nil then
            VFX.SpawnGroundCrackDecal(GROUND_CRACK_MAT, foot, Vector(3.0, 3.0, 3.0), 1.2, 0.8)
        end
    end

    -- 사운드 (시네마틱 임팩트 + 저음 럼블)
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
-- WaveDirector.Tick 의 코루틴 스코프(Begin/End) 안에서 호출되어야 한다(StartCoroutine 소유권).
function BossIntroCinematic.Play(onComplete)
    slamFired = false

    StartCoroutine(function()
        -- 보스는 스폰 다음 프레임에 BeginPlay 로 등록/태깅되므로 잠깐 폴링한다(최대 ~2초).
        local boss = nil
        local waitStart = World.GetGameTime()
        while World.GetGameTime() - waitStart < 2.0 do
            boss = resolveBoss()
            if isValid(boss) then break end
            WaitFrame()
        end

        if not isValid(boss) then
            print("[BossIntro] Boss actor not found after wait; skipping cinematic.")
            if onComplete then onComplete() end
            return
        end

        print("[BossIntro] Cinematic started.")
        freezePlayer(true)

        -- 시네마틱 카메라 생성 (임시 액터 + 카메라 컴포넌트)
        local camActor = World.SpawnActor("AActor")
        if not isValid(camActor) or camActor.AddCameraComponent == nil then
            print("[BossIntro] Failed to create cinematic camera; skipping.")
            freezePlayer(false)
            if onComplete then onComplete() end
            return
        end
        local camComp = camActor:AddCameraComponent()
        if camComp == nil then
            print("[BossIntro] AddCameraComponent returned nil; skipping.")
            if isValid(camActor) and camActor.Destroy ~= nil then camActor:Destroy() end
            freezePlayer(false)
            if onComplete then onComplete() end
            return
        end

        -- ① 로우앵글: 아래에서 위로, 천천히 상승
        placeShot(camComp, boss, SHOT.Low)
        -- PossessCamera 는 ActiveCamera 를 직접 세팅하므로 런타임 카메라의 등록(BeginPlay) 타이밍과
        -- 무관하게 즉시 전환된다(ToggleOwnerCamera 는 등록된 카메라만 찾아서 갓 만든 카메라엔 실패).
        if camComp ~= nil and CameraManager ~= nil and CameraManager.PossessCamera ~= nil then
            CameraManager.PossessCamera(camComp)   -- 즉시 컷
        end
        local t0 = World.GetGameTime()
        while World.GetGameTime() - t0 < SHOT.LowTime do
            if not isValid(boss) then break end
            local rise = (World.GetGameTime() - t0) * SHOT.LowRise
            placeShot(camComp, boss, SHOT.Low, SHOT.Low.up + rise)
            WaitFrame()
        end

        -- ② 좌측 3/4 하드컷
        if isValid(boss) then placeShot(camComp, boss, SHOT.Left) end
        Wait(SHOT.LeftHold)

        -- ③ 우측 3/4 하드컷
        if isValid(boss) then placeShot(camComp, boss, SHOT.Right) end
        Wait(SHOT.RightHold)

        -- ④ 정면 로우로 빠지며 DashSlash 트리거
        if isValid(boss) then placeShot(camComp, boss, SHOT.Attack) end
        Wait(DASH_TRIGGER_DELAY)
        local bctx = CombatContext.GetBossContext and CombatContext.GetBossContext()
        if bctx ~= nil and bctx.Brain ~= nil then
            bctx.Brain.AnimAttack = "dash"   -- ConsumeAnimSignal → DashStart → DashSlash 재생
        else
            print("[BossIntro] Boss context/brain unavailable; DashSlash not triggered.")
        end

        -- 임팩트: DashSlash 시퀀스의 notify(on_boss_intro_slam)가 호출.
        -- notify 가 아직 없으면 아래 폴백이 대신 발동(중복은 slamFired 가드).
        Wait(SLAM_FALLBACK_DELAY)
        on_boss_intro_slam()

        -- ⑤ 여운
        Wait(LINGER_TIME)

        -- ⑥ 플레이어로 카메라 복귀 → 정리 → 전투 시작
        -- 플레이어 카메라는 레벨 로드 때 등록돼 있으므로 ToggleOwnerCamera 로 부드럽게 블렌드.
        local player = World.FindFirstActorByTag("Player")
        if isValid(player) and CameraManager ~= nil and CameraManager.ToggleOwnerCamera ~= nil then
            CameraManager.ToggleOwnerCamera(player, RETURN_BLEND)
        end
        Wait(RETURN_BLEND)

        -- 블렌드가 안 먹었을 경우를 대비한 보장 복귀(즉시 컷). 플레이어 카메라 컴포넌트를 직접 Possess.
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

return BossIntroCinematic
