-- Player/PlayerContext.lua
-- Defines the PlayerContext data contract used across player Lua modules.
-- New code must use explicit buckets: player.Input / Action / Combat / Feedback / Runtime.

local Strict = require("Core/Strict")
local PlayerConfig = require("Config/PlayerConfig")

local PlayerContext = {}

---@class PlayerInputState
---@field MoveDir any
---@field AttackPressed boolean
---@field AttackDown boolean
---@field AttackHoldTime number
---@field DashPressed boolean
---@field DashReleased boolean
---@field DashDown boolean
---@field DashHoldTime number
---@field DashChargingPressed boolean
---@field DashChargingReleased boolean
---@field DashChargingConsumedInput boolean
---@field UltimatePressed boolean

---@class PlayerActionState
---@field State string
---@field AttackIndex integer
---@field AttackInstanceId string|nil
---@field ComboWindow boolean
---@field ComboQueued boolean
---@field AttackEnd boolean
---@field DashActive boolean
---@field DashElapsed number
---@field DashEnd boolean
---@field DashChargingActive boolean
---@field DashChargingElapsed number
---@field DashChargingEnd boolean
---@field DashChargeAttackActive boolean
---@field DashChargeAttackElapsed number
---@field DashChargeAttackEnd boolean
---@field DashChargeAttackInstanceId string|nil
---@field IsUltimateRunning boolean
---@field IsInUltimateMode boolean

---@class PlayerCombatState
---@field HP number
---@field MaxHP number
---@field UltimateGauge number
---@field MaxUltimateGauge number
---@field IsDead boolean
---@field InvincibleUntil number
---@field DodgeInvincibleUntil number
---@field PerfectDodgeConsumedUntil number
---@field RecentHitIds table
---@field CurrentThreat any

---@class PlayerFeedbackState
---@field KatanaComponent any
---@field KatanaPSC any

---@class PlayerRuntimeState
---@field MovementComp any
---@field LastMoveInputDirection any
---@field EventQueue PlayerEvent[]
---@field DashPrevOrientRotationToMovement any
---@field DashMoveDirection any
---@field StepForwardActive boolean
---@field StepForwardElapsed number
---@field StepForwardDuration number
---@field StepForwardDistance number
---@field StepForwardAppliedDistance number
---@field StepForwardDirection any
---@field TargetAssistMode string|nil
---@field TargetAssistTarget any
---@field TargetAssistDirection any
---@field TargetAssistDistance number|nil
---@field TargetAssistLockedDirection any
---@field TargetAssistEndTime number
---@field TargetAssistKeepUntil number

---@class PlayerContext
---@field Kind string
---@field Owner any
---@field Component any
---@field Config table
---@field Input PlayerInputState
---@field Action PlayerActionState
---@field Combat PlayerCombatState
---@field Feedback PlayerFeedbackState
---@field Runtime PlayerRuntimeState

local function CreateInputState()
    return {
        MoveDir = nil,
        AttackPressed = false,
        AttackDown = false,
        AttackHoldTime = 0.0,
        DashPressed = false,
        DashReleased = false,
        DashDown = false,
        DashHoldTime = 0.0,
        DashChargingPressed = false,
        DashChargingReleased = false,
        DashChargingConsumedInput = false,
        UltimatePressed = false,
    }
end

local function CreateActionState()
    return {
        State = "Locomotion",
        AttackIndex = 0,
        AttackInstanceId = nil,
        ComboWindow = false,
        ComboQueued = false,
        AttackEnd = false,
        DashActive = false,
        DashElapsed = 0.0,
        DashEnd = false,
        DashChargingActive = false,
        DashChargingElapsed = 0.0,
        DashChargingEnd = false,
        DashChargeAttackActive = false,
        DashChargeAttackElapsed = 0.0,
        DashChargeAttackEnd = false,
        DashChargeAttackInstanceId = nil,
        IsUltimateRunning = false,
        IsInUltimateMode = false,
    }
end

local function CreateCombatState(config)
    local combatConfig = config.Combat
    return {
        HP = combatConfig.MaxHP,
        MaxHP = combatConfig.MaxHP,
        UltimateGauge = 0,
        MaxUltimateGauge = combatConfig.MaxUltimateGauge,
        IsDead = false,
        InvincibleUntil = 0.0,
        DodgeInvincibleUntil = 0.0,
        PerfectDodgeConsumedUntil = 0.0,
        RecentHitIds = {},
        CurrentThreat = nil,
        CombatDodgeActive = false,
        DodgeStartLocation = nil,
        LastHitTime = 0.0,
    }
end

local function CreateRuntimeState()
    return {
        MovementComp = nil,
        LastMoveInputDirection = nil,
        EventQueue = {},
        DashPrevOrientRotationToMovement = nil,
        DashMoveDirection = nil,
        StepForwardActive = false,
        StepForwardElapsed = 0.0,
        StepForwardDuration = 0.0,
        StepForwardDistance = 0.0,
        StepForwardAppliedDistance = 0.0,
        StepForwardDirection = nil,
        TargetAssistMode = nil,
        TargetAssistTarget = nil,
        TargetAssistDirection = nil,
        TargetAssistDistance = nil,
        TargetAssistLockedDirection = nil,
        TargetAssistEndTime = 0.0,
        TargetAssistKeepUntil = 0.0,
    }
end

-- =========================================================
-- Public API
-- =========================================================

---@param owner any
---@param component any
---@return PlayerContext
function PlayerContext.Create(owner, component)
    Strict.AssertNotNil(owner, "owner", "PlayerContext.Create")

    local config = PlayerConfig.Create()
    local player = {
        Kind = "PlayerContext",
        Owner = owner,
        Component = component,
        Config = config,
        Input = CreateInputState(),
        Action = CreateActionState(),
        Combat = CreateCombatState(config),
        Feedback = {},
        Runtime = CreateRuntimeState(),
    }

    return player
end

---@param player PlayerContext
---@param caller string
---@return PlayerContext
function PlayerContext.Assert(player, caller)
    Strict.AssertKind(player, "PlayerContext", "player", caller or "PlayerContext.Assert")
    Strict.AssertTable(player.Input, "player.Input", caller or "PlayerContext.Assert")
    Strict.AssertTable(player.Action, "player.Action", caller or "PlayerContext.Assert")
    Strict.AssertTable(player.Combat, "player.Combat", caller or "PlayerContext.Assert")
    Strict.AssertTable(player.Runtime, "player.Runtime", caller or "PlayerContext.Assert")
    Strict.AssertTable(player.Config, "player.Config", caller or "PlayerContext.Assert")
    Strict.AssertTable(player.Config.Input, "player.Config.Input", caller or "PlayerContext.Assert")
    Strict.AssertTable(player.Config.Action, "player.Config.Action", caller or "PlayerContext.Assert")
    Strict.AssertTable(player.Config.Combat, "player.Config.Combat", caller or "PlayerContext.Assert")
    Strict.AssertTable(player.Config.Feedback, "player.Config.Feedback", caller or "PlayerContext.Assert")
    Strict.AssertTable(player.Config.Animation, "player.Config.Animation", caller or "PlayerContext.Assert")
    return player
end

return PlayerContext
