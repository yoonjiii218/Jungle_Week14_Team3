-- Player/PlayerEvents.lua
-- Typed internal message protocol for playerContext gameplay events.
-- Prefer Emit* functions over ad-hoc table literals.

local Strict = require("Core/Strict")
local PlayerContext = require("Player/PlayerContext")

local PlayerEvents = {}

PlayerEvents.Type = {
    DashStarted = "Player.DashStarted",
    DashEnded = "Player.DashEnded",
    DashChargingStarted = "Player.DashChargingStarted",
    DashChargingEnded = "Player.DashChargingEnded",
    DashChargeAttackStarted = "Player.DashChargeAttackStarted",
    DashChargeAttackEnded = "Player.DashChargeAttackEnded",
    AttackStarted = "Player.AttackStarted",
    AttackHit = "Player.AttackHit",
    AttackEnded = "Player.AttackEnded",
    Hit = "Player.Hit",
    PerfectDodge = "Player.PerfectDodge",
    UltimateStarted = "Player.UltimateStarted",
    UltimateEnded = "Player.UltimateEnded",
    Dead = "Player.Dead",
    GaugeChanged = "Player.GaugeChanged",
}

---@class PlayerEvent
---@field Kind string
---@field Type string

---@class PlayerDashStartedEvent : PlayerEvent
---@field Dir any

---@class PlayerAttackStartedEvent : PlayerEvent
---@field AttackIndex integer
---@field AttackId string|nil

---@class PlayerAttackHitEvent : PlayerEvent
---@field AttackId string
---@field AttackIndex integer|nil
---@field TargetActor any
---@field Damage number
---@field GaugeDelta number
---@field HP number|nil
---@field MaxHP number|nil

---@class PlayerHitEvent : PlayerEvent
---@field SourceActor any
---@field AttackId string
---@field Damage number
---@field HP number
---@field MaxHP number

---@class PlayerPerfectDodgeEvent : PlayerEvent
---@field Threat any
---@field AttackId string
---@field GaugeDelta number
---@field SlomoDuration number
---@field SlomoScale number

local function MakeEvent(eventType, args)
    args = args or {}
    args.Kind = "PlayerEvent"
    args.Type = eventType
    return args
end

-- =========================================================
-- Public API
-- =========================================================

---@param playerContext PlayerContext
---@return nil
function PlayerEvents.BeginFrame(playerContext)
    PlayerContext.Assert(playerContext, "PlayerEvents.BeginFrame")
    playerContext.Runtime.EventQueue = playerContext.Runtime.EventQueue or {}
end

---@param playerContext PlayerContext
---@param event PlayerEvent
---@return nil
function PlayerEvents.Push(playerContext, event)
    PlayerContext.Assert(playerContext, "PlayerEvents.Push")
    Strict.AssertTable(event, "event", "PlayerEvents.Push")
    if event.Kind ~= "PlayerEvent" then
        error("[PlayerEvents.Push] event.Kind must be PlayerEvent")
    end
    Strict.AssertString(event.Type, "event.Type", "PlayerEvents.Push")
    table.insert(playerContext.Runtime.EventQueue, event)
end

---@param playerContext PlayerContext
---@return PlayerEvent[]
function PlayerEvents.Drain(playerContext)
    PlayerContext.Assert(playerContext, "PlayerEvents.Drain")
    local events = playerContext.Runtime.EventQueue
    playerContext.Runtime.EventQueue = {}
    return events
end

---@param playerContext PlayerContext
---@param args table
---@return nil
function PlayerEvents.EmitDashStarted(playerContext, args)
    PlayerEvents.Push(playerContext, MakeEvent(PlayerEvents.Type.DashStarted, args))
end

---@param playerContext PlayerContext
---@return nil
function PlayerEvents.EmitDashEnded(playerContext)
    PlayerEvents.Push(playerContext, MakeEvent(PlayerEvents.Type.DashEnded))
end

---@param playerContext PlayerContext
---@return nil
function PlayerEvents.EmitDashChargingStarted(playerContext)
    PlayerEvents.Push(playerContext, MakeEvent(PlayerEvents.Type.DashChargingStarted))
end

---@param playerContext PlayerContext
---@return nil
function PlayerEvents.EmitDashChargingEnded(playerContext)
    PlayerEvents.Push(playerContext, MakeEvent(PlayerEvents.Type.DashChargingEnded))
end

---@param playerContext PlayerContext
---@return nil
function PlayerEvents.EmitDashChargeAttackStarted(playerContext)
    PlayerEvents.Push(playerContext, MakeEvent(PlayerEvents.Type.DashChargeAttackStarted))
end

---@param playerContext PlayerContext
---@return nil
function PlayerEvents.EmitDashChargeAttackEnded(playerContext)
    PlayerEvents.Push(playerContext, MakeEvent(PlayerEvents.Type.DashChargeAttackEnded))
end

---@param playerContext PlayerContext
---@param args table
---@return nil
function PlayerEvents.EmitAttackStarted(playerContext, args)
    PlayerEvents.Push(playerContext, MakeEvent(PlayerEvents.Type.AttackStarted, args))
end

---@param playerContext PlayerContext
---@param args table
---@return nil
function PlayerEvents.EmitAttackHit(playerContext, args)
    PlayerEvents.Push(playerContext, MakeEvent(PlayerEvents.Type.AttackHit, args))
end

---@param playerContext PlayerContext
---@param args table
---@return nil
function PlayerEvents.EmitAttackEnded(playerContext, args)
    PlayerEvents.Push(playerContext, MakeEvent(PlayerEvents.Type.AttackEnded, args))
end

---@param playerContext PlayerContext
---@param args table
---@return nil
function PlayerEvents.EmitHit(playerContext, args)
    PlayerEvents.Push(playerContext, MakeEvent(PlayerEvents.Type.Hit, args))
end

---@param playerContext PlayerContext
---@param args table
---@return nil
function PlayerEvents.EmitPerfectDodge(playerContext, args)
    PlayerEvents.Push(playerContext, MakeEvent(PlayerEvents.Type.PerfectDodge, args))
end

---@param playerContext PlayerContext
---@return nil
function PlayerEvents.EmitUltimateStarted(playerContext)
    PlayerEvents.Push(playerContext, MakeEvent(PlayerEvents.Type.UltimateStarted))
end

---@param playerContext PlayerContext
---@return nil
function PlayerEvents.EmitUltimateEnded(playerContext)
    PlayerEvents.Push(playerContext, MakeEvent(PlayerEvents.Type.UltimateEnded))
end

---@param playerContext PlayerContext
---@param args table
---@return nil
function PlayerEvents.EmitDead(playerContext, args)
    PlayerEvents.Push(playerContext, MakeEvent(PlayerEvents.Type.Dead, args))
end

---@param playerContext PlayerContext
---@param args table
---@return nil
function PlayerEvents.EmitGaugeChanged(playerContext, args)
    PlayerEvents.Push(playerContext, MakeEvent(PlayerEvents.Type.GaugeChanged, args))
end

---@param event PlayerEvent
---@param eventType string
---@return boolean
function PlayerEvents.Is(event, eventType)
    return event ~= nil and event.Type == eventType
end

return PlayerEvents
