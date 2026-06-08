-- PlayerCharacter.lua
-- ULuaScriptComponent entry point for the playerContext actor.
-- Owns the PlayerContext instance and orchestrates action -> combat -> feedback event flow.

local PlayerContext = require("Player/PlayerContext")
local PlayerEvents = require("Player/PlayerEvents")
local PlayerAction = require("Player/PlayerAction")
local PlayerProjectile = require("Player/PlayerProjectile")
local CombatContext = require("Combat/CombatContext")
local PlayerFeedback = require("Player/PlayerFeedback")

local PlayerCharacter = {}
local playerContext = nil

local function GetPlayerContext()
    if playerContext ~= nil then
        return playerContext
    end

    if obj ~= nil then
        playerContext = CombatContext.GetPlayerByOwner(obj)
    end

    return playerContext
end

---@param active boolean
---@return nil
function PlayerCharacter.SetKatanaTrailActive(active)
    local currentPlayerContext = GetPlayerContext()
    if currentPlayerContext ~= nil then
        PlayerFeedback.SetKatanaTrailActive(currentPlayerContext, active)
    end
end

function BeginPlay()
    if obj ~= nil and obj.HasTag ~= nil and obj.AddTag ~= nil and not obj:HasTag("Player") then
        obj:AddTag("Player")
    end

    playerContext = CombatContext.GetPlayerByOwner(obj)
    if playerContext == nil then
        playerContext = PlayerContext.Create(obj, this)
    else
        playerContext.Owner = obj
        playerContext.Component = this
    end

    PlayerAction.Init(playerContext)
    PlayerProjectile.Init(playerContext)
    CombatContext.RegisterPlayer(playerContext)
    PlayerFeedback.Init(playerContext)

    print("[BeginPlay] " .. obj.UUID)
end

function EndPlay()
    if playerContext ~= nil then
        PlayerProjectile.Shutdown(playerContext)
        CombatContext.UnregisterPlayer(playerContext)
        PlayerFeedback.Shutdown(playerContext)
    end
    playerContext = nil

    print("[EndPlay] " .. obj.UUID)
end

function OnOverlap(OtherActor, OverlappedComponent, OtherComp)
    local currentPlayerContext = GetPlayerContext()
    if currentPlayerContext ~= nil then
        CombatContext.TryResolvePlayerOverlapHit({
            PlayerContext = currentPlayerContext,
            OtherActor = OtherActor,
            OverlappedComponent = OverlappedComponent,
            OtherComponent = OtherComp,
        })
    end
end

function Tick(dt)
    UpdateCoroutines(dt)

    local currentPlayerContext = GetPlayerContext()
    if currentPlayerContext == nil then
        return
    end

    PlayerEvents.BeginFrame(currentPlayerContext)
    PlayerAction.Update(currentPlayerContext, dt)
    PlayerProjectile.Update(currentPlayerContext, dt)
    PlayerFeedback.Update(currentPlayerContext, dt)

    local events = PlayerEvents.Drain(currentPlayerContext)
    CombatContext.ProcessPlayerEvents(currentPlayerContext, events)
    PlayerFeedback.ProcessEvents(currentPlayerContext, events)
end

local function BoolText(value)
    return value == true and "true" or "false"
end

local function NumberOrZero(value)
    return value or 0.0
end

local function Clamp(value, minValue, maxValue)
    if value < minValue then return minValue end
    if value > maxValue then return maxValue end
    return value
end

local function MakeGaugeBar(ratio)
    local barSize = 10
    local filled = math.floor(Clamp(ratio, 0.0, 1.0) * barSize + 0.5)
    return string.rep("#", filled) .. string.rep("-", barSize - filled)
end

local function DerivePlayerDebugState(ctx)
    if ctx == nil or ctx.Action == nil then return "None" end
    if ctx.Combat ~= nil and ctx.Combat.IsDead == true then return "Dead" end
    local action = ctx.Action
    if action.IsUltimateRunning or action.IsInUltimateMode then return "Ultimate" end
    if action.DashChargeAttackActive then return "DashChargeAttack" end
    if action.DashChargingActive then return "DashCharging" end
    if action.DashActive then return "Dash" end
    if action.PostDashAttackActive then return "PostDashAttack" .. tostring(action.PostDashAttackVariant or action.AttackIndex or 0) end
    if (action.AttackIndex or 0) > 0 then return "Attack" .. tostring(action.AttackIndex) end
    return "Locomotion"
end

function GetDebugSnapshotText()
    local ctx = GetPlayerContext()
    if ctx == nil then
        return "[Player] No PlayerContext"
    end

    local now = World.GetGameTime()
    local action = ctx.Action or {}
    local input = ctx.Input or {}
    local combat = ctx.Combat or {}
    local config = ctx.Config or {}
    local actionConfig = config.Action or {}
    local combatConfig = config.Combat or {}
    local runtime = ctx.Runtime or {}

    local dodgeUntil = NumberOrZero(combat.DodgeInvincibleUntil)
    local consumedUntil = NumberOrZero(combat.PerfectDodgeConsumedUntil)
    local invincibleUntil = NumberOrZero(combat.InvincibleUntil)
    local perfectWindow = dodgeUntil > now
    local perfectConsumed = consumedUntil >= dodgeUntil and dodgeUntil > 0.0
    local hp = NumberOrZero(combat.HP)
    local maxHP = NumberOrZero(combat.MaxHP or combatConfig.MaxHP)
    local ultimateGauge = NumberOrZero(combat.UltimateGauge)
    local maxUltimateGauge = NumberOrZero(combat.MaxUltimateGauge or combatConfig.MaxUltimateGauge)
    local ultimateRatio = 0.0
    if maxUltimateGauge > 0.0 then
        ultimateRatio = Clamp(ultimateGauge / maxUltimateGauge, 0.0, 1.0)
    end
    local ultimatePercent = math.floor(ultimateRatio * 100.0 + 0.5)

    local targetAssist = runtime.TargetAssistMode or "None"
    local targetName = "None"
    if runtime.TargetAssistTarget ~= nil and runtime.TargetAssistTarget.GetName ~= nil then
        targetName = runtime.TargetAssistTarget:GetName()
    end

    return string.format(
        "LuaState: %s\n" ..
        "HP: %.0f / %.0f\n" ..
        "UltimateGauge: %.0f / %.0f (%d%%)\n" ..
        "Ultimate: [%s] %d%%\n" ..
        "Attack: index=%d comboWindow=%s queued=%s end=%s\n" ..
        "PostDashAttack: window=%s timer=%.3f uses=%d next=%d active=%s variant=%d\n" ..
        "Dash: active=%s elapsed=%.3f / %.3f end=%s\n" ..
        "DashCharge: charging=%s elapsed=%.3f released=%s consumedInput=%s turnTarget=%s\n" ..
        "DashChargeAttack: active=%s elapsed=%.3f end=%s\n" ..
        "PerfectDodge: window=%s consumed=%s  now=%.3f until=%.3f consumedUntil=%.3f\n" ..
        "InvincibleUntil: %.3f\n" ..
        "InputBuffer: attackBuffered=%s attackTimer=%.3f dashBuffered=%s dashTimer=%.3f last=%s\n" ..
        "InputPulse: attackPressed=%s dashPressed=%s dashChargingPressed=%s dashChargingReleased=%s\n" ..
        "InputHold: DashDown=%s DashHoldTime=%.3f\n" ..
        "Assist: mode=%s target=%s\n" ..
        "ActiveFlyingSlashes: %d",
        DerivePlayerDebugState(ctx),
        hp, maxHP,
        ultimateGauge, maxUltimateGauge, ultimatePercent,
        MakeGaugeBar(ultimateRatio), ultimatePercent,
        math.floor(NumberOrZero(action.AttackIndex)), BoolText(action.ComboWindow), BoolText(action.ComboQueued), BoolText(action.AttackEnd),
        BoolText(action.PostDashAttackWindowActive), NumberOrZero(action.PostDashAttackWindowTimer), math.floor(NumberOrZero(action.PostDashAttackUseCount)), math.floor(NumberOrZero(action.PostDashAttackNextVariant)), BoolText(action.PostDashAttackActive), math.floor(NumberOrZero(action.PostDashAttackVariant)),
        BoolText(action.DashActive), NumberOrZero(action.DashElapsed), NumberOrZero(actionConfig.DashDuration), BoolText(action.DashEnd),
        BoolText(action.DashChargingActive), NumberOrZero(action.DashChargingElapsed), BoolText(input.DashChargingReleased), BoolText(input.DashChargingConsumedInput), tostring(runtime.DashChargingTurnTarget or "None"),
        BoolText(action.DashChargeAttackActive), NumberOrZero(action.DashChargeAttackElapsed), BoolText(action.DashChargeAttackEnd),
        BoolText(perfectWindow), BoolText(perfectConsumed), now, dodgeUntil, consumedUntil,
        invincibleUntil,
        BoolText(input.AttackBuffered), NumberOrZero(input.AttackBufferTimer), BoolText(input.DashBuffered), NumberOrZero(input.DashBufferTimer), tostring(input.LastBufferedAction or "None"),
        BoolText(input.AttackPressed), BoolText(input.DashPressed), BoolText(input.DashChargingPressed), BoolText(input.DashChargingReleased),
        BoolText(input.DashDown), NumberOrZero(input.DashHoldTime),
        tostring(targetAssist), tostring(targetName),
        #(runtime.FlyingSlashes or {})
    )
end

return PlayerCharacter
