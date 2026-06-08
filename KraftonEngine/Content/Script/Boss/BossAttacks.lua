-- Boss/BossAttacks.lua
-- Owns bossContext.Attack pattern timing, attack zones, and HitRequest creation.
-- BossFeedback displays zones only; it does not own damage or hitbox policy.

local BossAttacks = {}

local BossContext = require("Boss/BossContext")
local BossEvents = require("Boss/BossEvents")
local HitTypes = require("Combat/HitTypes")
local Strict = require("Core/Strict")

local CombatContext = nil
local BossFeedback = nil
local BossHitbox = nil

local PATTERN_ANIM = {
    P1 = { kind = "heavy", start = 1, hits = 1 },
    P2 = { kind = "heavy", start = 2, hits = 3 },
    P3 = { kind = "light", start = 3, hits = 4 },
}

local function LoadDeferredModules()
    if CombatContext == nil then CombatContext = require("Combat/CombatContext") end
    if BossFeedback == nil then BossFeedback = require("Boss/BossFeedback") end
    if BossHitbox == nil then BossHitbox = require("Boss/BossHitbox") end
end

local function WaitForNotify(bossContext, flag, timeout)
    local elapsed = 0.0
    local attackState = bossContext.Attack
    while not attackState[flag] and elapsed < timeout do
        elapsed = elapsed + WaitFrame()
    end
    attackState[flag] = false
    if elapsed >= timeout and bossContext.Config.DEBUG then
        print("[BossAttacks] WaitForNotify timeout: " .. flag
            .. " (" .. string.format("%.1f", timeout) .. "s)")
    end
end

-- 공격이 실제로 시작(swing)된 뒤 ZoneFlash 노티파이가 뜰 때까지의 간격(초). PLAY_RATE = 1.0 기준 실측값.
-- 장판 채움 지속시간 = BB.ZONE_LEAD(리드 타임) + 이 값 으로 잡아서, flash 순간에 장판이 딱 다 차게 한다.
--   - P1/P2-1/P3 : TriggerPatternAnim(swing 시작) → ZoneFlash 간격
--   - P2-2       : 콤보 중 2타 장판 spawn → ZoneFlash 간격 (별도 리드 타임 없음)
-- 아래 로그([BossAttacks] fill~ZoneFlash)가 찍는 값을 그대로 복붙하면 된다(play rate 1.0 기준으로 환산해 출력).
local FILL_DURATION = {
    P1 = 0.149,
    ["P2-1"] = 0.141,
    ["P2-2"] = 0.812,
    P3 = 0.739,
}

-- 실측값을 만든 콤보 단(애니 클립). BossBlackboard.ANIM 의 play rate 가 바뀌면
-- 노티파이가 실제로 불리는 시점도 그만큼(1 / playRate) 늦춰지므로, 차오름 연출도 같이 보정해야
-- "장판이 다 찬 뒤에야 ZoneFlash 가 도착" 하는 불일치가 생기지 않는다.
local FILL_DURATION_STAGE = {
    P1        = { kind = "heavy", index = 1 },
    ["P2-1"]  = { kind = "heavy", index = 2 },
    ["P2-2"]  = { kind = "heavy", index = 3 },
    P3        = { kind = "light", index = 3 },
}

-- attackId 가 재생되는 콤보 단의 현재 play rate (표에 없으면 DEFAULT_PLAY_RATE).
local function GetStagePlayRate(bossContext, attackId)
    local animConfig = bossContext.Config.ANIM or {}
    local rate = animConfig.DEFAULT_PLAY_RATE or 1.0
    local stage = FILL_DURATION_STAGE[attackId]
    if stage then
        local rates = (stage.kind == "heavy") and animConfig.HEAVY_PLAY_RATES or animConfig.LIGHT_PLAY_RATES
        if rates and rates[stage.index] ~= nil then
            rate = rates[stage.index]
        end
    end
    return rate
end

-- 실제 채움~ZoneFlash 간격을 로그로 확인해 FILL_DURATION 을 맞추기 위한 디버그 출력.
-- 실측은 현재 play rate 로 느려진 실제 시간이므로, FILL_DURATION 에 그대로 복붙할 수 있도록
-- play rate 1.0 기준값(= 실측 × rate)으로 환산해 찍는다.
local function LogZoneFillSpan(bossContext, attackId, sinceTime)
    if not bossContext.Config.DEBUG then return end
    local elapsed = (World.GetGameTime() or 0.0) - sinceTime
    local rate = GetStagePlayRate(bossContext, attackId)
    print("[BossAttacks] fill~ZoneFlash: " .. attackId
        .. " = " .. string.format("%.3f", elapsed * rate) .. "s  ← FILL_DURATION 에 입력"
        .. "  (실측 " .. string.format("%.3f", elapsed) .. "s @ rate " .. string.format("%.2f", rate) .. ")")
end

-- attackId 의 실측 FILL_DURATION 을 현재 BossBlackboard.ANIM play rate 기준으로 보정한다.
-- (저장값은 play rate 1.0 기준: 실제 간격 = 저장값 / 현재 play rate)
local function GetFillDuration(bossContext, attackId)
    local base = FILL_DURATION[attackId]
    if base == nil then return nil end
    local rate = GetStagePlayRate(bossContext, attackId)
    if rate == nil or rate <= 0 then return base end
    return base / rate
end

local function RunZoneFill(bossContext, zone, fillDuration)
    local attackState = bossContext.Attack
    local duration = fillDuration
    StartCoroutine(function()
        local t = 0.0
        while attackState.ActiveZone == zone do
            t = t + WaitFrame()
            BossFeedback.FillZone(bossContext, zone, math.min(t / duration, 0.99))
        end
    end)
end

local function BeginPattern(bossContext, attackId)
    local brain = bossContext.Brain
    local attackState = bossContext.Attack

    brain.ActionLock = true
    brain.IsTracking = true
    brain.LastPattern = attackId

    attackState.CurrentAttackId = attackId
    attackState.CurrentPhase = "Startup"
    attackState.AttackStartedAt = World.GetGameTime() or 0.0
    attackState.HitWindowOpen = false
    attackState.ActiveZones = {}

    if bossContext.Runtime.MovementComp then
        bossContext.Runtime.MovementComp:StopMovementImmediately()
    end

    BossEvents.EmitAttackStarted(bossContext, { AttackId = attackId })

    if bossContext.Config.DEBUG then
        print("[BossAttacks] -- " .. attackId .. " START -- @ "
            .. string.format("%.3f", World.GetGameTime()))
    end
end

-- 준비 모션(AttackPrep) 제거에 따른 분리: BeginPattern 은 락/장판 셋업만 하고,
-- 실제 공격 애니는 장판 리드 타임이 끝난 뒤 이 함수로 트리거한다.
-- (이 신호를 BossAnimation.ConsumeAnimSignal 이 받아 Locomotion → 콤보로 직접 진입시킨다)
local function TriggerPatternAnim(bossContext, attackId)
    local brain = bossContext.Brain
    local anim = PATTERN_ANIM[attackId]
    if anim then
        brain.AnimAttack = anim.kind
        brain.AnimAttackStart = anim.start
        brain.AnimAttackHits = anim.hits
    end

    if bossContext.Config.DEBUG then
        print("[BossAttacks] -- " .. attackId .. " SWING -- @ "
            .. string.format("%.3f", World.GetGameTime()))
    end
end

local function EndPattern(bossContext, attackId, patternCooldown, heavyCooldown)
    local brain = bossContext.Brain
    local attackState = bossContext.Attack

    brain.PatternCooldown = patternCooldown
    if heavyCooldown ~= nil then
        brain.HeavyAttackCooldown = heavyCooldown
    end
    brain.IsTracking = true
    brain.ActionLock = false

    attackState.CurrentPhase = "Recovery"
    attackState.HitWindowOpen = false
    attackState.ActiveZone = nil
    attackState.ActiveZones = {}

    BossEvents.EmitAttackEnded(bossContext, { AttackId = attackId })

    if bossContext.Config.DEBUG then
        print("[BossAttacks] -- " .. attackId .. " END -- PatternCD="
            .. string.format("%.1f", brain.PatternCooldown)
            .. " @ " .. string.format("%.3f", World.GetGameTime()))
    end
end

local function ResolveHit(bossContext, attackId, zone, damage, hitStopDuration)
    LoadDeferredModules()

    if bossContext.Combat.IsDead then
        if bossContext.Config.DEBUG then print("[" .. attackId .. "] skipped because boss is dead") end
        return false
    end

    local targetActor = bossContext.Brain.TargetActor
    if not BossHitbox.Check(bossContext, zone, targetActor) then
        local dodging, dodgeLoc = CombatContext.GetPlayerDodgeSnapshot(targetActor)
        local startedInZone = dodging and dodgeLoc ~= nil
            and BossHitbox.CheckXY(bossContext, zone, dodgeLoc.X, dodgeLoc.Y)
        if not startedInZone then
            if bossContext.Config.DEBUG then
                print(string.format("[%s] missed (outside zone), dodge=%s", attackId, tostring(dodging)))
            end
            return false
        end
    end

    local hitRequest = BossAttacks.CreateHitRequest(bossContext, {
        AttackId = attackId,
        TargetActor = targetActor,
        Damage = damage,
        CanPerfectDodge = true,
        HitStopDuration = hitStopDuration,
    })

    local hitResult = CombatContext.ApplyHit(hitRequest)

    if bossContext.Config.DEBUG then
        if hitResult.Applied == true then
            print("[" .. attackId .. "] HIT damage=" .. tostring(hitResult.Damage))
        else
            print("[" .. attackId .. "] HIT resolved as " .. tostring(hitResult.Reason))
        end
    end

    return hitResult.Applied == true or hitResult.Reason == "PerfectDodge"
end

local function Pattern1(bossContext)
    local config = bossContext.Config
    local attackState = bossContext.Attack

    BeginPattern(bossContext, "P1")

    -- 준비 모션 대체: 장판을 먼저 띄우고 리드 타임 동안 차오르게 한 뒤 공격을 시작한다.
    local zone = BossFeedback.ShowAttackZone(bossContext, { AttackId = "P1", Shape = "P1" })
    BossFeedback.FillZone(bossContext, zone, 0.0)
    attackState.ActiveZone = zone
    table.insert(attackState.ActiveZones, zone)
    local lead = config.ZONE_LEAD.P1
    RunZoneFill(bossContext, zone, lead + (GetFillDuration(bossContext, "P1") or 0))
    Wait(lead)

    TriggerPatternAnim(bossContext, "P1")
    local swingAt = World.GetGameTime() or 0.0

    WaitForNotify(bossContext, "ZoneFlash", 3.0)
    LogZoneFillSpan(bossContext, "P1", swingAt)
    BossFeedback.FillZone(bossContext, zone, 1.0)

    WaitForNotify(bossContext, "ZoneHide", 3.0)
    BossFeedback.HideAttackZone(bossContext, { Zone = zone })
    attackState.ActiveZone = nil

    WaitForNotify(bossContext, "HitboxOpen", 3.0)
    BossAttacks.OpenHitWindow(bossContext, { AttackId = "P1" })
    local hitResolved = false
    while not attackState.HitboxClose do
        WaitFrame()
        if not hitResolved then
            hitResolved = ResolveHit(bossContext, "P1", zone, config.P1.DAMAGE, config.P1.HITSTOP)
        end
    end
    BossAttacks.CloseHitWindow(bossContext, { AttackId = "P1" })

    -- 후딜(반격 타임): 슈퍼아머를 풀어 이 구간 피격에는 모션이 나오게 한다. (IsBossAttacking 참조)
    attackState.CurrentPhase = "Recovery"
    Wait(config.P1.RECOVERY)
    EndPattern(bossContext, "P1", config.PATTERN_COOLDOWN.AFTER_P1, nil)
end

local function Pattern2(bossContext)
    local config = bossContext.Config
    local attackState = bossContext.Attack

    BeginPattern(bossContext, "P2")

    -- 준비 모션 대체: 1타 장판을 먼저 띄우고 리드 타임 동안 차오르게 한 뒤 공격을 시작한다.
    local zone1 = BossFeedback.ShowAttackZone(bossContext, { AttackId = "P2-1", Shape = "Fan" })
    BossFeedback.FillZone(bossContext, zone1, 0.0)
    attackState.ActiveZone = zone1
    table.insert(attackState.ActiveZones, zone1)
    local lead = config.ZONE_LEAD.P2
    RunZoneFill(bossContext, zone1, lead + (GetFillDuration(bossContext, "P2-1") or 0))
    Wait(lead)

    TriggerPatternAnim(bossContext, "P2")
    local swingAt = World.GetGameTime() or 0.0

    WaitForNotify(bossContext, "ZoneFlash", 3.0)
    LogZoneFillSpan(bossContext, "P2-1", swingAt)
    BossFeedback.FillZone(bossContext, zone1, 1.0)

    WaitForNotify(bossContext, "ZoneHide", 3.0)
    BossFeedback.HideAttackZone(bossContext, { Zone = zone1 })

    WaitForNotify(bossContext, "HitboxOpen", 3.0)
    BossAttacks.OpenHitWindow(bossContext, { AttackId = "P2-1" })
    local hit1 = false
    while not attackState.HitboxClose do
        WaitFrame()
        if not hit1 then
            hit1 = ResolveHit(bossContext, "P2-1", zone1, config.P2.DAMAGE1, config.P2.HITSTOP)
        end
    end
    BossAttacks.CloseHitWindow(bossContext, { AttackId = "P2-1" })

    if (config.P2.HIT_GAP or 0) > 0 then
        Wait(config.P2.HIT_GAP)
    end

    local zone2ShowAt = World.GetGameTime() or 0.0
    local zone2 = BossFeedback.ShowAttackZone(bossContext, { AttackId = "P2-2", Shape = "Fan" })
    BossFeedback.FillZone(bossContext, zone2, 0.0)
    attackState.ActiveZone = zone2
    table.insert(attackState.ActiveZones, zone2)
    RunZoneFill(bossContext, zone2, GetFillDuration(bossContext, "P2-2"))

    WaitForNotify(bossContext, "ZoneFlash", 3.0)
    LogZoneFillSpan(bossContext, "P2-2", zone2ShowAt)
    BossFeedback.FillZone(bossContext, zone2, 1.0)

    WaitForNotify(bossContext, "ZoneHide", 3.0)
    BossFeedback.HideAttackZone(bossContext, { Zone = zone2 })
    attackState.ActiveZone = nil

    WaitForNotify(bossContext, "HitboxOpen", 3.0)
    BossAttacks.OpenHitWindow(bossContext, { AttackId = "P2-2" })
    local hit2 = false
    while not attackState.HitboxClose do
        WaitFrame()
        if not hit2 then
            hit2 = ResolveHit(bossContext, "P2-2", zone2, config.P2.DAMAGE2, config.P2.HITSTOP)
        end
    end
    BossAttacks.CloseHitWindow(bossContext, { AttackId = "P2-2" })

    -- 후딜(반격 타임): 슈퍼아머를 풀어 이 구간 피격에는 모션이 나오게 한다. (IsBossAttacking 참조)
    attackState.CurrentPhase = "Recovery"
    Wait(config.P2.RECOVERY)
    EndPattern(bossContext, "P2", config.PATTERN_COOLDOWN.AFTER_P2, nil)
end

local function Pattern3(bossContext)
    local config = bossContext.Config
    local attackState = bossContext.Attack

    BeginPattern(bossContext, "P3")

    -- 준비 모션 대체: 장판을 먼저 띄우고 리드 타임 동안 차오르게 한 뒤 공격을 시작한다.
    local zone = BossFeedback.ShowAttackZone(bossContext, { AttackId = "P3", Shape = "Rect" })
    BossFeedback.FillZone(bossContext, zone, 0.0)
    attackState.ActiveZone = zone
    table.insert(attackState.ActiveZones, zone)
    local lead = config.ZONE_LEAD.P3
    RunZoneFill(bossContext, zone, lead + (GetFillDuration(bossContext, "P3") or 0))
    Wait(lead)

    TriggerPatternAnim(bossContext, "P3")
    local swingAt = World.GetGameTime() or 0.0

    WaitForNotify(bossContext, "TrackEnd", 3.0)
    bossContext.Brain.IsTracking = false

    WaitForNotify(bossContext, "ZoneFlash", 3.0)
    LogZoneFillSpan(bossContext, "P3", swingAt)
    BossFeedback.FillZone(bossContext, zone, 1.0)

    WaitForNotify(bossContext, "ZoneHide", 3.0)
    BossFeedback.HideAttackZone(bossContext, { Zone = zone })
    attackState.ActiveZone = nil

    WaitForNotify(bossContext, "HitboxOpen", 3.0)
    BossAttacks.OpenHitWindow(bossContext, { AttackId = "P3" })
    local hitResolved = false
    while not attackState.HitboxClose do
        WaitFrame()
        if not hitResolved then
            hitResolved = ResolveHit(bossContext, "P3", zone, config.P3.DAMAGE, config.P3.HITSTOP)
        end
    end
    BossAttacks.CloseHitWindow(bossContext, { AttackId = "P3" })

    -- 후딜(반격 타임): 슈퍼아머를 풀어 이 구간 피격에는 모션이 나오게 한다. (IsBossAttacking 참조)
    attackState.CurrentPhase = "Recovery"
    Wait(config.P3.RECOVERY)
    EndPattern(bossContext, "P3", config.PATTERN_COOLDOWN.AFTER_P3, config.HEAVY_ATTACK_COOLDOWN)
end

-- =========================================================
-- Public API
-- =========================================================

---@param bossContext BossContext
---@return nil
function BossAttacks.Init(bossContext)
    BossContext.Assert(bossContext, "BossAttacks.Init")
    LoadDeferredModules()
end

---@param bossContext BossContext
---@param dt number
---@return nil
function BossAttacks.Update(bossContext, dt)
    BossContext.Assert(bossContext, "BossAttacks.Update")
    Strict.AssertNumber(dt, "dt", "BossAttacks.Update")
end

---@param bossContext BossContext
---@param args table
---@return nil
function BossAttacks.StartAttack(bossContext, args)
    BossContext.Assert(bossContext, "BossAttacks.StartAttack")
    Strict.AssertTable(args, "args", "BossAttacks.StartAttack")
    Strict.AssertString(args.AttackId, "args.AttackId", "BossAttacks.StartAttack")
    LoadDeferredModules()

    if args.AttackId == "P1" then
        StartCoroutine(function() Pattern1(bossContext) end)
    elseif args.AttackId == "P2" then
        StartCoroutine(function() Pattern2(bossContext) end)
    elseif args.AttackId == "P3" then
        StartCoroutine(function() Pattern3(bossContext) end)
    else
        error("[BossAttacks.StartAttack] unknown AttackId: " .. tostring(args.AttackId))
    end
end

---@param bossContext BossContext
---@param args table
---@return nil
function BossAttacks.OpenHitWindow(bossContext, args)
    BossContext.Assert(bossContext, "BossAttacks.OpenHitWindow")
    args = args or {}
    bossContext.Attack.HitWindowOpen = true
    bossContext.Attack.HitboxOpen = true
    bossContext.Attack.HitboxClose = false
    BossEvents.EmitAttackHitWindowOpened(bossContext, { AttackId = args.AttackId or bossContext.Attack.CurrentAttackId })
end

---@param bossContext BossContext
---@param args table
---@return nil
function BossAttacks.CloseHitWindow(bossContext, args)
    BossContext.Assert(bossContext, "BossAttacks.CloseHitWindow")
    args = args or {}
    bossContext.Attack.HitWindowOpen = false
    bossContext.Attack.HitboxOpen = false
    bossContext.Attack.HitboxClose = false
    BossEvents.EmitAttackHitWindowClosed(bossContext, { AttackId = args.AttackId or bossContext.Attack.CurrentAttackId })
end

---@param bossContext BossContext
---@param args table
---@return HitRequest
function BossAttacks.CreateHitRequest(bossContext, args)
    BossContext.Assert(bossContext, "BossAttacks.CreateHitRequest")
    Strict.AssertTable(args, "args", "BossAttacks.CreateHitRequest")
    Strict.AssertString(args.AttackId, "args.AttackId", "BossAttacks.CreateHitRequest")

    return HitTypes.CreateBossAttack({
        SourceActor = bossContext.Owner,
        TargetActor = args.TargetActor,
        AttackId = args.AttackId,
        AttackInstanceId = args.AttackInstanceId
            or (args.AttackId .. "_" .. tostring(World.GetGameTime())),
        Damage = args.Damage,
        CanPerfectDodge = args.CanPerfectDodge,
        HitStopDuration = args.HitStopDuration,
    })
end

return BossAttacks
