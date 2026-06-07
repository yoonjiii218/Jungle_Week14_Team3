-- Player/PlayerContext.lua
-- Defines the PlayerContext data contract used across player Lua modules.
-- The legacy flat field proxy exists only to keep this first refactor behavior-compatible.

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
---@field DashSlashMoveDirection any
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

local LEGACY_FIELD_MAP = {
    -- Input
    MoveDir = { "Input", "MoveDir" },
    AttackPressed = { "Input", "AttackPressed" },
    AttackDown = { "Input", "AttackDown" },
    AttackHoldTime = { "Input", "AttackHoldTime" },
    DashPressed = { "Input", "DashPressed" },
    DashReleased = { "Input", "DashReleased" },
    DashDown = { "Input", "DashDown" },
    DashHoldTime = { "Input", "DashHoldTime" },
    DashChargingPressed = { "Input", "DashChargingPressed" },
    DashChargingReleased = { "Input", "DashChargingReleased" },
    DashChargingConsumedInput = { "Input", "DashChargingConsumedInput" },
    DashSlashPressed = { "Input", "DashPressed" },
    UltimatePressed = { "Input", "UltimatePressed" },

    -- Action
    State = { "Action", "State" },
    AttackIndex = { "Action", "AttackIndex" },
    AttackInstanceId = { "Action", "AttackInstanceId" },
    ComboWindow = { "Action", "ComboWindow" },
    ComboQueued = { "Action", "ComboQueued" },
    AttackEnd = { "Action", "AttackEnd" },
    DashActive = { "Action", "DashActive" },
    DashElapsed = { "Action", "DashElapsed" },
    DashEnd = { "Action", "DashEnd" },
    DashSlashActive = { "Action", "DashActive" },
    DashSlashElapsed = { "Action", "DashElapsed" },
    DashSlashEnd = { "Action", "DashEnd" },
    DashChargingActive = { "Action", "DashChargingActive" },
    DashChargingElapsed = { "Action", "DashChargingElapsed" },
    DashChargingEnd = { "Action", "DashChargingEnd" },
    DashChargeAttackActive = { "Action", "DashChargeAttackActive" },
    DashChargeAttackElapsed = { "Action", "DashChargeAttackElapsed" },
    DashChargeAttackEnd = { "Action", "DashChargeAttackEnd" },
    DashChargeAttackInstanceId = { "Action", "DashChargeAttackInstanceId" },
    IsUltimateRunning = { "Action", "IsUltimateRunning" },
    IsInUltimateMode = { "Action", "IsInUltimateMode" },

    -- Combat
    HP = { "Combat", "HP" },
    MaxHP = { "Combat", "MaxHP" },
    UltimateGauge = { "Combat", "UltimateGauge" },
    MaxUltimateGauge = { "Combat", "MaxUltimateGauge" },
    IsDead = { "Combat", "IsDead" },
    InvincibleUntil = { "Combat", "InvincibleUntil" },
    DodgeInvincibleUntil = { "Combat", "DodgeInvincibleUntil" },
    PerfectDodgeConsumedUntil = { "Combat", "PerfectDodgeConsumedUntil" },
    RecentHitIds = { "Combat", "RecentHitIds" },
    CurrentThreat = { "Combat", "CurrentThreat" },
    CombatDodgeActive = { "Combat", "CombatDodgeActive" },
    DodgeStartLocation = { "Combat", "DodgeStartLocation" },
    LastHitTime = { "Combat", "LastHitTime" },

    -- Feedback
    KatanaComponent = { "Feedback", "KatanaComponent" },
    KatanaPSC = { "Feedback", "KatanaPSC" },

    -- Runtime
    MovementComp = { "Runtime", "MovementComp" },
    LastMoveInputDirection = { "Runtime", "LastMoveInputDirection" },
    PendingActionEvents = { "Runtime", "EventQueue" },
    EventQueue = { "Runtime", "EventQueue" },
    DashPrevOrientRotationToMovement = { "Runtime", "DashPrevOrientRotationToMovement" },
    DashMoveDirection = { "Runtime", "DashMoveDirection" },
    DashSlashMoveDirection = { "Runtime", "DashMoveDirection" },
    DashSlashPrevOrientRotationToMovement = { "Runtime", "DashPrevOrientRotationToMovement" },
    StepForwardActive = { "Runtime", "StepForwardActive" },
    StepForwardElapsed = { "Runtime", "StepForwardElapsed" },
    StepForwardDuration = { "Runtime", "StepForwardDuration" },
    StepForwardDistance = { "Runtime", "StepForwardDistance" },
    StepForwardAppliedDistance = { "Runtime", "StepForwardAppliedDistance" },
    StepForwardDirection = { "Runtime", "StepForwardDirection" },
    TargetAssistMode = { "Runtime", "TargetAssistMode" },
    TargetAssistTarget = { "Runtime", "TargetAssistTarget" },
    TargetAssistDirection = { "Runtime", "TargetAssistDirection" },
    TargetAssistDistance = { "Runtime", "TargetAssistDistance" },
    TargetAssistLockedDirection = { "Runtime", "TargetAssistLockedDirection" },
    TargetAssistEndTime = { "Runtime", "TargetAssistEndTime" },
    TargetAssistKeepUntil = { "Runtime", "TargetAssistKeepUntil" },
}

local PlayerContextMetatable = {
    __index = function(player, key)
        local map = LEGACY_FIELD_MAP[key]
        if map ~= nil then
            local bucket = rawget(player, map[1])
            return bucket and bucket[map[2]] or nil
        end
        return nil
    end,
    __newindex = function(player, key, value)
        local map = LEGACY_FIELD_MAP[key]
        if map ~= nil then
            local bucket = rawget(player, map[1])
            if bucket == nil then
                bucket = {}
                rawset(player, map[1], bucket)
            end
            bucket[map[2]] = value
            return
        end
        rawset(player, key, value)
    end,
}

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
    local combatConfig = config.Combat or PlayerConfig.Default.Combat
    return {
        HP = combatConfig.MaxHP or PlayerConfig.Default.Combat.MaxHP,
        MaxHP = combatConfig.MaxHP or PlayerConfig.Default.Combat.MaxHP,
        UltimateGauge = 0,
        MaxUltimateGauge = combatConfig.MaxUltimateGauge or PlayerConfig.Default.Combat.MaxUltimateGauge,
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
        DashSlashMoveDirection = nil,
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

    return setmetatable(player, PlayerContextMetatable)
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
    return player
end

---@return table
function PlayerContext.GetLegacyFieldMap()
    return LEGACY_FIELD_MAP
end

return PlayerContext
