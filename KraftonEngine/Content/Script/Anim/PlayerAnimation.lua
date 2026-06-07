-- Anim/PlayerAnimation.lua
-- Owns animation graph state only. Gameplay state lives in PlayerContext.
-- Notify callbacks are adapted into PlayerAction / CombatContext calls.

local PlayerAction = require("Player/PlayerAction")
local CombatContext = require("Combat/CombatContext")
local HitTypes = require("Combat/HitTypes")
local PlayerConfig = require("Config/PlayerConfig")
local PlayerContext = require("Player/PlayerContext")
local PlayerEvents = require("Player/PlayerEvents")
local PlayerFeedback = require("Player/PlayerFeedback")

local DEFAULT_SAMURAI_CONFIG = PlayerConfig.Default.Animation.Samurai

local ANIM_ACTION_FIELDS = {
    "AttackPressed", "DashPressed", "DashChargingPressed", "DashChargingReleased",
    "DashActive", "DashElapsed", "DashEnd",
    "DashSlashPressed", "DashSlashActive", "DashSlashElapsed", "DashSlashEnd",
    "DashChargingActive", "DashChargingElapsed", "DashChargingEnd",
    "DashChargeAttackActive", "DashChargeAttackElapsed", "DashChargeAttackEnd",
    "AttackIndex", "AttackInstanceId", "DashChargeAttackInstanceId",
    "ComboWindow", "ComboQueued", "AttackEnd",
}

local function EnsurePlayerCtx(self)
    local player = CombatContext.GetPlayerByOwner(obj)
    if player == nil then
        -- AnimInstance init can run before PlayerCharacter.BeginPlay in editor/PIE reload paths.
        -- Create a typed context instead of passing AnimInstance self into PlayerAction.
        player = PlayerContext.Create(obj, this)
        CombatContext.RegisterPlayer(player)
        PlayerAction.Init(player)
    end

    self.PlayerCtx = player
    return player
end

local function InstallAnimStateProxy(self, player)
    if self.__PlayerAnimProxyInstalled == true then
        return
    end

    for _, key in ipairs(ANIM_ACTION_FIELDS) do
        rawset(self, key, nil)
    end

    local previous = getmetatable(self) or {}
    local previousIndex = previous.__index
    local previousNewIndex = previous.__newindex
    local legacyMap = PlayerContext.GetLegacyFieldMap()

    previous.__index = function(t, key)
        local map = legacyMap[key]
        if map ~= nil then
            return player[map[1]][map[2]]
        end
        if type(previousIndex) == "function" then
            return previousIndex(t, key)
        elseif type(previousIndex) == "table" then
            return previousIndex[key]
        end
        return nil
    end

    previous.__newindex = function(t, key, value)
        local map = legacyMap[key]
        if map ~= nil then
            player[map[1]][map[2]] = value
            return
        end
        if type(previousNewIndex) == "function" then
            previousNewIndex(t, key, value)
            return
        end
        rawset(t, key, value)
    end

    setmetatable(self, previous)
    self.__PlayerAnimProxyInstalled = true
end

local function GetPlayerCtx(self)
    local player = EnsurePlayerCtx(self)
    InstallAnimStateProxy(self, player)
    return player
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

local function GetAttackPlayRate(samuraiConfig, attackIndex)
    local playRates = samuraiConfig.AttackPlayRates
    if playRates ~= nil and playRates[attackIndex] ~= nil then
        return playRates[attackIndex]
    end

    local defaultPlayRates = DEFAULT_SAMURAI_CONFIG.AttackPlayRates
    if defaultPlayRates ~= nil and defaultPlayRates[attackIndex] ~= nil then
        return defaultPlayRates[attackIndex]
    end

    return samuraiConfig.AttackPlayRate or DEFAULT_SAMURAI_CONFIG.AttackPlayRate
end

local function PrepareActionPlayer(self)
    return GetPlayerCtx(self)
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
        PlayerAction.SetMovementInputEnabled(GetPlayerCtx(self), true)
    end

    PlayerAction.EndAttackAssist(GetPlayerCtx(self))

    if attackIndex ~= nil and attackIndex > 0 then
        PlayerEvents.EmitAttackEnded(GetPlayerCtx(self), { AttackIndex = attackIndex })
    end
end

local function BeginAttack(self, index)
    self.AttackIndex = index
    self.AttackInstanceId = "PlayerAttack" .. tostring(index) .. "_" .. tostring(World.GetGameTime())
    self.ComboWindow = false
    self.ComboQueued = false
    self.AttackEnd = false
    PlayerAction.StopMovementImmediately(GetPlayerCtx(self))
    PlayerAction.BeginAttackAssist(GetPlayerCtx(self), index)
    PlayerAction.StepAttackForward(GetPlayerCtx(self), index)
    PlayerEvents.EmitAttackStarted(GetPlayerCtx(self), { AttackIndex = index })
end

local function BeginDash(self)
    ResetAttack(self, false)
    self.DashPressed = false
    PlayerAction.BeginDash(PrepareActionPlayer(self))
end

local function EndDash(self)
    PlayerAction.EndDash(PrepareActionPlayer(self))
end

local function BeginDashCharging(self)
    ResetAttack(self, false)
    self.DashChargingPressed = false
    self.DashChargingReleased = false
    PlayerAction.BeginDashCharging(PrepareActionPlayer(self))
end

local function EndDashCharging(self, unlockMovement)
    PlayerAction.EndDashCharging(PrepareActionPlayer(self), unlockMovement)
end

local function BeginDashChargeAttack(self)
    ResetAttack(self, false)
    self.DashChargeAttackEnd = false
    self.DashChargeAttackInstanceId = "PlayerDashChargeAttack_" .. tostring(World.GetGameTime())
    PlayerAction.BeginDashChargeAttack(PrepareActionPlayer(self))
end

local function EndDashChargeAttack(self)
    PlayerAction.EndDashChargeAttack(PrepareActionPlayer(self))
end

function init(self)
    self.Speed = 0.0
    self.BlendSpeed = 0.0

    local player = GetPlayerCtx(self)
    PlayerAction.Init(player)
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

    Anim.sm_add_state(top, "Attack1", Anim.create_sequence_player(attackPaths[1] or DEFAULT_SAMURAI_CONFIG.AttackPaths[1], GetAttackPlayRate(samuraiConfig, 1), false))
    Anim.sm_add_state(top, "Attack2", Anim.create_sequence_player(attackPaths[2] or DEFAULT_SAMURAI_CONFIG.AttackPaths[2], GetAttackPlayRate(samuraiConfig, 2), false))
    Anim.sm_add_state(top, "Attack3", Anim.create_sequence_player(attackPaths[3] or DEFAULT_SAMURAI_CONFIG.AttackPaths[3], GetAttackPlayRate(samuraiConfig, 3), false))
    Anim.sm_add_state(top, "Attack4", Anim.create_sequence_player(attackPaths[4] or DEFAULT_SAMURAI_CONFIG.AttackPaths[4], GetAttackPlayRate(samuraiConfig, 4), false))
    Anim.sm_add_state(top, "Attack5", Anim.create_sequence_player(attackPaths[5] or DEFAULT_SAMURAI_CONFIG.AttackPaths[5], GetAttackPlayRate(samuraiConfig, 5), false))
    Anim.sm_add_state(top, "Attack6", Anim.create_sequence_player(attackPaths[6] or DEFAULT_SAMURAI_CONFIG.AttackPaths[6], GetAttackPlayRate(samuraiConfig, 6), false))
    Anim.sm_add_state(top, "Attack7", Anim.create_sequence_player(attackPaths[7] or DEFAULT_SAMURAI_CONFIG.AttackPaths[7], GetAttackPlayRate(samuraiConfig, 7), false))

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
                PlayerAction.CancelDashActions(PrepareActionPlayer(self), false)
                return true
            end
            return false
        end,
        samuraiConfig.UltimateAttackBlendIn or DEFAULT_SAMURAI_CONFIG.UltimateAttackBlendIn
    )

    Anim.sm_add_transition(top, "UltimateAttack", "Locomotion",
        function()
            if IsInUltimateMode(self) ~= true then
                ResetAttack(self)
                return true
            end
            return false
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

    Anim.sm_add_transition(top, "Attack5", "Attack6",
        function()
            if self.AttackEnd and self.ComboQueued then
                BeginAttack(self, 6)
                return true
            end
            return false
        end,
        samuraiConfig.AttackBlendIn or DEFAULT_SAMURAI_CONFIG.AttackBlendIn
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

    Anim.sm_add_transition(top, "Attack6", "Attack7",
        function()
            if self.AttackEnd and self.ComboQueued then
                BeginAttack(self, 7)
                return true
            end
            return false
        end,
        samuraiConfig.AttackBlendIn or DEFAULT_SAMURAI_CONFIG.AttackBlendIn
    )

    Anim.sm_add_transition(top, "Attack6", "Locomotion",
        function()
            if self.AttackEnd then
                ResetAttack(self)
                return true
            end
            return false
        end,
        samuraiConfig.AttackBlendOut or DEFAULT_SAMURAI_CONFIG.AttackBlendOut
    )

    Anim.sm_add_transition(top, "Attack7", "Locomotion",
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
    local player = GetPlayerCtx(self)
    PlayerAction.UpdateActionInput(player, dt)

    self.Speed = Anim.get_owner_speed()
    local samuraiConfig = GetSamuraiConfig(self)
    local blendAlpha = math.min(dt * (samuraiConfig.LocomotionSpeedResponse or DEFAULT_SAMURAI_CONFIG.LocomotionSpeedResponse), 1.0)
    self.BlendSpeed = self.BlendSpeed + (self.Speed - self.BlendSpeed) * blendAlpha
    Anim.blend_space_1d_set_input(self.LocomotionBlendSpace, self.BlendSpeed)

    if self.AttackPressed and self.AttackIndex > 0 and self.ComboWindow then
        self.ComboQueued = true
    end

    PlayerAction.UpdateStepForward(player, dt)

    if self.DashActive then
        PlayerAction.UpdateDash(player, dt)
    elseif self.DashChargingActive then
        PlayerAction.UpdateDashCharging(player, dt)
    elseif self.DashChargeAttackActive then
        PlayerAction.UpdateDashChargeAttack(player, dt)
    elseif self.AttackIndex == 0 then
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

---@param self table
---@param targetActor any
---@param hitboxComponent any
---@param targetComponent any
---@param hitResult any
---@param hitStopDuration number
---@return nil
function on_attack_hit(self, targetActor, hitboxComponent, targetComponent, hitResult, hitStopDuration)
    local player = GetPlayerCtx(self)
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
    PlayerFeedback.SetKatanaTrailActive(GetPlayerCtx(self), true)
end

function on_trail_deactivate(self)
    PlayerFeedback.SetKatanaTrailActive(GetPlayerCtx(self), false)
end

function on_notify(self, name)
    local player = GetPlayerCtx(self)
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
