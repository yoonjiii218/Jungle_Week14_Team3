-- Boss/BossCharacter.lua
-- ULuaScriptComponent entry point for the boss actor.
-- Owns BossContext and wires explicit boss module calls.

local CoroutineManager = require("CoroutineManager")
local BossConfig    = require("Boss/BossBlackboard")
local BossContext   = require("Boss/BossContext")
local BossEvents    = require("Boss/BossEvents")
local BossAction    = require("Boss/BossAction")
local BossAttacks   = require("Boss/BossAttacks")
local BossFeedback  = require("Boss/BossFeedback")
local BossHitbox    = require("Boss/BossHitbox")
local CombatContext = require("Combat/CombatContext")
local GameplayEventBus = require("Core/GameplayEventBus")

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

    -- 보스는 넉백을 받지 않는다. 넉백은 플레이어 공격 클립의 AttackHitWindow 노티파이(C++)가
    -- 대상의 ActionComponent.Knockback 으로 직접 거는데, 면역 플래그를 켜면 그 호출이 무시된다.
    -- (C++ ApplyKnockback 은 GetComponentByClass 로 같은 ActionComponent 를 찾으므로 여기서 미리 확보해 둔다.)
    local bossAction = obj.GetActionComponent and obj:GetActionComponent() or nil
    if bossAction == nil and obj.AddActionComponent ~= nil then
        bossAction = obj:AddActionComponent()
    end
    if bossAction ~= nil and bossAction.SetKnockbackImmune ~= nil then
        bossAction:SetKnockbackImmune(true)
        bossContext.Runtime.ActionComp = bossAction
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

    -- 첫 활성화 시 로딩 hitch 로 dt 가 비정상적으로 커지면 WaitForNotify 타임아웃이
    -- 한 프레임에 통째로 지나가버려 장판/공격 시퀀스가 애니메이션과 어긋난다. 클램프로 방지.
    dt = math.min(dt, 0.1)

    -- Own coroutine pool: this boss's coroutines must only ever advance by
    -- this boss's scaledDt, never another actor's (see CoroutineManager.lua).
    CoroutineManager.Begin(obj.UUID)

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
    GameplayEventBus.PublishMany(events, bossContext)
    BossFeedback.ProcessEvents(bossContext, events)

    CoroutineManager.End()
end

function EndPlay()
    CoroutineManager.Destroy(obj.UUID)
    CombatContext.Clear()
    bossContext = nil
    if BossConfig.DEBUG then
        print("[BossCharacter] EndPlay")
    end
end
