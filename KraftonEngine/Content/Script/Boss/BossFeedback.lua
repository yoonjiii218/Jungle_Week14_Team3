-- Boss/BossFeedback.lua
-- Owns boss visual/audio feedback only.
-- BossAttacks owns attack zone policy and hit request data.

local BossFeedback = {}

local BossContext = require("Boss/BossContext")
local BossEvents = require("Boss/BossEvents")
local Strict = require("Core/Strict")

local KATANA_MESH_PATH = "Content/Data/scifi-katana_extracted/source/KatanaSwordSketch_StaticMesh.uasset"
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

local function GetOrAddActionComponent(ownerActor)
    if ownerActor == nil or ownerActor:IsValid() ~= true then
        return nil
    end

    if ownerActor.GetActionComponent ~= nil then
        local action = ownerActor:GetActionComponent()
        if action ~= nil then
            return action
        end
    end

    if ownerActor.AddActionComponent ~= nil then
        return ownerActor:AddActionComponent()
    end

    return nil
end

local function ResolveBossMeshComponent(bossContext)
    local ownerActor = bossContext.Owner
    if ownerActor == nil or ownerActor:IsValid() ~= true then
        return nil
    end

    local meshComp = bossContext.Runtime.SkeletalMeshComp
    if meshComp == nil and ownerActor.GetSkeletalMeshComponent ~= nil then
        meshComp = ownerActor:GetSkeletalMeshComponent()
    end
    return meshComp
end

local function PlayHitSquash(bossContext, event)
    local feedbackConfig = bossContext.Config.FEEDBACK
    if feedbackConfig.HIT_SQUASH_ENABLED == false then
        return
    end

    local ownerActor = bossContext.Owner
    local meshComp = ResolveBossMeshComponent(bossContext)
    if meshComp == nil then
        if bossContext.Config.DEBUG then
            print("[BossFeedback] Hit squash skipped: SkeletalMeshComponent not found")
        end
        return
    end

    local action = GetOrAddActionComponent(ownerActor)
    if action == nil or action.HitSquashComponentByMultiplier == nil then
        if bossContext.Config.DEBUG then
            print("[BossFeedback] Hit squash skipped: ActionComponent.HitSquashComponentByMultiplier not available")
        end
        return
    end

    local ok, err = pcall(function()
        action:HitSquashComponentByMultiplier(
            meshComp,
            feedbackConfig.HIT_SQUASH_SCALE,
            feedbackConfig.HIT_SQUASH_IN_DURATION,
            feedbackConfig.HIT_SQUASH_RECOVER_DURATION
        )
    end)

    if not ok and bossContext.Config.DEBUG then
        print("[BossFeedback] Hit squash failed: " .. tostring(err))
    end
end

local function PlayHitShake(bossContext, event)
    local feedbackConfig = bossContext.Config.FEEDBACK
    if feedbackConfig.HIT_SHAKE_ENABLED == false then
        return
    end

    local ownerActor = bossContext.Owner
    local meshComp = ResolveBossMeshComponent(bossContext)
    if meshComp == nil then
        if bossContext.Config.DEBUG then
            print("[BossFeedback] Hit shake skipped: SkeletalMeshComponent not found")
        end
        return
    end

    local action = GetOrAddActionComponent(ownerActor)
    if action == nil or action.HitShakeComponent == nil then
        if bossContext.Config.DEBUG then
            print("[BossFeedback] Hit shake skipped: ActionComponent.HitShakeComponent not available")
        end
        return
    end

    local ok, err = pcall(function()
        action:HitShakeComponent(
            meshComp,
            feedbackConfig.HIT_SHAKE_AMPLITUDE or 3.0,
            feedbackConfig.HIT_SHAKE_DURATION or 0.08,
            feedbackConfig.HIT_SHAKE_FREQUENCY or 70.0
        )
    end)

    if not ok and bossContext.Config.DEBUG then
        print("[BossFeedback] Hit shake failed: " .. tostring(err))
    end
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

local function SpawnPiece(feedbackConfig, centerX, centerY, centerZ, yaw, length, width, color)
    local decal = VFX.SpawnGroundCrackDecal(
        feedbackConfig.DECAL_MATERIAL,
        Vector(centerX, centerY, centerZ),
        Vector(length, width, feedbackConfig.ZONE_HEIGHT),
        feedbackConfig.NO_FADE_DELAY,
        0.2
    )
    if decal then
        decal:SetRotation(Vector(0.0, 0.0, yaw))
        local c = color or feedbackConfig.ZONE_COLOR_IDLE
        decal:SetColorRGBA(c[1], c[2], c[3], c[4])
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
    local centerX = bossPos.X + dir.X * (length * 0.5)
    local centerY = bossPos.Y + dir.Y * (length * 0.5)

    -- 전체 범위를 아주 흐릿하게 미리 보여주는 윤곽 데칼 (차오름과 무관하게 고정 크기)
    local outlineDecals = {}
    local outlineDecal = SpawnPiece(
        feedbackConfig, centerX, centerY, spawnZ, yaw, length, width,
        feedbackConfig.ZONE_COLOR_OUTLINE
    )
    if outlineDecal then
        table.insert(outlineDecals, outlineDecal)
    end

    local decal = SpawnPiece(
        feedbackConfig, centerX, centerY, spawnZ, yaw, length, width,
        feedbackConfig.ZONE_COLOR_IDLE
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
        outlineDecals = outlineDecals,
        kind = "rect",
        origin = Vector(bossPos.X, bossPos.Y, bossPos.Z),
        yaw = yaw,
        length = length,
        width = width,
        decalZ = decalZ,
    }
end

local function SpawnFanPiece(feedbackConfig, centerX, centerY, centerZ, yaw, length, width, color)
    local decal = VFX.SpawnGroundCrackDecal(
        feedbackConfig.FAN_DECAL_MATERIAL,
        Vector(centerX, centerY, centerZ),
        Vector(length, width, feedbackConfig.ZONE_HEIGHT),
        feedbackConfig.NO_FADE_DELAY,
        0.2
    )
    if decal then
        decal:SetRotation(Vector(0.0, 0.0, yaw + (feedbackConfig.FAN_YAW_OFFSET or 0.0)))
        local c = color or feedbackConfig.ZONE_COLOR_IDLE
        decal:SetColorRGBA(c[1], c[2], c[3], c[4])
    end
    return decal
end

-- CircleZone.png decal: fixed translucent guide plus an opaque fill growing from the center.
local function ShowFanZone(bossContext)
    local feedbackConfig = bossContext.Config.FEEDBACK
    local bossPos = bossContext.Owner.Location
    local _, baseYaw = ResolveDirection(bossContext, bossContext.Brain.TargetActor)
    local radius = feedbackConfig.FAN_RADIUS
    local diameter = radius * 2.0
    local spawnZ = bossPos.Z + feedbackConfig.ZONE_Z_OFFSET
    local centerX = bossPos.X
    local centerY = bossPos.Y

    -- 전체 범위를 아주 흐릿하게 미리 보여주는 윤곽 데칼 (차오름과 무관하게 고정 크기)
    local outlineDecals = {}
    local outlineDecal = SpawnFanPiece(
        feedbackConfig, centerX, centerY, spawnZ, baseYaw, diameter, diameter,
        feedbackConfig.ZONE_COLOR_OUTLINE
    )
    if outlineDecal then
        table.insert(outlineDecals, outlineDecal)
    end

    local decal = SpawnFanPiece(
        feedbackConfig, centerX, centerY, spawnZ, baseYaw, diameter, diameter,
        feedbackConfig.ZONE_COLOR_IDLE
    )

    local decals = {}
    local decalZ = spawnZ
    if decal then
        table.insert(decals, decal)
        decalZ = decal.Location.Z
    elseif bossContext.Config.DEBUG then
        print("[BossFeedback] ShowFanZone decal spawn failed")
    end

    return {
        decals = decals,
        outlineDecals = outlineDecals,
        kind = "circle",
        origin = Vector(bossPos.X, bossPos.Y, bossPos.Z),
        yaw = baseYaw,
        radius = radius,
        length = diameter,
        width = diameter,
        decalZ = decalZ,
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

    for _, event in ipairs(events) do
        if BossEvents.Is(event, BossEvents.Type.Hit) then
            PlayHitSquash(bossContext, event)
            PlayHitShake(bossContext, event)
        end
    end
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
    if zone == nil then return end
    if zone.decals ~= nil then
        for _, decal in ipairs(zone.decals) do
            decal:SetFadeOut(0.0, 0.15)
        end
        zone.decals = {}
    end
    if zone.outlineDecals ~= nil then
        for _, decal in ipairs(zone.outlineDecals) do
            decal:SetFadeOut(0.0, 0.15)
        end
        zone.outlineDecals = {}
    end
    if bossContext.Feedback.CurrentTelegraph == zone then
        bossContext.Feedback.CurrentTelegraph = nil
    end
end

local function FillRectZone(bossContext, zone, ratio)
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

-- Grow the filled circle from the same center as the guide.
local function FillFanZone(bossContext, zone, ratio)
    local decal = zone.decals[1]
    if decal == nil then return end

    local feedbackConfig = bossContext.Config.FEEDBACK
    local fullDiameter = (zone.radius or feedbackConfig.FAN_RADIUS) * 2.0
    local fill = math.max(0.0, math.min(ratio, 1.0))
    local diameter = math.max(0.01, fullDiameter * fill)
    local cx = zone.origin.X
    local cy = zone.origin.Y
    local cz = zone.decalZ or decal.Location.Z or (zone.origin.Z + feedbackConfig.ZONE_Z_OFFSET)

    decal:SetLocation(Vector(cx, cy, cz))
    decal:SetRelativeScale(Vector(diameter, diameter, feedbackConfig.ZONE_HEIGHT))
end

---@param bossContext BossContext
---@param zone table
---@param ratio number
---@return nil
function BossFeedback.FillZone(bossContext, zone, ratio)
    BossContext.Assert(bossContext, "BossFeedback.FillZone")
    Strict.AssertNumber(ratio, "ratio", "BossFeedback.FillZone")
    if zone == nil or zone.decals == nil or #zone.decals == 0 then return end

    if zone.kind == "rect" then
        FillRectZone(bossContext, zone, ratio)
    elseif zone.kind == "fan" or zone.kind == "circle" then
        FillFanZone(bossContext, zone, ratio)
    end
end

return BossFeedback
