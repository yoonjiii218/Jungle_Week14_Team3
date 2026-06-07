-- Boss/BossFeedback.lua
-- Owns boss visual/audio feedback only.
-- BossAttacks owns attack zone policy and hit request data.

local BossFeedback = {}

local BossContext = require("Boss/BossContext")
local Strict = require("Core/Strict")

local KATANA_MESH_PATH = "Content/Mesh/Katana/source/red cyber katana_StaticMesh.uasset"
local KATANA_SOCKET_NAME = "pinky_01_r_socket"
local KATANA_LOCATION = Vector(0.0, 0.0, 0.0)
local KATANA_ROTATION = Vector(0.0, 0.0, 0.0)
local KATANA_SCALE = Vector(1.0, 1.0, 1.0)

local function AttachKatanaToBoss(bossContext)
    local ownerActor = bossContext.Owner
    if ownerActor == nil then return end

    if bossContext.Feedback.KatanaComponent ~= nil
        and bossContext.Feedback.KatanaComponent:IsValid() then
        return
    end

    local meshComp = bossContext.Runtime.SkeletalMeshComp
    if meshComp == nil then
        print("[BossFeedback] SkeletalMeshComponent not found")
        return
    end

    local katana = ownerActor:AddStaticMeshComponent()
    if katana == nil then
        print("[BossFeedback] Failed to create katana component")
        return
    end

    katana:SetMeshPath(KATANA_MESH_PATH)
    katana:AttachToComponentWithSocket(meshComp, KATANA_SOCKET_NAME)
    katana.RelativeLocation = KATANA_LOCATION
    katana:SetRotation(KATANA_ROTATION)
    katana:SetRelativeScale(KATANA_SCALE)

    bossContext.Feedback.KatanaComponent = katana
end

local function ResolveDirection(bossContext, targetActor)
    local bossPos = bossContext.Owner.Location
    if targetActor and targetActor:IsValid() then
        local toTarget = Vector(targetActor.Location.X - bossPos.X, targetActor.Location.Y - bossPos.Y, 0.0)
        if toTarget:Length() > 0.001 then
            local dir = toTarget:Normalized()
            local yaw = math.atan2(dir.Y, dir.X) * 180.0 / math.pi
            return dir, yaw
        end
    end

    local forward = bossContext.Owner.Forward
    local yaw = math.atan2(forward.Y, forward.X) * 180.0 / math.pi
    return forward, yaw
end

local function SpawnPiece(feedbackConfig, centerX, centerY, centerZ, yaw, length, width)
    local decal = VFX.SpawnGroundCrackDecal(
        feedbackConfig.DECAL_MATERIAL,
        Vector(centerX, centerY, centerZ),
        Vector(length, width, feedbackConfig.ZONE_HEIGHT),
        feedbackConfig.NO_FADE_DELAY,
        0.2
    )
    if decal then
        decal:SetRotation(Vector(0.0, 0.0, yaw))
        local color = feedbackConfig.ZONE_COLOR_IDLE
        decal:SetColorRGBA(color[1], color[2], color[3], color[4])
    end
    return decal
end

local function ShowRectZone(bossContext, args)
    local feedbackConfig = bossContext.Config.FEEDBACK
    local bossPos = bossContext.Owner.Location
    local dir, yaw = ResolveDirection(bossContext, bossContext.Brain.TargetActor)
    local length = args.Length or feedbackConfig.ZONE_LENGTH
    local width = args.Width or feedbackConfig.ZONE_WIDTH
    local spawnZ = bossPos.Z + feedbackConfig.ZONE_Z_OFFSET

    local decal = SpawnPiece(
        feedbackConfig,
        bossPos.X + dir.X * (length * 0.5),
        bossPos.Y + dir.Y * (length * 0.5),
        spawnZ,
        yaw,
        length,
        width
    )

    local decals = {}
    local decalZ = spawnZ
    if decal then
        table.insert(decals, decal)
        decalZ = decal.Location.Z
    elseif bossContext.Config.DEBUG then
        print("[BossFeedback] ShowRectZone decal spawn failed")
    end

    return {
        decals = decals,
        kind = "rect",
        origin = Vector(bossPos.X, bossPos.Y, bossPos.Z),
        yaw = yaw,
        length = length,
        width = width,
        decalZ = decalZ,
    }
end

local function ShowFanZone(bossContext)
    local feedbackConfig = bossContext.Config.FEEDBACK
    local bossPos = bossContext.Owner.Location
    local _, baseYaw = ResolveDirection(bossContext, bossContext.Brain.TargetActor)
    local decals = {}
    local segmentCount = feedbackConfig.FAN_SEGMENTS
    local halfAngle = feedbackConfig.FAN_ANGLE * 0.5

    for i = 0, segmentCount - 1 do
        local offset = -halfAngle + feedbackConfig.FAN_ANGLE * ((i + 0.5) / segmentCount)
        local segmentYaw = baseYaw + offset
        local rad = segmentYaw * math.pi / 180.0
        local dx, dy = math.cos(rad), math.sin(rad)
        local decal = SpawnPiece(
            feedbackConfig,
            bossPos.X + dx * (feedbackConfig.FAN_RADIUS * 0.5),
            bossPos.Y + dy * (feedbackConfig.FAN_RADIUS * 0.5),
            bossPos.Z + feedbackConfig.ZONE_Z_OFFSET,
            segmentYaw,
            feedbackConfig.FAN_RADIUS,
            feedbackConfig.FAN_SEG_WIDTH
        )
        if decal then
            table.insert(decals, decal)
        end
    end

    if #decals == 0 and bossContext.Config.DEBUG then
        print("[BossFeedback] ShowFanZone decal spawn failed")
    end

    return {
        decals = decals,
        kind = "fan",
        origin = Vector(bossPos.X, bossPos.Y, bossPos.Z),
        yaw = baseYaw,
    }
end

-- =========================================================
-- Public API
-- =========================================================

---@param bossContext BossContext
---@return nil
function BossFeedback.Init(bossContext)
    BossContext.Assert(bossContext, "BossFeedback.Init")
    local ok, err = pcall(function()
        AttachKatanaToBoss(bossContext)
    end)
    if not ok then
        print("[BossFeedback] AttachKatanaToBoss failed: " .. tostring(err))
    end
end

---@param bossContext BossContext
---@param events BossEvent[]
---@return nil
function BossFeedback.ProcessEvents(bossContext, events)
    BossContext.Assert(bossContext, "BossFeedback.ProcessEvents")
    Strict.AssertTable(events, "events", "BossFeedback.ProcessEvents")
end

---@param bossContext BossContext
---@param args table
---@return table
function BossFeedback.ShowAttackZone(bossContext, args)
    BossContext.Assert(bossContext, "BossFeedback.ShowAttackZone")
    Strict.AssertTable(args, "args", "BossFeedback.ShowAttackZone")

    local shape = args.Shape or "Rect"
    local zone
    if shape == "Fan" then
        zone = ShowFanZone(bossContext)
    elseif shape == "P1" then
        zone = ShowRectZone(bossContext, {
            Length = bossContext.Config.FEEDBACK.P1_LENGTH,
            Width = bossContext.Config.FEEDBACK.P1_WIDTH,
        })
    else
        zone = ShowRectZone(bossContext, args)
    end

    bossContext.Feedback.CurrentTelegraph = zone
    return zone
end

---@param bossContext BossContext
---@param args table
---@return nil
function BossFeedback.HideAttackZone(bossContext, args)
    BossContext.Assert(bossContext, "BossFeedback.HideAttackZone")
    Strict.AssertTable(args, "args", "BossFeedback.HideAttackZone")
    local zone = args.Zone
    if zone == nil or zone.decals == nil then return end
    for _, decal in ipairs(zone.decals) do
        decal:SetFadeOut(0.0, 0.15)
    end
    zone.decals = {}
    if bossContext.Feedback.CurrentTelegraph == zone then
        bossContext.Feedback.CurrentTelegraph = nil
    end
end

---@param bossContext BossContext
---@param zone table
---@param ratio number
---@return nil
function BossFeedback.FillZone(bossContext, zone, ratio)
    BossContext.Assert(bossContext, "BossFeedback.FillZone")
    Strict.AssertNumber(ratio, "ratio", "BossFeedback.FillZone")
    if zone == nil or zone.decals == nil or #zone.decals == 0 then return end
    if zone.kind ~= "rect" then return end

    local decal = zone.decals[1]
    if decal == nil then return end

    local feedbackConfig = bossContext.Config.FEEDBACK
    local full = zone.length or feedbackConfig.ZONE_LENGTH
    local width = zone.width or feedbackConfig.ZONE_WIDTH
    local length = math.max(0.01, full * ratio)
    local rad = zone.yaw * math.pi / 180.0
    local dx, dy = math.cos(rad), math.sin(rad)
    local cx = zone.origin.X + dx * (length * 0.5)
    local cy = zone.origin.Y + dy * (length * 0.5)
    local cz = zone.decalZ or decal.Location.Z or (zone.origin.Z + feedbackConfig.ZONE_Z_OFFSET)

    decal:SetLocation(Vector(cx, cy, cz))
    decal:SetRelativeScale(Vector(length, width, feedbackConfig.ZONE_HEIGHT))
end

---@param bossContext BossContext
---@param zone table
---@return nil
function BossFeedback.FlashZone(bossContext, zone)
    BossContext.Assert(bossContext, "BossFeedback.FlashZone")
    if zone == nil or zone.decals == nil then return end
    local color = bossContext.Config.FEEDBACK.ZONE_COLOR_FLASH
    for _, decal in ipairs(zone.decals) do
        decal:SetColorRGBA(color[1], color[2], color[3], color[4])
    end
end

return BossFeedback
