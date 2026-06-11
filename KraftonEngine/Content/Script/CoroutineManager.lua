-- CoroutineManager.lua
-- Per-owner coroutine pools.
--
-- A coroutine must only ever be advanced by the dt of the actor that started
-- it (Player / Boss / Mob each tick with their own, possibly time-scaled, dt).
-- Mixing dt sources breaks anything that depends on elapsed time — zone fill
-- ratios, WaitForNotify timeouts, Wait() recovery timers — which is exactly
-- what happens once per-actor TimeScale diverges (perfect-dodge slomo slows
-- the boss/mobs while speeding the player up).
--
-- Owners bracket their Tick with CoroutineManager.Begin(key)/End() so the
-- existing global StartCoroutine/Wait/WaitFrame/UpdateCoroutines calls used
-- throughout attack/feedback code keep working unchanged, just routed to that
-- owner's own pool.

local CoroutineManager = {}
CoroutineManager.__index = CoroutineManager

local pools = {}
local current = nil

local function GetOrCreatePool(ownerKey)
    local pool = pools[ownerKey]
    if pool == nil then
        pool = setmetatable({ coroutines = {} }, CoroutineManager)
        pools[ownerKey] = pool
    end
    return pool
end

---@param ownerKey any  unique per-actor key (e.g. obj.UUID)
---@return table the owner's coroutine pool
function CoroutineManager.Begin(ownerKey)
    current = GetOrCreatePool(ownerKey)
    return current
end

---@return nil
function CoroutineManager.End()
    current = nil
end

---@param ownerKey any
---@return nil
function CoroutineManager.Destroy(ownerKey)
    local pool = pools[ownerKey]
    if pool == nil then
        return
    end

    pool:StopAll()
    pools[ownerKey] = nil
    if current == pool then
        current = nil
    end
end

local function CurrentPool(callerName)
    if current == nil then
        error(callerName .. " called outside of CoroutineManager.Begin/End scope")
    end
    return current
end

function StartCoroutine(func)
    return CurrentPool("StartCoroutine"):Create(func)
end

function StopCoroutine(handle)
    return CurrentPool("StopCoroutine"):Stop(handle)
end

function StopAllCoroutines()
    CurrentPool("StopAllCoroutines"):StopAll()
end

---@param ownerKey any
---@param func function
---@return table|nil
function CoroutineManager.StartForOwner(ownerKey, func)
    if ownerKey == nil or func == nil then
        return nil
    end

    -- Queue the coroutine into the owner's pool, but do not resume it immediately.
    -- Attack notifies can be fired while the engine is iterating collision targets;
    -- deferred follow-up hits run during the owner's next coroutine tick instead
    -- of recursively mutating combat / collision state in that C++ traversal.
    return GetOrCreatePool(ownerKey):Create(func, false)
end

function Wait(seconds)
    return CurrentPool("Wait"):Wait(seconds)
end

-- Waits using real frame time, ignoring global/custom time dilation.
-- Use this for camera/cutscene presentation that must remain smooth during slomo.
function WaitRaw(seconds)
    return CurrentPool("WaitRaw"):WaitRaw(seconds)
end

function WaitFrame()
    return CurrentPool("WaitFrame"):WaitFrame()
end

function WaitFrameRaw()
    return CurrentPool("WaitFrameRaw"):WaitFrameRaw()
end

function WaitUntil(predicate)
    CurrentPool("WaitUntil"):WaitUntil(predicate)
end

function UpdateCoroutines(dt)
    CurrentPool("UpdateCoroutines"):Update(dt)
end

function CoroutineManager:Create(func, resumeImmediately)
    local routine = {
        co = coroutine.create(func),
        wait = nil,
        dead = false
    }

    table.insert(self.coroutines, routine)
    if resumeImmediately ~= false then
        self:Resume(routine, 0)
    end

    return routine
end

function CoroutineManager:Stop(handle)
    if handle == nil then
        return false
    end

    for i = #self.coroutines, 1, -1 do
        local routine = self.coroutines[i]
        if routine == handle or routine.co == handle then
            routine.dead = true
            table.remove(self.coroutines, i)
            return true
        end
    end

    return false
end

function CoroutineManager:StopAll()
    for i = #self.coroutines, 1, -1 do
        local routine = self.coroutines[i]
        routine.dead = true
        table.remove(self.coroutines, i)
    end
end

function CoroutineManager:Resume(routine, dt)
    local success, waitInfo = coroutine.resume(routine.co, dt or 0)

    if not success then
        print("Error in coroutine: " .. tostring(waitInfo))
        routine.dead = true
        return
    end

    routine.wait = waitInfo
end

function CoroutineManager:Wait(seconds)
    return coroutine.yield({
        type = "wait",
        time = seconds,
        elapsed = 0.0
    }) or 0.0
end

function CoroutineManager:WaitRaw(seconds)
    return coroutine.yield({
        type = "wait_raw",
        time = seconds,
        elapsed = 0.0
    }) or 0.0
end

function CoroutineManager:WaitFrame()
    return coroutine.yield({
        type = "frame"
    }) or 0.0
end

function CoroutineManager:WaitFrameRaw()
    return coroutine.yield({
        type = "frame_raw"
    }) or 0.0
end

function CoroutineManager:WaitUntil(predicate)
    coroutine.yield({
        type = "wait_until",
        predicate = predicate
    })
end

local function GetRawDeltaTime(fallback)
    local rawDelta = tonumber(fallback) or 0.0

    if World ~= nil and World.GetRawDeltaTime ~= nil then
        local ok, value = pcall(World.GetRawDeltaTime)
        if ok and value ~= nil then
            rawDelta = tonumber(value) or rawDelta
        end
    end

    if rawDelta < 0.0 then
        rawDelta = 0.0
    end
    return rawDelta
end

function CoroutineManager:Update(dt)
    local scaledDelta = tonumber(dt) or 0.0
    local rawDelta = nil

    for i = #self.coroutines, 1, -1 do
        local routine = self.coroutines[i]

        if coroutine.status(routine.co) == "dead" or routine.dead then
            table.remove(self.coroutines, i)
        else
            local wait = routine.wait
            local shouldResume = false
            local resumeDelta = scaledDelta

            if wait == nil then
                shouldResume = true
            elseif wait.type == "wait" then
                wait.time = wait.time - scaledDelta
                wait.elapsed = (wait.elapsed or 0.0) + scaledDelta
                resumeDelta = wait.elapsed
                shouldResume = wait.time <= 0
            elseif wait.type == "wait_raw" then
                if rawDelta == nil then
                    rawDelta = GetRawDeltaTime(scaledDelta)
                end
                wait.time = wait.time - rawDelta
                wait.elapsed = (wait.elapsed or 0.0) + rawDelta
                resumeDelta = wait.elapsed
                shouldResume = wait.time <= 0
            elseif wait.type == "frame" then
                shouldResume = true
            elseif wait.type == "frame_raw" then
                if rawDelta == nil then
                    rawDelta = GetRawDeltaTime(scaledDelta)
                end
                resumeDelta = rawDelta
                shouldResume = true
            elseif wait.type == "wait_until" then
                local ok, result = pcall(wait.predicate)
                if not ok then
                    print("Error in wait_until predicate: " .. result)
                    routine.dead = true
                else
                    shouldResume = result == true
                end
            else
                shouldResume = true
            end

            if shouldResume and not routine.dead then
                self:Resume(routine, resumeDelta)
            end
        end
    end
end

return CoroutineManager
