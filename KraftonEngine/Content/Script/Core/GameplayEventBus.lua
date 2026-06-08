-- Core/GameplayEventBus.lua
-- Lightweight gameplay event publish/subscribe hub.
-- Internal PlayerEvents/BossEvents remain the source of truth; this bus exposes
-- those typed events to outer systems such as tutorials and debug tools.

local Strict = require("Core/Strict")

local GameplayEventBus = {}

local nextHandleId = 1
local subscribersByType = {}
local handlesById = {}
local eventSequence = 0

local WILDCARD_EVENT_TYPE = "*"

local function Now()
    if World ~= nil and World.GetGameTime ~= nil then
        return World.GetGameTime()
    end
    return 0.0
end

local function SafeEventType(eventType)
    if eventType == nil or eventType == "" then
        return WILDCARD_EVENT_TYPE
    end
    return eventType
end

local function AddSubscriber(eventType, handle)
    local key = SafeEventType(eventType)
    subscribersByType[key] = subscribersByType[key] or {}
    subscribersByType[key][handle.Id] = handle
end

local function RemoveSubscriber(handle)
    if handle == nil then
        return
    end

    local key = SafeEventType(handle.EventType)
    local bucket = subscribersByType[key]
    if bucket ~= nil then
        bucket[handle.Id] = nil
        if next(bucket) == nil then
            subscribersByType[key] = nil
        end
    end

    handlesById[handle.Id] = nil
end

---@param eventType string|nil use nil or "*" to receive every event
---@param owner any owner token used by ClearOwner
---@param callback function
---@return table
function GameplayEventBus.Subscribe(eventType, owner, callback)
    Strict.AssertFunction(callback, "callback", "GameplayEventBus.Subscribe")

    local handle = {
        Id = nextHandleId,
        EventType = SafeEventType(eventType),
        Owner = owner,
        Callback = callback,
    }
    nextHandleId = nextHandleId + 1

    handlesById[handle.Id] = handle
    AddSubscriber(handle.EventType, handle)
    return handle
end

---@param handle table|nil
---@return nil
function GameplayEventBus.Unsubscribe(handle)
    RemoveSubscriber(handle)
end

---@param owner any
---@return nil
function GameplayEventBus.ClearOwner(owner)
    if owner == nil then
        return
    end

    local toRemove = {}
    for id, handle in pairs(handlesById) do
        if handle.Owner == owner then
            table.insert(toRemove, id)
        end
    end

    for _, id in ipairs(toRemove) do
        RemoveSubscriber(handlesById[id])
    end
end

---@return nil
function GameplayEventBus.Reset()
    subscribersByType = {}
    handlesById = {}
    nextHandleId = 1
    eventSequence = 0
end

local function DispatchToBucket(bucket, event)
    if bucket == nil then
        return
    end

    local snapshot = {}
    for _, handle in pairs(bucket) do
        table.insert(snapshot, handle)
    end

    table.sort(snapshot, function(a, b)
        return (a.Id or 0) < (b.Id or 0)
    end)

    for _, handle in ipairs(snapshot) do
        if handlesById[handle.Id] ~= nil then
            local ok, err = pcall(handle.Callback, event)
            if not ok then
                print("[GameplayEventBus] subscriber failed for " .. tostring(event.Type) .. ": " .. tostring(err))
            end
        end
    end
end

---@param event table
---@param sourceContext table|nil
---@return nil
function GameplayEventBus.Publish(event, sourceContext)
    Strict.AssertTable(event, "event", "GameplayEventBus.Publish")
    Strict.AssertString(event.Type, "event.Type", "GameplayEventBus.Publish")

    eventSequence = eventSequence + 1
    event.Sequence = event.Sequence or eventSequence
    event.Time = event.Time or Now()

    if sourceContext ~= nil then
        event.SourceContext = event.SourceContext or sourceContext
        event.SourceOwner = event.SourceOwner or sourceContext.Owner
    end

    DispatchToBucket(subscribersByType[event.Type], event)
    DispatchToBucket(subscribersByType[WILDCARD_EVENT_TYPE], event)
end

---@param events table
---@param sourceContext table|nil
---@return nil
function GameplayEventBus.PublishMany(events, sourceContext)
    Strict.AssertTable(events, "events", "GameplayEventBus.PublishMany")
    for _, event in ipairs(events) do
        GameplayEventBus.Publish(event, sourceContext)
    end
end

return GameplayEventBus
