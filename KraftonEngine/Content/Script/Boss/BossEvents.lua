-- Boss/BossEvents.lua
-- Typed internal message protocol for boss gameplay events.
-- Prefer Emit* functions over ad-hoc table literals.

local Strict = require("Core/Strict")
local BossContext = require("Boss/BossContext")

local BossEvents = {}

BossEvents.Type = {
    AttackStarted = "Boss.AttackStarted",
    AttackTelegraphStarted = "Boss.AttackTelegraphStarted",
    AttackHitWindowOpened = "Boss.AttackHitWindowOpened",
    AttackHitWindowClosed = "Boss.AttackHitWindowClosed",
    AttackEnded = "Boss.AttackEnded",
    Hit = "Boss.Hit",
    Staggered = "Boss.Staggered",
    Dead = "Boss.Dead",
}

---@class BossEvent
---@field Kind string
---@field Type string

local function MakeEvent(eventType, args)
    args = args or {}
    args.Kind = "BossEvent"
    args.Type = eventType
    return args
end

-- =========================================================
-- Public API
-- =========================================================

---@param bossContext BossContext
---@return nil
function BossEvents.BeginFrame(bossContext)
    BossContext.Assert(bossContext, "BossEvents.BeginFrame")
    bossContext.Runtime.EventQueue = {}
end

---@param bossContext BossContext
---@param event BossEvent
---@return nil
function BossEvents.Push(bossContext, event)
    BossContext.Assert(bossContext, "BossEvents.Push")
    Strict.AssertTable(event, "event", "BossEvents.Push")
    if event.Kind ~= "BossEvent" then
        error("[BossEvents.Push] event.Kind must be BossEvent")
    end
    Strict.AssertString(event.Type, "event.Type", "BossEvents.Push")
    table.insert(bossContext.Runtime.EventQueue, event)
end

---@param bossContext BossContext
---@return BossEvent[]
function BossEvents.Drain(bossContext)
    BossContext.Assert(bossContext, "BossEvents.Drain")
    local events = bossContext.Runtime.EventQueue
    bossContext.Runtime.EventQueue = {}
    return events
end

---@param bossContext BossContext
---@param args table
---@return nil
function BossEvents.EmitAttackStarted(bossContext, args)
    BossEvents.Push(bossContext, MakeEvent(BossEvents.Type.AttackStarted, args))
end

---@param bossContext BossContext
---@param args table
---@return nil
function BossEvents.EmitAttackTelegraphStarted(bossContext, args)
    BossEvents.Push(bossContext, MakeEvent(BossEvents.Type.AttackTelegraphStarted, args))
end

---@param bossContext BossContext
---@param args table
---@return nil
function BossEvents.EmitAttackHitWindowOpened(bossContext, args)
    BossEvents.Push(bossContext, MakeEvent(BossEvents.Type.AttackHitWindowOpened, args))
end

---@param bossContext BossContext
---@param args table
---@return nil
function BossEvents.EmitAttackHitWindowClosed(bossContext, args)
    BossEvents.Push(bossContext, MakeEvent(BossEvents.Type.AttackHitWindowClosed, args))
end

---@param bossContext BossContext
---@param args table
---@return nil
function BossEvents.EmitAttackEnded(bossContext, args)
    BossEvents.Push(bossContext, MakeEvent(BossEvents.Type.AttackEnded, args))
end

---@param bossContext BossContext
---@param args table
---@return nil
function BossEvents.EmitHit(bossContext, args)
    BossEvents.Push(bossContext, MakeEvent(BossEvents.Type.Hit, args))
end

---@param bossContext BossContext
---@param args table
---@return nil
function BossEvents.EmitStaggered(bossContext, args)
    BossEvents.Push(bossContext, MakeEvent(BossEvents.Type.Staggered, args))
end

---@param bossContext BossContext
---@param args table
---@return nil
function BossEvents.EmitDead(bossContext, args)
    BossEvents.Push(bossContext, MakeEvent(BossEvents.Type.Dead, args))
end

---@param event BossEvent
---@param eventType string
---@return boolean
function BossEvents.Is(event, eventType)
    return event ~= nil and event.Type == eventType
end

return BossEvents
