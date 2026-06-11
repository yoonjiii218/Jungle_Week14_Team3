-- Player/PlayerFeedback.lua
-- PlayerFeedback owns presentation: camera, VFX, trails, hitstop/slomo visuals.
-- It consumes PlayerEvent lists and should not own gameplay state transitions.

local PlayerFeedback = {}

local PlayerContext = require("Player/PlayerContext")
local PlayerEvents = require("Player/PlayerEvents")
local PlayerTargeting = require("Player/PlayerTargeting")
local PlayerAction = require("Player/PlayerAction")
local CombatContext = require("Combat/CombatContext")

local COLLISION_QUERY_AND_PHYSICS = 3

local function Now()
    if World ~= nil and World.GetGameTime ~= nil then
        return World.GetGameTime() or 0.0
    end
    return 0.0
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


local function IsValidObject(obj)
    return obj ~= nil and (obj.IsValid == nil or obj:IsValid() == true)
end

local function GetOwnerLocation(playerContext)
    local owner = playerContext.Owner
    if owner == nil then
        return nil
    end

    if owner.Location ~= nil then
        return owner.Location
    end

    return Reflection.Call(owner, "GetActorLocation")
end

local function GetDashChargeConfig(playerContext)
    local feedbackConfig = playerContext.Config.Feedback or {}
    return feedbackConfig.DashCharge or {}
end

local function GetDashChargeRatio(playerContext)
    local action = playerContext.Action or {}
    return Clamp(action.DashChargeRatio or 0.0, 0.0, 1.0)
end

local function SpawnParticleSystem(path, location, rotation, scale, life, materialPath)
    if VFX == nil or VFX.SpawnParticleSystem == nil then
        return nil
    end

    if path == nil or path == "" or path == "None" then
        return nil
    end

    return VFX.SpawnParticleSystem(
        path,
        location,
        rotation or Vector(0.0, 0.0, 0.0),
        scale or Vector(1.0, 1.0, 1.0),
        life or 1.0,
        materialPath or "None"
    )
end

local function GetConfiguredSoundKey(soundConfig)
    if soundConfig == nil then
        return nil
    end

    local key = soundConfig.Key or soundConfig.SoundName
    if key == nil or key == "" or key == "None" then
        key = soundConfig.Path
    end

    if key == nil or key == "" or key == "None" then
        return nil
    end

    return key
end

local function GetLoadedFeedbackSounds(playerContext)
    playerContext.Feedback.LoadedAudioKeys = playerContext.Feedback.LoadedAudioKeys or {}
    return playerContext.Feedback.LoadedAudioKeys
end

local function EnsureConfiguredSoundLoaded(playerContext, soundConfig)
    if soundConfig == nil or soundConfig.Enabled == false then
        return nil
    end

    if AudioManager == nil or AudioManager.Play == nil then
        return nil
    end

    local key = GetConfiguredSoundKey(soundConfig)
    if key == nil then
        return nil
    end

    local path = soundConfig.Path
    if path == nil or path == "" or path == "None" then
        return key
    end

    if AudioManager.Load == nil then
        return key
    end

    local loaded = GetLoadedFeedbackSounds(playerContext)
    if loaded[key] ~= path then
        if AudioManager.Load(key, path, soundConfig.Loop == true) ~= true then
            print("[PlayerFeedback] Failed to load sound: " .. tostring(path))
            return nil
        end
        loaded[key] = path
    end

    return key
end

local function PlayConfiguredSound(playerContext, soundConfig)
    local key = EnsureConfiguredSoundLoaded(playerContext, soundConfig)
    if key == nil then
        return
    end

    AudioManager.Play(key, soundConfig.Volume or 1.0, soundConfig.Pitch or 1.0, soundConfig.MaxInstances)
end


local function ScaleByImpactCount(baseValue, perTargetValue, maxValue, countForScale)
    local count = math.max(1, countForScale or 1)
    local value = (baseValue or 0.0) + (perTargetValue or 0.0) * (count - 1)
    if maxValue ~= nil then
        value = math.min(value, maxValue)
    end
    return value
end

local function ClampOptional(value, minValue, maxValue)
    if minValue ~= nil and value < minValue then
        value = minValue
    end
    if maxValue ~= nil and value > maxValue then
        value = maxValue
    end
    return value
end

local function ResetDashChargeFeedbackState(playerContext)
    playerContext.Feedback.DashChargeGroundPSC = nil
    playerContext.Feedback.DashChargeReadyBursted = false
    playerContext.Feedback.DashChargeVFXTimer = 0.0
    playerContext.Feedback.DashChargeShakeTimer = 0.0
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

local function CanUseVignette(playerContext)
    local feedbackConfig = playerContext.Config.Feedback or {}
    local vignetteConfig = feedbackConfig.Vignette
    return vignetteConfig ~= nil
        and vignetteConfig.Enabled ~= false
        and CameraManager ~= nil
        and CameraManager.SetVignetteLayer ~= nil
        and CameraManager.StartVignettePulse ~= nil
        and CameraManager.StopVignetteLayer ~= nil
end

local function GetVignetteConfig(playerContext, key)
    local feedbackConfig = playerContext.Config.Feedback or {}
    local vignetteConfig = feedbackConfig.Vignette or {}
    return vignetteConfig[key]
end

local function GetVignetteColor(config)
    if config == nil then
        return 0.0, 0.0, 0.0, 1.0
    end

    return config.R or 0.0,
        config.G or 0.0,
        config.B or 0.0,
        config.A or 1.0
end

local function StartVignettePulse(playerContext, name, pulseConfig)
    if CanUseVignette(playerContext) ~= true then
        return
    end

    if pulseConfig == nil or pulseConfig.Enabled == false then
        return
    end

    local intensity = pulseConfig.Intensity or 0.0
    local duration = pulseConfig.Duration or 0.0
    if intensity <= 0.0 or duration <= 0.0 then
        return
    end

    local r, g, b, a = GetVignetteColor(pulseConfig)
    CameraManager.StartVignettePulse(
        name,
        intensity,
        pulseConfig.Radius or 0.75,
        pulseConfig.Softness or 0.35,
        duration,
        pulseConfig.BlendIn or 0.0,
        pulseConfig.BlendOut or 0.0,
        r, g, b, a
    )
end

local function SetVignetteLayer(playerContext, name, layerConfig, intensityOverride)
    if CanUseVignette(playerContext) ~= true then
        return
    end

    if layerConfig == nil or layerConfig.Enabled == false then
        return
    end

    local intensity = intensityOverride or layerConfig.Intensity or 0.0
    if intensity <= 0.0 then
        CameraManager.StopVignetteLayer(name, 0.0)
        return
    end

    local r, g, b, a = GetVignetteColor(layerConfig)
    CameraManager.SetVignetteLayer(
        name,
        intensity,
        layerConfig.Radius or 0.75,
        layerConfig.Softness or 0.35,
        r, g, b, a
    )
end

local function StopVignetteLayer(playerContext, name, layerConfig)
    if CameraManager == nil or CameraManager.StopVignetteLayer == nil then
        return
    end

    local blendOut = 0.0
    if layerConfig ~= nil then
        blendOut = layerConfig.BlendOut or 0.0
    end

    CameraManager.StopVignetteLayer(name, blendOut)
end

local function UpdateLowHPVignette(playerContext)
    if CanUseVignette(playerContext) ~= true then
        return
    end

    local lowHPConfig = GetVignetteConfig(playerContext, "LowHP")
    if lowHPConfig == nil or lowHPConfig.Enabled == false then
        StopVignetteLayer(playerContext, "Player.LowHPVignette", lowHPConfig)
        return
    end

    local combat = playerContext.Combat or {}
    local hp = combat.HP or 0.0
    local maxHP = combat.MaxHP or 0.0
    if maxHP <= 0.0 or combat.IsDead == true then
        StopVignetteLayer(playerContext, "Player.LowHPVignette", lowHPConfig)
        return
    end

    local ratio = Clamp(hp / maxHP, 0.0, 1.0)
    local startRatio = lowHPConfig.StartRatio or 0.45
    local criticalRatio = lowHPConfig.CriticalRatio or 0.18

    if ratio >= startRatio then
        StopVignetteLayer(playerContext, "Player.LowHPVignette", lowHPConfig)
        return
    end

    local denom = math.max(startRatio - criticalRatio, 0.001)
    local t = Clamp((startRatio - ratio) / denom, 0.0, 1.0)
    local minIntensity = lowHPConfig.MinIntensity or 0.0
    local maxIntensity = lowHPConfig.MaxIntensity or lowHPConfig.Intensity or 0.55
    local intensity = minIntensity + (maxIntensity - minIntensity) * t
    SetVignetteLayer(playerContext, "Player.LowHPVignette", lowHPConfig, intensity)
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

    PlayConfiguredSound(playerContext, perfectDodgeConfig.Sound)

    if CameraManager ~= nil and CameraManager.StartPerfectDodgeEffect ~= nil then
        local duration = event.SlomoDuration or perfectDodgeConfig.PostProcessDuration or 1.5
        local intensity = perfectDodgeConfig.PostProcessIntensity or 1.0
        local focusHighlightStrength = perfectDodgeConfig.FocusHighlightStrength or 0.55
        CameraManager.StartPerfectDodgeEffect(duration, intensity, focusHighlightStrength)
    end

    StartFOVPulse(playerContext, "Player.PerfectDodgeFOV", GetFOVConfig(playerContext, "PerfectDodge"))
    StartVignettePulse(playerContext, "Player.PerfectDodgeVignette", GetVignetteConfig(playerContext, "PerfectDodge"))

    print("Perfect Dodge")
end

local function GetActorLocationSafe(actor)
    if actor == nil then
        return nil
    end

    if actor.Location ~= nil then
        return actor.Location
    end

    if Reflection ~= nil and Reflection.Call ~= nil then
        local ok, result = pcall(function()
            return Reflection.Call(actor, "GetActorLocation")
        end)
        if ok then
            return result
        end
    end

    return nil
end

local function ResolveDamageTextLocation(event, config)
    local hitLocation = event.HitLocation
    if hitLocation == nil and event.HitResult ~= nil then
        hitLocation = event.HitResult.WorldHitLocation
    end

    local location = hitLocation
    if location == nil then
        location = GetActorLocationSafe(event.TargetActor)
    end
    if location == nil then
        return nil
    end

    local zOffset = config.ZOffset or 2.4
    if hitLocation ~= nil then
        zOffset = config.HitLocationZOffset or 1.0
    end

    local jitter = config.HorizontalJitter or 0.35
    local jitterX = 0.0
    local jitterY = 0.0
    if jitter > 0.0 then
        jitterX = (math.random() * 2.0 - 1.0) * jitter
        jitterY = (math.random() * 2.0 - 1.0) * jitter
    end

    return Vector(location.X + jitterX, location.Y + jitterY, location.Z + zOffset)
end

local function FormatDamageText(damage, config)
    if damage == nil then
        return nil
    end

    local rounded = math.floor((damage or 0.0) + 0.5)
    if rounded <= 0 then
        return nil
    end

    local prefix = config.Prefix or ""
    local suffix = config.Suffix or ""
    return prefix .. tostring(rounded) .. suffix
end

local function SpawnDamageTextFeedback(playerContext, event)
    local feedbackConfig = playerContext.Config.Feedback or {}
    local config = feedbackConfig.DamageText or {}
    if config.Enabled == false then
        return
    end
    if VFX == nil or VFX.SpawnDamageText == nil then
        return
    end

    local text = FormatDamageText(event.Damage, config)
    if text == nil then
        return
    end

    local spawnLocation = ResolveDamageTextLocation(event, config)
    if spawnLocation == nil then
        return
    end

    local color = config.Color or {}
    local textComp = VFX.SpawnDamageText(
        text,
        spawnLocation,
        config.FontSize or 1.25,
        color.R or color[1] or 1.0,
        color.G or color[2] or 0.84,
        color.B or color[3] or 0.08,
        color.A or color[4] or 1.0,
        config.FontName or "Default"
    )
    if textComp == nil then
        return
    end
    if textComp.SetDisableDepthTest ~= nil then
        textComp:SetDisableDepthTest(config.DisableDepthTest ~= false)
    end

    local owner = nil
    if textComp.GetOwner ~= nil then
        owner = textComp:GetOwner()
    end
    if owner == nil then
        return
    end

    StartCoroutine(function()
        local duration = config.Duration or 0.65
        local riseDistance = config.RiseDistance or 1.65
        local drift = config.DriftDistance or 0.25
        local driftX = 0.0
        local driftY = 0.0
        if drift > 0.0 then
            driftX = (math.random() * 2.0 - 1.0) * drift
            driftY = (math.random() * 2.0 - 1.0) * drift
        end

        local elapsed = 0.0
        while elapsed < duration and IsValidObject(owner) do
            local dt = WaitFrame() or 0.0
            elapsed = elapsed + dt

            local t = Clamp(elapsed / duration, 0.0, 1.0)
            local ease = EaseOutCubic(t)
            owner.Location = Vector(
                spawnLocation.X + driftX * ease,
                spawnLocation.Y + driftY * ease,
                spawnLocation.Z + riseDistance * ease
            )

            if textComp.SetColorRGBA ~= nil then
                local alpha = (color.A or color[4] or 1.0) * (1.0 - t)
                textComp:SetColorRGBA(
                    color.R or color[1] or 1.0,
                    color.G or color[2] or 0.84,
                    color.B or color[3] or 0.08,
                    alpha
                )
            end
        end

        if IsValidObject(owner) then
            owner:Destroy()
        end
    end)
end

local function PlayAttackHitFeedback(playerContext, event)
    -- Individual AttackHit remains per-target UI feedback. Camera/audio/VFX are
    -- emitted once per HitIndex group, regardless of how many targets were hit.
    SpawnDamageTextFeedback(playerContext, event)
end

local function IsUltimateAttackImpact(event)
    return tostring(event.ImpactKind or "") == "Ultimate"
        or tostring(event.AttackId or "") == "PlayerUltimate"
end

local function ResolveAttackImpactFeedbackConfig(feedbackConfig, event)
    if IsUltimateAttackImpact(event) then
        return feedbackConfig.UltimateAttackImpact or feedbackConfig.AttackImpact or {}, "UltimateAttackImpact"
    end
    return feedbackConfig.AttackImpact or {}, "AttackImpact"
end

local function ShouldSuppressAttackImpactFeedback(event, impactConfig)
    if IsUltimateAttackImpact(event) ~= true or impactConfig.FinalHitOnly ~= true then
        return false
    end

    local hitIndex = math.max(1, tonumber(event.HitIndex) or 1)
    local hitCount = math.max(hitIndex, tonumber(event.HitCount) or hitIndex)
    return hitCount > 1 and hitIndex < hitCount
end

local function GetAttackImpactHitPhase(event)
    local hitIndex = math.max(1, tonumber(event.HitIndex) or 1)
    local hitCount = math.max(hitIndex, tonumber(event.HitCount) or hitIndex)
    if hitCount <= 1 then
        return "Single"
    end
    if hitIndex >= hitCount then
        return "Final"
    end
    if hitIndex <= 1 then
        return "First"
    end
    return "Middle"
end

local function GetHitPhaseNumber(config, phase, suffix, fallback)
    local value = config[phase .. suffix]
    if value == nil then
        return fallback
    end
    return value
end

local function CanPlayAttackImpactSound(playerContext, event, soundConfig)
    local minInterval = math.max(0.0, tonumber(soundConfig.MinInterval) or 0.0)
    if minInterval <= 0.0 then
        return true
    end

    local soundKey = GetConfiguredSoundKey(soundConfig) or "AttackImpact"
    local lastTimes = playerContext.Feedback.LastImpactSoundTimes or {}
    playerContext.Feedback.LastImpactSoundTimes = lastTimes

    local now = Now()
    local phase = GetAttackImpactHitPhase(event)
    local alwaysPlay = phase == "Final" and soundConfig.AlwaysPlayFinalHit ~= false
    if alwaysPlay ~= true and now < (lastTimes[soundKey] or -999.0) + minInterval then
        return false
    end

    lastTimes[soundKey] = now
    return true
end

local function PlayAttackImpactFeedback(playerContext, event)
    local feedbackConfig = playerContext.Config.Feedback or {}
    local impactConfig, pulseConfigKey = ResolveAttackImpactFeedbackConfig(feedbackConfig, event)
    if impactConfig.Enabled == false then
        return
    end

    -- UltimateAttackImpact.FinalHitOnly == true 인 경우,
    -- 중간타에서는 카메라 흔들림 / VFX / FOV / Vignette 같은 무거운 피드백만 막고,
    -- Sound는 계속 재생되게 분리한다.
    local suppressHeavyFeedback = ShouldSuppressAttackImpactFeedback(event, impactConfig) == true
    local countForScale = event.CountForScale or event.TargetCount or 1
    local hitPhase = GetAttackImpactHitPhase(event)

    if suppressHeavyFeedback ~= true then
        local shakeConfig = impactConfig.CameraShake or {}
        local shakeScale = event.CameraShakeScale
            or ScaleByImpactCount(
                shakeConfig.Base or 0.0,
                shakeConfig.PerTarget or 0.0,
                shakeConfig.Max,
                countForScale)
        shakeScale = shakeScale * GetHitPhaseNumber(shakeConfig, hitPhase, "HitMultiplier", 1.0)

        if CameraManager ~= nil and CameraManager.StartWaveShake ~= nil and shakeScale > 0.0 then
            CameraManager.StartWaveShake(shakeScale)
        end

        local vfxConfig = impactConfig.VFX or {}
        local particlePath = vfxConfig.ParticlePath
        local center = event.CenterLocation
        if center ~= nil and particlePath ~= nil and particlePath ~= "" and particlePath ~= "None" then
            local zOffset = vfxConfig.ZOffset or 0.0
            local scaleValue = event.VfxScale
                or ScaleByImpactCount(
                    vfxConfig.BaseScale or 1.0,
                    vfxConfig.PerTargetScale or 0.0,
                    vfxConfig.MaxScale,
                    countForScale)

            SpawnParticleSystem(
                particlePath,
                Vector(center.X, center.Y, center.Z + zOffset),
                vfxConfig.Rotation or Vector(0.0, 0.0, 0.0),
                Vector(scaleValue, scaleValue, scaleValue),
                vfxConfig.Life or 0.45,
                vfxConfig.MaterialPath or "None")
        end
    end

    -- Sound는 suppressHeavyFeedback 밖에서 처리한다.
    -- 그래서 UltimateHitCount 반복 중간타에서도 소리는 계속 난다.
    local soundConfig = impactConfig.Sound
    if soundConfig ~= nil and soundConfig.Enabled ~= false
        and CanPlayAttackImpactSound(playerContext, event, soundConfig) then
        local volume = event.SoundVolume
            or ScaleByImpactCount(
                soundConfig.BaseVolume or soundConfig.Volume or 1.0,
                soundConfig.PerTargetVolume or 0.0,
                soundConfig.MaxVolume,
                countForScale)
        volume = volume * GetHitPhaseNumber(soundConfig, hitPhase, "HitMultiplier", 1.0)
        volume = ClampOptional(volume, soundConfig.MinVolume, soundConfig.MaxVolume)

        local pitch = event.SoundPitch
            or ScaleByImpactCount(
                soundConfig.BasePitch or soundConfig.Pitch or 1.0,
                soundConfig.PerTargetPitch or 0.0,
                soundConfig.MaxPitch,
                countForScale)
        pitch = pitch + GetHitPhaseNumber(soundConfig, hitPhase, "HitPitchOffset", 0.0)
        local randomPitchRange = math.max(0.0, tonumber(soundConfig.RandomPitchRange) or 0.0)
        if randomPitchRange > 0.0 then
            pitch = pitch + (math.random() * 2.0 - 1.0) * randomPitchRange
        end
        pitch = ClampOptional(pitch, soundConfig.MinPitch, soundConfig.MaxPitch)

        local resolvedSound = {}
        for key, value in pairs(soundConfig) do
            resolvedSound[key] = value
        end

        resolvedSound.Volume = volume
        resolvedSound.Pitch = pitch

        PlayConfiguredSound(playerContext, resolvedSound)
    end

    local shouldPlayPulse = impactConfig.PulseFirstAndFinalOnly ~= true
        or hitPhase == "Single" or hitPhase == "First" or hitPhase == "Final"
    if suppressHeavyFeedback ~= true and shouldPlayPulse then
        local pulsePrefix = "Player." .. tostring(pulseConfigKey)
        StartFOVPulse(playerContext, pulsePrefix .. "FOV",
            GetFOVConfig(playerContext, pulseConfigKey)
                or GetFOVConfig(playerContext, "AttackImpact")
                or GetFOVConfig(playerContext, "AttackHit"))
        StartVignettePulse(playerContext, pulsePrefix .. "Vignette",
            GetVignetteConfig(playerContext, pulseConfigKey)
                or GetVignetteConfig(playerContext, "AttackImpact")
                or GetVignetteConfig(playerContext, "AttackHit"))
    end
end

local function PlayDashStartedFeedback(playerContext, event)
    StartFOVPulse(playerContext, "Player.DashFOV", GetFOVConfig(playerContext, "Dash"))
    SetVignetteLayer(playerContext, "Player.DashVignette", GetVignetteConfig(playerContext, "Dash"))
end

local function PlayDashEndedFeedback(playerContext, event)
    StopFOVPulse("Player.DashFOV")
    StopVignetteLayer(playerContext, "Player.DashVignette", GetVignetteConfig(playerContext, "Dash"))
end

local function PlayDashChargingStartedFeedback(playerContext, event)
    StopFOVPulse("Player.DashFOV")
    StopVignetteLayer(playerContext, "Player.DashVignette", GetVignetteConfig(playerContext, "Dash"))
    StartFOVPulse(playerContext, "Player.DashChargingFOV", GetFOVConfig(playerContext, "DashCharging"))
    SetVignetteLayer(playerContext, "Player.DashChargingVignette", GetVignetteConfig(playerContext, "DashCharging"))

    ResetDashChargeFeedbackState(playerContext)

    local config = GetDashChargeConfig(playerContext)
    local loc = GetOwnerLocation(playerContext)
    if loc ~= nil then
        local scaleValue = config.GroundRingScale or 1.0
        local ground = Vector(loc.X, loc.Y, loc.Z + 0.05)
        local psc = SpawnParticleSystem(
            config.GroundRingPath,
            ground,
            Vector(0.0, 0.0, 0.0),
            Vector(scaleValue, scaleValue, scaleValue),
            30.0,
            config.GroundRingMaterialPath)
        playerContext.Feedback.DashChargeGroundPSC = psc
    end
end

local function PlayDashChargingEndedFeedback(playerContext, event)
    StopFOVPulse("Player.DashChargingFOV")
    StopVignetteLayer(playerContext, "Player.DashChargingVignette", GetVignetteConfig(playerContext, "DashCharging"))

    local psc = playerContext.Feedback.DashChargeGroundPSC
    if IsValidObject(psc) then
        if psc.StopSpawning ~= nil then
            psc:StopSpawning()
        else
            psc:Deactivate()
        end
        if psc.SetAutoDestroyOwnerAfter ~= nil then
            psc:SetAutoDestroyOwnerAfter(0.35)
        end
    end
    ResetDashChargeFeedbackState(playerContext)
end

local function PlayDashChargeAttackStartedFeedback(playerContext, event)
    StopFOVPulse("Player.DashChargingFOV")
    StopVignetteLayer(playerContext, "Player.DashChargingVignette", GetVignetteConfig(playerContext, "DashCharging"))
    StartFOVPulse(playerContext, "Player.DashChargeAttackFOV", GetFOVConfig(playerContext, "DashChargeAttack"))
    SetVignetteLayer(playerContext, "Player.DashChargeAttackVignette", GetVignetteConfig(playerContext, "DashChargeAttack"))
end

local function PlayDashChargeAttackEndedFeedback(playerContext, event)
    StopFOVPulse("Player.DashChargeAttackFOV")
    StopVignetteLayer(playerContext, "Player.DashChargeAttackVignette", GetVignetteConfig(playerContext, "DashChargeAttack"))
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
    StartVignettePulse(playerContext, "Player.HitReactVignette", GetVignetteConfig(playerContext, "HitReact"))

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
        return Vector(baseRotation.X, baseRotation.Y, baseRotation.Z)
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

local function GetUltimateCameraBaseLocation(cameraConfig, focusLocation, actorForward, up)
    return
        focusLocation
        - actorForward * (cameraConfig.BackDistance or 40.0)
        + up * (cameraConfig.Height or 10.0)
end

local function GetUltimateCameraMotionTransform(cameraConfig, focusLocation, actorForward, actorRight, up, baseRotation, phase, t)
    local location = GetUltimateCameraBaseLocation(cameraConfig, focusLocation, actorForward, up)
    local rotation = GetUltimateCameraRotation(cameraConfig, baseRotation, t)

    if cameraConfig.MotionEnabled == false then
        return location, rotation
    end

    local easedT = EaseOutCubic(Clamp(t or 0.0, 0.0, 1.0))
    local waveT = math.sin(Clamp(t or 0.0, 0.0, 1.0) * math.pi)

    if phase == "Intro" then
        location = location
            - actorRight * ((cameraConfig.IntroSideDrift or 3.0) * (1.0 - easedT))
            - actorForward * ((cameraConfig.IntroForwardDrift or 2.0) * (1.0 - easedT))
            + up * ((cameraConfig.IntroHeightDrift or 0.8) * waveT)
        rotation.X = rotation.X - (cameraConfig.IntroPitchDrift or 0.8) * waveT
        rotation.Z = rotation.Z - (cameraConfig.IntroYawDrift or 1.5) * (1.0 - easedT)
    elseif phase == "Move" then
        location = location
            + actorRight * ((cameraConfig.MoveSideDrift or 6.0) * waveT)
            + actorForward * ((cameraConfig.MoveForwardDrift or -4.0) * easedT)
            + up * ((cameraConfig.MoveHeightDrift or 1.2) * waveT)
    elseif phase == "Attack" then
        location = location
            + actorRight * ((cameraConfig.AttackSideDrift or 10.0) * easedT)
            + actorForward * ((cameraConfig.AttackForwardDrift or 6.0) * easedT)
            + up * ((cameraConfig.AttackHeightDrift or 2.0) * waveT)
        rotation.X = rotation.X + (cameraConfig.AttackPitchDrift or 1.2) * waveT
        rotation.Z = rotation.Z + (cameraConfig.AttackYawDrift or 4.0) * easedT
    elseif phase == "Recover" then
        location = location
            + actorRight * ((cameraConfig.RecoverSideDrift or 4.0) * (1.0 - easedT))
            + actorForward * ((cameraConfig.RecoverForwardDrift or 3.0) * (1.0 - easedT))
            + up * ((cameraConfig.RecoverHeightDrift or 1.0) * waveT)
        rotation.X = rotation.X + (cameraConfig.RecoverPitchDrift or 0.8) * waveT
        rotation.Z = rotation.Z + (cameraConfig.RecoverYawDrift or 1.5) * (1.0 - easedT)
    end

    return location, rotation
end

local function UpdateUltimateCameraRayFade(cameraLocation, cameraConfig, focusLocation, ignoreActor, up)
    if CameraManager == nil or CameraManager.UpdateCameraRayFade == nil then
        return
    end

    if cameraLocation == nil or focusLocation == nil then
        return
    end

    if cameraConfig ~= nil and cameraConfig.CameraRayFadeEnabled == false then
        return
    end

    local focusOffset = 1.2
    if cameraConfig ~= nil and cameraConfig.CameraRayFadeFocusHeightOffset ~= nil then
        focusOffset = tonumber(cameraConfig.CameraRayFadeFocusHeightOffset) or focusOffset
    end

    local targetLocation = focusLocation
    if up ~= nil then
        targetLocation = focusLocation + up * focusOffset
    end

    local opacity = 0.35
    local maxHits = 8
    local debug = false
    if cameraConfig ~= nil then
        opacity = tonumber(cameraConfig.CameraRayFadeOpacity) or opacity
        maxHits = math.max(1, math.floor(tonumber(cameraConfig.CameraRayFadeMaxHits) or maxHits))
        debug = cameraConfig.CameraRayFadeDebug == true
    end

    CameraManager.UpdateCameraRayFade(cameraLocation, targetLocation, ignoreActor, opacity, maxHits, debug)
end

local function ClearUltimateCameraRayFade()
    if CameraManager ~= nil and CameraManager.ClearCameraRayFade ~= nil then
        CameraManager.ClearCameraRayFade()
    end
end

local function ApplyUltimateCameraMotion(ultimateCamera, cameraConfig, focusLocation, actorForward, actorRight, up, baseRotation, phase, t, rayFadeIgnoreActor)
    if ultimateCamera == nil then
        return
    end

    local location, rotation = GetUltimateCameraMotionTransform(
        cameraConfig,
        focusLocation,
        actorForward,
        actorRight,
        up,
        baseRotation,
        phase,
        t
    )

    Reflection.Call(ultimateCamera, "SetActorLocation", location)
    Reflection.Call(ultimateCamera, "SetActorRotation", rotation)
    UpdateUltimateCameraRayFade(location, cameraConfig, focusLocation, rayFadeIgnoreActor, up)
end

local function WaitWithUltimateCameraMotion(duration, frameStep, updateFunc)
    local total = math.max(0.0, tonumber(duration) or 0.0)
    if total <= 0.0 then
        return
    end

    local step = math.max(1.0 / 120.0, tonumber(frameStep) or (1.0 / 60.0))
    local elapsed = 0.0

    while elapsed < total do
        local waitStep = math.min(step, total - elapsed)
        Wait(waitStep)
        elapsed = elapsed + waitStep

        if updateFunc ~= nil then
            updateFunc(Clamp(elapsed / total, 0.0, 1.0), elapsed, waitStep)
        end
    end
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

local function GetActorLocationSafe(actor)
    if actor == nil then
        return nil
    end

    local location = nil
    if Reflection ~= nil and Reflection.Call ~= nil then
        location = Reflection.Call(actor, "GetActorLocation")
    end
    if location == nil then
        location = actor.Location
    end
    return location
end

local function GetDirection2D(from, to)
    if from == nil or to == nil then
        return nil, 0.0
    end

    local dir = to - from
    dir.Z = 0.0
    local distance = dir:Length()
    if distance <= 0.001 then
        return nil, distance
    end

    return dir:Normalized(), distance
end

local function GetRightFromForward(forward)
    if forward == nil then
        return nil
    end

    local right = Vector(-forward.Y, forward.X, 0.0)
    if right:Length() <= 0.001 then
        return nil
    end
    return right:Normalized()
end

local function ResolveUltimateFocus(playerContext, actorLocation, fallbackForward)
    local target, targetDir = PlayerTargeting.FindTarget(playerContext, "Ultimate", fallbackForward)
    if target == nil then
        return nil, nil, fallbackForward
    end

    local targetLocation = GetActorLocationSafe(target)
    local dir = GetDirection2D(actorLocation, targetLocation)
    if dir == nil then
        dir = targetDir
    end
    if dir == nil then
        dir = fallbackForward
    end

    playerContext.Action.UltimateFocusTarget = target
    playerContext.Action.UltimateFocusLocation = targetLocation
    return target, targetLocation, dir
end

local function GetOrCreateUltimateCameraActor()
    local ultimateCamera = World.FindFirstActorByTag("UltimateCamera")
    if IsValidObject(ultimateCamera) then
        return ultimateCamera
    end

    if World.SpawnActor == nil then
        return nil
    end

    ultimateCamera = World.SpawnActor("AActor")
    if not IsValidObject(ultimateCamera) then
        return nil
    end

    if ultimateCamera.AddTag ~= nil then
        ultimateCamera:AddTag("UltimateCamera")
    end
    if ultimateCamera.AddCameraComponent ~= nil then
        ultimateCamera:AddCameraComponent()
    end

    print("[PlayerFeedback] Runtime UltimateCamera created")
    return ultimateCamera
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
    ResetDashChargeFeedbackState(playerContext)
    playerContext.Feedback.LastImpactSoundTimes = {}
    PlayerFeedback.AttachKatanaToWeaponSocket(playerContext)
    PlayerFeedback.AttachPSCToWeaponSocket(playerContext)

    local feedbackConfig = playerContext.Config.Feedback or {}
    local attackHitConfig = feedbackConfig.AttackHit or {}
    local attackImpactConfig = feedbackConfig.AttackImpact or {}
    local ultimateAttackImpactConfig = feedbackConfig.UltimateAttackImpact or {}
    local perfectDodgeConfig = feedbackConfig.PerfectDodge or {}
    EnsureConfiguredSoundLoaded(playerContext, perfectDodgeConfig.Sound)
    EnsureConfiguredSoundLoaded(playerContext, attackHitConfig.Sound)
    EnsureConfiguredSoundLoaded(playerContext, attackImpactConfig.Sound)
    EnsureConfiguredSoundLoaded(playerContext, ultimateAttackImpactConfig.Sound)
end

---@param playerContext PlayerContext
---@return nil
function PlayerFeedback.Shutdown(playerContext)
    PlayerContext.Assert(playerContext, "PlayerFeedback.Shutdown")
    StopVignetteLayer(playerContext, "Player.LowHPVignette", nil)
    StopVignetteLayer(playerContext, "Player.DashVignette", nil)
    StopVignetteLayer(playerContext, "Player.DashChargingVignette", nil)
    StopVignetteLayer(playerContext, "Player.DashChargeAttackVignette", nil)
    local dashChargePSC = playerContext.Feedback.DashChargeGroundPSC
    if IsValidObject(dashChargePSC) then
        dashChargePSC:Deactivate()
        if dashChargePSC.SetAutoDestroyOwnerAfter ~= nil then
            dashChargePSC:SetAutoDestroyOwnerAfter(0.1)
        end
    end
    ResetDashChargeFeedbackState(playerContext)
    playerContext.Feedback.LoadedAudioKeys = nil
    playerContext.Feedback.LastImpactSoundTimes = nil
    playerContext.Feedback.KatanaComponent = nil
    playerContext.Feedback.KatanaPSC = nil
end

---@param playerContext PlayerContext
---@return nil
function PlayerFeedback.BeginUltimate(playerContext)
    PlayerContext.Assert(playerContext, "PlayerFeedback.BeginUltimate")
    print("Begin Ultimate")

    local action = playerContext.Action
    action.IsUltimateRunning = true
    action.IsUltimateCinematic = true
    action.IsInUltimateMode = false
    action.UltimateAttackInstanceId = nil
    action.UltimateFocusTarget = nil
    action.UltimateFocusLocation = nil

    local owner = playerContext.Owner
    if owner == nil then
        action.IsUltimateRunning = false
        action.IsUltimateCinematic = false
        return
    end

    local movementComp = owner:GetCharacterMovement()
    if movementComp == nil then
        print("Movement not found")
        action.IsUltimateRunning = false
        action.IsUltimateCinematic = false
        return
    end

    PlayerAction.CancelDashActions(playerContext, false)
    PlayerAction.StopMovementImmediately(playerContext)

    local ultimateCamera = GetOrCreateUltimateCameraActor()
    if ultimateCamera == nil then
        print("UltimateCamera not found")
        action.IsUltimateRunning = false
        action.IsUltimateCinematic = false
        return
    end

    local actorLocation = Reflection.Call(owner, "GetActorLocation")
    local actorForward, actorRight = GetSafeOwnerBasis(owner)

    if actorLocation == nil or actorForward == nil or actorRight == nil then
        print("Invalid owner transform")
        action.IsUltimateRunning = false
        action.IsUltimateCinematic = false
        return
    end

    local focusTarget, focusLocation, focusForward = ResolveUltimateFocus(playerContext, actorLocation, actorForward)
    if focusForward ~= nil then
        actorForward = focusForward
        actorRight = GetRightFromForward(actorForward) or actorRight
    end
    if focusLocation == nil then
        focusLocation = actorLocation + actorForward * 30.0
    end
    focusLocation.Z = actorLocation.Z

    FaceOwnerToDirection(playerContext, actorForward)

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
    local slashAnchor =
        focusLocation
        + actorForward * (cameraConfig.SlashCameraDistance)
        + up * (cameraConfig.SlashCameraHeightOffset)
        + actorRight * (cameraConfig.SlashCameraRightOffset)

    local cameraYaw = math.atan2(actorForward.Y, actorForward.X) * 180.0 / math.pi
    local baseCameraRotation = Vector(-10.0, 15.0, cameraYaw)

    ApplyUltimateCameraMotion(
        ultimateCamera,
        cameraConfig,
        focusLocation,
        actorForward,
        actorRight,
        up,
        baseCameraRotation,
        "Intro",
        0.0,
        owner
    )

    CameraManager.ToggleOwnerCamera(ultimateCamera, 0)
    StartFOVPulse(playerContext, "Player.UltimateStartFOV", fovConfig.UltimateStart)
    StartVignettePulse(playerContext, "Player.UltimateStartVignette", GetVignetteConfig(playerContext, "UltimateStart"))
    local ownerAction = GetOrAddActionComponent(owner)
    if ownerAction ~= nil and ownerAction.Slomo ~= nil then
        ownerAction:Slomo(moveConfig.SlomoDuration or 0.0, moveConfig.SlomoScale or 1.0)
    end
    Reflection.Call(movementComp, "StopMovementImmediately")
    Reflection.Call(movementComp, "SetMovementInputEnabled", false)

    WaitWithUltimateCameraMotion(cameraConfig.IntroHold or 0.15, moveConfig.FrameStep, function(t)
        ApplyUltimateCameraMotion(
            ultimateCamera,
            cameraConfig,
            focusLocation,
            actorForward,
            actorRight,
            up,
            baseCameraRotation,
            "Intro",
            t,
            owner
        )
    end)

    local startPos =
        focusLocation
        - actorForward * (moveConfig.StartDistance)
        + actorRight * (moveConfig.SideOffset)

    startPos.Z = actorLocation.Z

    local cinematicEndPos =
        focusLocation
        - actorForward * (moveConfig.EndDistance)
        + actorRight * (moveConfig.EndRightDistance)

    cinematicEndPos.Z = actorLocation.Z
    local subUVSlashAnchor = cinematicEndPos

    local controlPos =
        focusLocation
        - actorForward * (((moveConfig.StartDistance) + (moveConfig.EndDistance)) * 0.5)
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
    FaceOwnerToDirection(playerContext, actorForward)

    local elapsed = 0.0

    local spawnedAirSlashA = false
    local spawnedAirSlashB = false
    local spawnedAirSlashC = false
    local spawnedAirSlashD = false
    local spawnedAirSlashE = false
    local spawnedSlashFlash = false

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
            VFX.SpawnSubUV(vfxConfig.SlashSubUVResource, subUVSlashAnchor - actorForward * 6.0 - actorRight * 8.0 + up * 0.4, Vector(1.0, 88.0, 7.0), -12.0, vfxConfig.SlashFrameRate, false, true)
            spawnedAirSlashA = true
        end

        if not spawnedAirSlashB and t >= 0.34 then
            VFX.SpawnSubUV(vfxConfig.SlashSubUVResource, subUVSlashAnchor + actorForward * 2.0 + actorRight * 9.0 + up * 3.0, Vector(1.0, 65.0, 4.5), 32.0, vfxConfig.SlashFrameRate, false, true)
            spawnedAirSlashB = true
        end

        if not spawnedAirSlashD and t >= 0.42 then
            VFX.SpawnSubUV(vfxConfig.SlashSubUVResource, subUVSlashAnchor + actorForward * 8.0 - actorRight * 3.0 + up * 5.0, Vector(1.0, 72.0, 4.0), 58.0, vfxConfig.SlashFrameRate, false, true)
            spawnedAirSlashD = true
        end

        if not spawnedAirSlashC and t >= 0.50 then
            VFX.SpawnSubUV(vfxConfig.SlashSubUVResource, subUVSlashAnchor + actorForward * 12.0 - actorRight * 12.0 + up * -2.0, Vector(1.0, 55.0, 3.5), -36.0, vfxConfig.SlashFrameRate, false, true)
            spawnedAirSlashC = true
        end

        if not spawnedAirSlashE and t >= 0.62 then
            VFX.SpawnSubUV(vfxConfig.SlashSubUVResource, subUVSlashAnchor - actorForward * 2.0 + actorRight * 15.0 + up * -3.4, Vector(1.0, 50.0, 3.0), -62.0, vfxConfig.SlashFrameRate, false, true)
            spawnedAirSlashE = true
        end

        local nextPos = Bezier2(startPos, controlPos, cinematicEndPos, easedT)
        nextPos.Z = actorLocation.Z

        ApplyUltimateCameraMotion(
            ultimateCamera,
            cameraConfig,
            focusLocation,
            actorForward,
            actorRight,
            up,
            baseCameraRotation,
            "Move",
            t,
            owner
        )
        Reflection.Call(owner, "SetActorLocation", nextPos)

        local faceDir = actorForward
        if focusTarget ~= nil then
            local latestFocusLocation = GetActorLocationSafe(focusTarget) or focusLocation
            latestFocusLocation.Z = actorLocation.Z
            faceDir = GetDirection2D(nextPos, latestFocusLocation) or actorForward
            focusLocation = latestFocusLocation
        end

        if faceDir ~= nil then
            FaceOwnerToDirection(playerContext, faceDir)
        end
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
    local attackFaceDir = GetDirection2D(cinematicEndPos, focusLocation) or actorForward
    FaceOwnerToDirection(playerContext, attackFaceDir)
    CameraManager.StartWaveShake(1.0)
    StartFOVPulse(playerContext, "Player.UltimateImpactFOV", fovConfig.UltimateImpact)
    StartVignettePulse(playerContext, "Player.UltimateImpactVignette", GetVignetteConfig(playerContext, "UltimateImpact"))

    local combatConfig = playerContext.Config.Combat or {}
    local ultimateHitCount = math.max(1, math.min(20, math.floor(tonumber(combatConfig.UltimateHitCount) or 1)))
    local ultimateHitInterval = math.max(0.0, tonumber(combatConfig.UltimateHitInterval) or 0.0)
    local attackCameraDuration = math.max(
        moveConfig.AttackDuration or 0.0,
        (moveConfig.AttackStartDelay or 0.0)
            + (moveConfig.AttackDamageDelay or 0.0)
            + ultimateHitInterval * math.max(0, ultimateHitCount - 1)
    )
    local attackCameraElapsed = 0.0

    local function UpdateAttackCamera(deltaTime)
        if attackCameraDuration <= 0.0 then
            return
        end

        attackCameraElapsed = math.min(attackCameraDuration, attackCameraElapsed + (deltaTime or 0.0))
        ApplyUltimateCameraMotion(
            ultimateCamera,
            cameraConfig,
            focusLocation,
            actorForward,
            actorRight,
            up,
            baseCameraRotation,
            "Attack",
            Clamp(attackCameraElapsed / attackCameraDuration, 0.0, 1.0),
            owner
        )
    end

    local function WaitAttackCamera(duration)
        WaitWithUltimateCameraMotion(duration, moveConfig.FrameStep, function(_, _, deltaTime)
            UpdateAttackCamera(deltaTime)
        end)
    end

    WaitAttackCamera(moveConfig.AttackStartDelay or 0.0)

    action.IsUltimateCinematic = false
    action.UltimateAttackInstanceId = "PlayerUltimate_" .. tostring(World.GetGameTime())
    action.IsInUltimateMode = true

    WaitAttackCamera(moveConfig.AttackDamageDelay or 0.0)

    local baseUltimateAttackInstanceId = action.UltimateAttackInstanceId
    local repeatedHitTime = 0.0

    for hitIndex = 1, ultimateHitCount do
        if hitIndex > 1 then
            if ultimateHitInterval > 0.0 then
                WaitAttackCamera(ultimateHitInterval)
                repeatedHitTime = repeatedHitTime + ultimateHitInterval
            else
                WaitFrame()
                UpdateAttackCamera(moveConfig.FrameStep or (1.0 / 60.0))
            end
            action.UltimateAttackInstanceId = tostring(baseUltimateAttackInstanceId) .. "_H" .. tostring(hitIndex)
        end

        CombatContext.ApplyPlayerUltimateDamage(playerContext, focusLocation, focusTarget, {
            AttackImpactGroupId = tostring(baseUltimateAttackInstanceId) .. "_UltimateImpact_H" .. tostring(hitIndex),
            HitIndex = hitIndex,
            HitCount = ultimateHitCount,
            HitInterval = ultimateHitInterval,
        })
    end

    action.UltimateAttackInstanceId = baseUltimateAttackInstanceId

    local remainingAttackTime = (moveConfig.AttackDuration or 0.0) - (moveConfig.AttackDamageDelay or 0.0) - repeatedHitTime
    if remainingAttackTime > 0.0 then
        WaitAttackCamera(remainingAttackTime)
    end

    action.IsInUltimateMode = false

    WaitWithUltimateCameraMotion(moveConfig.RecoverHold or 0.0, moveConfig.FrameStep, function(t)
        ApplyUltimateCameraMotion(
            ultimateCamera,
            cameraConfig,
            focusLocation,
            actorForward,
            actorRight,
            up,
            baseCameraRotation,
            "Recover",
            t,
            owner
        )
    end)

    Reflection.Call(movementComp, "SetMovementInputEnabled", true)
    StartFOVPulse(playerContext, "Player.UltimateRecoverFOV", fovConfig.UltimateRecover)
    StartVignettePulse(playerContext, "Player.UltimateRecoverVignette", GetVignetteConfig(playerContext, "UltimateRecover"))
    CameraManager.ToggleOwnerCamera(owner, 0.4)
    ClearUltimateCameraRayFade()

    if PrimComp ~= nil then
        Reflection.Call(PrimComp, "SetSimulatePhysics", PrevSimulatePhysics)
    end

    action.IsUltimateCinematic = false
    action.IsInUltimateMode = false
    action.IsUltimateRunning = false
    action.UltimateFocusTarget = nil
    action.UltimateFocusLocation = nil
    PlayerEvents.EmitUltimateEnded(playerContext)

    print("End Ultimate")
end

local function SpawnDashChargeInwardParticle(playerContext, config, ratio)
    local ownerLoc = GetOwnerLocation(playerContext)
    if ownerLoc == nil then
        return
    end

    local minRadius = config.InwardMinRadius or 2.0
    local maxRadius = config.InwardMaxRadius or 4.5
    local radius = minRadius + (maxRadius - minRadius) * ratio
    local angle = math.random() * math.pi * 2.0
    local spawn = Vector(
        ownerLoc.X + math.cos(angle) * radius,
        ownerLoc.Y + math.sin(angle) * radius,
        ownerLoc.Z + (config.InwardHeight or 0.75))

    local target = Vector(ownerLoc.X, ownerLoc.Y, ownerLoc.Z + (config.InwardTargetHeight or 1.05))
    local toTarget = target - spawn
    local yaw = 0.0
    local pitch = 0.0
    if toTarget:Length() > 0.001 then
        local n = toTarget:Normalized()
        yaw = math.atan2(n.Y, n.X) * 180.0 / math.pi
        pitch = math.atan2(n.Z, math.sqrt(n.X * n.X + n.Y * n.Y)) * 180.0 / math.pi
    end

    local minScale = config.InwardMinScale or 0.35
    local maxScale = config.InwardMaxScale or 1.0
    local scaleValue = minScale + (maxScale - minScale) * ratio
    SpawnParticleSystem(
        config.InwardParticlePath,
        spawn,
        Vector(pitch, 0.0, yaw),
        Vector(scaleValue, scaleValue, scaleValue),
        config.InwardLife or 0.32,
        config.InwardMaterialPath)
end

local function UpdateDashChargeFeedback(playerContext, dt)
    if playerContext.Action.DashChargingActive ~= true then
        return
    end

    local config = GetDashChargeConfig(playerContext)
    local ratio = GetDashChargeRatio(playerContext)

    playerContext.Feedback.DashChargeVFXTimer = (playerContext.Feedback.DashChargeVFXTimer or 0.0) - (dt or 0.0)
    if playerContext.Feedback.DashChargeVFXTimer <= 0.0 then
        SpawnDashChargeInwardParticle(playerContext, config, ratio)
        local interval = config.InwardSpawnInterval or 0.06
        playerContext.Feedback.DashChargeVFXTimer = math.max(0.01, interval * (1.0 - ratio * 0.55))
    end

    if config.CameraShakeEnabled ~= false and CameraManager ~= nil and CameraManager.StartWaveShake ~= nil then
        playerContext.Feedback.DashChargeShakeTimer = (playerContext.Feedback.DashChargeShakeTimer or 0.0) - (dt or 0.0)
        if playerContext.Feedback.DashChargeShakeTimer <= 0.0 then
            local minScale = config.CameraShakeMinScale or 0.08
            local maxScale = config.CameraShakeMaxScale or 0.35
            CameraManager.StartWaveShake(minScale + (maxScale - minScale) * ratio)
            playerContext.Feedback.DashChargeShakeTimer = config.CameraShakeInterval or 0.16
        end
    end

    if ratio >= 1.0 and playerContext.Feedback.DashChargeReadyBursted ~= true then
        local loc = GetOwnerLocation(playerContext)
        if loc ~= nil then
            local scaleValue = config.ReadyBurstScale or 1.5
            SpawnParticleSystem(
                config.ReadyBurstPath,
                Vector(loc.X, loc.Y, loc.Z + 0.1),
                Vector(0.0, 0.0, 0.0),
                Vector(scaleValue, scaleValue, scaleValue),
                0.75,
                config.ReadyBurstMaterialPath)
        end
        if CameraManager ~= nil and CameraManager.StartWaveShake ~= nil then
            CameraManager.StartWaveShake(config.CameraShakeMaxScale or 0.45)
        end
        playerContext.Feedback.DashChargeReadyBursted = true
    end

    local ground = playerContext.Feedback.DashChargeGroundPSC
    local loc = GetOwnerLocation(playerContext)
    if IsValidObject(ground) and loc ~= nil then
        ground.Location = Vector(loc.X, loc.Y, loc.Z + 0.05)
        if ground.SetParticleSizeScale ~= nil then
            local baseScale = config.GroundRingScale or 1.0
            local scaleValue = baseScale * (0.8 + 0.45 * ratio)
            ground:SetParticleSizeScale(Vector(scaleValue, scaleValue, scaleValue))
        end
    end
end

---@param playerContext PlayerContext
---@param dt number
---@return nil
function PlayerFeedback.Update(playerContext, dt)
    PlayerContext.Assert(playerContext, "PlayerFeedback.Update")
    UpdateLowHPVignette(playerContext)
    UpdateDashChargeFeedback(playerContext, dt)
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
        elseif PlayerEvents.Is(event, PlayerEvents.Type.AttackImpact) then
            PlayAttackImpactFeedback(playerContext, event)
        elseif PlayerEvents.Is(event, PlayerEvents.Type.Dead) then
            StartDeathRagdoll(playerContext)
            StopVignetteLayer(playerContext, "Player.LowHPVignette", nil)
            StartVignettePulse(playerContext, "Player.DeathVignette", GetVignetteConfig(playerContext, "Death"))
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
