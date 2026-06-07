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

local function GetAttackPlayRate(samuraiConfig, attackIndex)
    return samuraiConfig.AttackPlayRates[attackIndex] or samuraiConfig.AttackPlayRate
end

local function ResetAttack(self, unlockMovement)
    local playerContext = self.PlayerContext
    PlayerContext.Assert(playerContext, "PlayerAnimation.ResetAttack")
    local actionState = playerContext.Action
    local attackIndex = actionState.AttackIndex

    actionState.AttackIndex = 0
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
    actionState.AttackInstanceId = "PlayerAttack" .. tostring(index) .. "_" .. tostring(World.GetGameTime())
    actionState.ComboWindow = false
    actionState.ComboQueued = false
    actionState.AttackEnd = false
    PlayerAction.StopMovementImmediately(playerContext)
    PlayerAction.BeginAttackAssist(playerContext, index)
    PlayerAction.StepAttackForward(playerContext, index)
    PlayerEvents.EmitAttackStarted(playerContext, { AttackIndex = index })
end

local function BeginDash(self)
    ResetAttack(self, false)
    local playerContext = self.PlayerContext
    PlayerContext.Assert(playerContext, "PlayerAnimation.BeginDash")
    playerContext.Input.DashPressed = false
    PlayerAction.BeginDash(playerContext)
end

local function EndDash(self)
    local playerContext = self.PlayerContext
    PlayerContext.Assert(playerContext, "PlayerAnimation.EndDash")
    PlayerAction.EndDash(playerContext)
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

function init(self)
    self.Speed = 0.0
    self.BlendSpeed = 0.0

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
    Anim.sm_add_state(top, "Attack3", Anim.create_sequence_player(attackPaths[3], GetAttackPlayRate(samuraiConfig, 3), false))
    Anim.sm_add_state(top, "Attack4", Anim.create_sequence_player(attackPaths[4], GetAttackPlayRate(samuraiConfig, 4), false))
    Anim.sm_add_state(top, "Attack5", Anim.create_sequence_player(attackPaths[5], GetAttackPlayRate(samuraiConfig, 5), false))
    Anim.sm_add_state(top, "Attack6", Anim.create_sequence_player(attackPaths[6], GetAttackPlayRate(samuraiConfig, 6), false))
    Anim.sm_add_state(top, "Attack7", Anim.create_sequence_player(attackPaths[7], GetAttackPlayRate(samuraiConfig, 7), false))

    Anim.sm_add_state(top, "Dash", Anim.create_sequence_player(samuraiConfig.DashPath, samuraiConfig.DashPlayRate, false))
    Anim.sm_add_state(top, "DashCharging", Anim.create_sequence_player(samuraiConfig.DashChargingPath, samuraiConfig.DashChargingPlayRate, false))
    Anim.sm_add_state(top, "DashChargeAttack", Anim.create_sequence_player(samuraiConfig.DashChargeAttackPath, samuraiConfig.DashChargeAttackPlayRate, false))

    Anim.sm_add_transition(top, "AnyState", "DashCharging",
        function()
            if self.PlayerContext == nil then return false end
            if self.PlayerContext.Input.DashChargingPressed
                and not self.PlayerContext.Input.DashPressed
                and not self.PlayerContext.Action.DashActive
                and not self.PlayerContext.Action.DashChargingActive
                and not self.PlayerContext.Action.DashChargeAttackActive
                and not Anim.is_owner_falling()
                and not self.PlayerContext.Action.IsUltimateRunning then
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
                and not Anim.is_owner_falling()
                and not self.PlayerContext.Action.IsUltimateRunning then
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
            if self.PlayerContext.Action.DashEnd and not self.PlayerContext.Input.DashChargingPressed then
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
            if self.PlayerContext.Input.DashChargingPressed
                and not self.PlayerContext.Action.DashChargingActive
                and not self.PlayerContext.Action.DashChargeAttackActive
                and not Anim.is_owner_falling()
                and not self.PlayerContext.Action.IsUltimateRunning then
                self.PlayerContext.Input.DashChargingPressed = false
                EndDash(self)
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
            if self.PlayerContext.Action.IsInUltimateMode == true then
                PlayerAction.CancelDashActions(self.PlayerContext, false)
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

    Anim.sm_add_transition(top, "Locomotion", "Attack1",
        function()
            if self.PlayerContext == nil then return false end
            if self.PlayerContext.Input.AttackPressed then
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

    local root = Anim.create_slot("DefaultSlot", top)
    Anim.set_root_node(root)
end

function update(self, dt)
    self.PlayerContext = CombatContext.GetPlayerByOwner(obj)
    local player = self.PlayerContext
    if player == nil then
        return
    end
    PlayerContext.Assert(player, "PlayerAnimation.update")
    PlayerAction.UpdateActionInput(player, dt)

    self.Speed = Anim.get_owner_speed()
    local samuraiConfig = player.Config.Animation.Samurai
    local blendAlpha = math.min(dt * (samuraiConfig.LocomotionSpeedResponse), 1.0)
    self.BlendSpeed = self.BlendSpeed + (self.Speed - self.BlendSpeed) * blendAlpha
    Anim.blend_space_1d_set_input(self.LocomotionBlendSpace, self.BlendSpeed)

    if self.PlayerContext.Input.AttackPressed and self.PlayerContext.Action.AttackIndex > 0 and self.PlayerContext.Action.ComboWindow then
        self.PlayerContext.Action.ComboQueued = true
    end

    PlayerAction.UpdateStepForward(player, dt)

    if self.PlayerContext.Action.DashActive then
        PlayerAction.UpdateDash(player, dt)
    elseif self.PlayerContext.Action.DashChargingActive then
        PlayerAction.UpdateDashCharging(player, dt)
    elseif self.PlayerContext.Action.DashChargeAttackActive then
        PlayerAction.UpdateDashChargeAttack(player, dt)
    elseif self.PlayerContext.Action.AttackIndex == 0 then
        PlayerAction.ApplyMoveInput(player)
    else
        if PlayerAction.UpdateAttackAssist(player, dt) ~= true then
            local dir = PlayerAction.GetMoveInputWorldDirection(player)
            if dir ~= nil then
                PlayerAction.SmoothFaceOwnerToDirection(player, dir, dt)
            end
        end
    end
end

function on_combo_window_open(self)
    self.PlayerContext = CombatContext.GetPlayerByOwner(obj)
    PlayerContext.Assert(self.PlayerContext, "PlayerAnimation.on_combo_window_open")
    self.PlayerContext.Action.ComboWindow = true
end

function on_combo_window_close(self)
    self.PlayerContext = CombatContext.GetPlayerByOwner(obj)
    PlayerContext.Assert(self.PlayerContext, "PlayerAnimation.on_combo_window_close")
    self.PlayerContext.Action.ComboWindow = false
end

function on_attack_end(self)
    self.PlayerContext = CombatContext.GetPlayerByOwner(obj)
    PlayerContext.Assert(self.PlayerContext, "PlayerAnimation.on_attack_end")
    self.PlayerContext.Action.ComboWindow = false
    if self.PlayerContext.Action.DashChargeAttackActive then
        self.PlayerContext.Action.DashChargeAttackEnd = true
    else
        self.PlayerContext.Action.AttackEnd = true
    end
end

---@param self table
---@param targetActor any
---@param hitboxComponent any
---@param targetComponent any
---@param hitResult any
---@param hitStopDuration number
---@return nil
function on_attack_hit(self, targetActor, hitboxComponent, targetComponent, hitResult, hitStopDuration)
    self.PlayerContext = CombatContext.GetPlayerByOwner(obj)
    local player = self.PlayerContext
    PlayerContext.Assert(player, "PlayerAnimation.on_attack_hit")
    local hitRequest = HitTypes.CreatePlayerAttackFromState({
        Player = player,
        TargetActor = targetActor,
        HitboxComponent = hitboxComponent,
        TargetComponent = targetComponent,
        HitResult = hitResult,
        HitStopDuration = hitStopDuration,
    })

    local hitResultInfo = CombatContext.ApplyHit(hitRequest)

    if hitResultInfo.Applied == true then
        print("on attack hit " .. targetActor:GetName() .. " damage=" .. tostring(hitResultInfo.Damage))
    else
        print("on attack hit ignored " .. targetActor:GetName() .. " reason=" .. tostring(hitResultInfo.Reason))
    end
end

function on_trail_activate(self)
    self.PlayerContext = CombatContext.GetPlayerByOwner(obj)
    PlayerContext.Assert(self.PlayerContext, "PlayerAnimation.on_trail_activate")
    PlayerFeedback.SetKatanaTrailActive(self.PlayerContext, true)
end

function on_trail_deactivate(self)
    self.PlayerContext = CombatContext.GetPlayerByOwner(obj)
    PlayerContext.Assert(self.PlayerContext, "PlayerAnimation.on_trail_deactivate")
    PlayerFeedback.SetKatanaTrailActive(self.PlayerContext, false)
end

function on_notify(self, name)
    self.PlayerContext = CombatContext.GetPlayerByOwner(obj)
    local player = self.PlayerContext
    PlayerContext.Assert(player, "PlayerAnimation.on_notify")
    PlayerAction.OnAnimNotify(player, name)
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

    if name == "DashEnd" then
        self.PlayerContext.Action.DashEnd = true
        return
    end

    if name == "DashChargeAttackEnd" or name == "DashChargingAttackEnd" then
        self.PlayerContext.Action.DashChargeAttackEnd = true
        return
    end
end
