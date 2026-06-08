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

-- 주변 잡몹으로부터 멀어지는 반발 벡터(boids separation). 가까울수록 강하게 민다.
local function ComputeSeparation(mobContext)
    local sep = Vector(0.0, 0.0, 0.0)
    local myPos = mobContext.Owner.Location
    local radius = mobContext.Config.SEPARATION_RADIUS

    MobContext.ForEach(function(other)
        if other == mobContext then return end
        local otherPos = other.Owner.Location
        local away = Vector(myPos.X - otherPos.X, myPos.Y - otherPos.Y, 0.0)
        local dist = away:Length()
        if dist > 0.001 and dist < radius then
            -- 가까울수록(작은 dist) 1.0 에 가깝게, 반경 끝에선 0 에 가깝게.
            sep = sep + away:Normalized() * ((radius - dist) / radius)
        end
    end)

    return sep
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

    -- 추격 방향에 잡몹 간 반발을 섞어 서로 겹치지 않게 한다.
    local sep = ComputeSeparation(mobContext)
    local weight = mobContext.Config.SEPARATION_WEIGHT
    local moveDir = Vector(
        toTarget.X + sep.X * weight,
        toTarget.Y + sep.Y * weight,
        0.0)
    if moveDir:Length() < 0.001 then moveDir = toTarget end

    Reflection.Call(ownerActor, "AddMovementInput", moveDir:Normalized(), 1.0)
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

    -- 피격 모션 재생 중에는 추격/공격을 멈춘다.
    -- (공격 캔슬로 ActionLock 이 풀린 직후 곧바로 재공격하는 것도 이 가드가 막아준다.)
    if combat.HitReactActive then
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
