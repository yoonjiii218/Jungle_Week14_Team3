-- Player/PlayerEvents.lua
-- Typed internal message protocol for player gameplay events.
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

---@param player PlayerContext
---@return nil
function PlayerEvents.BeginFrame(player)
    PlayerContext.Assert(player, "PlayerEvents.BeginFrame")
    player.Runtime.EventQueue = {}
end

---@param player PlayerContext
---@param event PlayerEvent
---@return nil
function PlayerEvents.Push(player, event)
    PlayerContext.Assert(player, "PlayerEvents.Push")
    Strict.AssertTable(event, "event", "PlayerEvents.Push")
    if event.Kind ~= "PlayerEvent" then
        error("[PlayerEvents.Push] event.Kind must be PlayerEvent")
    end
    Strict.AssertString(event.Type, "event.Type", "PlayerEvents.Push")
    table.insert(player.Runtime.EventQueue, event)
end

---@param player PlayerContext
---@return PlayerEvent[]
function PlayerEvents.Drain(player)
    PlayerContext.Assert(player, "PlayerEvents.Drain")
    local events = player.Runtime.EventQueue
    player.Runtime.EventQueue = {}
    return events
end

---@param player PlayerContext
---@param args table
---@return nil
function PlayerEvents.EmitDashStarted(player, args)
    PlayerEvents.Push(player, MakeEvent(PlayerEvents.Type.DashStarted, args))
end

---@param player PlayerContext
---@return nil
function PlayerEvents.EmitDashEnded(player)
    PlayerEvents.Push(player, MakeEvent(PlayerEvents.Type.DashEnded))
end

---@param player PlayerContext
---@return nil
function PlayerEvents.EmitDashChargingStarted(player)
    PlayerEvents.Push(player, MakeEvent(PlayerEvents.Type.DashChargingStarted))
end

---@param player PlayerContext
---@return nil
function PlayerEvents.EmitDashChargingEnded(player)
    PlayerEvents.Push(player, MakeEvent(PlayerEvents.Type.DashChargingEnded))
end

---@param player PlayerContext
---@return nil
function PlayerEvents.EmitDashChargeAttackStarted(player)
    PlayerEvents.Push(player, MakeEvent(PlayerEvents.Type.DashChargeAttackStarted))
end

---@param player PlayerContext
---@return nil
function PlayerEvents.EmitDashChargeAttackEnded(player)
    PlayerEvents.Push(player, MakeEvent(PlayerEvents.Type.DashChargeAttackEnded))
end

---@param player PlayerContext
---@param args table
---@return nil
function PlayerEvents.EmitAttackStarted(player, args)
    PlayerEvents.Push(player, MakeEvent(PlayerEvents.Type.AttackStarted, args))
end

---@param player PlayerContext
---@param args table
---@return nil
function PlayerEvents.EmitAttackHit(player, args)
    PlayerEvents.Push(player, MakeEvent(PlayerEvents.Type.AttackHit, args))
end

---@param player PlayerContext
---@param args table
---@return nil
function PlayerEvents.EmitAttackEnded(player, args)
    PlayerEvents.Push(player, MakeEvent(PlayerEvents.Type.AttackEnded, args))
end

---@param player PlayerContext
---@param args table
---@return nil
function PlayerEvents.EmitHit(player, args)
    PlayerEvents.Push(player, MakeEvent(PlayerEvents.Type.Hit, args))
end

---@param player PlayerContext
---@param args table
---@return nil
function PlayerEvents.EmitPerfectDodge(player, args)
    PlayerEvents.Push(player, MakeEvent(PlayerEvents.Type.PerfectDodge, args))
end

---@param player PlayerContext
---@return nil
function PlayerEvents.EmitUltimateStarted(player)
    PlayerEvents.Push(player, MakeEvent(PlayerEvents.Type.UltimateStarted))
end

---@param player PlayerContext
---@return nil
function PlayerEvents.EmitUltimateEnded(player)
    PlayerEvents.Push(player, MakeEvent(PlayerEvents.Type.UltimateEnded))
end

---@param player PlayerContext
---@param args table
---@return nil
function PlayerEvents.EmitDead(player, args)
    PlayerEvents.Push(player, MakeEvent(PlayerEvents.Type.Dead, args))
end

---@param player PlayerContext
---@param args table
---@return nil
function PlayerEvents.EmitGaugeChanged(player, args)
    PlayerEvents.Push(player, MakeEvent(PlayerEvents.Type.GaugeChanged, args))
end

---@param event PlayerEvent
---@param eventType string
---@return boolean
function PlayerEvents.Is(event, eventType)
    return event ~= nil and event.Type == eventType
end

return PlayerEvents
