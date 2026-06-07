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

    local anim = PATTERN_ANIM[attackId]
    if anim then
        brain.AnimAttack = anim.kind
        brain.AnimAttackStart = anim.start
        brain.AnimAttackHits = anim.hits
    end

    if bossContext.Runtime.MovementComp then
        bossContext.Runtime.MovementComp:StopMovementImmediately()
    end

    BossEvents.EmitAttackStarted(bossContext, { AttackId = attackId })

    if bossContext.Config.DEBUG then
        print("[BossAttacks] -- " .. attackId .. " START -- @ "
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

    WaitForNotify(bossContext, "ZoneShow", 3.0)
    local zone = BossFeedback.ShowAttackZone(bossContext, { AttackId = "P1", Shape = "P1" })
    attackState.ActiveZone = zone
    table.insert(attackState.ActiveZones, zone)

    WaitForNotify(bossContext, "ZoneFlash", 3.0)
    BossFeedback.FlashZone(bossContext, zone)

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

    Wait(config.P1.RECOVERY)
    EndPattern(bossContext, "P1", config.PATTERN_COOLDOWN.AFTER_P1, nil)
end

local function Pattern2(bossContext)
    local config = bossContext.Config
    local attackState = bossContext.Attack

    BeginPattern(bossContext, "P2")

    WaitForNotify(bossContext, "ZoneShow", 3.0)
    local zone1 = BossFeedback.ShowAttackZone(bossContext, { AttackId = "P2-1", Shape = "Fan" })
    attackState.ActiveZone = zone1
    table.insert(attackState.ActiveZones, zone1)

    WaitForNotify(bossContext, "ZoneFlash", 3.0)
    BossFeedback.FlashZone(bossContext, zone1)

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

    local zone2 = BossFeedback.ShowAttackZone(bossContext, { AttackId = "P2-2", Shape = "Fan" })
    attackState.ActiveZone = zone2
    table.insert(attackState.ActiveZones, zone2)

    WaitForNotify(bossContext, "ZoneFlash", 3.0)
    BossFeedback.FlashZone(bossContext, zone2)

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

    Wait(config.P2.RECOVERY)
    EndPattern(bossContext, "P2", config.PATTERN_COOLDOWN.AFTER_P2, nil)
end

local function Pattern3(bossContext)
    local config = bossContext.Config
    local attackState = bossContext.Attack

    BeginPattern(bossContext, "P3")

    WaitForNotify(bossContext, "ZoneShow", 3.0)
    local zone = BossFeedback.ShowAttackZone(bossContext, { AttackId = "P3", Shape = "Rect" })
    BossFeedback.FillZone(bossContext, zone, 0.0)
    attackState.ActiveZone = zone
    table.insert(attackState.ActiveZones, zone)

    StartCoroutine(function()
        local t = 0.0
        while attackState.ActiveZone == zone do
            t = t + WaitFrame()
            BossFeedback.FillZone(bossContext, zone, math.min(t / config.P3.FILL_DURATION, 0.99))
        end
    end)

    WaitForNotify(bossContext, "TrackEnd", 3.0)
    bossContext.Brain.IsTracking = false

    WaitForNotify(bossContext, "ZoneFlash", 3.0)
    BossFeedback.FlashZone(bossContext, zone)

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
