-- Player/PlayerFeedback.lua
-- PlayerFeedback owns presentation: camera, VFX, trails, hitstop/slomo visuals.
-- It consumes PlayerEvent lists and should not own gameplay state transitions.

local PlayerFeedback = {}

local PlayerContext = require("Player/PlayerContext")
local PlayerEvents = require("Player/PlayerEvents")
local function GetFeedbackConfig(player)
    return player.Config.Feedback
end

local function GetUltimateCameraConfig(player)
    return GetFeedbackConfig(player).UltimateCamera
end

local function GetUltimateVfxConfig(player)
    return GetFeedbackConfig(player).UltimateVfx
end

local function GetUltimateMoveConfig(player)
    return GetFeedbackConfig(player).UltimateMove
end

local function Clamp(v, minValue, maxValue)
    if v < minValue then return minValue end
    if v > maxValue then return maxValue end
    return v
end

local function EaseOutCubic(t)
    local u = 1.0 - t
    return 1.0 - u * u * u
end

local function Bezier2(a, b, c, t)
    local u = 1.0 - t
    return a * (u * u) + b * (2.0 * u * t) + c * (t * t)
end

local function GetOwner(player)
    return player.Owner
end

local function PlayPerfectDodgeFeedback(ctx, event)
    local feedbackConfig = GetFeedbackConfig(ctx)
    local perfectDodgeConfig = feedbackConfig.PerfectDodge
    local shakeScale = perfectDodgeConfig.CameraShakeScale

    if CameraManager ~= nil and CameraManager.StartWaveShake ~= nil and shakeScale > 0.0 then
        CameraManager.StartWaveShake(shakeScale)
    end

    print("Perfect Dodge")
end

local function BuildGroundDecalAABBScale3(a, b, c, padding, minSize, projectionDepth)
    padding = padding or 5.0
    minSize = minSize or 8.0
    projectionDepth = projectionDepth or 16.0

    local minX = math.min(a.X, b.X, c.X)
    local maxX = math.max(a.X, b.X, c.X)
    local minY = math.min(a.Y, b.Y, c.Y)
    local maxY = math.max(a.Y, b.Y, c.Y)

    local sizeX = math.max((maxX - minX) + padding * 2.0, minSize)
    local sizeY = math.max((maxY - minY) + padding * 2.0, minSize)

    local center = Vector(
        (minX + maxX) * 0.5,
        (minY + maxY) * 0.5,
        a.Z
    )

    return center, Vector(sizeX, sizeY, projectionDepth)
end

local function GetUltimateCameraRotation(cameraConfig, baseRotation, t)
    local rotationStart = cameraConfig.RotationStart
    if t <= rotationStart then
        return baseRotation
    end

    local rotationT = Clamp((t - rotationStart) / (1.0 - rotationStart), 0.0, 1.0)
    local pitchSwing = cameraConfig.PitchSwing
    local yawSwing = cameraConfig.YawSwing
    local rollSwing = cameraConfig.RollSwing

    local pitch =
        baseRotation.X
        - math.sin(rotationT * math.pi) * pitchSwing
        + math.sin(rotationT * math.pi * 4.0) * (pitchSwing * 0.35)

    local roll = baseRotation.Y + math.sin(rotationT * math.pi * 4.0) * rollSwing
    local yaw = baseRotation.Z + math.sin(rotationT * math.pi * 2.0) * yawSwing

    return Vector(pitch, roll, yaw)
end

local function GetSafeOwnerBasis(owner)
    local forward = Reflection.Call(owner, "GetActorForward")
    if forward == nil then
        return nil, nil
    end

    forward.Z = 0.0
    if forward:Length() <= 0.001 then
        return nil, nil
    end
    forward = forward:Normalized()

    local right = Reflection.Call(owner, "GetActorRight")
    if right == nil then
        right = Vector(-forward.Y, forward.X, 0.0)
    else
        right.Z = 0.0
        if right:Length() <= 0.001 then
            right = Vector(-forward.Y, forward.X, 0.0)
        else
            right = right:Normalized()
        end
    end

    return forward, right
end

local function FaceOwnerToDirection(ctx, dir)
    local owner = GetOwner(ctx)
    if owner == nil or dir == nil then
        return
    end

    local targetYaw = math.atan2(dir.Y, dir.X) * 180.0 / math.pi
    Reflection.Call(owner, "SetActorRotation", Vector(0.0, 0.0, targetYaw))
end

-- =========================================================
-- Public API
-- =========================================================

---@param player PlayerContext
---@return nil
function PlayerFeedback.AttachKatanaToWeaponSocket(player)
    local ctx = PlayerContext.Assert(player, "PlayerFeedback.AttachKatanaToWeaponSocket")
    local owner = GetOwner(ctx)
    if owner == nil then
        return
    end

    if ctx.Feedback.KatanaComponent ~= nil and ctx.Feedback.KatanaComponent:IsValid() then
        if ctx.Feedback.KatanaComponent:GetOwner() == owner then
            print("Katana already exists")
            return
        end

        ctx.Feedback.KatanaComponent = nil
    end

    if owner.GetSkeletalMeshComponent == nil or owner.AddStaticMeshComponent == nil then
        print("Katana attach API not available")
        return
    end

    local meshComp = owner:GetSkeletalMeshComponent()
    if meshComp == nil then
        print("Player skeletal mesh component not found")
        return
    end

    local katana = owner:AddStaticMeshComponent()
    if katana == nil then
        print("Failed to create Katana static mesh component")
        return
    end

    local feedbackConfig = GetFeedbackConfig(ctx)
    katana:SetMeshPath(feedbackConfig.KatanaMeshPath)
    katana:AttachToComponentWithSocket(meshComp, feedbackConfig.KatanaSocketName)
    katana.RelativeLocation = Vector(0.0, 0.0, 0.0)
    katana:SetRotation(Vector(0.0, 0.0, 0.0))
    katana:SetRelativeScale(Vector(1.0, 1.0, 1.0))

    ctx.Feedback.KatanaComponent = katana
end

---@param player PlayerContext
---@return nil
function PlayerFeedback.SetKatanaTrailActive(player, active)
    local ctx = PlayerContext.Assert(player, "PlayerFeedback.SetKatanaTrailActive")
    local PSC = ctx.Feedback.KatanaPSC
    if PSC == nil or not PSC:IsValid() then
        return
    end

    if active then
        PSC:Activate()
    else
        PSC:Deactivate()
    end
end

---@param player PlayerContext
---@return nil
function PlayerFeedback.AttachPSCToWeaponSocket(player)
    local ctx = PlayerContext.Assert(player, "PlayerFeedback.AttachPSCToWeaponSocket")
    local owner = GetOwner(ctx)
    if owner == nil then
        return
    end

    if ctx.Feedback.KatanaPSC ~= nil and ctx.Feedback.KatanaPSC:IsValid() then
        return
    end

    local meshComp = owner:GetSkeletalMeshComponent()
    if meshComp == nil then
        print("Player skeletal mesh component not found")
        return
    end

    local PSC = owner:AddParticleSystemComponent()
    if PSC == nil then
        print("Failed to create PSC")
        return
    end

    local feedbackConfig = GetFeedbackConfig(ctx)
    PSC:SetTemplatePath(feedbackConfig.TrailParticlePath)
    PSC:SetAnimTrailSourceComponent(meshComp)
    PSC:AttachToComponentWithSocket(meshComp, feedbackConfig.KatanaSocketName)
    PSC.RelativeLocation = Vector(0.0, 0.0, 0.0)
    PSC:SetRotation(Vector(0.0, 0.0, 0.0))
    PSC:SetRelativeScale(Vector(1.0, 1.0, 1.0))

    ctx.Feedback.KatanaPSC = PSC
    PlayerFeedback.SetKatanaTrailActive(ctx, false)
end

---@param player PlayerContext
---@return nil
function PlayerFeedback.Init(player)
    local ctx = PlayerContext.Assert(player, "PlayerFeedback.Init")
    PlayerFeedback.AttachKatanaToWeaponSocket(ctx)
    PlayerFeedback.AttachPSCToWeaponSocket(ctx)
end

---@param player PlayerContext
---@return nil
function PlayerFeedback.Shutdown(player)
    local ctx = PlayerContext.Assert(player, "PlayerFeedback.Shutdown")
    ctx.Feedback.KatanaComponent = nil
    ctx.Feedback.KatanaPSC = nil
end

---@param player PlayerContext
---@return nil
function PlayerFeedback.BeginUltimate(player)
    local ctx = PlayerContext.Assert(player, "PlayerFeedback.BeginUltimate")
    print("Begin Ultimate")

    ctx.Action.IsUltimateRunning = true
    ctx.Action.IsInUltimateMode = false

    local owner = GetOwner(ctx)
    if owner == nil then
        ctx.Action.IsUltimateRunning = false
        return
    end

    local movementComp = owner:GetCharacterMovement()
    if movementComp == nil then
        print("Movement not found")
        ctx.Action.IsUltimateRunning = false
        return
    end

    local ultimateCamera = World.FindFirstActorByTag("UltimateCamera")
    if ultimateCamera == nil then
        print("UltimateCamera not found")
        ctx.Action.IsUltimateRunning = false
        return
    end

    local actorLocation = Reflection.Call(owner, "GetActorLocation")
    local actorForward, actorRight = GetSafeOwnerBasis(owner)

    if actorLocation == nil or actorForward == nil or actorRight == nil then
        print("Invalid owner transform")
        ctx.Action.IsUltimateRunning = false
        return
    end

    local PrimComp = owner:GetPrimitiveComponent()
    local PrevSimulatePhysics = false

    if PrimComp ~= nil then
        PrevSimulatePhysics = Reflection.Call(PrimComp, "GetSimulatePhysics")
        Reflection.Call(PrimComp, "SetSimulatePhysics", false)
    end

    local up = Vector(0.0, 0.0, 1.0)
    local cameraConfig = GetUltimateCameraConfig(ctx)
    local moveConfig = GetUltimateMoveConfig(ctx)
    local vfxConfig = GetUltimateVfxConfig(ctx)
    local cameraLocation =
        actorLocation
        - actorForward * (cameraConfig.BackDistance)
        + up * (cameraConfig.Height)

    local slashAnchor =
        cameraLocation
        + actorForward * (cameraConfig.SlashCameraDistance)
        + up * (cameraConfig.SlashCameraHeightOffset)
        + actorRight * (cameraConfig.SlashCameraRightOffset)

    local cameraYaw = math.atan2(actorForward.Y, actorForward.X) * 180.0 / math.pi
    local baseCameraRotation = Vector(-10.0, 15.0, cameraYaw)

    Reflection.Call(ultimateCamera, "SetActorLocation", cameraLocation)
    Reflection.Call(ultimateCamera, "SetActorRotation", GetUltimateCameraRotation(cameraConfig, baseCameraRotation, 0.0))

    CameraManager.ToggleOwnerCamera(ultimateCamera, 0)
    Reflection.Call(movementComp, "StopMovementImmediately")
    Reflection.Call(movementComp, "SetMovementInputEnabled", false)

    Wait(0.15)

    local startPos =
        cameraLocation
        + actorForward * (moveConfig.StartDistance)
        + actorRight * (moveConfig.SideOffset)

    startPos.Z = actorLocation.Z

    local cinematicEndPos =
        cameraLocation
        + actorForward * (moveConfig.EndDistance)
        + actorRight * (moveConfig.EndRightDistance)

    cinematicEndPos.Z = actorLocation.Z

    local controlPos =
        cameraLocation
        + actorForward * (((moveConfig.StartDistance) + (moveConfig.EndDistance)) * 0.5)
        + actorRight * (moveConfig.ControlSideOffset)

    controlPos.Z = actorLocation.Z

    local decalPos, decalScale = BuildGroundDecalAABBScale3(
        startPos,
        controlPos,
        cinematicEndPos,
        0.0,
        0.0,
        16.0
    )

    Reflection.Call(owner, "SetActorLocation", startPos)

    local elapsed = 0.0
    local prevPos = startPos

    local spawnedAirSlashA = false
    local spawnedAirSlashB = false
    local spawnedAirSlashC = false
    local spawnedAirSlashD = false
    local spawnedAirSlashE = false
    local spawnedSlashFlash = false

    ctx.Action.IsInUltimateMode = true

    local moveDuration = moveConfig.Duration
    local frameStep = moveConfig.FrameStep

    while elapsed < moveDuration do
        Wait(frameStep)

        elapsed = elapsed + frameStep

        local t = Clamp(elapsed / moveDuration, 0.0, 1.0)
        local easedT = EaseOutCubic(t)

        if not spawnedSlashFlash and t >= 0.38 then
            VFX.SpawnSlashFlash(
                vfxConfig.SlashFlashPath,
                slashAnchor + actorForward * 2.0 + up * 1.0,
                Vector(0.0, 0.0, 0.0),
                Vector(1.0, 1.8, 1.8),
                0.25,
                vfxConfig.LightningMaterialPath
            )
            spawnedSlashFlash = true
        end

        if not spawnedAirSlashA and t >= 0.20 then
            VFX.SpawnSubUV(vfxConfig.SlashSubUVResource, slashAnchor - actorForward * 6.0 - actorRight * 8.0 + up * 0.4, Vector(1.0, 88.0, 7.0), -12.0, vfxConfig.SlashFrameRate, false, true)
            spawnedAirSlashA = true
        end

        if not spawnedAirSlashB and t >= 0.34 then
            VFX.SpawnSubUV(vfxConfig.SlashSubUVResource, slashAnchor + actorForward * 2.0 + actorRight * 9.0 + up * 3.0, Vector(1.0, 65.0, 4.5), 32.0, vfxConfig.SlashFrameRate, false, true)
            spawnedAirSlashB = true
        end

        if not spawnedAirSlashD and t >= 0.42 then
            VFX.SpawnSubUV(vfxConfig.SlashSubUVResource, slashAnchor + actorForward * 8.0 - actorRight * 3.0 + up * 5.0, Vector(1.0, 72.0, 4.0), 58.0, vfxConfig.SlashFrameRate, false, true)
            spawnedAirSlashD = true
        end

        if not spawnedAirSlashC and t >= 0.50 then
            VFX.SpawnSubUV(vfxConfig.SlashSubUVResource, slashAnchor + actorForward * 12.0 - actorRight * 12.0 + up * -2.0, Vector(1.0, 55.0, 3.5), -36.0, vfxConfig.SlashFrameRate, false, true)
            spawnedAirSlashC = true
        end

        if not spawnedAirSlashE and t >= 0.62 then
            VFX.SpawnSubUV(vfxConfig.SlashSubUVResource, slashAnchor - actorForward * 2.0 + actorRight * 15.0 + up * -3.4, Vector(1.0, 50.0, 3.0), -62.0, vfxConfig.SlashFrameRate, false, true)
            spawnedAirSlashE = true
        end

        local nextPos = Bezier2(startPos, controlPos, cinematicEndPos, easedT)
        nextPos.Z = actorLocation.Z

        Reflection.Call(ultimateCamera, "SetActorRotation", GetUltimateCameraRotation(cameraConfig, baseCameraRotation, t))
        Reflection.Call(owner, "SetActorLocation", nextPos)

        local moveDir = nextPos - prevPos
        moveDir.Z = 0.0

        if moveDir:Length() > 0.001 then
            FaceOwnerToDirection(ctx, moveDir:Normalized())
        end

        prevPos = nextPos
    end

    local decal = VFX.SpawnGroundCrackDecal(
        vfxConfig.GroundCrackMaterialPath,
        cinematicEndPos,
        decalScale,
        0.35,
        0.45
    )

    if decal ~= nil then
        decal:SetColorRGBA(1.0, 0.05, 0.02, 1.0)
    end

    Reflection.Call(owner, "SetActorLocation", cinematicEndPos)
    CameraManager.StartWaveShake(1.0)

    Wait(0.4)

    Reflection.Call(movementComp, "SetMovementInputEnabled", true)
    CameraManager.ToggleOwnerCamera(owner, 0.4)

    if PrimComp ~= nil then
        Reflection.Call(PrimComp, "SetSimulatePhysics", PrevSimulatePhysics)
    end

    ctx.Action.IsInUltimateMode = false
    ctx.Action.IsUltimateRunning = false
    PlayerEvents.EmitUltimateEnded(ctx)

    print("End Ultimate")
end

---@param player PlayerContext
---@param events PlayerEvent[]
---@return nil
function PlayerFeedback.ProcessEvents(player, events)
    local ctx = PlayerContext.Assert(player, "PlayerFeedback.ProcessEvents")
    for _, event in ipairs(events) do
        if PlayerEvents.Is(event, PlayerEvents.Type.PerfectDodge) then
            PlayPerfectDodgeFeedback(ctx, event)
        elseif PlayerEvents.Is(event, PlayerEvents.Type.Hit) then
            if CameraManager ~= nil and CameraManager.StartWaveShake ~= nil then
                CameraManager.StartWaveShake(0.35)
            end
        elseif PlayerEvents.Is(event, PlayerEvents.Type.AttackHit) then
            -- AttackHitWindow 자체 hitstop은 C++ NotifyState가 처리한다.
            -- 여기서는 이후 피격 VFX/UI/사운드를 붙일 수 있도록 이벤트만 한 곳에서 받는다.
        elseif PlayerEvents.Is(event, PlayerEvents.Type.Dead) then
            if CameraManager ~= nil and CameraManager.StartWaveShake ~= nil then
                CameraManager.StartWaveShake(0.8)
            end
        elseif PlayerEvents.Is(event, PlayerEvents.Type.UltimateStarted) then
            StartCoroutine(function()
                PlayerFeedback.BeginUltimate(ctx)
            end)
        end
    end
end

return PlayerFeedback
