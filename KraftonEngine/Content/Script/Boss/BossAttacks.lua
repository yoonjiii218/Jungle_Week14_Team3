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

-- 공통 판정 + CombatContext Hit Resolution.
-- Hitbox는 "닿았는가"만 판단하고, 실제 HP 감소/무적/퍼펙트 회피/슬로모는 CombatContext가 처리한다.
local function ResolveHit(tag, zone, damage, hitStopDuration)
    -- 죽은 보스의 공격은 판정 무효
    if ctx_ref.bb.IsDead then
        if ctx_ref.BB.DEBUG then print("[" .. tag .. "] 판정 무효 (보스 사망)") end
        return false
    end

    if not Hitbox.Check(zone, ctx_ref.playerRef) then
        if ctx_ref.BB.DEBUG then print("[" .. tag .. "] 빗나감 (플레이어 회피)") end
        return false
    end

    local result = CombatContext.ApplyHit({
        SourceActor = ctx_ref.obj,
        SourceTeam = "Enemy",
        TargetActor = ctx_ref.playerRef,
        TargetTeam = "Player",
        AttackId = tag,
        AttackInstanceId = tag .. "_" .. tostring(World.GetGameTime()),
        Damage = damage or 10,
        CanPerfectDodge = true,
        HitStopDuration = hitStopDuration or 0.04,
    })

    if ctx_ref.BB.DEBUG then
        if result.Applied == true then
            print("[" .. tag .. "] ★ HIT! 플레이어 데미지=" .. tostring(result.Damage))
        else
            print("[" .. tag .. "] HIT resolved as " .. tostring(result.Reason))
        end
    end

    return result.Applied == true
end

-- ────────────────────────────────────────────
-- 헬퍼: 노티파이 대기
-- 애니메이션 에셋의 노티파이가 on_notify → bb 플래그를 세울 때까지 프레임 단위 폴링.
-- timeout(초) 초과 시 경고 로그 후 반환 (에셋에 노티파이 누락됐을 때 무한 대기 방지).
-- ────────────────────────────────────────────
local function WaitForNotify(flag, timeout)
    local elapsed = 0.0
    local bb = ctx_ref.bb
    while not bb[flag] and elapsed < timeout do
        elapsed = elapsed + WaitFrame()
    end
    bb[flag] = false   -- 소비
    if elapsed >= timeout and ctx_ref.BB.DEBUG then
        print("[BossAttacks] WaitForNotify timeout: " .. flag
              .. " (" .. string.format("%.1f", timeout) .. "s)")
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

-- 패턴 → 애니메이션 신호 매핑.
-- AnimInstance(BossAnimation.lua)가 bb.AnimAttack 를 폴링해 상태머신을 구동한다.
--   kind  = "light" | "heavy" | "dash"
--   hits  = 콤보 단수 (light 1~4 / heavy 1~5)
local PATTERN_ANIM = {
    P1 = { kind = "heavy", start = 1, hits = 1 },
    P2 = { kind = "heavy", start = 2, hits = 3 },
    P3 = { kind = "light", start = 3, hits = 4 },   
}

-- ────────────────────────────────────────────
-- 헬퍼: 패턴 시작 공통 처리
-- ────────────────────────────────────────────
local function BeginPattern(name)
    local bb = ctx_ref.bb
    bb.ActionLock  = true
    bb.IsTracking  = true
    bb.LastPattern = name

    -- 애니메이션 트리거 신호 (AnimInstance 가 다음 프레임에 소비)
    local anim = PATTERN_ANIM[name]
    if anim then
        bb.AnimAttack     = anim.kind
        bb.AnimAttackStart = anim.start
        bb.AnimAttackHits = anim.hits
    end

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
-- 패턴 1: 종베기 (HeavyCombo1)
-- 좁은 직사각형 장판 → 옆으로 피해야 회피 / 피한 뒤 측면 반격 유도
-- 타이밍: HeavyCombo1 에셋의 FlashWarning → HitboxOpen 노티파이로 제어
-- ════════════════════════════════════════════
local function Pattern1_BasicSlash()
    local BB = ctx_ref.BB
    local bb = ctx_ref.bb

    BeginPattern("P1")
    PlayMontage("BossVerticalSlash")

    local zone = Feedback.ShowP1Zone(ctx_ref.playerRef)
    bb.ActiveZone = zone
    if BB.DEBUG then print("[P1] 장판 스폰, FlashWarning 대기") end

    WaitForNotify("FlashWarning", 3.0)
    Feedback.FlashZone(zone)
    if BB.DEBUG then print("[P1] FlashWarning 수신 → 번쩍임") end

    WaitForNotify("ZoneHide", 3.0)
    Feedback.HideZone(zone)
    bb.ActiveZone = nil
    if BB.DEBUG then print("[P1] ZoneHide 수신 → 장판 제거") end

    WaitForNotify("HitboxOpen", 3.0)
    if BB.DEBUG then print("[P1] HitboxOpen 수신 → 판정 창 시작") end
    local hit = false
    while not bb.HitboxClose do
        WaitFrame()
        if not hit then
            hit = ResolveHit("P1", zone, BB.P1.DAMAGE, BB.P1.HITSTOP)
        end
    end
    bb.HitboxClose = false
    if BB.DEBUG then print("[P1] HitboxClose 수신 → 판정 창 종료") end

    Wait(BB.P1.RECOVERY)
    if BB.DEBUG then print("[P1] 후딜 종료") end

    EndPattern("P1", BB.PATTERN_COOLDOWN.AFTER_P1, nil)
end

-- ════════════════════════════════════════════
-- 패턴 2: 횡베기 2연타 (HeavyCombo2 → HeavyCombo3)
-- 부채꼴 장판 ×2 → 뒤로 빠지거나 타이밍 회피 / 반격 어려움으로 압박감
-- 타이밍: 각 클립에 FlashWarning + HitboxOpen 노티파이 1쌍씩
-- ════════════════════════════════════════════
local function Pattern2_DoubleSlash()
    local BB = ctx_ref.BB
    local bb = ctx_ref.bb

    BeginPattern("P2")
    PlayMontage("BossDoubleSlash")

    -- 1타: HeavyCombo2 클립의 FlashWarning → HitboxOpen
    local zone1 = Feedback.ShowFanZone(ctx_ref.playerRef)
    bb.ActiveZone = zone1
    if BB.DEBUG then print("[P2] 1타 장판 스폰, FlashWarning 대기") end

    WaitForNotify("FlashWarning", 3.0)
    Feedback.FlashZone(zone1)

    WaitForNotify("ZoneHide", 3.0)
    Feedback.HideZone(zone1)
    if BB.DEBUG then print("[P2] 1타 ZoneHide 수신 → 장판 제거") end

    WaitForNotify("HitboxOpen", 3.0)
    local hit1 = false
    while not bb.HitboxClose do
        WaitFrame()
        if not hit1 then
            hit1 = ResolveHit("P2-1", zone1, BB.P2.DAMAGE1, BB.P2.HITSTOP)
        end
    end
    bb.HitboxClose = false
    if BB.DEBUG then print("[P2] 1타 판정 완료") end

    -- 2타: HeavyCombo3 클립의 FlashWarning → ZoneHide → HitboxOpen → HitboxClose
    -- (클립 전환 직후 장판 스폰 — HeavyCombo3 진입 시 보스가 여전히 추적 중이므로 방향 갱신됨)
    local zone2 = Feedback.ShowFanZone(ctx_ref.playerRef)
    bb.ActiveZone = zone2
    if BB.DEBUG then print("[P2] 2타 장판 스폰, FlashWarning 대기") end

    WaitForNotify("FlashWarning", 3.0)
    Feedback.FlashZone(zone2)

    WaitForNotify("ZoneHide", 3.0)
    Feedback.HideZone(zone2)
    bb.ActiveZone = nil
    if BB.DEBUG then print("[P2] 2타 ZoneHide 수신 → 장판 제거") end

    WaitForNotify("HitboxOpen", 3.0)
    local hit2 = false
    while not bb.HitboxClose do
        WaitFrame()
        if not hit2 then
            hit2 = ResolveHit("P2-2", zone2, BB.P2.DAMAGE2, BB.P2.HITSTOP)
        end
    end
    bb.HitboxClose = false
    if BB.DEBUG then print("[P2] 2타 판정 완료") end

    Wait(BB.P2.RECOVERY)
    EndPattern("P2", BB.PATTERN_COOLDOWN.AFTER_P2, nil)
end

-- ════════════════════════════════════════════
-- 패턴 3: 강한 내려찍기 (LightCombo3 → LightCombo4) ★핵심★
-- 거리 3.0 이하, 글로벌 쿨타임 완료, HeavyAttackCooldown 완료
-- 타이밍: TrackEnd(회전 멈춤) → FlashWarning(섬광) → HitboxOpen(판정) 노티파이 순서
-- ════════════════════════════════════════════
local function Pattern3_HeavySmash()
    local BB = ctx_ref.BB
    local bb = ctx_ref.bb

    BeginPattern("P3")
    PlayMontage("BossHeavySmash")

    -- 직사각형 장판 스폰 + 차오름 시작
    local zone = Feedback.ShowRectZone(ctx_ref.playerRef)
    Feedback.FillZone(zone, 0.0)
    bb.ActiveZone = zone
    if BB.DEBUG then print("[P3] 장판 스폰, 차오름 시작") end

    -- 차오름 코루틴: bb.ActiveZone이 유지되는 동안 장판을 점점 채움
    -- HitboxOpen 후 메인 코루틴에서 bb.ActiveZone = nil 로 종료
    StartCoroutine(function()
        local t = 0.0
        while bb.ActiveZone == zone do
            t = t + WaitFrame()   -- scaledDt 반환 (Slomo 보정됨)
            Feedback.FillZone(zone, math.min(t / BB.P3.FILL_DURATION, 0.99))
        end
    end)

    -- 보스 회전 멈춤 (LightCombo3 클립의 TrackEnd 노티파이)
    -- → 플레이어가 옆으로 피해 반격할 공간 보장
    WaitForNotify("TrackEnd", 3.0)
    bb.IsTracking = false
    if BB.DEBUG then print("[P3] TrackEnd 수신 → 보스 회전 멈춤") end

    -- 섬광 (회피 신호, LightCombo3 or LightCombo4 의 FlashWarning 노티파이)
    WaitForNotify("FlashWarning", 3.0)
    Feedback.FlashZone(zone)
    if BB.DEBUG then print("[P3] FlashWarning 수신 → 섬광") end

    -- 장판 제거 (판정 전에 사라짐 — ZoneHide 노티파이)
    WaitForNotify("ZoneHide", 3.0)
    Feedback.HideZone(zone)
    bb.ActiveZone = nil   -- 차오름 코루틴 종료 트리거
    if BB.DEBUG then print("[P3] ZoneHide 수신 → 장판 제거") end

    -- 판정 창 (HitboxOpen ~ HitboxClose)
    WaitForNotify("HitboxOpen", 3.0)
    if BB.DEBUG then print("[P3] HitboxOpen 수신 → 판정 창 시작") end
    local hit = false
    while not bb.HitboxClose do
        WaitFrame()
        if not hit then
            hit = ResolveHit("P3", zone, BB.P3.DAMAGE, BB.P3.HITSTOP)
        end
    end
    bb.HitboxClose = false
    if BB.DEBUG then print("[P3] HitboxClose 수신 → 판정 창 종료") end

    -- 긴 후딜: 이 구간이 플레이어 발도 대시/폭딜 타임
    Wait(BB.P3.RECOVERY)
    if BB.DEBUG then print("[P3] 후딜 종료") end

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
