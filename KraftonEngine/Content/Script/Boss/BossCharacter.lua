-- Boss/BossCharacter.lua
-- ULuaScriptComponent entry point for the boss actor.
-- Owns BossContext and passes it explicitly to boss modules.

local BB            = require("Boss/BossBlackboard")
local BossContext   = require("Boss/BossContext")
local Action        = require("Boss/BossAction")
local Attacks       = require("Boss/BossAttacks")
local Feedback      = require("Boss/BossFeedback")
local Hitbox        = require("Boss/BossHitbox")
local CombatContext = require("Combat/CombatContext")

local boss = nil

function BeginPlay()
    math.randomseed((World.GetGameTime() or 0) * 1000.0 + 1.0)

    boss = BossContext.Create(obj, this, BB)

    if not obj:HasTag("Boss") then
        obj:AddTag("Boss")
    end

    if not obj:HasTag("HitTarget") then
        obj:AddTag("HitTarget")
    end

    boss.Runtime.PlayerRef = World.FindFirstActorByTag("Player")

    if boss.Runtime.MovementComp then
        Reflection.Call(boss.Runtime.MovementComp, "SetMovementInputEnabled", true)
    end

    if BB.DEBUG then
        local found = (boss.Runtime.PlayerRef ~= nil and boss.Runtime.PlayerRef:IsValid())
        print("[BossCharacter] BeginPlay - playerRef found: " .. tostring(found)
              .. " / movComp: " .. tostring(boss.Runtime.MovementComp ~= nil))
    end

    Action.Init(boss)
    Attacks.Init(boss)
    Feedback.Init(boss)
    Hitbox.Init(boss)

    CombatContext.RegisterBoss(boss)
end

function Tick(dt)
    if boss == nil then
        return
    end

    local bb = boss.bb
    if bb.SlomoRemaining == nil then
        return
    end

    if bb.SlomoRemaining > 0 then
        bb.SlomoRemaining = bb.SlomoRemaining - dt
        if bb.SlomoRemaining <= 0 then
            bb.SlomoRemaining = 0.0
            bb.TimeScale = 1.0
            if BB.DEBUG then print("[BossCharacter] Slomo 종료 @ " .. string.format("%.3f", World.GetGameTime())) end
        end
    end

    local scaledDt = dt * bb.TimeScale

    bb.PatternCooldown = math.max(0.0, bb.PatternCooldown - scaledDt)
    bb.HeavyAttackCooldown = math.max(0.0, bb.HeavyAttackCooldown - scaledDt)

    local playerRef = Action.GetPlayerRef()
    if playerRef and playerRef:IsValid() then
        local d = obj.Location - playerRef.Location
        d.Z = 0.0
        bb.Distance = d:Length()
    end

    UpdateCoroutines(scaledDt)
    Action.UpdateAI(boss, dt)
end

function EndPlay()
    CombatContext.Clear()
    boss = nil
    if BB.DEBUG then print("[BossCharacter] EndPlay") end
end
