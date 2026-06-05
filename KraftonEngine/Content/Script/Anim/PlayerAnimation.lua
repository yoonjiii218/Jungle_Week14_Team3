-- Samurai animation state script.
-- Player input, movement, and dash movement live in Script/PlayerAction.lua.

local PlayerAction = require("PlayerAction")
local CombatContext = require("CombatContext")
local PlayerConfig = require("PlayerConfig")
local PlayerFeedback = require("PlayerFeedback")

local DEFAULT_SAMURAI_CONFIG = PlayerConfig.Default.Animation.Samurai

local function GetPlayerCtx(self)
    local playerCtx = CombatContext.GetPlayerByOwner(obj)
    if playerCtx ~= nil then
        self.PlayerCtx = playerCtx
        return playerCtx
    end

    return self.PlayerCtx
end

local function PushPlayerEvent(self, event)
    PlayerAction.PushEvent(GetPlayerCtx(self), event)
end

local function GetSamuraiConfig(self)
    local playerCtx = self.PlayerCtx or GetPlayerCtx(self)
    if playerCtx ~= nil
        and playerCtx.Config ~= nil
        and playerCtx.Config.Animation ~= nil
        and playerCtx.Config.Animation.Samurai ~= nil then
        return playerCtx.Config.Animation.Samurai
    end

    return DEFAULT_SAMURAI_CONFIG
end

local function PrepareActionCtx(self)
    self.PlayerCtx = GetPlayerCtx(self)
    return self
end

local function IsUltimateRunning(self)
    return PlayerAction.IsUltimateRunning(GetPlayerCtx(self))
end

local function IsInUltimateMode(self)
    return PlayerAction.IsInUltimateMode(GetPlayerCtx(self))
end

local function ResetAttack(self, unlockMovement)
    local attackIndex = self.AttackIndex

    self.AttackIndex = 0
    self.ComboWindow = false
    self.ComboQueued = false
    self.AttackEnd = false

    if unlockMovement ~= false then
        PlayerAction.SetMovementInputEnabled(self, true)
    end

    if attackIndex ~= nil and attackIndex > 0 then
        PushPlayerEvent(self, { Type = "AttackEnd", AttackIndex = attackIndex })
    end
end

local function BeginAttack(self, index)
    self.AttackIndex = index
    self.ComboWindow = false
    self.ComboQueued = false
    self.AttackEnd = false
    PlayerAction.StopMovementImmediately(self)
    PlayerAction.StepAttackForward(self, index)
    PushPlayerEvent(self, { Type = "AttackStart", AttackIndex = index })
end

local function BeginDash(self)
    ResetAttack(self, false)
    self.DashPressed = false
    PlayerAction.BeginDash(PrepareActionCtx(self))
end

local function EndDash(self)
    PlayerAction.EndDash(PrepareActionCtx(self))
end

local function BeginDashCharging(self)
    ResetAttack(self, false)
    self.DashChargingPressed = false
    self.DashChargingReleased = false
    PlayerAction.BeginDashCharging(PrepareActionCtx(self))
end

local function EndDashCharging(self, unlockMovement)
    PlayerAction.EndDashCharging(PrepareActionCtx(self), unlockMovement)
end

local function BeginDashChargeAttack(self)
    ResetAttack(self, false)
    self.DashChargeAttackEnd = false
    PlayerAction.BeginDashChargeAttack(PrepareActionCtx(self))
end

local function EndDashChargeAttack(self)
    PlayerAction.EndDashChargeAttack(PrepareActionCtx(self))
end

function init(self)
    self.Speed = 0.0
    self.BlendSpeed = 0.0

    self.AttackPressed = false
    self.DashPressed = false
    self.DashChargingPressed = false
    self.DashChargingReleased = false

    self.DashActive = false
    self.DashElapsed = 0.0
    self.DashEnd = false

    self.DashChargingActive = false
    self.DashChargingElapsed = 0.0
    self.DashChargingEnd = false

    self.DashChargeAttackActive = false
    self.DashChargeAttackElapsed = 0.0
    self.DashChargeAttackEnd = false

    -- Compatibility fields for notifies/assets that still use the old DashSlash name.
    self.DashSlashPressed = false
    self.DashSlashActive = false
    self.DashSlashElapsed = 0.0
    self.DashSlashEnd = false

    PlayerAction.Init(self, obj)
    self.PlayerCtx = GetPlayerCtx(self)
    ResetAttack(self)

    local samuraiConfig = GetSamuraiConfig(self)
    local attackPaths = samuraiConfig.AttackPaths or DEFAULT_SAMURAI_CONFIG.AttackPaths

    local loco = Anim.create_blend_space_1d(0.0)
    Anim.blend_space_1d_add_sample(loco, samuraiConfig.IdlePath or DEFAULT_SAMURAI_CONFIG.IdlePath, 0.0, 1.0, true)
    Anim.blend_space_1d_add_sample(loco, samuraiConfig.WalkPath or DEFAULT_SAMURAI_CONFIG.WalkPath, samuraiConfig.RunThreshold or DEFAULT_SAMURAI_CONFIG.RunThreshold, 1.0, true)
    Anim.blend_space_1d_add_sample(loco, samuraiConfig.RunPath or DEFAULT_SAMURAI_CONFIG.RunPath, samuraiConfig.RunSampleSpeed or DEFAULT_SAMURAI_CONFIG.RunSampleSpeed, 1.0, true)
    self.LocomotionBlendSpace = loco

    local top = Anim.create_state_machine("Top")

    Anim.sm_add_state(top, "Locomotion", loco)
    Anim.sm_add_state(top, "Jump", Anim.create_sequence_player(samuraiConfig.JumpPath or DEFAULT_SAMURAI_CONFIG.JumpPath, samuraiConfig.JumpPlayRate or DEFAULT_SAMURAI_CONFIG.JumpPlayRate, samuraiConfig.JumpLoop or DEFAULT_SAMURAI_CONFIG.JumpLoop))

    Anim.sm_add_state(top, "Attack1", Anim.create_sequence_player(attackPaths[1] or DEFAULT_SAMURAI_CONFIG.AttackPaths[1], samuraiConfig.AttackPlayRate or DEFAULT_SAMURAI_CONFIG.AttackPlayRate, false))
    Anim.sm_add_state(top, "Attack2", Anim.create_sequence_player(attackPaths[2] or DEFAULT_SAMURAI_CONFIG.AttackPaths[2], samuraiConfig.AttackPlayRate or DEFAULT_SAMURAI_CONFIG.AttackPlayRate, false))
    Anim.sm_add_state(top, "Attack3", Anim.create_sequence_player(attackPaths[3] or DEFAULT_SAMURAI_CONFIG.AttackPaths[3], samuraiConfig.AttackPlayRate or DEFAULT_SAMURAI_CONFIG.AttackPlayRate, false))
    Anim.sm_add_state(top, "Attack4", Anim.create_sequence_player(attackPaths[4] or DEFAULT_SAMURAI_CONFIG.AttackPaths[4], samuraiConfig.AttackPlayRate or DEFAULT_SAMURAI_CONFIG.AttackPlayRate, false))
    Anim.sm_add_state(top, "Attack5", Anim.create_sequence_player(attackPaths[5] or DEFAULT_SAMURAI_CONFIG.AttackPaths[5], samuraiConfig.AttackPlayRate or DEFAULT_SAMURAI_CONFIG.AttackPlayRate, false))

    Anim.sm_add_state(top, "Dash", Anim.create_sequence_player(samuraiConfig.DashPath or DEFAULT_SAMURAI_CONFIG.DashPath, samuraiConfig.DashPlayRate or DEFAULT_SAMURAI_CONFIG.DashPlayRate, false))
    Anim.sm_add_state(top, "DashCharging", Anim.create_sequence_player(samuraiConfig.DashChargingPath or DEFAULT_SAMURAI_CONFIG.DashChargingPath, samuraiConfig.DashChargingPlayRate or DEFAULT_SAMURAI_CONFIG.DashChargingPlayRate, false))
    Anim.sm_add_state(top, "DashChargeAttack", Anim.create_sequence_player(samuraiConfig.DashChargeAttackPath or DEFAULT_SAMURAI_CONFIG.DashChargeAttackPath, samuraiConfig.DashChargeAttackPlayRate or DEFAULT_SAMURAI_CONFIG.DashChargeAttackPlayRate, false))

    Anim.sm_add_transition(top, "AnyState", "DashCharging",
        function()
            if self.DashChargingPressed
                and not self.DashPressed
                and not self.DashActive
                and not self.DashChargingActive
                and not self.DashChargeAttackActive
                and not Anim.is_owner_falling()
                and not IsUltimateRunning(self) then
                BeginDashCharging(self)
                return true
            end
            return false
        end,
        samuraiConfig.DashChargingBlendIn or DEFAULT_SAMURAI_CONFIG.DashChargingBlendIn
    )

    Anim.sm_add_transition(top, "AnyState", "Dash",
        function()
            if self.DashPressed
                and not self.DashActive
                and not self.DashChargingActive
                and not self.DashChargeAttackActive
                and not Anim.is_owner_falling()
                and not IsUltimateRunning(self) then
                BeginDash(self)
                return true
            end
            return false
        end,
        samuraiConfig.DashBlendIn or DEFAULT_SAMURAI_CONFIG.DashBlendIn
    )

    Anim.sm_add_transition(top, "Dash", "Locomotion",
        function()
            if self.DashEnd and not self.DashChargingPressed then
                EndDash(self)
                return true
            end
            return false
        end,
        samuraiConfig.DashBlendOut or DEFAULT_SAMURAI_CONFIG.DashBlendOut
    )

    Anim.sm_add_transition(top, "Dash", "DashCharging",
        function()
            if self.DashChargingPressed
                and not self.DashChargingActive
                and not self.DashChargeAttackActive
                and not Anim.is_owner_falling()
                and not IsUltimateRunning(self) then
                self.DashChargingPressed = false
                EndDash(self)
                BeginDashCharging(self)
                return true
            end
            return false
        end,
        samuraiConfig.DashChargingBlendIn or DEFAULT_SAMURAI_CONFIG.DashChargingBlendIn
    )

    Anim.sm_add_transition(top, "DashCharging", "DashChargeAttack",
        function()
            if self.DashChargingReleased then
                self.DashChargingReleased = false
                EndDashCharging(self, false)
                BeginDashChargeAttack(self)
                return true
            end
            return false
        end,
        samuraiConfig.DashChargingToAttackBlend or DEFAULT_SAMURAI_CONFIG.DashChargingToAttackBlend
    )

    Anim.sm_add_transition(top, "DashChargeAttack", "Locomotion",
        function()
            if self.DashChargeAttackEnd or (self.DashChargeAttackElapsed or 0.0) >= (samuraiConfig.DashChargeAttackFallbackDuration or DEFAULT_SAMURAI_CONFIG.DashChargeAttackFallbackDuration) then
                EndDashChargeAttack(self)
                return true
            end
            return false
        end,
        samuraiConfig.DashChargeAttackBlendOut or DEFAULT_SAMURAI_CONFIG.DashChargeAttackBlendOut
    )

    Anim.sm_add_state(top, "UltimateAttack", Anim.create_sequence_player(samuraiConfig.UltimateAttackPath or DEFAULT_SAMURAI_CONFIG.UltimateAttackPath, samuraiConfig.UltimateAttackPlayRate or DEFAULT_SAMURAI_CONFIG.UltimateAttackPlayRate, false))

    Anim.sm_add_transition(top, "AnyState", "UltimateAttack",
        function()
            if IsInUltimateMode(self) == true then
                PlayerAction.CancelDashActions(PrepareActionCtx(self), false)
                return true
            end
            return false
        end,
        samuraiConfig.UltimateAttackBlendIn or DEFAULT_SAMURAI_CONFIG.UltimateAttackBlendIn
    )

    Anim.sm_add_transition(top, "UltimateAttack", "Locomotion",
        function()
            return IsInUltimateMode(self) ~= true
        end,
        samuraiConfig.UltimateAttackBlendOut or DEFAULT_SAMURAI_CONFIG.UltimateAttackBlendOut
    )

    Anim.sm_add_transition(top, "Locomotion", "Jump",
        function()
            return Anim.is_owner_falling()
        end,
        samuraiConfig.JumpBlendIn or DEFAULT_SAMURAI_CONFIG.JumpBlendIn
    )

    Anim.sm_add_transition(top, "Jump", "Locomotion",
        function()
            return not Anim.is_owner_falling()
        end,
        samuraiConfig.JumpBlendOut or DEFAULT_SAMURAI_CONFIG.JumpBlendOut
    )

    Anim.sm_add_transition(top, "Locomotion", "Attack1",
        function()
            if self.AttackPressed then
                BeginAttack(self, 1)
                return true
            end
            return false
        end,
        samuraiConfig.AttackBlendIn or DEFAULT_SAMURAI_CONFIG.AttackBlendIn
    )

    Anim.sm_add_transition(top, "Attack1", "Attack2",
        function()
            if self.AttackEnd and self.ComboQueued then
                BeginAttack(self, 2)
                return true
            end
            return false
        end,
        samuraiConfig.AttackBlendIn or DEFAULT_SAMURAI_CONFIG.AttackBlendIn
    )

    Anim.sm_add_transition(top, "Attack1", "Locomotion",
        function()
            if self.AttackEnd then
                ResetAttack(self)
                return true
            end
            return false
        end,
        samuraiConfig.AttackBlendOut or DEFAULT_SAMURAI_CONFIG.AttackBlendOut
    )

    Anim.sm_add_transition(top, "Attack2", "Attack3",
        function()
            if self.AttackEnd and self.ComboQueued then
                BeginAttack(self, 3)
                return true
            end
            return false
        end,
        samuraiConfig.AttackBlendIn or DEFAULT_SAMURAI_CONFIG.AttackBlendIn
    )

    Anim.sm_add_transition(top, "Attack2", "Locomotion",
        function()
            if self.AttackEnd then
                ResetAttack(self)
                return true
            end
            return false
        end,
        samuraiConfig.AttackBlendOut or DEFAULT_SAMURAI_CONFIG.AttackBlendOut
    )

    Anim.sm_add_transition(top, "Attack3", "Attack4",
        function()
            if self.AttackEnd and self.ComboQueued then
                BeginAttack(self, 4)
                return true
            end
            return false
        end,
        samuraiConfig.AttackBlendIn or DEFAULT_SAMURAI_CONFIG.AttackBlendIn
    )

    Anim.sm_add_transition(top, "Attack3", "Locomotion",
        function()
            if self.AttackEnd then
                ResetAttack(self)
                return true
            end
            return false
        end,
        samuraiConfig.AttackBlendOut or DEFAULT_SAMURAI_CONFIG.AttackBlendOut
    )

    Anim.sm_add_transition(top, "Attack4", "Attack5",
        function()
            if self.AttackEnd and self.ComboQueued then
                BeginAttack(self, 5)
                return true
            end
            return false
        end,
        samuraiConfig.AttackBlendIn or DEFAULT_SAMURAI_CONFIG.AttackBlendIn
    )

    Anim.sm_add_transition(top, "Attack4", "Locomotion",
        function()
            if self.AttackEnd then
                ResetAttack(self)
                return true
            end
            return false
        end,
        samuraiConfig.AttackBlendOut or DEFAULT_SAMURAI_CONFIG.AttackBlendOut
    )

    Anim.sm_add_transition(top, "Attack5", "Locomotion",
        function()
            if self.AttackEnd then
                ResetAttack(self)
                return true
            end
            return false
        end,
        samuraiConfig.AttackBlendOut or DEFAULT_SAMURAI_CONFIG.AttackBlendOut
    )

    Anim.sm_set_initial_state(top, "Locomotion")

    local root = Anim.create_slot("DefaultSlot", top)
    Anim.set_root_node(root)
end

function update(self, dt)
    self.PlayerCtx = GetPlayerCtx(self)
    PlayerAction.UpdateActionInput(self, dt)

    self.Speed = Anim.get_owner_speed()
    local samuraiConfig = GetSamuraiConfig(self)
    local blendAlpha = math.min(dt * (samuraiConfig.LocomotionSpeedResponse or DEFAULT_SAMURAI_CONFIG.LocomotionSpeedResponse), 1.0)
    self.BlendSpeed = self.BlendSpeed + (self.Speed - self.BlendSpeed) * blendAlpha
    Anim.blend_space_1d_set_input(self.LocomotionBlendSpace, self.BlendSpeed)

    if self.AttackPressed and self.AttackIndex > 0 and self.ComboWindow then
        self.ComboQueued = true
    end

    PlayerAction.UpdateStepForward(self, dt)

    if self.DashActive then
        PlayerAction.UpdateDash(self, dt)
    elseif self.DashChargingActive then
        PlayerAction.UpdateDashCharging(self, dt)
    elseif self.DashChargeAttackActive then
        PlayerAction.UpdateDashChargeAttack(self, dt)
    elseif self.AttackIndex == 0 then
        PlayerAction.ApplyMoveInput(self)
    else
        local dir = PlayerAction.GetMoveInputWorldDirection(self)
        if dir ~= nil then
            PlayerAction.SmoothFaceOwnerToDirection(self, dir, dt)
        end
    end
end

function on_combo_window_open(self)
    self.ComboWindow = true
end

function on_combo_window_close(self)
    self.ComboWindow = false
end

function on_attack_end(self)
    self.ComboWindow = false
    if self.DashChargeAttackActive then
        self.DashChargeAttackEnd = true
    else
        self.AttackEnd = true
    end
end

function on_trail_activate(self)
    PlayerFeedback.SetKatanaTrailActive(GetPlayerCtx(self), true)
end

function on_trail_deactivate(self)
    PlayerFeedback.SetKatanaTrailActive(GetPlayerCtx(self), false)
end

function on_notify(self, name)
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

    if name == "TrailActivate" or name == "TrailOn" then
        on_trail_activate(self)
        return
    end

    if name == "TrailDeactivate" or name == "TrailOff" then
        on_trail_deactivate(self)
        return
    end

    if name == "DashEnd" or name == "DashSlashEnd" then
        self.DashEnd = true
        self.DashSlashEnd = true
        return
    end

    if name == "DashChargeAttackEnd" or name == "DashChargingAttackEnd" then
        self.DashChargeAttackEnd = true
        return
    end
end
