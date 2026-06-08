-- Player/PlayerFeedback.lua
-- PlayerFeedback owns presentation: camera, VFX, trails, hitstop/slomo visuals.
-- It consumes PlayerEvent lists and should not own gameplay state transitions.

local PlayerFeedback = {}

local PlayerContext = require("Player/PlayerContext")
local PlayerEvents = require("Player/PlayerEvents")

local COLLISION_QUERY_AND_PHYSICS = 3

local function Clamp(v, minValue, maxValue)
    if v < minValue then return minValue end
    if v > maxValue then return maxValue end
    return v
end

local function EaseOutCubic(t)
    local u = 1.0 - t
    return 1.0 - u * u * u
end

local function CanUseFOVPulse(playerContext)
    local feedbackConfig = playerContext.Config.Feedback or {}
    local fovConfig = feedbackConfig.FOV
    return fovConfig ~= nil
        and fovConfig.Enabled ~= false
        and CameraManager ~= nil
        and CameraManager.StartFOVPulse ~= nil
end

local function StartFOVPulse(playerContext, name, pulseConfig)
    if CanUseFOVPulse(playerContext) ~= true then
        return
    end

    if pulseConfig == nil or pulseConfig.Enabled == false then
        return
    end

    local deltaDegrees = pulseConfig.DeltaDegrees or pulseConfig.Delta or 0.0
    local duration = pulseConfig.Duration or 0.0
    if deltaDegrees == 0.0 or duration <= 0.0 then
        return
    end

    CameraManager.StartFOVPulse(
        name,
        deltaDegrees,
        duration,
        pulseConfig.BlendIn or 0.0,
        pulseConfig.BlendOut or 0.0
    )
end

local function StopFOVPulse(name)
    if CameraManager ~= nil and CameraManager.StopFOVPulse ~= nil then
        CameraManager.StopFOVPulse(name)
    end
end

local function GetFOVConfig(playerContext, key)
    local feedbackConfig = playerContext.Config.Feedback or {}
    local fovConfig = feedbackConfig.FOV or {}
    return fovConfig[key]
end

local function Bezier2(a, b, c, t)
    local u = 1.0 - t
    return a * (u * u) + b * (2.0 * u * t) + c * (t * t)
end

local function SetComponentVisible(component, visible)
    if component == nil then
        return
    end

    if component.IsValid ~= nil and component:IsValid() ~= true then
        return
    end

    if component.SetVisibility ~= nil then
        component:SetVisibility(visible)
        return
    end

    pcall(function()
        Reflection.Call(component, "SetVisibility", visible)
    end)
end

local function PlayPerfectDodgeFeedback(playerContext, event)
    local feedbackConfig = playerContext.Config.Feedback
    local perfectDodgeConfig = feedbackConfig.PerfectDodge
    local shakeScale = perfectDodgeConfig.CameraShakeScale

    if CameraManager ~= nil and CameraManager.StartWaveShake ~= nil and shakeScale > 0.0 then
        CameraManager.StartWaveShake(shakeScale)
    end

    if CameraManager ~= nil and CameraManager.StartPerfectDodgeEffect ~= nil then
        local duration = event.SlomoDuration or perfectDodgeConfig.PostProcessDuration or 1.5
        local intensity = perfectDodgeConfig.PostProcessIntensity or 1.0
        local focusHighlightStrength = perfectDodgeConfig.FocusHighlightStrength or 0.55
        CameraManager.StartPerfectDodgeEffect(duration, intensity, focusHighlightStrength)
    end

    StartFOVPulse(playerContext, "Player.PerfectDodgeFOV", GetFOVConfig(playerContext, "PerfectDodge"))

    print("Perfect Dodge")
end

local function PlayAttackHitFeedback(playerContext, event)
    local feedbackConfig = playerContext.Config.Feedback
    local attackHitConfig = feedbackConfig.AttackHit or {}
    local shakeScale = attackHitConfig.CameraShakeScale or 0.0

    if CameraManager ~= nil and CameraManager.StartWaveShake ~= nil and shakeScale > 0.0 then
        CameraManager.StartWaveShake(shakeScale)
    end

    StartFOVPulse(playerContext, "Player.AttackHitFOV", GetFOVConfig(playerContext, "AttackHit"))
end

local function PlayDashStartedFeedback(playerContext, event)
    StartFOVPulse(playerContext, "Player.DashFOV", GetFOVConfig(playerContext, "Dash"))
end

local function PlayDashEndedFeedback(playerContext, event)
    StopFOVPulse("Player.DashFOV")
end

local function PlayDashChargingStartedFeedback(playerContext, event)
    StopFOVPulse("Player.DashFOV")
    StartFOVPulse(playerContext, "Player.DashChargingFOV", GetFOVConfig(playerContext, "DashCharging"))
end

local function PlayDashChargingEndedFeedback(playerContext, event)
    StopFOVPulse("Player.DashChargingFOV")
end

local function PlayDashChargeAttackStartedFeedback(playerContext, event)
    StopFOVPulse("Player.DashChargingFOV")
    StartFOVPulse(playerContext, "Player.DashChargeAttackFOV", GetFOVConfig(playerContext, "DashChargeAttack"))
end

local function PlayDashChargeAttackEndedFeedback(playerContext, event)
    StopFOVPulse("Player.DashChargeAttackFOV")
end

local function PlayAttackStartedFeedback(playerContext, event)
    if event ~= nil and event.IsPostDashAttack == true then
        StartFOVPulse(playerContext, "Player.PostDashAttackFOV", GetFOVConfig(playerContext, "PostDashAttack"))
        return
    end

    StartFOVPulse(playerContext, "Player.AttackStartFOV", GetFOVConfig(playerContext, "AttackStart"))
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

local function ResolvePlayerMeshComponent(playerContext)
    local owner = playerContext.Owner
    if owner == nil or owner.GetSkeletalMeshComponent == nil then
        return nil
    end

    return owner:GetSkeletalMeshComponent()
end

local function PlayHitReactFeedback(playerContext, event)
    local feedbackConfig = playerContext.Config.Feedback
    local hitConfig = feedbackConfig.HitReact or {}

    local shakeScale = hitConfig.CameraShakeScale or 0.0
    if CameraManager ~= nil and CameraManager.StartWaveShake ~= nil and shakeScale > 0.0 then
        CameraManager.StartWaveShake(shakeScale)
    end

    StartFOVPulse(playerContext, "Player.HitReactFOV", GetFOVConfig(playerContext, "HitReact"))

    local owner = playerContext.Owner
    local meshComp = ResolvePlayerMeshComponent(playerContext)
    if meshComp == nil then
        return
    end

    local action = GetOrAddActionComponent(owner)
    if action == nil then
        return
    end

    if hitConfig.SquashEnabled ~= false and action.HitSquashComponentByMultiplier ~= nil then
        pcall(function()
            action:HitSquashComponentByMultiplier(
                meshComp,
                hitConfig.SquashScale or Vector(1.06, 1.06, 0.94),
                hitConfig.SquashInDuration or 0.035,
                hitConfig.SquashRecoverDuration or 0.09
            )
        end)
    end

    if hitConfig.ShakeEnabled ~= false and action.HitShakeComponent ~= nil then
        pcall(function()
            action:HitShakeComponent(
                meshComp,
                hitConfig.ShakeAmplitude or 3.0,
                hitConfig.ShakeDuration or 0.08,
                hitConfig.ShakeFrequency or 70.0
            )
        end)
    end
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

local function FaceOwnerToDirection(playerContext, dir)
    local owner = playerContext.Owner
    if owner == nil or dir == nil then
        return
    end

    local targetYaw = math.atan2(dir.Y, dir.X) * 180.0 / math.pi
    Reflection.Call(owner, "SetActorRotation", Vector(0.0, 0.0, targetYaw))
end

local function StartDeathRagdoll(playerContext)
    local owner = playerContext.Owner
    if owner == nil or owner.GetSkeletalMeshComponent == nil then
        return
    end

    local movementComp = owner.GetCharacterMovement and owner:GetCharacterMovement() or nil
    if movementComp ~= nil then
        Reflection.Call(movementComp, "StopMovementImmediately")
        Reflection.Call(movementComp, "SetMovementInputEnabled", false)
    end

    local meshComp = owner:GetSkeletalMeshComponent()
    if meshComp == nil then
        return
    end

    local ok, err = pcall(function()
        meshComp:SetCollisionEnabled(COLLISION_QUERY_AND_PHYSICS)
        meshComp:SetEnableGravity(true)
        meshComp:StartRagdoll()
    end)

    if not ok then
        print("[PlayerFeedback] StartDeathRagdoll failed: " .. tostring(err))
    end
end

-- =========================================================
-- Public API
-- =========================================================

---@param playerContext PlayerContext
---@return nil
function PlayerFeedback.AttachKatanaToWeaponSocket(playerContext)
    PlayerContext.Assert(playerContext, "PlayerFeedback.AttachKatanaToWeaponSocket")
    local owner = playerContext.Owner
    if owner == nil then
        return
    end

    if playerContext.Feedback.KatanaComponent ~= nil and playerContext.Feedback.KatanaComponent:IsValid() then
        if playerContext.Feedback.KatanaComponent:GetOwner() == owner then
            print("Katana already exists")
            return
        end

        playerContext.Feedback.KatanaComponent = nil
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

    local feedbackConfig = playerContext.Config.Feedback
    katana:SetMeshPath(feedbackConfig.KatanaMeshPath)
    katana:AttachToComponentWithSocket(meshComp, feedbackConfig.KatanaSocketName)
    katana.RelativeLocation = Vector(0.0, 0.0, 0.0)
    katana:SetRotation(Vector(0.0, 0.0, 0.0))
    katana:SetRelativeScale(Vector(1.0, 1.0, 1.0))

    playerContext.Feedback.KatanaComponent = katana
end

---@param playerContext PlayerContext
---@return nil
function PlayerFeedback.SetKatanaTrailActive(playerContext, active)
    PlayerContext.Assert(playerContext, "PlayerFeedback.SetKatanaTrailActive")
    local PSC = playerContext.Feedback.KatanaPSC
    if PSC == nil or not PSC:IsValid() then
        return
    end

    if active then
        PSC:Activate()
    else
        PSC:Deactivate()
    end
end

---@param playerContext PlayerContext
---@return nil
function PlayerFeedback.BeginDashVanish(playerContext)
    PlayerContext.Assert(playerContext, "PlayerFeedback.BeginDashVanish")

    local owner = playerContext.Owner
    if owner == nil or owner.GetSkeletalMeshComponent == nil then
        return
    end

    SetComponentVisible(owner:GetSkeletalMeshComponent(), false)
    SetComponentVisible(playerContext.Feedback.KatanaComponent, false)
    SetComponentVisible(playerContext.Feedback.KatanaPSC, false)
end

---@param playerContext PlayerContext
---@return nil
function PlayerFeedback.EndDashVanish(playerContext)
    PlayerContext.Assert(playerContext, "PlayerFeedback.EndDashVanish")

    local owner = playerContext.Owner
    if owner ~= nil and owner.GetSkeletalMeshComponent ~= nil then
        SetComponentVisible(owner:GetSkeletalMeshComponent(), true)
    end

    SetComponentVisible(playerContext.Feedback.KatanaComponent, true)
    SetComponentVisible(playerContext.Feedback.KatanaPSC, true)
end

---@param playerContext PlayerContext
---@return nil
function PlayerFeedback.AttachPSCToWeaponSocket(playerContext)
    PlayerContext.Assert(playerContext, "PlayerFeedback.AttachPSCToWeaponSocket")
    local owner = playerContext.Owner
    if owner == nil then
        return
    end

    if playerContext.Feedback.KatanaPSC ~= nil and playerContext.Feedback.KatanaPSC:IsValid() then
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

    local feedbackConfig = playerContext.Config.Feedback
    PSC:SetTemplatePath(feedbackConfig.TrailParticlePath)
    PSC:SetAnimTrailSourceComponent(meshComp)
    PSC:AttachToComponentWithSocket(meshComp, feedbackConfig.KatanaSocketName)
    PSC.RelativeLocation = Vector(0.0, 0.0, 0.0)
    PSC:SetRotation(Vector(0.0, 0.0, 0.0))
    PSC:SetRelativeScale(Vector(1.0, 1.0, 1.0))

    playerContext.Feedback.KatanaPSC = PSC
    PlayerFeedback.SetKatanaTrailActive(playerContext, false)
end

---@param playerContext PlayerContext
---@return nil
function PlayerFeedback.Init(playerContext)
    PlayerContext.Assert(playerContext, "PlayerFeedback.Init")
    PlayerFeedback.AttachKatanaToWeaponSocket(playerContext)
    PlayerFeedback.AttachPSCToWeaponSocket(playerContext)
end

---@param playerContext PlayerContext
---@return nil
function PlayerFeedback.Shutdown(playerContext)
    PlayerContext.Assert(playerContext, "PlayerFeedback.Shutdown")
    playerContext.Feedback.KatanaComponent = nil
    playerContext.Feedback.KatanaPSC = nil
end

---@param playerContext PlayerContext
---@return nil
function PlayerFeedback.BeginUltimate(playerContext)
    PlayerContext.Assert(playerContext, "PlayerFeedback.BeginUltimate")
    print("Begin Ultimate")

    playerContext.Action.IsUltimateRunning = true
    playerContext.Action.IsInUltimateMode = false

    local owner = playerContext.Owner
    if owner == nil then
        playerContext.Action.IsUltimateRunning = false
        return
    end

    local movementComp = owner:GetCharacterMovement()
    if movementComp == nil then
        print("Movement not found")
        playerContext.Action.IsUltimateRunning = false
        return
    end

    local ultimateCamera = World.FindFirstActorByTag("UltimateCamera")
    if ultimateCamera == nil then
        print("UltimateCamera not found")
        playerContext.Action.IsUltimateRunning = false
        return
    end

    local actorLocation = Reflection.Call(owner, "GetActorLocation")
    local actorForward, actorRight = GetSafeOwnerBasis(owner)

    if actorLocation == nil or actorForward == nil or actorRight == nil then
        print("Invalid owner transform")
        playerContext.Action.IsUltimateRunning = false
        return
    end

    local PrimComp = owner:GetPrimitiveComponent()
    local PrevSimulatePhysics = false

    if PrimComp ~= nil then
        PrevSimulatePhysics = Reflection.Call(PrimComp, "GetSimulatePhysics")
        Reflection.Call(PrimComp, "SetSimulatePhysics", false)
    end

    local up = Vector(0.0, 0.0, 1.0)
    local cameraConfig = playerContext.Config.Feedback.UltimateCamera
    local moveConfig = playerContext.Config.Feedback.UltimateMove
    local vfxConfig = playerContext.Config.Feedback.UltimateVfx
    local fovConfig = playerContext.Config.Feedback.FOV or {}
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
    StartFOVPulse(playerContext, "Player.UltimateStartFOV", fovConfig.UltimateStart)
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

    playerContext.Action.IsInUltimateMode = true

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
            FaceOwnerToDirection(playerContext, moveDir:Normalized())
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
    StartFOVPulse(playerContext, "Player.UltimateImpactFOV", fovConfig.UltimateImpact)

    Wait(0.4)

    Reflection.Call(movementComp, "SetMovementInputEnabled", true)
    StartFOVPulse(playerContext, "Player.UltimateRecoverFOV", fovConfig.UltimateRecover)
    CameraManager.ToggleOwnerCamera(owner, 0.4)

    if PrimComp ~= nil then
        Reflection.Call(PrimComp, "SetSimulatePhysics", PrevSimulatePhysics)
    end

    playerContext.Action.IsInUltimateMode = false
    playerContext.Action.IsUltimateRunning = false
    PlayerEvents.EmitUltimateEnded(playerContext)

    print("End Ultimate")
end

---@param playerContext PlayerContext
---@param events PlayerEvent[]
---@return nil
function PlayerFeedback.ProcessEvents(playerContext, events)
    PlayerContext.Assert(playerContext, "PlayerFeedback.ProcessEvents")
    for _, event in ipairs(events) do
        if PlayerEvents.Is(event, PlayerEvents.Type.DashStarted) then
            PlayDashStartedFeedback(playerContext, event)
        elseif PlayerEvents.Is(event, PlayerEvents.Type.DashEnded) then
            PlayDashEndedFeedback(playerContext, event)
        elseif PlayerEvents.Is(event, PlayerEvents.Type.DashChargingStarted) then
            PlayDashChargingStartedFeedback(playerContext, event)
        elseif PlayerEvents.Is(event, PlayerEvents.Type.DashChargingEnded) then
            PlayDashChargingEndedFeedback(playerContext, event)
        elseif PlayerEvents.Is(event, PlayerEvents.Type.DashChargeAttackStarted) then
            PlayDashChargeAttackStartedFeedback(playerContext, event)
        elseif PlayerEvents.Is(event, PlayerEvents.Type.DashChargeAttackEnded) then
            PlayDashChargeAttackEndedFeedback(playerContext, event)
        elseif PlayerEvents.Is(event, PlayerEvents.Type.AttackStarted) then
            PlayAttackStartedFeedback(playerContext, event)
        elseif PlayerEvents.Is(event, PlayerEvents.Type.PerfectDodge) then
            PlayPerfectDodgeFeedback(playerContext, event)
        elseif PlayerEvents.Is(event, PlayerEvents.Type.Hit) then
            PlayHitReactFeedback(playerContext, event)
        elseif PlayerEvents.Is(event, PlayerEvents.Type.AttackHit) then
            PlayAttackHitFeedback(playerContext, event)
            -- AttackHitWindow 자체 hitstop은 C++ NotifyState가 처리한다.
            -- 여기서는 이후 피격 VFX/UI/사운드를 붙일 수 있도록 이벤트만 한 곳에서 받는다.
        elseif PlayerEvents.Is(event, PlayerEvents.Type.Dead) then
            StartDeathRagdoll(playerContext)
            if CameraManager ~= nil and CameraManager.StartWaveShake ~= nil then
                CameraManager.StartWaveShake(0.8)
            end
        elseif PlayerEvents.Is(event, PlayerEvents.Type.UltimateStarted) then
            StartCoroutine(function()
                PlayerFeedback.BeginUltimate(playerContext)
            end)
        end
    end
end

return PlayerFeedback
