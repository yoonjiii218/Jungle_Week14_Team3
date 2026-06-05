-- BossAttacks.lua
-- 패턴 1/2/3 코루틴 정의
-- 핵심 원칙: ActionLock 이 전체 애니메이션(후딜 포함)을 커버하고 마지막에 해제

local BossAttacks = {}

local ctx_ref       = nil   -- BossCharacter.lua 에서 Init 으로 주입
local CombatContext = nil   -- 순환 require 방지: Init 시점에 로드
local Feedback      = nil   -- 순환 require 방지: Init 시점에 로드
local Hitbox        = nil   -- 순환 require 방지: Init 시점에 로드

-- ────────────────────────────────────────────
function BossAttacks.Init(ctx)
    ctx_ref       = ctx
    CombatContext = require("CombatContext")
    Feedback      = require("Boss/BossFeedback")
    Hitbox        = require("Boss/BossHitbox")
end

-- 공통 판정 + 로그 (1단계: print 만, 데미지 없음)
local function ResolveHit(tag, zone)
    -- 죽은 보스의 공격은 판정 무효
    if ctx_ref.bb.IsDead then
        if ctx_ref.BB.DEBUG then print("[" .. tag .. "] 판정 무효 (보스 사망)") end
        return false
    end

    if Hitbox.Check(zone, ctx_ref.playerRef) then
        if ctx_ref.BB.DEBUG then print("[" .. tag .. "] ★ HIT! 플레이어 맞음") end
        return true
    else
        if ctx_ref.BB.DEBUG then print("[" .. tag .. "] 빗나감 (플레이어 회피)") end
        return false
    end
end

-- ────────────────────────────────────────────
-- 헬퍼: 몽타주 재생
-- 1단계: print 로그만, 2단계에서 실제 AnimInstance 연결
-- ────────────────────────────────────────────
local function PlayMontage(name)
    if ctx_ref.BB.DEBUG then
        print("[BossAttacks] PlayMontage=" .. name
              .. " @ " .. string.format("%.3f", World.GetGameTime()))
    end
    -- TODO (2단계): Reflection.Call(animInstance, "PlayMontage", asset)
end

-- ────────────────────────────────────────────
-- 헬퍼: 패턴 시작 공통 처리
-- ────────────────────────────────────────────
local function BeginPattern(name)
    local bb = ctx_ref.bb
    bb.ActionLock  = true
    bb.IsTracking  = true   -- 공격 시작 시 추적 켬 (P3는 중간에 끔)
    bb.LastPattern = name

    -- 이동 정지 (공격 중 미끄러짐 방지)
    if ctx_ref.movComp then
        ctx_ref.movComp:StopMovementImmediately()
    end

    if ctx_ref.BB.DEBUG then
        print("[BossAttacks] ── " .. name .. " START ──"
              .. " @ " .. string.format("%.3f", World.GetGameTime()))
    end
end

-- ────────────────────────────────────────────
-- 헬퍼: 패턴 종료 공통 처리
-- ④ ActionLock 은 이 함수에서만 해제 (후딜 Wait 완료 후)
-- ────────────────────────────────────────────
local function EndPattern(name, patternCooldown, heavyCooldown)
    local bb = ctx_ref.bb
    local BB = ctx_ref.BB

    bb.PatternCooldown = patternCooldown or 0.0
    if heavyCooldown then
        bb.HeavyAttackCooldown = heavyCooldown
    end
    bb.IsTracking = true
    bb.ActionLock = false   -- ← 반드시 마지막에 해제

    if BB.DEBUG then
        print("[BossAttacks] ── " .. name .. " END ──"
              .. " PatternCD=" .. string.format("%.1f", bb.PatternCooldown)
              .. " @ " .. string.format("%.3f", World.GetGameTime()))
    end
end

-- ════════════════════════════════════════════
-- 패턴 1: 기본 베기 (총 1.0초)
-- 거리 3.0 이하, 글로벌 쿨타임 완료
-- ════════════════════════════════════════════
local function Pattern1_BasicSlash()
    local BB = ctx_ref.BB

    BeginPattern("P1")
    PlayMontage("BossSlash1")

    -- 0.0초: 보스 정지. 부채꼴 빨간 장판 스폰
    local zone = Feedback.ShowFanZone(ctx_ref.playerRef)
    if BB.DEBUG then print("[P1] 0.0s  부채꼴 장판 스폰") end

    -- 0.4초: 장판 번쩍임 (회피 타이밍 가이드)
    Wait(BB.P1.WINDUP)
    Feedback.FlashZone(zone)
    if BB.DEBUG then print("[P1] " .. BB.P1.WINDUP .. "s  장판 번쩍임") end

    -- 0.5초: 데미지 판정 (플레이어 위치 ∈ 부채꼴?) + 장판 제거
    Wait(BB.P1.HIT - BB.P1.WINDUP)
    ResolveHit("P1", zone)
    Feedback.HideZone(zone)
    if BB.DEBUG then print("[P1] " .. BB.P1.HIT .. "s  판정 완료 + 장판 제거") end

    -- ④ 후딜 Wait: ActionLock 이 이 구간 동안 유지됨 (플레이어 반격 타임)
    Wait(BB.P1.TOTAL - BB.P1.HIT)
    if BB.DEBUG then print("[P1] " .. BB.P1.TOTAL .. "s  후딜 종료") end

    EndPattern("P1", BB.PATTERN_COOLDOWN.AFTER_P1, nil)
end

-- ════════════════════════════════════════════
-- 패턴 2: 2연속 베기 (총 1.8초)
-- 거리 3.0 이하, 글로벌 쿨타임 완료
-- ════════════════════════════════════════════
local function Pattern2_DoubleSlash()
    local BB = ctx_ref.BB

    BeginPattern("P2")
    PlayMontage("BossDoubleSlash")

    -- 0.0초: 1타 가로 예고선 스폰
    local zone1 = Feedback.ShowSlashLine(ctx_ref.playerRef)
    if BB.DEBUG then print("[P2] 0.0s  1타 가로 예고선") end

    -- 0.4초: 1타 판정 + 제거
    Wait(BB.P2.HIT1)
    ResolveHit("P2-1", zone1)
    Feedback.HideZone(zone1)
    if BB.DEBUG then print("[P2] " .. BB.P2.HIT1 .. "s  1타 판정") end

    -- 0.5초: 2타 가로 예고선 스폰 (반대 방향 꺾음)
    Wait(BB.P2.SECOND_WIND - BB.P2.HIT1)
    local zone2 = Feedback.ShowSlashLine(ctx_ref.playerRef)
    if BB.DEBUG then print("[P2] " .. BB.P2.SECOND_WIND .. "s  2타 가로 예고선") end

    -- 0.9초: 2타 판정 + 제거
    Wait(BB.P2.HIT2 - BB.P2.SECOND_WIND)
    ResolveHit("P2-2", zone2)
    Feedback.HideZone(zone2)
    if BB.DEBUG then print("[P2] " .. BB.P2.HIT2 .. "s  2타 판정") end

    -- ④ 후딜 Wait
    Wait(BB.P2.TOTAL - BB.P2.HIT2)

    EndPattern("P2", BB.PATTERN_COOLDOWN.AFTER_P2, nil)
end

-- ════════════════════════════════════════════
-- 패턴 3: 강한 내려찍기 (총 3.0초) ★핵심★
-- 거리 3.0 이하, 글로벌 쿨타임 완료, HeavyAttackCooldown 완료
-- ════════════════════════════════════════════
local function Pattern3_HeavySmash()
    local BB = ctx_ref.BB
    local bb = ctx_ref.bb

    BeginPattern("P3")
    PlayMontage("BossHeavySmash")

    -- 0.0초: 직사각형 장판 스폰 (플레이어 방향 정렬)
    local zone = Feedback.ShowRectZone(ctx_ref.playerRef)
    if BB.DEBUG then print("[P3] 0.0s  직사각형 장판 스폰") end

    -- 0.8초: 추적 멈춤 → 장판 위치 고정
    -- (플레이어가 옆으로 피해 반격할 공간 보장)
    Wait(BB.P3.TRACK_END)
    bb.IsTracking = false
    Feedback.LockZone(zone)
    if BB.DEBUG then print("[P3] " .. BB.P3.TRACK_END .. "s  추적 멈춤 (IsTracking=false)") end

    -- 1.2초: 붉은 섬광 + 날카로운 사운드 (퍼펙트 회피 신호)
    --        퍼펙트 회피 윈도우 오픈
    Wait(BB.P3.FLASH - BB.P3.TRACK_END)
    CombatContext.BeginPerfectDodgeWindow(BB.P3.PERFECT_WINDOW)
    Feedback.FlashZone(zone)
    if BB.DEBUG then
        print("[P3] " .. BB.P3.FLASH .. "s  섬광 + 퍼펙트 회피 윈도우 OPEN ("
              .. BB.P3.PERFECT_WINDOW .. "s)")
    end

    -- 1.4초: 데미지 판정 (플레이어 위치 ∈ 직사각형?) + 장판 제거
    --        (2단계에서 퍼펙트 회피 무효화 연동 예정)
    Wait(BB.P3.HIT - BB.P3.FLASH)
    ResolveHit("P3", zone)
    Feedback.HideZone(zone)
    if BB.DEBUG then print("[P3] " .. BB.P3.HIT .. "s  판정 완료 + 카메라 흔들림") end

    -- ④ 긴 후딜 Wait: ActionLock 이 3.0초까지 유지
    --    이 구간이 플레이어의 발도 대시/폭딜 타임
    Wait(BB.P3.TOTAL - BB.P3.HIT)
    if BB.DEBUG then print("[P3] " .. BB.P3.TOTAL .. "s  후딜 종료") end

    EndPattern("P3", BB.PATTERN_COOLDOWN.AFTER_P3, BB.HEAVY_ATTACK_COOLDOWN)
end

-- ────────────────────────────────────────────
-- 외부 인터페이스: BossAction.SelectPattern 에서 호출
-- ────────────────────────────────────────────
function BossAttacks.RunPattern(name)
    if name == "P1" then
        StartCoroutine(Pattern1_BasicSlash)
    elseif name == "P2" then
        StartCoroutine(Pattern2_DoubleSlash)
    elseif name == "P3" then
        StartCoroutine(Pattern3_HeavySmash)
    else
        print("[BossAttacks] 알 수 없는 패턴: " .. tostring(name))
    end
end

return BossAttacks
