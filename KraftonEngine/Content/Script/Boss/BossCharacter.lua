-- BossCharacter.lua
-- ULuaScriptComponent 에 할당. 보스 액터의 실행 주체.
-- BeginPlay / Tick / EndPlay 진입점.

local BB            = require("Boss/BossBlackboard")
local Action        = require("Boss/BossAction")
local Attacks       = require("Boss/BossAttacks")
local Feedback      = require("Boss/BossFeedback")
local Hitbox        = require("Boss/BossHitbox")
local CombatContext = require("CombatContext")

-- Runtime Blackboard (매 판마다 초기화되는 가변 상태)
local bb = {}

local function InitBB()
    bb.ActionLock          = false   -- 공격 애니메이션 재생 중 여부
    bb.IsTracking          = true    -- LookAt 회전 허용 여부
    bb.PatternCooldown     = 0.0     -- 글로벌 공격 쿨타임
    bb.HeavyAttackCooldown = 0.0     -- P3 개별 쿨타임
    bb.Distance            = 999.0   -- 보스 ↔ 플레이어 수평 거리
    bb.LastPattern         = nil     -- 직전 패턴 ("P1"/"P2"/"P3")
    bb.TimeScale           = 1.0     -- ⑤ Slomo 보상용 스케일
    bb.SlomoRemaining      = 0.0     -- ⑤ Slomo 남은 시간

    -- 체력
    bb.HP     = BB.MAX_HP            -- 현재 체력
    bb.MaxHP  = BB.MAX_HP            -- 최대 체력
    bb.IsDead = false                -- 사망 여부 (한 번만 처리)

    -- 노티파이 수신 플래그 (BossAnimation.on_notify → BossAttacks 코루틴)
    bb.ZoneShow    = false
    bb.ZoneFlash   = false
    bb.ZoneHide    = false
    bb.HitboxOpen  = false
    bb.HitboxClose = false
    bb.TrackEnd    = false
    bb.ActiveZone   = nil
end

-- ────────────────────────────────────────────
function BeginPlay()
    -- 샌드박스 Lua에는 os 라이브러리가 없음.
    -- 게임 시작 후 경과 시간으로 시드 (완벽하진 않아도 deterministic 회피)
    math.randomseed((World.GetGameTime() or 0) * 1000.0 + 1.0)

    InitBB()

    -- 컨텍스트: 각 모듈이 공유하는 참조 묶음
    local ctx = {
        obj        = obj,
        bb         = bb,
        BB         = BB,
        movComp    = obj:GetCharacterMovement(),
        actionComp = obj:GetActionComponent(),
        playerRef  = nil,
    }

    -- 보스 식별용 태그 (플레이어팀이 World.FindFirstActorByTag("Boss")로 찾음)
    if not obj:HasTag("Boss") then
        obj:AddTag("Boss")
    end

    -- AnimNotifyState_AttackHitWindow 의 기본 타겟 태그가 HitTarget 인 경우도 맞도록 유지.
    if not obj:HasTag("HitTarget") then
        obj:AddTag("HitTarget")
    end

    -- 더미 or 실제 플레이어 찾기 (태그 "Player")
    ctx.playerRef = World.FindFirstActorByTag("Player")

    -- 이동 입력 활성화: AddMovementInput 이 실제 이동으로 변환되려면 필요
    -- (플레이어는 PlayerAction.lua 에서 SetMovementInputEnabled(true) 호출함)
    if ctx.movComp then
        Reflection.Call(ctx.movComp, "SetMovementInputEnabled", true)
    end

    if BB.DEBUG then
        local found = (ctx.playerRef ~= nil and ctx.playerRef:IsValid())
        print("[BossCharacter] BeginPlay - playerRef found: " .. tostring(found)
              .. " / movComp: " .. tostring(ctx.movComp ~= nil))
    end

    -- 모듈 초기화 (ctx 주입)
    Action.Init(ctx)
    Attacks.Init(ctx)
    Feedback.Init(ctx)
    Hitbox.Init(ctx)

    -- ⑥ CombatContext에 보스 등록
    CombatContext.RegisterBoss(obj, bb, BB)
end

-- ────────────────────────────────────────────
function Tick(dt)
    -- 방어 가드: BeginPlay 가 아직/제대로 안 돌았으면 bb 비어있음
    if bb.SlomoRemaining == nil then
        return
    end

    -- ⑤ Slomo 자체 추적
    -- GetActorTimeScale 미존재 → Lua에서 bb.TimeScale 직접 관리
    if bb.SlomoRemaining > 0 then
        bb.SlomoRemaining = bb.SlomoRemaining - dt
        if bb.SlomoRemaining <= 0 then
            bb.SlomoRemaining = 0.0
            bb.TimeScale      = 1.0
            if BB.DEBUG then print("[BossCharacter] Slomo 종료 @ " .. string.format("%.3f", World.GetGameTime())) end
        end
    end

    local scaledDt = dt * bb.TimeScale

    -- ④ 쿨타임 감산 (scaledDt: Slomo 중 타이머도 같이 느려짐)
    bb.PatternCooldown     = math.max(0.0, bb.PatternCooldown     - scaledDt)
    bb.HeavyAttackCooldown = math.max(0.0, bb.HeavyAttackCooldown - scaledDt)

    -- 플레이어와의 수평 거리 갱신 (Vector API 사용: math.sqrt 의존 제거)
    local playerRef = Action.GetPlayerRef()
    if playerRef and playerRef:IsValid() then
        local d = obj.Location - playerRef.Location
        d.Z = 0.0
        bb.Distance = d:Length()
    end

    -- ⑤ 코루틴도 scaledDt 전달 → Slomo 중 Wait()가 느리게 흐름
    UpdateCoroutines(scaledDt)

    -- AI 의사결정
    Action.UpdateAI(dt)
end

-- ────────────────────────────────────────────
function EndPlay()
    -- ⑥ 레벨 언로드/재시작 시 참조 정리
    CombatContext.Clear()
    if BB.DEBUG then print("[BossCharacter] EndPlay") end
end
