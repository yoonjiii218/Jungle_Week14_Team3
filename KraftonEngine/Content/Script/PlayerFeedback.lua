-- 연출 로직 담당 객체라고 볼 수 있음

local PlayerFeedback = {}

local PlayerConfig = require("PlayerConfig")
local DEFAULT_FEEDBACK_CONFIG = PlayerConfig.Default.Feedback

local function GetFeedbackConfig(ctx)
    if ctx ~= nil and ctx.Config ~= nil and ctx.Config.Feedback ~= nil then
        return ctx.Config.Feedback
    end

    return DEFAULT_FEEDBACK_CONFIG
end

local function GetUltimateCameraConfig(ctx)
    local feedbackConfig = GetFeedbackConfig(ctx)
    return feedbackConfig.UltimateCamera or DEFAULT_FEEDBACK_CONFIG.UltimateCamera
end

local function GetUltimateVfxConfig(ctx)
    local feedbackConfig = GetFeedbackConfig(ctx)
    return feedbackConfig.UltimateVfx or DEFAULT_FEEDBACK_CONFIG.UltimateVfx
end

local function GetUltimateMoveConfig(ctx)
    local feedbackConfig = GetFeedbackConfig(ctx)
    return feedbackConfig.UltimateMove or DEFAULT_FEEDBACK_CONFIG.UltimateMove
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

local function GetOwner(ctx)
    if ctx ~= nil and ctx.Owner ~= nil then
        return ctx.Owner
    end

    return obj
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
    local rotationStart = cameraConfig.RotationStart or DEFAULT_FEEDBACK_CONFIG.UltimateCamera.RotationStart
    if t <= rotationStart then
        return baseRotation
    end

    local rotationT = Clamp((t - rotationStart) / (1.0 - rotationStart), 0.0, 1.0)
    local pitchSwing = cameraConfig.PitchSwing or DEFAULT_FEEDBACK_CONFIG.UltimateCamera.PitchSwing
    local yawSwing = cameraConfig.YawSwing or DEFAULT_FEEDBACK_CONFIG.UltimateCamera.YawSwing
    local rollSwing = cameraConfig.RollSwing or DEFAULT_FEEDBACK_CONFIG.UltimateCamera.RollSwing

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

function PlayerFeedback.AttachKatanaToWeaponSocket(ctx)
    local owner = GetOwner(ctx)
    if owner == nil then
        return
    end

    if ctx.KatanaComponent ~= nil and ctx.KatanaComponent:IsValid() then
        if ctx.KatanaComponent:GetOwner() == owner then
            print("Katana already exists")
            return
        end

        ctx.KatanaComponent = nil
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
    katana:SetMeshPath(feedbackConfig.KatanaMeshPath or DEFAULT_FEEDBACK_CONFIG.KatanaMeshPath)
    katana:AttachToComponentWithSocket(meshComp, feedbackConfig.KatanaSocketName or DEFAULT_FEEDBACK_CONFIG.KatanaSocketName)
    katana.RelativeLocation = Vector(0.0, 0.0, 0.0)
    katana:SetRotation(Vector(0.0, 0.0, 0.0))
    katana:SetRelativeScale(Vector(1.0, 1.0, 1.0))

    ctx.KatanaComponent = katana
end

function PlayerFeedback.SetKatanaTrailActive(ctx, active)
    if ctx == nil then
        return
    end

    local PSC = ctx.KatanaPSC
    if PSC == nil or not PSC:IsValid() then
        return
    end

    if active then
        PSC:Activate()
    else
        PSC:Deactivate()
    end
end

function PlayerFeedback.AttachPSCToWeaponSocket(ctx)
    local owner = GetOwner(ctx)
    if owner == nil then
        return
    end

    if ctx.KatanaPSC ~= nil and ctx.KatanaPSC:IsValid() then
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
    PSC:SetTemplatePath(feedbackConfig.TrailParticlePath or DEFAULT_FEEDBACK_CONFIG.TrailParticlePath)
    PSC:SetAnimTrailSourceComponent(meshComp)
    PSC:AttachToComponentWithSocket(meshComp, feedbackConfig.KatanaSocketName or DEFAULT_FEEDBACK_CONFIG.KatanaSocketName)
    PSC.RelativeLocation = Vector(0.0, 0.0, 0.0)
    PSC:SetRotation(Vector(0.0, 0.0, 0.0))
    PSC:SetRelativeScale(Vector(1.0, 1.0, 1.0))

    ctx.KatanaPSC = PSC
    PlayerFeedback.SetKatanaTrailActive(ctx, false)
end

function PlayerFeedback.Init(ctx)
    PlayerFeedback.AttachKatanaToWeaponSocket(ctx)
    PlayerFeedback.AttachPSCToWeaponSocket(ctx)
end

function PlayerFeedback.Shutdown(ctx)
    if ctx == nil then
        return
    end

    ctx.KatanaComponent = nil
    ctx.KatanaPSC = nil
end

function PlayerFeedback.BeginUltimate(ctx)
    print("Begin Ultimate")

    if ctx == nil then
        return
    end

    ctx.IsUltimateRunning = true
    ctx.IsInUltimateMode = false

    local owner = GetOwner(ctx)
    if owner == nil then
        ctx.IsUltimateRunning = false
        return
    end

    local movementComp = owner:GetCharacterMovement()
    if movementComp == nil then
        print("Movement not found")
        ctx.IsUltimateRunning = false
        return
    end

    local ultimateCamera = World.FindFirstActorByTag("UltimateCamera")
    if ultimateCamera == nil then
        print("UltimateCamera not found")
        ctx.IsUltimateRunning = false
        return
    end

    local actorLocation = Reflection.Call(owner, "GetActorLocation")
    local actorForward, actorRight = GetSafeOwnerBasis(owner)

    if actorLocation == nil or actorForward == nil or actorRight == nil then
        print("Invalid owner transform")
        ctx.IsUltimateRunning = false
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
        - actorForward * (cameraConfig.BackDistance or DEFAULT_FEEDBACK_CONFIG.UltimateCamera.BackDistance)
        + up * (cameraConfig.Height or DEFAULT_FEEDBACK_CONFIG.UltimateCamera.Height)

    local slashAnchor =
        cameraLocation
        + actorForward * (cameraConfig.SlashCameraDistance or DEFAULT_FEEDBACK_CONFIG.UltimateCamera.SlashCameraDistance)
        + up * (cameraConfig.SlashCameraHeightOffset or DEFAULT_FEEDBACK_CONFIG.UltimateCamera.SlashCameraHeightOffset)
        + actorRight * (cameraConfig.SlashCameraRightOffset or DEFAULT_FEEDBACK_CONFIG.UltimateCamera.SlashCameraRightOffset)

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
        + actorForward * (moveConfig.StartDistance or DEFAULT_FEEDBACK_CONFIG.UltimateMove.StartDistance)
        + actorRight * (moveConfig.SideOffset or DEFAULT_FEEDBACK_CONFIG.UltimateMove.SideOffset)

    startPos.Z = actorLocation.Z

    local cinematicEndPos =
        cameraLocation
        + actorForward * (moveConfig.EndDistance or DEFAULT_FEEDBACK_CONFIG.UltimateMove.EndDistance)
        + actorRight * (moveConfig.EndRightDistance or DEFAULT_FEEDBACK_CONFIG.UltimateMove.EndRightDistance)

    cinematicEndPos.Z = actorLocation.Z

    local controlPos =
        cameraLocation
        + actorForward * (((moveConfig.StartDistance or DEFAULT_FEEDBACK_CONFIG.UltimateMove.StartDistance) + (moveConfig.EndDistance or DEFAULT_FEEDBACK_CONFIG.UltimateMove.EndDistance)) * 0.5)
        + actorRight * (moveConfig.ControlSideOffset or DEFAULT_FEEDBACK_CONFIG.UltimateMove.ControlSideOffset)

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

    ctx.IsInUltimateMode = true
    PlayerFeedback.SetKatanaTrailActive(ctx, true)

    local moveDuration = moveConfig.Duration or DEFAULT_FEEDBACK_CONFIG.UltimateMove.Duration
    local frameStep = moveConfig.FrameStep or DEFAULT_FEEDBACK_CONFIG.UltimateMove.FrameStep

    while elapsed < moveDuration do
        Wait(frameStep)

        elapsed = elapsed + frameStep

        local t = Clamp(elapsed / moveDuration, 0.0, 1.0)
        local easedT = EaseOutCubic(t)

        if not spawnedSlashFlash and t >= 0.38 then
            VFX.SpawnSlashFlash(
                vfxConfig.SlashFlashPath or DEFAULT_FEEDBACK_CONFIG.UltimateVfx.SlashFlashPath,
                slashAnchor + actorForward * 2.0 + up * 1.0,
                Vector(0.0, 0.0, 0.0),
                Vector(1.0, 1.8, 1.8),
                0.25,
                vfxConfig.LightningMaterialPath or DEFAULT_FEEDBACK_CONFIG.UltimateVfx.LightningMaterialPath
            )
            spawnedSlashFlash = true
        end

        if not spawnedAirSlashA and t >= 0.20 then
            VFX.SpawnSubUV(vfxConfig.SlashSubUVResource or DEFAULT_FEEDBACK_CONFIG.UltimateVfx.SlashSubUVResource, slashAnchor - actorForward * 6.0 - actorRight * 8.0 + up * 0.4, Vector(1.0, 88.0, 7.0), -12.0, vfxConfig.SlashFrameRate or DEFAULT_FEEDBACK_CONFIG.UltimateVfx.SlashFrameRate, false, true)
            spawnedAirSlashA = true
        end

        if not spawnedAirSlashB and t >= 0.34 then
            VFX.SpawnSubUV(vfxConfig.SlashSubUVResource or DEFAULT_FEEDBACK_CONFIG.UltimateVfx.SlashSubUVResource, slashAnchor + actorForward * 2.0 + actorRight * 9.0 + up * 3.0, Vector(1.0, 65.0, 4.5), 32.0, vfxConfig.SlashFrameRate or DEFAULT_FEEDBACK_CONFIG.UltimateVfx.SlashFrameRate, false, true)
            spawnedAirSlashB = true
        end

        if not spawnedAirSlashD and t >= 0.42 then
            VFX.SpawnSubUV(vfxConfig.SlashSubUVResource or DEFAULT_FEEDBACK_CONFIG.UltimateVfx.SlashSubUVResource, slashAnchor + actorForward * 8.0 - actorRight * 3.0 + up * 5.0, Vector(1.0, 72.0, 4.0), 58.0, vfxConfig.SlashFrameRate or DEFAULT_FEEDBACK_CONFIG.UltimateVfx.SlashFrameRate, false, true)
            spawnedAirSlashD = true
        end

        if not spawnedAirSlashC and t >= 0.50 then
            VFX.SpawnSubUV(vfxConfig.SlashSubUVResource or DEFAULT_FEEDBACK_CONFIG.UltimateVfx.SlashSubUVResource, slashAnchor + actorForward * 12.0 - actorRight * 12.0 + up * -2.0, Vector(1.0, 55.0, 3.5), -36.0, vfxConfig.SlashFrameRate or DEFAULT_FEEDBACK_CONFIG.UltimateVfx.SlashFrameRate, false, true)
            spawnedAirSlashC = true
        end

        if not spawnedAirSlashE and t >= 0.62 then
            VFX.SpawnSubUV(vfxConfig.SlashSubUVResource or DEFAULT_FEEDBACK_CONFIG.UltimateVfx.SlashSubUVResource, slashAnchor - actorForward * 2.0 + actorRight * 15.0 + up * -3.4, Vector(1.0, 50.0, 3.0), -62.0, vfxConfig.SlashFrameRate or DEFAULT_FEEDBACK_CONFIG.UltimateVfx.SlashFrameRate, false, true)
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
        vfxConfig.GroundCrackMaterialPath or DEFAULT_FEEDBACK_CONFIG.UltimateVfx.GroundCrackMaterialPath,
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

    ctx.IsInUltimateMode = false
    ctx.IsUltimateRunning = false
    PlayerFeedback.SetKatanaTrailActive(ctx, false)
    PlayerFeedback.HandlePlayerResult(ctx, { Events = { { Type = "UltimateEnd" } } })

    print("End Ultimate")
end

function PlayerFeedback.HandlePlayerResult(ctx, result)
    if ctx == nil or result == nil or result.Events == nil then
        return
    end

    for _, event in ipairs(result.Events) do
        if event.Type == "AttackStart" then
            PlayerFeedback.SetKatanaTrailActive(ctx, true)
        elseif event.Type == "AttackEnd" then
            PlayerFeedback.SetKatanaTrailActive(ctx, false)
        elseif event.Type == "DashStart" or event.Type == "DashSlashStart" then
            PlayerFeedback.SetKatanaTrailActive(ctx, true)
        elseif event.Type == "DashEnd" or event.Type == "DashSlashEnd" then
            PlayerFeedback.SetKatanaTrailActive(ctx, false)
        elseif event.Type == "DashChargingStart" then
            PlayerFeedback.SetKatanaTrailActive(ctx, false)
        elseif event.Type == "DashChargeAttackStart" then
            PlayerFeedback.SetKatanaTrailActive(ctx, true)
        elseif event.Type == "DashChargeAttackEnd" then
            PlayerFeedback.SetKatanaTrailActive(ctx, false)
        elseif event.Type == "PerfectDodge" then
            if CameraManager ~= nil and CameraManager.StartWaveShake ~= nil then
                CameraManager.StartWaveShake(0.5)
            end
        elseif event.Type == "UltimateStart" then
            StartCoroutine(function()
                PlayerFeedback.BeginUltimate(ctx)
            end)
        end
    end
end

return PlayerFeedback
