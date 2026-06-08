-- Boss/BossHitbox.lua
-- Pure Lua geometry checks for boss attack zones.
-- Receives explicit bossContext and zone data from BossAttacks.

local BossHitbox = {}

local BossContext = require("Boss/BossContext")
local Strict = require("Core/Strict")

-- =========================================================
-- Public API
-- =========================================================

---@param bossContext BossContext
---@return nil
function BossHitbox.Init(bossContext)
    BossContext.Assert(bossContext, "BossHitbox.Init")
end

---@param bossContext BossContext
---@param zone table
---@param px number
---@param py number
---@return boolean
function BossHitbox.CheckRectXY(bossContext, zone, px, py)
    BossContext.Assert(bossContext, "BossHitbox.CheckRectXY")
    Strict.AssertNumber(px, "px", "BossHitbox.CheckRectXY")
    Strict.AssertNumber(py, "py", "BossHitbox.CheckRectXY")
    if zone == nil or zone.origin == nil then return false end

    local feedbackConfig = bossContext.Config.FEEDBACK
    local length = zone.length or feedbackConfig.ZONE_LENGTH
    local width = zone.width or feedbackConfig.ZONE_WIDTH
    local origin = zone.origin
    local dx = px - origin.X
    local dy = py - origin.Y
    local rad = zone.yaw * math.pi / 180.0
    local fx, fy = math.cos(rad), math.sin(rad)
    local rx, ry = -fy, fx
    local forwardDist = dx * fx + dy * fy
    local sideDist = dx * rx + dy * ry

    return forwardDist >= 0.0
        and forwardDist <= length
        and math.abs(sideDist) <= width * 0.5
end

---@param bossContext BossContext
---@param zone table
---@param px number
---@param py number
---@return boolean
function BossHitbox.CheckFanXY(bossContext, zone, px, py)
    BossContext.Assert(bossContext, "BossHitbox.CheckFanXY")
    Strict.AssertNumber(px, "px", "BossHitbox.CheckFanXY")
    Strict.AssertNumber(py, "py", "BossHitbox.CheckFanXY")
    if zone == nil or zone.origin == nil then return false end

    local feedbackConfig = bossContext.Config.FEEDBACK
    local origin = zone.origin
    local toPx = px - origin.X
    local toPy = py - origin.Y
    local dist = math.sqrt(toPx * toPx + toPy * toPy)
    if dist > feedbackConfig.FAN_RADIUS then return false end
    if dist < 0.001 then return true end

    local targetYaw = math.atan2(toPy, toPx) * 180.0 / math.pi
    local diff = targetYaw - zone.yaw
    while diff > 180.0 do diff = diff - 360.0 end
    while diff < -180.0 do diff = diff + 360.0 end

    return math.abs(diff) <= feedbackConfig.FAN_ANGLE * 0.5
end

---@param bossContext BossContext
---@param zone table
---@param px number
---@param py number
---@return boolean
function BossHitbox.CheckCircleXY(bossContext, zone, px, py)
    BossContext.Assert(bossContext, "BossHitbox.CheckCircleXY")
    Strict.AssertNumber(px, "px", "BossHitbox.CheckCircleXY")
    Strict.AssertNumber(py, "py", "BossHitbox.CheckCircleXY")
    if zone == nil or zone.origin == nil then return false end

    local feedbackConfig = bossContext.Config.FEEDBACK
    local radius = zone.radius or feedbackConfig.FAN_RADIUS
    local dx = px - zone.origin.X
    local dy = py - zone.origin.Y
    return dx * dx + dy * dy <= radius * radius
end

---@param bossContext BossContext
---@param zone table
---@param px number
---@param py number
---@return boolean
function BossHitbox.CheckXY(bossContext, zone, px, py)
    BossContext.Assert(bossContext, "BossHitbox.CheckXY")
    if zone == nil then return false end
    if zone.kind == "circle" then
        return BossHitbox.CheckCircleXY(bossContext, zone, px, py)
    end
    if zone.kind == "fan" then
        return BossHitbox.CheckFanXY(bossContext, zone, px, py)
    end
    return BossHitbox.CheckRectXY(bossContext, zone, px, py)
end

---@param bossContext BossContext
---@param zone table
---@param targetActor any
---@return boolean
function BossHitbox.CheckRect(bossContext, zone, targetActor)
    BossContext.Assert(bossContext, "BossHitbox.CheckRect")
    if not (targetActor and targetActor:IsValid()) then return false end
    local targetPos = targetActor.Location
    return BossHitbox.CheckRectXY(bossContext, zone, targetPos.X, targetPos.Y)
end

---@param bossContext BossContext
---@param zone table
---@param targetActor any
---@return boolean
function BossHitbox.CheckFan(bossContext, zone, targetActor)
    BossContext.Assert(bossContext, "BossHitbox.CheckFan")
    if not (targetActor and targetActor:IsValid()) then return false end
    local targetPos = targetActor.Location
    return BossHitbox.CheckFanXY(bossContext, zone, targetPos.X, targetPos.Y)
end

---@param bossContext BossContext
---@param zone table
---@param targetActor any
---@return boolean
function BossHitbox.Check(bossContext, zone, targetActor)
    BossContext.Assert(bossContext, "BossHitbox.Check")
    if zone == nil then return false end
    if not (targetActor and targetActor:IsValid()) then return false end
    return BossHitbox.CheckXY(bossContext, zone, targetActor.Location.X, targetActor.Location.Y)
end

return BossHitbox
