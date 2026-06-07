-- Mob/MobCharacter.lua
-- ULuaScriptComponent entry point for the rusher mob actor.
-- Owns MobContext and wires explicit mob module calls (mirrors Boss/BossCharacter).

local MobConfig  = require("Mob/MobBlackboard")
local MobContext = require("Mob/MobContext")
local MobAction  = require("Mob/MobAction")
local MobAttacks = require("Mob/MobAttacks")

local mobContext = nil

function BeginPlay()
    mobContext = MobContext.Create(obj, this, MobConfig)

    if not obj:HasTag("Mob") then
        obj:AddTag("Mob")
    end

    mobContext.Brain.TargetActor = World.FindFirstActorByTag("Player")

    mobContext.Runtime.MovementComp = obj.GetCharacterMovement and obj:GetCharacterMovement() or nil
    mobContext.Runtime.SkeletalMeshComp = obj.GetSkeletalMeshComponent and obj:GetSkeletalMeshComponent() or nil

    if mobContext.Runtime.MovementComp then
        Reflection.Call(mobContext.Runtime.MovementComp, "SetMovementInputEnabled", true)
    end

    if MobConfig.DEBUG then
        local found = mobContext.Brain.TargetActor ~= nil and mobContext.Brain.TargetActor:IsValid()
        print("[MobCharacter] BeginPlay - playerRef found: " .. tostring(found)
            .. " / movComp: " .. tostring(mobContext.Runtime.MovementComp ~= nil))
    end

    MobAction.Init(mobContext)
    MobAttacks.Init(mobContext)
    MobContext.Register(mobContext)   -- MobAnimation 이 obj 로 컨텍스트를 찾도록 등록
end

function Tick(dt)
    if mobContext == nil then
        return
    end

    local brain = mobContext.Brain
    local scaledDt = dt * brain.TimeScale
    brain.PatternCooldown = math.max(0.0, brain.PatternCooldown - scaledDt)

    local targetActor = brain.TargetActor
    if targetActor and targetActor:IsValid() then
        local d = obj.Location - targetActor.Location
        d.Z = 0.0
        brain.Distance = d:Length()
    end

    UpdateCoroutines(scaledDt)
    MobAction.Update(mobContext, dt)
    MobAttacks.Update(mobContext, scaledDt)
end

function EndPlay()
    if mobContext ~= nil then
        MobContext.Unregister(mobContext)
    end
    mobContext = nil
    if MobConfig.DEBUG then
        print("[MobCharacter] EndPlay")
    end
end
