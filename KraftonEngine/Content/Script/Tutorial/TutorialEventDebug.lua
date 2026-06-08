-- Tutorial/TutorialEventDebug.lua
-- Temporary TrainingMap event logger. This is intentionally separate from the
-- future TutorialDirector so the first integration step can verify event flow.

local GameplayEventBus = require("Core/GameplayEventBus")
local PlayerEvents = require("Player/PlayerEvents")
local BossEvents = require("Boss/BossEvents")

local TutorialEventDebug = {}

local OWNER = { Name = "TutorialEventDebug" }
local queuedTrainingSceneName = nil
local active = false
local activeLabel = "TrainingMap"

local EVENT_TYPES = {
    -- Movement / camera basics
    PlayerEvents.Type.MoveStarted,
    PlayerEvents.Type.MoveStopped,
    PlayerEvents.Type.LookStarted,
    PlayerEvents.Type.LookStopped,

    -- Basic combat and combo tutorials
    PlayerEvents.Type.AttackStarted,
    PlayerEvents.Type.AttackHit,
    PlayerEvents.Type.AttackEnded,

    -- Dash / charge tutorials
    PlayerEvents.Type.DashStarted,
    PlayerEvents.Type.DashEnded,
    PlayerEvents.Type.DashChargingStarted,
    PlayerEvents.Type.DashChargingEnded,
    PlayerEvents.Type.DashChargeAttackStarted,
    PlayerEvents.Type.DashChargeAttackEnded,

    -- Enemy attack avoidance / perfect dodge tutorials
    PlayerEvents.Type.Hit,
    PlayerEvents.Type.PerfectDodge,

    -- Ultimate tutorial
    PlayerEvents.Type.GaugeChanged,
    PlayerEvents.Type.UltimateStarted,
    PlayerEvents.Type.UltimateEnded,
    PlayerEvents.Type.Dead,

    -- Boss/enemy-driven dodge tutorial hooks
    BossEvents.Type.AttackStarted,
    BossEvents.Type.AttackTelegraphStarted,
    BossEvents.Type.AttackHitWindowOpened,
    BossEvents.Type.AttackHitWindowClosed,
    BossEvents.Type.AttackEnded,
    BossEvents.Type.Hit,
    BossEvents.Type.Staggered,
    BossEvents.Type.Dead,
}

local function ActorName(actor)
    if actor == nil then
        return "nil"
    end
    if actor.GetName ~= nil then
        return tostring(actor:GetName())
    end
    if actor.UUID ~= nil then
        return tostring(actor.UUID)
    end
    return tostring(actor)
end

local function NumberText(value)
    if type(value) ~= "number" then
        return nil
    end
    return string.format("%.2f", value)
end

local function Append(parts, text)
    if text ~= nil and text ~= "" then
        table.insert(parts, text)
    end
end

local function FormatEvent(event)
    local parts = {}

    Append(parts, "seq=" .. tostring(event.Sequence or "?"))
    Append(parts, "t=" .. string.format("%.3f", event.Time or 0.0))

    if event.AttackId ~= nil then Append(parts, "attack=" .. tostring(event.AttackId)) end
    if event.AttackIndex ~= nil then Append(parts, "idx=" .. tostring(event.AttackIndex)) end
    if event.Damage ~= nil then Append(parts, "damage=" .. tostring(event.Damage)) end
    if event.GaugeDelta ~= nil then Append(parts, "gaugeDelta=" .. tostring(event.GaugeDelta)) end
    if event.ComboDelta ~= nil then Append(parts, "comboDelta=" .. tostring(event.ComboDelta)) end
    if event.Value ~= nil then Append(parts, "value=" .. tostring(event.Value)) end
    if event.MaxValue ~= nil then Append(parts, "max=" .. tostring(event.MaxValue)) end
    if event.HP ~= nil then Append(parts, "hp=" .. tostring(event.HP)) end
    if event.MaxHP ~= nil then Append(parts, "maxHp=" .. tostring(event.MaxHP)) end
    if event.HitDirection ~= nil then Append(parts, "hitDir=" .. tostring(event.HitDirection)) end
    if event.AxisX ~= nil or event.AxisY ~= nil then
        Append(parts, "axis=(" .. tostring(NumberText(event.AxisX) or event.AxisX or 0.0)
            .. "," .. tostring(NumberText(event.AxisY) or event.AxisY or 0.0) .. ")")
    end
    if event.Dir ~= nil then Append(parts, "dir=" .. tostring(event.Dir)) end
    if event.TargetActor ~= nil then Append(parts, "target=" .. ActorName(event.TargetActor)) end
    if event.SourceActor ~= nil then Append(parts, "source=" .. ActorName(event.SourceActor)) end
    if event.Threat ~= nil then Append(parts, "threat=" .. ActorName(event.Threat)) end

    return table.concat(parts, " ")
end

local function SubscribeEvent(eventType)
    GameplayEventBus.Subscribe(eventType, OWNER, function(event)
        print("[TutorialEventDebug] " .. tostring(activeLabel) .. " event=" .. tostring(event.Type) .. " " .. FormatEvent(event))
    end)
end

---@param sceneName string|nil
---@return nil
function TutorialEventDebug.QueueTrainingSession(sceneName)
    queuedTrainingSceneName = sceneName or "TrainingMap"
    print("[TutorialEventDebug] queued event debug for scene=" .. tostring(queuedTrainingSceneName))
end

---@return boolean
function TutorialEventDebug.HasQueuedTrainingSession()
    return queuedTrainingSceneName ~= nil
end

---@param label string|nil
---@return nil
function TutorialEventDebug.Begin(label)
    TutorialEventDebug.End()

    active = true
    activeLabel = label or queuedTrainingSceneName or "TrainingMap"
    queuedTrainingSceneName = nil

    for _, eventType in ipairs(EVENT_TYPES) do
        SubscribeEvent(eventType)
    end

    print("[TutorialEventDebug] begin event subscription label=" .. tostring(activeLabel)
        .. " count=" .. tostring(#EVENT_TYPES))
end

---@param label string|nil
---@return boolean
function TutorialEventDebug.BeginIfQueued(label)
    if queuedTrainingSceneName == nil then
        return false
    end

    TutorialEventDebug.Begin(label or queuedTrainingSceneName)
    return true
end

---@return nil
function TutorialEventDebug.End()
    if active == true then
        print("[TutorialEventDebug] end event subscription label=" .. tostring(activeLabel))
    end

    GameplayEventBus.ClearOwner(OWNER)
    active = false
end

return TutorialEventDebug
