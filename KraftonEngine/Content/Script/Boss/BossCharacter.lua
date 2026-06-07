-- Boss/BossCharacter.lua
-- ULuaScriptComponent entry point for the boss actor.
-- Owns BossContext and wires explicit boss module calls.

local BossConfig    = require("Boss/BossBlackboard")
local BossContext   = require("Boss/BossContext")
local BossEvents    = require("Boss/BossEvents")
local BossAction    = require("Boss/BossAction")
local BossAttacks   = require("Boss/BossAttacks")
local BossFeedback  = require("Boss/BossFeedback")
local BossHitbox    = require("Boss/BossHitbox")
local CombatContext = require("Combat/CombatContext")

local bossContext = nil

function BeginPlay()
    math.randomseed((World.GetGameTime() or 0) * 1000.0 + 1.0)

    bossContext = BossContext.Create(obj, this, BossConfig)

    if not obj:HasTag("Boss") then
        obj:AddTag("Boss")
    end

    if not obj:HasTag("HitTarget") then
        obj:AddTag("HitTarget")
    end

    bossContext.Brain.TargetActor = World.FindFirstActorByTag("Player")

    if bossContext.Runtime.MovementComp then
        Reflection.Call(bossContext.Runtime.MovementComp, "SetMovementInputEnabled", true)
    end

    if BossConfig.DEBUG then
        local found = bossContext.Brain.TargetActor ~= nil and bossContext.Brain.TargetActor:IsValid()
        print("[BossCharacter] BeginPlay - playerRef found: " .. tostring(found)
            .. " / movComp: " .. tostring(bossContext.Runtime.MovementComp ~= nil))
    end

    BossAction.Init(bossContext)
    BossAttacks.Init(bossContext)
    BossFeedback.Init(bossContext)
    BossHitbox.Init(bossContext)
    CombatContext.RegisterBoss(bossContext)
end

function Tick(dt)
    if bossContext == nil then
        return
    end

    BossEvents.BeginFrame(bossContext)

    local brain = bossContext.Brain
    if brain.SlomoRemaining > 0 then
        brain.SlomoRemaining = brain.SlomoRemaining - dt
        if brain.SlomoRemaining <= 0 then
            brain.SlomoRemaining = 0.0
            brain.TimeScale = 1.0
            if BossConfig.DEBUG then
                print("[BossCharacter] Slomo end @ " .. string.format("%.3f", World.GetGameTime()))
            end
        end
    end

    local scaledDt = dt * brain.TimeScale
    brain.PatternCooldown = math.max(0.0, brain.PatternCooldown - scaledDt)
    brain.HeavyAttackCooldown = math.max(0.0, brain.HeavyAttackCooldown - scaledDt)

    local targetActor = brain.TargetActor
    if targetActor and targetActor:IsValid() then
        local d = obj.Location - targetActor.Location
        d.Z = 0.0
        brain.Distance = d:Length()
        brain.TargetLastKnownPosition = targetActor.Location
    end

    UpdateCoroutines(scaledDt)
    BossAction.Update(bossContext, dt)
    BossAttacks.Update(bossContext, scaledDt)

    local events = BossEvents.Drain(bossContext)
    CombatContext.ProcessBossEvents(bossContext, events)
    BossFeedback.ProcessEvents(bossContext, events)
end

function EndPlay()
    CombatContext.Clear()
    bossContext = nil
    if BossConfig.DEBUG then
        print("[BossCharacter] EndPlay")
    end
end
