-- Anim/PlayerAnimation.lua
-- Owns animation graph state only. Gameplay state lives in PlayerContext.
-- Notify callbacks are adapted into PlayerAction / CombatContext calls.

local PlayerAction = require("Player/PlayerAction")
local CombatContext = require("Combat/CombatContext")
local HitTypes = require("Combat/HitTypes")
local PlayerContext = require("Player/PlayerContext")
local PlayerConfig = require("Config/PlayerConfig")
local PlayerEvents = require("Player/PlayerEvents")
local PlayerFeedback = require("Player/PlayerFeedback")
local CoroutineManager = require("CoroutineManager")

local function GetAttackPlayRate(samuraiConfig, attackIndex)
    return samuraiConfig.AttackPlayRates[attackIndex] or samuraiConfig.AttackPlayRate
end

local function GetPostDashAttackPath(samuraiConfig, attackPaths, variant)
    local postDashAttackPaths = samuraiConfig.PostDashAttackPaths or {}
    return postDashAttackPaths[variant] or attackPaths[variant] or attackPaths[1]
end

local function GetPostDashAttackPlayRate(samuraiConfig, variant)
    if samuraiConfig.PostDashAttackPlayRates ~= nil and samuraiConfig.PostDashAttackPlayRates[variant] ~= nil then
        return samuraiConfig.PostDashAttackPlayRates[variant]
    end
    if samuraiConfig.PostDashAttackPlayRate ~= nil then
        return samuraiConfig.PostDashAttackPlayRate
    end
    return GetAttackPlayRate(samuraiConfig, variant)
end

local function IsValidActor(actor)
    if actor == nil then
        return false
    end
    if actor.IsValid ~= nil then
        return actor:IsValid()
    end
    return true
end

local function GetActorName(actor)
    if actor ~= nil and actor.GetName ~= nil then
        return actor:GetName()
    end
    return tostring(actor)
end

local function GetOwnerKey(owner)
    if owner == nil then
        return nil
    end
    return owner.UUID or tostring(owner)
end

local function ShouldStopRepeatedAttackHit(result)
    if result == nil then
        return true
    end

    -- If the C++ notify window calls Lua again in the same animation window,
    -- CombatContext will reject the stable first-hit AttackInstanceId as DuplicateHit.
    -- Do not schedule another multi-hit coroutine from such duplicate callbacks.
    if result.Applied ~= true then
        return true
    end

    local reason = result.Reason
    return reason == "MobDead"
        or reason == "BossDead"
        or reason == "MissingTarget"
        or reason == "NoCombatTarget"
        or reason == "PlayerMissing"
end

local function ResolveAttackHitRepeat(playerContext, notifyHitCount, notifyHitInterval)
    local combatConfig = playerContext.Config and playerContext.Config.Combat or PlayerConfig.Combat or {}
    local action = playerContext.Action or {}

    local count = tonumber(notifyHitCount) or 1
    local interval = tonumber(notifyHitInterval) or 0.0

    -- NotifyState values are intentionally edit-only hot overrides. When left at
    -- the safe default 1, use persistent Lua config instead.
    if count <= 1 then
        if action.DashChargeAttackActive == true then
            count = tonumber(combatConfig.DashChargeAttackHitCount) or count
            interval = tonumber(combatConfig.DashChargeAttackHitInterval) or interval
        elseif action.IsInUltimateMode == true then
            count = tonumber(combatConfig.UltimateHitCount) or count
            interval = tonumber(combatConfig.UltimateHitInterval) or interval
        else
            local attackIndex = action.AttackIndex or 1
            if combatConfig.AttackHitCounts ~= nil then
                count = tonumber(combatConfig.AttackHitCounts[attackIndex]) or count
            end
            if combatConfig.AttackHitIntervals ~= nil then
                interval = tonumber(combatConfig.AttackHitIntervals[attackIndex]) or interval
            end
        end
    end

    count = math.max(1, math.min(8, math.floor(count or 1)))
    interval = math.max(0.0, tonumber(interval) or 0.0)
    return count, interval
end


local function ApplyAttackHitOnce(playerContext, targetActor, hitboxComponent, targetComponent, hitResult,
    hitStopDuration, hitIndex, hitCount, hitInterval, hitWindowSerial, attackImpactGroupId)
    local requestHitStop = hitStopDuration
    if hitIndex ~= nil and hitIndex > 1 then
        -- Prevent repeated local hit-stop from making the game look permanently frozen.
        requestHitStop = 0.0
    end

    local hitRequest = HitTypes.CreatePlayerAttackFromState({
        PlayerContext = playerContext,
        TargetActor = targetActor,
        HitboxComponent = hitboxComponent,
        TargetComponent = targetComponent,
        HitResult = hitResult,
        HitStopDuration = requestHitStop,
        HitWindowSerial = hitWindowSerial,
        AttackImpactGroupId = attackImpactGroupId,
        HitIndex = hitIndex or 1,
        HitCount = hitCount or 1,
        HitInterval = hitInterval or 0.0,
    })

    if hitIndex ~= nil and hitIndex > 1 then
        -- Keep the first hit on the original attack instance so the existing
        -- duplicate-hit table still filters repeated notify ticks. Only follow-up
        -- multi-hit applications get a deterministic per-hit suffix.
        hitRequest.AttackInstanceId = tostring(hitRequest.AttackInstanceId or hitRequest.AttackId or "PlayerAttack")
            .. "_MH" .. tostring(hitIndex)
    end

    return CombatContext.ApplyHit(hitRequest)
end

local function LogAttackHitResult(targetActor, result, hitIndex, hitCount)
    local prefix = "on attack hit"
    if hitCount ~= nil and hitCount > 1 then
        prefix = string.format("on attack hit [%d/%d]", hitIndex or 1, hitCount)
    end

    if result ~= nil and result.Applied == true then
        print(prefix .. " " .. GetActorName(targetActor) .. " damage=" .. tostring(result.Damage))
    elseif result ~= nil and result.Reason == "DuplicateHit" then
        -- NotifyTick can still invoke the callback more than once in this engine.
        -- The combat layer correctly filters it; keep logs focused on real hits.
        return
    else
        print(prefix .. " ignored " .. GetActorName(targetActor) .. " reason=" .. tostring(result and result.Reason or "nil"))
    end
end

local function ResetAttack(self, unlockMovement)
    local playerContext = self.PlayerContext
    PlayerContext.Assert(playerContext, "PlayerAnimation.ResetAttack")
    local actionState = playerContext.Action
    local attackIndex = actionState.AttackIndex

    actionState.AttackIndex = 0
    actionState.PostDashAttackActive = false
    actionState.PostDashAttackVariant = 0
    actionState.ComboWindow = false
    actionState.ComboQueued = false
    actionState.AttackEnd = false

    if unlockMovement ~= false then
        PlayerAction.SetMovementInputEnabled(playerContext, true)
    end

    PlayerAction.EndAttackAssist(playerContext)

    if attackIndex ~= nil and attackIndex > 0 then
        PlayerEvents.EmitAttackEnded(playerContext, { AttackIndex = attackIndex })
    end
end

local function BeginAttack(self, index)
    local playerContext = self.PlayerContext
    PlayerContext.Assert(playerContext, "PlayerAnimation.BeginAttack")
    local actionState = playerContext.Action
    actionState.AttackIndex = index
    actionState.PostDashAttackActive = false
    actionState.PostDashAttackVariant = 0
    actionState.AttackInstanceId = "PlayerAttack" .. tostring(index) .. "_" .. tostring(World.GetGameTime())
    actionState.ComboWindow = false
    actionState.ComboQueued = false
    actionState.AttackEnd = false
    PlayerAction.StopMovementImmediately(playerContext)
    PlayerAction.BeginAttackAssist(playerContext, index)
    PlayerAction.StepAttackForward(playerContext, index)
    PlayerEvents.EmitAttackStarted(playerContext, { AttackIndex = index })
end

local function BeginPostDashAttack(self, variant)
    local playerContext = self.PlayerContext
    PlayerContext.Assert(playerContext, "PlayerAnimation.BeginPostDashAttack")
    PlayerAction.BeginPostDashAttack(playerContext, variant)
end

local function BeginDash(self)
    ResetAttack(self, false)
    local playerContext = self.PlayerContext
    PlayerContext.Assert(playerContext, "PlayerAnimation.BeginDash")
    playerContext.Input.DashPressed = false
    PlayerAction.BeginDash(playerContext)
end

local function EndDash(self, activatePostDashAttackWindow)
    local playerContext = self.PlayerContext
    PlayerContext.Assert(playerContext, "PlayerAnimation.EndDash")
    PlayerAction.EndDash(playerContext, activatePostDashAttackWindow)
end

local function BeginDashCharging(self)
    ResetAttack(self, false)
    local playerContext = self.PlayerContext
    PlayerContext.Assert(playerContext, "PlayerAnimation.BeginDashCharging")
    playerContext.Input.DashChargingPressed = false
    playerContext.Input.DashChargingReleased = false
    PlayerAction.BeginDashCharging(playerContext)
end

local function EndDashCharging(self, unlockMovement)
    local playerContext = self.PlayerContext
    PlayerContext.Assert(playerContext, "PlayerAnimation.EndDashCharging")
    PlayerAction.EndDashCharging(playerContext, unlockMovement)
end

local function BeginDashChargeAttack(self)
    ResetAttack(self, false)
    local playerContext = self.PlayerContext
    PlayerContext.Assert(playerContext, "PlayerAnimation.BeginDashChargeAttack")
    playerContext.Action.DashChargeAttackEnd = false
    playerContext.Action.DashChargeAttackInstanceId = "PlayerDashChargeAttack_" .. tostring(World.GetGameTime())
    PlayerAction.BeginDashChargeAttack(playerContext)
end

local function EndDashChargeAttack(self)
    local playerContext = self.PlayerContext
    PlayerContext.Assert(playerContext, "PlayerAnimation.EndDashChargeAttack")
    PlayerAction.EndDashChargeAttack(playerContext)
end

local function BeginUltimateAttack(self)
    ResetAttack(self, false)
    local playerContext = self.PlayerContext
    PlayerContext.Assert(playerContext, "PlayerAnimation.BeginUltimateAttack")
    PlayerAction.CancelDashActions(playerContext, false)
    PlayerAction.StopMovementImmediately(playerContext)
end

local function BeginHitReactionAnim(self, direction)
    local playerContext = self.PlayerContext
    PlayerContext.Assert(playerContext, "PlayerAnimation.BeginHitReactionAnim")
    playerContext.Action.HitReactPending = false
    playerContext.Action.HitReactDirection = direction
    playerContext.Action.HitReactEnd = false
end

local function EndHitReactionAnim(self)
    local playerContext = self.PlayerContext
    PlayerContext.Assert(playerContext, "PlayerAnimation.EndHitReactionAnim")
    PlayerAction.EndHitReaction(playerContext)
end

local function ShouldEnterHitReaction(self, direction)
    if self.PlayerContext == nil then
        return false
    end

    return self.PlayerContext.Action.HitReactPending == true
        and self.PlayerContext.Action.HitReactDirection == direction
        and self.PlayerContext.Action.IsUltimateRunning ~= true
        and self.PlayerContext.Action.IsUltimateCinematic ~= true
        and self.PlayerContext.Action.IsInUltimateMode ~= true
end

function init(self)
    self.Speed = 0.0
    self.BlendSpeed = 0.0

    self.PlayerContext = nil

    local samuraiConfig = PlayerConfig.Default.Animation.Samurai
    local attackPaths = samuraiConfig.AttackPaths

    local loco = Anim.create_blend_space_1d(0.0)
    Anim.blend_space_1d_add_sample(loco, samuraiConfig.IdlePath, 0.0, 1.0, true)
    Anim.blend_space_1d_add_sample(loco, samuraiConfig.WalkPath, samuraiConfig.RunThreshold, 1.0, true)
    Anim.blend_space_1d_add_sample(loco, samuraiConfig.RunPath, samuraiConfig.RunSampleSpeed, 1.0, true)
    self.LocomotionBlendSpace = loco

    local top = Anim.create_state_machine("Top")

    Anim.sm_add_state(top, "Locomotion", loco)
    Anim.sm_add_state(top, "Jump", Anim.create_sequence_player(samuraiConfig.JumpPath, samuraiConfig.JumpPlayRate, samuraiConfig.JumpLoop))

    Anim.sm_add_state(top, "Attack1", Anim.create_sequence_player(attackPaths[1], GetAttackPlayRate(samuraiConfig, 1), false))
    Anim.sm_add_state(top, "Attack2", Anim.create_sequence_player(attackPaths[2], GetAttackPlayRate(samuraiConfig, 2), false))
    Anim.sm_add_state(top, "PostDashAttack1", Anim.create_sequence_player(GetPostDashAttackPath(samuraiConfig, attackPaths, 1), GetPostDashAttackPlayRate(samuraiConfig, 1), false))
    Anim.sm_add_state(top, "PostDashAttack2", Anim.create_sequence_player(GetPostDashAttackPath(samuraiConfig, attackPaths, 2), GetPostDashAttackPlayRate(samuraiConfig, 2), false))
    Anim.sm_add_state(top, "Attack3", Anim.create_sequence_player(attackPaths[3], GetAttackPlayRate(samuraiConfig, 3), false))
    Anim.sm_add_state(top, "Attack4", Anim.create_sequence_player(attackPaths[4], GetAttackPlayRate(samuraiConfig, 4), false))
    Anim.sm_add_state(top, "Attack5", Anim.create_sequence_player(attackPaths[5], GetAttackPlayRate(samuraiConfig, 5), false))
    Anim.sm_add_state(top, "Attack6", Anim.create_sequence_player(attackPaths[6], GetAttackPlayRate(samuraiConfig, 6), false))
    Anim.sm_add_state(top, "Attack7", Anim.create_sequence_player(attackPaths[7], GetAttackPlayRate(samuraiConfig, 7), false))

    Anim.sm_add_state(top, "Dash", Anim.create_sequence_player(samuraiConfig.DashPath, samuraiConfig.DashPlayRate, false))
    Anim.sm_add_state(top, "DashCharging", Anim.create_sequence_player(samuraiConfig.DashChargingPath, samuraiConfig.DashChargingPlayRate, false))
    Anim.sm_add_state(top, "DashChargeAttack", Anim.create_sequence_player(samuraiConfig.DashChargeAttackPath, samuraiConfig.DashChargeAttackPlayRate, false))

    local hitReactPaths = samuraiConfig.HitReactPaths or {}
    Anim.sm_add_state(top, "HitFront", Anim.create_sequence_player(hitReactPaths.Front or attackPaths[1], samuraiConfig.HitReactPlayRate, false))
    Anim.sm_add_state(top, "HitLeft", Anim.create_sequence_player(hitReactPaths.Left or attackPaths[1], samuraiConfig.HitReactPlayRate, false))
    Anim.sm_add_state(top, "HitRight", Anim.create_sequence_player(hitReactPaths.Right or attackPaths[1], samuraiConfig.HitReactPlayRate, false))
    Anim.sm_add_state(top, "HitBack", Anim.create_sequence_player(hitReactPaths.Back or attackPaths[1], samuraiConfig.HitReactPlayRate, false))

    local function AddHitReactionTransitions(direction, stateName)
        Anim.sm_add_transition(top, "AnyState", stateName,
            function()
                if ShouldEnterHitReaction(self, direction) then
                    BeginHitReactionAnim(self, direction)
                    return true
                end
                return false
            end,
            samuraiConfig.HitReactBlendIn
        )

        Anim.sm_add_transition(top, stateName, "Locomotion",
            function()
                if self.PlayerContext == nil then return false end
                local elapsed = self.PlayerContext.Action.HitReactElapsed or 0.0
                if self.PlayerContext.Action.HitReactEnd
                    or elapsed >= (samuraiConfig.HitReactFallbackDuration or 0.45) then
                    EndHitReactionAnim(self)
                    return true
                end
                return false
            end,
            samuraiConfig.HitReactBlendOut
        )
    end

    AddHitReactionTransitions("Front", "HitFront")
    AddHitReactionTransitions("Left", "HitLeft")
    AddHitReactionTransitions("Right", "HitRight")
    AddHitReactionTransitions("Back", "HitBack")

    Anim.sm_add_transition(top, "AnyState", "DashCharging",
        function()
            if self.PlayerContext == nil then return false end
            if self.PlayerContext.Input.DashChargingPressed
                and not self.PlayerContext.Input.DashPressed
                and not self.PlayerContext.Action.DashActive
                and not self.PlayerContext.Action.DashChargingActive
                and not self.PlayerContext.Action.DashChargeAttackActive
                and not self.PlayerContext.Input.DashChargingReleased
                and not self.PlayerContext.Action.HitReactActive
                and (self.PlayerContext.Action.AttackIndex or 0) == 0
                and not Anim.is_owner_falling()
                and not self.PlayerContext.Action.IsUltimateRunning
                and self.PlayerContext.Action.IsUltimateCinematic ~= true then
                BeginDashCharging(self)
                return true
            end
            return false
        end,
        samuraiConfig.DashChargingBlendIn
    )

    Anim.sm_add_transition(top, "AnyState", "Dash",
        function()
            if self.PlayerContext == nil then return false end
            if self.PlayerContext.Input.DashPressed
                and not self.PlayerContext.Action.DashActive
                and not self.PlayerContext.Action.DashChargingActive
                and not self.PlayerContext.Action.DashChargeAttackActive
                and not self.PlayerContext.Action.HitReactActive
                and not Anim.is_owner_falling()
                and not self.PlayerContext.Action.IsUltimateRunning
                and self.PlayerContext.Action.IsUltimateCinematic ~= true then
                BeginDash(self)
                return true
            end
            return false
        end,
        samuraiConfig.DashBlendIn
    )

    Anim.sm_add_transition(top, "Dash", "Locomotion",
        function()
            if self.PlayerContext == nil then return false end
            if self.PlayerContext.Action.DashEnd
                and not self.PlayerContext.Input.DashChargingPressed
                and PlayerAction.ShouldChainDashToCharging(self.PlayerContext) ~= true then
                EndDash(self)
                return true
            end
            return false
        end,
        samuraiConfig.DashBlendOut
    )

    Anim.sm_add_transition(top, "Dash", "DashCharging",
        function()
            if self.PlayerContext == nil then return false end
            if (self.PlayerContext.Input.DashChargingPressed or PlayerAction.ShouldChainDashToCharging(self.PlayerContext) == true)
                and self.PlayerContext.Action.DashActive
                and not self.PlayerContext.Action.DashChargingActive
                and not self.PlayerContext.Action.DashChargeAttackActive
                and not self.PlayerContext.Input.DashChargingReleased
                and not self.PlayerContext.Action.HitReactActive
                and not Anim.is_owner_falling()
                and not self.PlayerContext.Action.IsUltimateRunning
                and self.PlayerContext.Action.IsUltimateCinematic ~= true then
                PlayerAction.ConsumeDashChargingInput(self.PlayerContext)
                EndDash(self, false)
                BeginDashCharging(self)
                return true
            end
            return false
        end,
        samuraiConfig.DashChargingBlendIn
    )

    Anim.sm_add_transition(top, "DashCharging", "DashChargeAttack",
        function()
            if self.PlayerContext == nil then return false end
            if self.PlayerContext.Input.DashChargingReleased then
                self.PlayerContext.Input.DashChargingReleased = false
                EndDashCharging(self, false)
                BeginDashChargeAttack(self)
                return true
            end
            return false
        end,
        samuraiConfig.DashChargingToAttackBlend
    )

    Anim.sm_add_transition(top, "DashChargeAttack", "Locomotion",
        function()
            if self.PlayerContext == nil then return false end
            if self.PlayerContext.Action.DashChargeAttackEnd or (self.PlayerContext.Action.DashChargeAttackElapsed or 0.0) >= (samuraiConfig.DashChargeAttackFallbackDuration) then
                EndDashChargeAttack(self)
                return true
            end
            return false
        end,
        samuraiConfig.DashChargeAttackBlendOut
    )

    Anim.sm_add_state(top, "UltimateAttack", Anim.create_sequence_player(samuraiConfig.UltimateAttackPath, samuraiConfig.UltimateAttackPlayRate, false))

    Anim.sm_add_transition(top, "AnyState", "UltimateAttack",
        function()
            if self.PlayerContext == nil then return false end
            if self.PlayerContext.Action.IsInUltimateMode == true
                and self.PlayerContext.Action.IsUltimateCinematic ~= true then
                BeginUltimateAttack(self)
                return true
            end
            return false
        end,
        samuraiConfig.UltimateAttackBlendIn
    )

    Anim.sm_add_transition(top, "UltimateAttack", "Locomotion",
        function()
            if self.PlayerContext == nil then return false end
            if self.PlayerContext.Action.IsInUltimateMode ~= true then
                ResetAttack(self)
                return true
            end
            return false
        end,
        samuraiConfig.UltimateAttackBlendOut
    )

    Anim.sm_add_transition(top, "Locomotion", "Jump",
        function()
            return Anim.is_owner_falling()
        end,
        samuraiConfig.JumpBlendIn
    )

    Anim.sm_add_transition(top, "Jump", "Locomotion",
        function()
            return not Anim.is_owner_falling()
        end,
        samuraiConfig.JumpBlendOut
    )

    Anim.sm_add_transition(top, "Locomotion", "PostDashAttack1",
        function()
            if self.PlayerContext == nil then return false end
            if self.PlayerContext.Input.AttackPressed
                and PlayerAction.ShouldStartPostDashAttackVariant(self.PlayerContext, 1)
                and self.PlayerContext.Action.HitReactActive ~= true
                and self.PlayerContext.Action.IsUltimateRunning ~= true
                and self.PlayerContext.Action.IsUltimateCinematic ~= true
                and self.PlayerContext.Action.IsInUltimateMode ~= true then
                BeginPostDashAttack(self, 1)
                return true
            end
            return false
        end,
        samuraiConfig.PostDashAttackBlendIn or samuraiConfig.AttackBlendIn
    )

    Anim.sm_add_transition(top, "Locomotion", "PostDashAttack2",
        function()
            if self.PlayerContext == nil then return false end
            if self.PlayerContext.Input.AttackPressed
                and PlayerAction.ShouldStartPostDashAttackVariant(self.PlayerContext, 2)
                and self.PlayerContext.Action.HitReactActive ~= true
                and self.PlayerContext.Action.IsUltimateRunning ~= true
                and self.PlayerContext.Action.IsUltimateCinematic ~= true
                and self.PlayerContext.Action.IsInUltimateMode ~= true then
                BeginPostDashAttack(self, 2)
                return true
            end
            return false
        end,
        samuraiConfig.PostDashAttackBlendIn or samuraiConfig.AttackBlendIn
    )

    Anim.sm_add_transition(top, "PostDashAttack1", "PostDashAttack2",
        function()
            if self.PlayerContext == nil then return false end
            if PlayerAction.ShouldChainPostDashAttack(self.PlayerContext)
                and PlayerAction.ShouldStartPostDashAttackVariant(self.PlayerContext, 2) then
                BeginPostDashAttack(self, 2)
                return true
            end
            return false
        end,
        samuraiConfig.PostDashAttackBlendIn or samuraiConfig.AttackBlendIn
    )

    Anim.sm_add_transition(top, "PostDashAttack2", "PostDashAttack1",
        function()
            if self.PlayerContext == nil then return false end
            if PlayerAction.ShouldChainPostDashAttack(self.PlayerContext)
                and PlayerAction.ShouldStartPostDashAttackVariant(self.PlayerContext, 1) then
                BeginPostDashAttack(self, 1)
                return true
            end
            return false
        end,
        samuraiConfig.PostDashAttackBlendIn or samuraiConfig.AttackBlendIn
    )

    Anim.sm_add_transition(top, "PostDashAttack1", "Locomotion",
        function()
            if self.PlayerContext == nil then return false end
            if self.PlayerContext.Action.AttackEnd then
                ResetAttack(self)
                return true
            end
            return false
        end,
        samuraiConfig.PostDashAttackBlendOut or samuraiConfig.AttackBlendOut
    )

    Anim.sm_add_transition(top, "PostDashAttack2", "Locomotion",
        function()
            if self.PlayerContext == nil then return false end
            if self.PlayerContext.Action.AttackEnd then
                ResetAttack(self)
                return true
            end
            return false
        end,
        samuraiConfig.PostDashAttackBlendOut or samuraiConfig.AttackBlendOut
    )

    Anim.sm_add_transition(top, "Locomotion", "Attack1",
        function()
            if self.PlayerContext == nil then return false end
            if self.PlayerContext.Input.AttackPressed
                and PlayerAction.CanStartPostDashAttack(self.PlayerContext) ~= true
                and self.PlayerContext.Action.HitReactActive ~= true
                and self.PlayerContext.Action.IsUltimateRunning ~= true
                and self.PlayerContext.Action.IsUltimateCinematic ~= true
                and self.PlayerContext.Action.IsInUltimateMode ~= true then
                BeginAttack(self, 1)
                return true
            end
            return false
        end,
        samuraiConfig.AttackBlendIn
    )

    Anim.sm_add_transition(top, "Attack1", "Attack2",
        function()
            if self.PlayerContext == nil then return false end
            if self.PlayerContext.Action.AttackEnd and self.PlayerContext.Action.ComboQueued then
                BeginAttack(self, 2)
                return true
            end
            return false
        end,
        samuraiConfig.AttackBlendIn
    )

    Anim.sm_add_transition(top, "Attack1", "Locomotion",
        function()
            if self.PlayerContext == nil then return false end
            if self.PlayerContext.Action.AttackEnd then
                ResetAttack(self)
                return true
            end
            return false
        end,
        samuraiConfig.AttackBlendOut
    )

    Anim.sm_add_transition(top, "Attack2", "Attack3",
        function()
            if self.PlayerContext == nil then return false end
            if self.PlayerContext.Action.AttackEnd and self.PlayerContext.Action.ComboQueued then
                BeginAttack(self, 3)
                return true
            end
            return false
        end,
        samuraiConfig.AttackBlendIn
    )

    Anim.sm_add_transition(top, "Attack2", "Locomotion",
        function()
            if self.PlayerContext == nil then return false end
            if self.PlayerContext.Action.AttackEnd then
                ResetAttack(self)
                return true
            end
            return false
        end,
        samuraiConfig.AttackBlendOut
    )

    Anim.sm_add_transition(top, "Attack3", "Attack4",
        function()
            if self.PlayerContext == nil then return false end
            if self.PlayerContext.Action.AttackEnd and self.PlayerContext.Action.ComboQueued then
                BeginAttack(self, 4)
                return true
            end
            return false
        end,
        samuraiConfig.AttackBlendIn
    )

    Anim.sm_add_transition(top, "Attack3", "Locomotion",
        function()
            if self.PlayerContext == nil then return false end
            if self.PlayerContext.Action.AttackEnd then
                ResetAttack(self)
                return true
            end
            return false
        end,
        samuraiConfig.AttackBlendOut
    )

    Anim.sm_add_transition(top, "Attack4", "Attack5",
        function()
            if self.PlayerContext == nil then return false end
            if self.PlayerContext.Action.AttackEnd and self.PlayerContext.Action.ComboQueued then
                BeginAttack(self, 5)
                return true
            end
            return false
        end,
        samuraiConfig.AttackBlendIn
    )

    Anim.sm_add_transition(top, "Attack4", "Locomotion",
        function()
            if self.PlayerContext == nil then return false end
            if self.PlayerContext.Action.AttackEnd then
                ResetAttack(self)
                return true
            end
            return false
        end,
        samuraiConfig.AttackBlendOut
    )

    Anim.sm_add_transition(top, "Attack5", "Attack6",
        function()
            if self.PlayerContext == nil then return false end
            if self.PlayerContext.Action.AttackEnd and self.PlayerContext.Action.ComboQueued then
                BeginAttack(self, 6)
                return true
            end
            return false
        end,
        samuraiConfig.AttackBlendIn
    )

    Anim.sm_add_transition(top, "Attack5", "Locomotion",
        function()
            if self.PlayerContext == nil then return false end
            if self.PlayerContext.Action.AttackEnd then
                ResetAttack(self)
                return true
            end
            return false
        end,
        samuraiConfig.AttackBlendOut
    )

    Anim.sm_add_transition(top, "Attack6", "Attack7",
        function()
            if self.PlayerContext == nil then return false end
            if self.PlayerContext.Action.AttackEnd and self.PlayerContext.Action.ComboQueued then
                BeginAttack(self, 7)
                return true
            end
            return false
        end,
        samuraiConfig.AttackBlendIn
    )

    Anim.sm_add_transition(top, "Attack6", "Locomotion",
        function()
            if self.PlayerContext == nil then return false end
            if self.PlayerContext.Action.AttackEnd then
                ResetAttack(self)
                return true
            end
            return false
        end,
        samuraiConfig.AttackBlendOut
    )

    Anim.sm_add_transition(top, "Attack7", "Locomotion",
        function()
            if self.PlayerContext == nil then return false end
            if self.PlayerContext.Action.AttackEnd then
                ResetAttack(self)
                return true
            end
            return false
        end,
        samuraiConfig.AttackBlendOut
    )

    Anim.sm_set_initial_state(top, "Locomotion")
    self.TopStateMachine = top

    local root = Anim.create_slot("DefaultSlot", top)
    Anim.set_root_node(root)
end

function update(self, dt)
    self.PlayerContext = CombatContext.GetPlayerByOwner(obj)
    local playerContext = self.PlayerContext

    if playerContext == nil then
        return
    end

    PlayerContext.Assert(playerContext, "PlayerAnimation.update")
    PlayerAction.UpdateActionInput(playerContext, dt)

    self.Speed = Anim.get_owner_speed()
    local samuraiConfig = playerContext.Config.Animation.Samurai
    local blendAlpha = math.min(dt * (samuraiConfig.LocomotionSpeedResponse), 1.0)
    self.BlendSpeed = self.BlendSpeed + (self.Speed - self.BlendSpeed) * blendAlpha
    Anim.blend_space_1d_set_input(self.LocomotionBlendSpace, self.BlendSpeed)

    if playerContext.Action.HitReactActive then
        PlayerAction.UpdateHitReaction(playerContext, dt)
        return
    end

    PlayerAction.UpdateStepForward(playerContext, dt)

    if playerContext.Action.DashActive then
        PlayerAction.UpdateDash(playerContext, dt)
    elseif playerContext.Action.DashChargingActive then
        PlayerAction.UpdateDashCharging(playerContext, dt)
    elseif playerContext.Action.DashChargeAttackActive then
        PlayerAction.UpdateDashChargeAttack(playerContext, dt)
    elseif playerContext.Action.AttackIndex == 0 then
        PlayerAction.ApplyMoveInput(playerContext)
    else
        if PlayerAction.UpdateAttackAssist(playerContext, dt) ~= true then
            local dir = PlayerAction.GetMoveInputWorldDirection(playerContext)
            if dir ~= nil then
                PlayerAction.SmoothFaceOwnerToDirection(playerContext, dir, dt)
            end
        end
    end
end

function on_combo_window_open(self)
    self.PlayerContext = CombatContext.GetPlayerByOwner(obj)
    local playerContext = self.PlayerContext
    if playerContext == nil then return end
    PlayerContext.Assert(playerContext, "PlayerAnimation.on_combo_window_open")
    playerContext.Action.ComboWindow = true
    PlayerAction.ConsumeBufferedAttackForCombo(playerContext)
end

function on_combo_window_close(self)
    self.PlayerContext = CombatContext.GetPlayerByOwner(obj)
    local playerContext = self.PlayerContext
    if playerContext == nil then return end
    PlayerContext.Assert(playerContext, "PlayerAnimation.on_combo_window_close")
    playerContext.Action.ComboWindow = false
end

function on_attack_end(self)
    self.PlayerContext = CombatContext.GetPlayerByOwner(obj)
    local playerContext = self.PlayerContext
    if playerContext == nil then return end
    PlayerContext.Assert(playerContext, "PlayerAnimation.on_attack_end")
    playerContext.Action.ComboWindow = false
    if playerContext.Action.HitReactActive then
        playerContext.Action.HitReactEnd = true
    elseif playerContext.Action.DashChargeAttackActive then
        playerContext.Action.DashChargeAttackEnd = true
    else
        playerContext.Action.AttackEnd = true
    end
end

---@param self table
---@param targetActor any
---@param hitboxComponent any
---@param targetComponent any
---@param hitResult any
---@param hitStopDuration number
---@param hitCount integer|nil
---@param hitInterval number|nil
---@param hitWindowSerial integer|nil
---@return nil
function on_attack_hit(self, targetActor, hitboxComponent, targetComponent, hitResult, hitStopDuration,
    hitCount, hitInterval, hitWindowSerial)
    self.PlayerContext = CombatContext.GetPlayerByOwner(obj)
    local playerContext = self.PlayerContext
    if playerContext == nil then return end
    PlayerContext.Assert(playerContext, "PlayerAnimation.on_attack_hit")

    local resolvedHitCount, resolvedHitInterval = ResolveAttackHitRepeat(playerContext, hitCount, hitInterval)

    -- Preserve the original stable behavior for the first hit: apply it immediately
    -- inside the notify callback. Only follow-up hits are deferred to the owner
    -- coroutine pool so damage/death/collision changes do not recurse inside the
    -- C++ overlap traversal.
    local baseAttackInstanceId = tostring(playerContext.Action.AttackInstanceId
        or playerContext.Action.DashChargeAttackInstanceId
        or playerContext.Action.UltimateAttackInstanceId
        or "PlayerAttack")
    local attackImpactGroupId = baseAttackInstanceId .. "_W" .. tostring(hitWindowSerial or "NoWindow")

    local firstHitResult = ApplyAttackHitOnce(playerContext, targetActor, hitboxComponent, targetComponent,
        hitResult, hitStopDuration, 1, resolvedHitCount, resolvedHitInterval, hitWindowSerial, attackImpactGroupId)
    LogAttackHitResult(targetActor, firstHitResult, 1, resolvedHitCount)

    if resolvedHitCount <= 1 or ShouldStopRepeatedAttackHit(firstHitResult) == true then
        return
    end

    local ownerKey = GetOwnerKey(playerContext.Owner)
    CoroutineManager.StartForOwner(ownerKey, function()
        for hitIndex = 2, resolvedHitCount do
            if resolvedHitInterval > 0.0 then
                Wait(resolvedHitInterval)
            else
                WaitFrame()
            end

            if IsValidActor(targetActor) ~= true then
                break
            end

            local repeatedHitResult = ApplyAttackHitOnce(playerContext, targetActor, hitboxComponent, targetComponent,
                hitResult, 0.0, hitIndex, resolvedHitCount, resolvedHitInterval, hitWindowSerial, attackImpactGroupId)
            LogAttackHitResult(targetActor, repeatedHitResult, hitIndex, resolvedHitCount)

            if ShouldStopRepeatedAttackHit(repeatedHitResult) == true then
                break
            end
        end
    end)
end

---@param self table
---@param hitWindowSerial integer|nil
---@return nil
function on_attack_hit_window_end(self, hitWindowSerial)
    self.PlayerContext = CombatContext.GetPlayerByOwner(obj)
    local playerContext = self.PlayerContext
    if playerContext == nil then return end
    PlayerContext.Assert(playerContext, "PlayerAnimation.on_attack_hit_window_end")

    PlayerEvents.EmitAttackImpactWindowClosed(playerContext, {
        HitWindowSerial = hitWindowSerial,
    })
end

function on_dash_vanish_begin(self)
    self.PlayerContext = CombatContext.GetPlayerByOwner(obj)
    local playerContext = self.PlayerContext
    if playerContext == nil then return end
    PlayerContext.Assert(playerContext, "PlayerAnimation.on_dash_vanish_begin")
    PlayerFeedback.BeginDashVanish(playerContext)
end

function on_dash_vanish_end(self)
    self.PlayerContext = CombatContext.GetPlayerByOwner(obj)
    local playerContext = self.PlayerContext
    if playerContext == nil then return end
    PlayerContext.Assert(playerContext, "PlayerAnimation.on_dash_vanish_end")
    PlayerFeedback.EndDashVanish(playerContext)
end

function on_trail_activate(self)
    self.PlayerContext = CombatContext.GetPlayerByOwner(obj)
    local playerContext = self.PlayerContext
    if playerContext == nil then return end
    PlayerContext.Assert(playerContext, "PlayerAnimation.on_trail_activate")
    PlayerFeedback.SetKatanaTrailActive(playerContext, true)
end

function on_trail_deactivate(self)
    self.PlayerContext = CombatContext.GetPlayerByOwner(obj)
    local playerContext = self.PlayerContext
    if playerContext == nil then return end
    PlayerContext.Assert(playerContext, "PlayerAnimation.on_trail_deactivate")
    PlayerFeedback.SetKatanaTrailActive(playerContext, false)
end

function on_spawn_flying_slash(self, args)
    self.PlayerContext = CombatContext.GetPlayerByOwner(obj)
    local playerContext = self.PlayerContext
    if playerContext == nil then return end
    PlayerContext.Assert(playerContext, "PlayerAnimation.on_spawn_flying_slash")
    PlayerAction.OnSpawnFlyingSlashNotify(playerContext, args)
end

function on_notify(self, name)
    self.PlayerContext = CombatContext.GetPlayerByOwner(obj)
    local playerContext = self.PlayerContext
    if playerContext == nil then return end
    PlayerContext.Assert(playerContext, "PlayerAnimation.on_notify")
    PlayerAction.OnAnimNotify(playerContext, name)
    print("[LuaAnim] notify: " .. name)

    if name == "ComboWindowOpen" then
        on_combo_window_open(self)
        return
    end

    if name == "ComboWindowClose" then
        on_combo_window_close(self)
        return
    end

    if name == "AttackEnd" then
        on_attack_end(self)
        return
    end

    if name == "HitReactEnd" or name == "HitEnd" then
        playerContext.Action.HitReactEnd = true
        return
    end

    if name == "DashVanishBegin" or name == "DashVanishStart" then
        on_dash_vanish_begin(self)
        return
    end

    if name == "DashVanishEnd" or name == "DashVanishStop" then
        on_dash_vanish_end(self)
        return
    end

    if name == "TrailActivate" or name == "TrailOn" then
        on_trail_activate(self)
        return
    end

    if name == "TrailDeactivate" or name == "TrailOff" then
        on_trail_deactivate(self)
        return
    end

    if name == "DashEnd" then
        playerContext.Action.DashEnd = true
        return
    end

    if name == "DashChargeAttackEnd" or name == "DashChargingAttackEnd" then
        playerContext.Action.DashChargeAttackEnd = true
        return
    end
end

function get_debug_snapshot_text(self)
    local animState = "None"
    if self ~= nil and self.TopStateMachine ~= nil and Anim.sm_get_current_state ~= nil then
        animState = Anim.sm_get_current_state(self.TopStateMachine) or "None"
    end

    local speed = 0.0
    local blendSpeed = 0.0
    if self ~= nil then
        speed = self.Speed or 0.0
        blendSpeed = self.BlendSpeed or 0.0
    end

    return string.format("AnimState: %s\nAnimSpeed: %.2f / blend %.2f",
        tostring(animState), speed, blendSpeed)
end
