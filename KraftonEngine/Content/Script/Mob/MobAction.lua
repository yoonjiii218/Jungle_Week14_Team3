-- Mob/MobAction.lua
-- Owns mobContext.Brain high-level decision transitions (lightweight FSM).
-- MobAttacks owns concrete attack timing and hit resolution.
-- Do not pass AnimInstance self as mobContext.

local MobAction = {}

local MobContext = require("Mob/MobContext")
local MobAttacks = require("Mob/MobAttacks")
local Strict = require("Core/Strict")

local function LookAtPlayer(mobContext, dt)
    local brain = mobContext.Brain
    if not brain.IsTracking then return end

    local targetActor = brain.TargetActor
    if not targetActor or not targetActor:IsValid() then return end

    local ownerActor = mobContext.Owner
    local mobPos = ownerActor.Location
    local targetPos = targetActor.Location

    local toTarget = Vector(targetPos.X - mobPos.X, targetPos.Y - mobPos.Y, 0.0)
    if toTarget:Length() < 0.001 then return end

    local targetYaw = math.atan2(toTarget.Y, toTarget.X) * 180.0 / math.pi
    local currentYaw = ownerActor.Rotation.Z
    local diff = targetYaw - currentYaw
    while diff > 180.0 do diff = diff - 360.0 end
    while diff < -180.0 do diff = diff + 360.0 end

    local scaledDt = dt * brain.TimeScale
    local maxStep = mobContext.Config.LOOK_AT_SPEED * scaledDt
    local step = math.max(-maxStep, math.min(maxStep, diff))

    ownerActor.Rotation = Vector(0.0, 0.0, currentYaw + step)
end

local function Chase(mobContext, dt)
    LookAtPlayer(mobContext, dt)

    local targetActor = mobContext.Brain.TargetActor
    if not targetActor or not targetActor:IsValid() then return end

    local ownerActor = mobContext.Owner
    local mobPos = ownerActor.Location
    local targetPos = targetActor.Location
    local toTarget = Vector(targetPos.X - mobPos.X, targetPos.Y - mobPos.Y, 0.0)
    if toTarget:Length() < 0.001 then return end

    Reflection.Call(ownerActor, "AddMovementInput", toTarget:Normalized(), 1.0)
end

-- =========================================================
-- Public API
-- =========================================================

---@param mobContext MobContext
---@return nil
function MobAction.Init(mobContext)
    MobContext.Assert(mobContext, "MobAction.Init")
end

---@param mobContext MobContext
---@param dt number
---@return nil
function MobAction.Update(mobContext, dt)
    MobContext.Assert(mobContext, "MobAction.Update")
    Strict.AssertNumber(dt, "dt", "MobAction.Update")

    local brain = mobContext.Brain
    local combat = mobContext.Combat
    local config = mobContext.Config

    if combat.IsDead or combat.ActionLock then
        return
    end

    LookAtPlayer(mobContext, dt)

    if brain.Distance > config.ATTACK_DISTANCE then
        brain.State = "Chase"
        Chase(mobContext, dt)
        return
    end

    brain.State = "Attack"
    if brain.PatternCooldown <= 0.0 then
        MobAttacks.StartAttack(mobContext)
        brain.PatternCooldown = config.ATTACK_COOLDOWN
    end
end

---@param mobContext MobContext
---@param notifyName string
---@return nil
function MobAction.OnAnimNotify(mobContext, notifyName)
    MobContext.Assert(mobContext, "MobAction.OnAnimNotify")
    Strict.AssertString(notifyName, "notifyName", "MobAction.OnAnimNotify")

    local attack = mobContext.Attack
    if notifyName == "ZoneShow" then
        attack.ZoneShow = true
    elseif notifyName == "ZoneFlash" then
        attack.ZoneFlash = true
    elseif notifyName == "ZoneHide" then
        attack.ZoneHide = true
    elseif notifyName == "HitboxOpen" then
        attack.HitboxOpen = true
    elseif notifyName == "HitboxClose" then
        attack.HitboxClose = true
    elseif notifyName == "TrackEnd" then
        attack.TrackEnd = true
    end
end

return MobAction
