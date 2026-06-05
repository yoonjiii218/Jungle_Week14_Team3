-- BossAction.lua
-- UpdateAI, LookAt, Chase, IdleLookAt, 패턴 선택 로직

local BossAction = {}

local ctx_ref   = nil   -- BossCharacter.lua 에서 Init 으로 주입
local Attacks   = nil   -- 순환 require 방지: Init 시점에 주입
local lastState = nil   -- 디버그: 상태 전환 시에만 로그 출력

-- 상태가 바뀔 때만 print (매 프레임 스팸 방지)
local function LogState(state, dist)
    if state ~= lastState then
        if ctx_ref.BB.DEBUG then
            print("[BossAction] STATE -> " .. state
                  .. "  dist=" .. string.format("%.2f", dist))
        end
        lastState = state
    end
end

-- ────────────────────────────────────────────
function BossAction.Init(ctx)
    ctx_ref = ctx
    Attacks = require("Boss/BossAttacks")
end

function BossAction.GetPlayerRef()
    return ctx_ref and ctx_ref.playerRef
end

-- ────────────────────────────────────────────
-- ① LookAt: 방향 벡터 → Yaw → SetActorRotation (보간)
-- bb.IsTracking == false 이면 회전 정지 (P3 TRACK_END 이후)
-- ────────────────────────────────────────────
local function LookAtPlayer(dt)
    if not ctx_ref.bb.IsTracking then return end

    local playerRef = ctx_ref.playerRef
    if not playerRef or not playerRef:IsValid() then return end

    local bossPos = ctx_ref.obj.Location
    local plrPos  = playerRef.Location

    local toPlayer = Vector(plrPos.X - bossPos.X, plrPos.Y - bossPos.Y, 0.0)
    if toPlayer:Length() < 0.001 then return end

    -- 목표 Yaw (도 단위, atan2는 라디안 반환 → 기존 코드와 동일 패턴)
    local targetYaw = math.atan2(toPlayer.Y, toPlayer.X) * 180.0 / math.pi

    -- 현재 Yaw: obj.Rotation = Vector(Roll, Pitch, Yaw), .Z = Yaw
    local currentYaw = ctx_ref.obj.Rotation.Z

    -- 각도 정규화 (-180 ~ +180)
    local diff = targetYaw - currentYaw
    while diff >  180.0 do diff = diff - 360.0 end
    while diff < -180.0 do diff = diff + 360.0 end

    -- bb.TimeScale 적용 후 clamp
    local scaledDt = dt * ctx_ref.bb.TimeScale
    local maxStep  = ctx_ref.BB.LOOK_AT_SPEED * scaledDt
    local step     = math.max(-maxStep, math.min(maxStep, diff))

    -- Vector(Roll, Pitch, Yaw) 컨벤션
    ctx_ref.obj.Rotation = Vector(0.0, 0.0, currentYaw + step)
end

-- ────────────────────────────────────────────
-- ② Chase: 플레이어 방향으로 이동 + LookAt
-- ────────────────────────────────────────────
local function Chase(dt)
    LookAtPlayer(dt)

    local playerRef = ctx_ref.playerRef
    if not playerRef or not playerRef:IsValid() then return end

    local bossPos = ctx_ref.obj.Location
    local plrPos  = playerRef.Location
    local toPlayer = Vector(plrPos.X - bossPos.X, plrPos.Y - bossPos.Y, 0.0)
    if toPlayer:Length() < 0.001 then return end

    -- AddMovementInput 은 정규화된 방향 필요 (Vector:Normalized 사용)
    Reflection.Call(ctx_ref.obj, "AddMovementInput", toPlayer:Normalized(), 1.0)
end

-- ────────────────────────────────────────────
-- Idle: 플레이어 방향만 바라보며 대기
-- ────────────────────────────────────────────
local function IdleLookAt(dt)
    LookAtPlayer(dt)
    -- TODO: Idle 애니메이션 상태 전환 (2단계에서 연결)
end

-- ────────────────────────────────────────────
-- ⑦ 패턴 선택: LastPattern 큐 + 가중치 랜덤
-- 직전 P3 → 무조건 P1 or P2 (연속 P3 방지)
-- ────────────────────────────────────────────
local function SelectPattern()
    local bb = ctx_ref.bb
    local BB = ctx_ref.BB
    local roll = math.random()

    -- 직전 패턴이 P3였으면 강제로 가벼운 패턴
    if bb.LastPattern == "P3" then
        if BB.DEBUG then print("[BossAction] P3 직후 → 강제 경량 패턴") end
        if roll < 0.5 then
            Attacks.RunPattern("P2")
        else
            Attacks.RunPattern("P1")
        end
        return
    end

    -- 일반 가중치 선택
    if bb.HeavyAttackCooldown <= 0 and roll < BB.PROB_HEAVY then
        Attacks.RunPattern("P3")
    elseif roll < BB.PROB_HEAVY + BB.PROB_DOUBLE then
        Attacks.RunPattern("P2")
    else
        Attacks.RunPattern("P1")
    end
end

-- ────────────────────────────────────────────
-- UpdateAI: 매 프레임 BossCharacter.Tick 에서 호출
-- ────────────────────────────────────────────
function BossAction.UpdateAI(dt)
    local bb = ctx_ref.bb
    local BB = ctx_ref.BB

    -- ③ 슈퍼아머: ActionLock 중에는 AI 진입 완전 차단
    if bb.ActionLock then
        LogState("ActionLock(공격중)", bb.Distance)
        return
    end

    -- 조건 1: 너무 멀면 추격
    if bb.Distance >= BB.CHASE_DISTANCE then
        LogState("Chase", bb.Distance)
        Chase(dt)
        return
    end

    -- 조건 2: 공격 가능 사거리 + 쿨타임 완료
    if bb.Distance <= BB.ATTACK_DISTANCE and bb.PatternCooldown <= 0.0 then
        LogState("Attack", bb.Distance)
        SelectPattern()
        return
    end

    -- 조건 3: 사거리 안이지만 쿨타임 중(또는 3~7 중간 거리) → Idle
    LogState("Idle", bb.Distance)
    IdleLookAt(dt)
end

return BossAction
