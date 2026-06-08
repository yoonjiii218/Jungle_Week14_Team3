-- Boss/BossAction.lua
-- Owns bossContext.Brain high-level decision transitions.
-- BossAttacks owns concrete attack timing and hit request creation.
-- Do not pass AnimInstance self as bossContext.

local BossAction = {}

local BossContext = require("Boss/BossContext")
local BossEvents = require("Boss/BossEvents")
local Strict = require("Core/Strict")

local BossAttacks = nil
local lastState = nil

local function GetBossAttacks()
    if BossAttacks == nil then
        BossAttacks = require("Boss/BossAttacks")
    end
    return BossAttacks
end

local function LogState(bossContext, state, distance)
    if state ~= lastState then
        if bossContext.Config.DEBUG then
            print("[BossAction] STATE -> " .. state .. "  dist=" .. string.format("%.2f", distance))
        end
        lastState = state
    end
end

local function LookAtPlayer(bossContext, dt)
    local brain = bossContext.Brain
    if not brain.IsTracking then return end

    local targetActor = brain.TargetActor
    if not targetActor or not targetActor:IsValid() then return end

    local ownerActor = bossContext.Owner
    local bossPos = ownerActor.Location
    local targetPos = targetActor.Location

    local toTarget = Vector(targetPos.X - bossPos.X, targetPos.Y - bossPos.Y, 0.0)
    if toTarget:Length() < 0.001 then return end

    local targetYaw = math.atan2(toTarget.Y, toTarget.X) * 180.0 / math.pi
    local currentYaw = ownerActor.Rotation.Z
    local diff = targetYaw - currentYaw
    while diff > 180.0 do diff = diff - 360.0 end
    while diff < -180.0 do diff = diff + 360.0 end

    local scaledDt = dt * brain.TimeScale
    local maxStep = bossContext.Config.LOOK_AT_SPEED * scaledDt
    local step = math.max(-maxStep, math.min(maxStep, diff))

    ownerActor.Rotation = Vector(0.0, 0.0, currentYaw + step)
end

local function Chase(bossContext, dt)
    LookAtPlayer(bossContext, dt)

    local targetActor = bossContext.Brain.TargetActor
    if not targetActor or not targetActor:IsValid() then return end

    local ownerActor = bossContext.Owner
    local bossPos = ownerActor.Location
    local targetPos = targetActor.Location
    local toTarget = Vector(targetPos.X - bossPos.X, targetPos.Y - bossPos.Y, 0.0)
    if toTarget:Length() < 0.001 then return end

    Reflection.Call(ownerActor, "AddMovementInput", toTarget:Normalized(), 1.0)
end

local function SelectPattern(bossContext)
    local brain = bossContext.Brain
    local config = bossContext.Config
    local roll = math.random()
    local attacks = GetBossAttacks()

    if brain.LastPattern == "P3" then
        if config.DEBUG then print("[BossAction] P3 cooldown pattern forced light") end
        if roll < 0.5 then
            attacks.StartAttack(bossContext, { AttackId = "P2" })
        else
            attacks.StartAttack(bossContext, { AttackId = "P1" })
        end
        return
    end

    if brain.HeavyAttackCooldown <= 0 and roll < config.PROB_HEAVY then
        attacks.StartAttack(bossContext, { AttackId = "P3" })
    elseif roll < config.PROB_HEAVY + config.PROB_DOUBLE then
        attacks.StartAttack(bossContext, { AttackId = "P2" })
    else
        attacks.StartAttack(bossContext, { AttackId = "P1" })
    end
end

-- =========================================================
-- Public API
-- =========================================================

---@param bossContext BossContext
---@return nil
function BossAction.Init(bossContext)
    BossContext.Assert(bossContext, "BossAction.Init")
    GetBossAttacks()
end

---@param bossContext BossContext
---@param dt number
---@return nil
function BossAction.Update(bossContext, dt)
    BossContext.Assert(bossContext, "BossAction.Update")
    Strict.AssertNumber(dt, "dt", "BossAction.Update")

    local brain = bossContext.Brain
    local config = bossContext.Config

    if bossContext.Combat.IsDead then
        brain.State = "Dead"
        LogState(bossContext, "Dead", brain.Distance)
        return
    end

    if brain.ActionLock then
        brain.State = "ActionLock"
        LogState(bossContext, "ActionLock", brain.Distance)
        return
    end

    if brain.Distance >= config.CHASE_DISTANCE then
        brain.State = "Chase"
        LogState(bossContext, "Chase", brain.Distance)
        Chase(bossContext, dt)
        return
    end

    if brain.Distance <= config.ATTACK_DISTANCE and brain.PatternCooldown <= 0.0 then
        brain.State = "Attack"
        LogState(bossContext, "Attack", brain.Distance)
        SelectPattern(bossContext)
        return
    end

    brain.State = "Idle"
    LogState(bossContext, "Idle", brain.Distance)
    LookAtPlayer(bossContext, dt)
end

---@param bossContext BossContext
---@param args table
---@return nil
function BossAction.RequestAttack(bossContext, args)
    BossContext.Assert(bossContext, "BossAction.RequestAttack")
    Strict.AssertTable(args, "args", "BossAction.RequestAttack")
    GetBossAttacks().StartAttack(bossContext, args)
end

---@param bossContext BossContext
---@param notifyName string
---@return nil
function BossAction.OnAnimNotify(bossContext, notifyName)
    BossContext.Assert(bossContext, "BossAction.OnAnimNotify")
    Strict.AssertString(notifyName, "notifyName", "BossAction.OnAnimNotify")

    if notifyName == "HitboxOpen" then
        GetBossAttacks().OpenHitWindow(bossContext, {})
    elseif notifyName == "HitboxClose" then
        GetBossAttacks().CloseHitWindow(bossContext, {})
    elseif notifyName == "ZoneShow" then
        bossContext.Attack.ZoneShow = true
        BossEvents.EmitAttackTelegraphStarted(bossContext, { AttackId = bossContext.Attack.CurrentAttackId })
    elseif notifyName == "ZoneFlash" then
        bossContext.Attack.ZoneFlash = true
    elseif notifyName == "ZoneHide" then
        bossContext.Attack.ZoneHide = true
    elseif notifyName == "TrackEnd" then
        bossContext.Attack.TrackEnd = true
    end
end

return BossAction
