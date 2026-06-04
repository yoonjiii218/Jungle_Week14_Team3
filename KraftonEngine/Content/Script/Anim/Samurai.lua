-- Samurai animation state script.
-- Player input, movement, and dash movement live in Script/PlayerCharacter.lua.

local PlayerCharacter = require("PlayerCharacter")
local PlayerAction = require("PlayerAction")
local CombatContext = require("CombatContext")

local IDLE_PATH = "Content/Animation/Samurai_UE4/SamuraiIdle.uasset"
local WALK_PATH = "Content/Animation/Samurai_UE4/SamuraiWalk.uasset"
local RUN_PATH  = "Content/Animation/Samurai_UE4/SamuraiSprint.uasset"
local JUMP_PATH = "Content/Animation/Samurai_UE4/SamuraiJump.uasset"

local ATTACK1_PATH = "Content/Animation/Samurai_UE4/SamuraiAttack1.uasset"
local ATTACK2_PATH = "Content/Animation/Samurai_UE4/SamuraiAttack2.uasset"
local ATTACK3_PATH = "Content/Animation/Samurai_UE4/SamuraiAttack3.uasset"
local ATTACK4_PATH = "Content/Animation/Samurai_UE4/SamuraiAttack4.uasset"
local ATTACK5_PATH = "Content/Animation/Samurai_UE4/SamuraiAttack5.uasset"

local DASH_PATH = "Content/Animation/Samurai_UE4/SamuraiAttackHeavy1_Start.uasset"
local DASH_CHARGING_PATH = "Content/Animation/Samurai_UE4/SamuraiAttackHeavy1_Start.uasset"
local DASH_CHARGE_ATTACK_PATH = "Content/Animation/Samurai_UE4/SamuraiAttack1.uasset"
local ULTIMATE_ATTACK_PATH = "Content/Animation/Samurai_UE4/SamuraiAttackUltimate.uasset"

local WALK_THRESHOLD = 0.1
local RUN_THRESHOLD  = 8.0
local RUN_SAMPLE_SPEED = 10.0
local LOCOMOTION_SPEED_RESPONSE = 12.0
local JUMP_LOOP = false

local ATTACK_BLEND_IN  = 0.08
local ATTACK_BLEND_OUT = 0.15

local DASH_BLEND_IN  = 0.05
local DASH_BLEND_OUT = 0.12
local DASH_CHARGING_BLEND_IN = 0.05
local DASH_CHARGING_TO_ATTACK_BLEND = 0.03
local DASH_CHARGE_ATTACK_BLEND_OUT = 0.12
local DASH_CHARGE_ATTACK_FALLBACK_DURATION = 0.65

local ULTIMATE_ATTACK_BLEND_IN  = 0.05
local ULTIMATE_ATTACK_BLEND_OUT = 0.12

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

local function ResetAttack(self, unlockMovement)
    local attackIndex = self.AttackIndex

    self.AttackIndex = 0
    self.ComboWindow = false
    self.ComboQueued = false
    self.AttackEnd = false

    if unlockMovement ~= false then
        PlayerCharacter.SetMovementInputEnabled(self, true)
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
    PlayerCharacter.StopMovementImmediately(self)
    PlayerCharacter.StepAttackForward(self)
    PushPlayerEvent(self, { Type = "AttackStart", AttackIndex = index })
end

local function BeginDash(self)
    ResetAttack(self, false)
    self.DashPressed = false
    PlayerCharacter.BeginDash(self)
end

local function EndDash(self)
    PlayerCharacter.EndDash(self)
end

local function BeginDashCharging(self)
    ResetAttack(self, false)
    self.DashChargingPressed = false
    self.DashChargingReleased = false
    PlayerCharacter.BeginDashCharging(self)
end

local function EndDashCharging(self, unlockMovement)
    PlayerCharacter.EndDashCharging(self, unlockMovement)
end

local function BeginDashChargeAttack(self)
    ResetAttack(self, false)
    self.DashChargeAttackEnd = false
    PlayerCharacter.BeginDashChargeAttack(self)
end

local function EndDashChargeAttack(self)
    PlayerCharacter.EndDashChargeAttack(self)
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

    PlayerCharacter.Initialize(self, obj)
    self.PlayerCtx = GetPlayerCtx(self)
    ResetAttack(self)

    local loco = Anim.create_blend_space_1d(0.0)
    Anim.blend_space_1d_add_sample(loco, IDLE_PATH, 0.0, 1.0, true)
    Anim.blend_space_1d_add_sample(loco, WALK_PATH, RUN_THRESHOLD, 1.0, true)
    Anim.blend_space_1d_add_sample(loco, RUN_PATH, RUN_SAMPLE_SPEED, 1.0, true)
    self.LocomotionBlendSpace = loco

    local top = Anim.create_state_machine("Top")

    Anim.sm_add_state(top, "Locomotion", loco)
    Anim.sm_add_state(top, "Jump", Anim.create_sequence_player(JUMP_PATH, 1.0, JUMP_LOOP))

    Anim.sm_add_state(top, "Attack1", Anim.create_sequence_player(ATTACK1_PATH, 1.5, false))
    Anim.sm_add_state(top, "Attack2", Anim.create_sequence_player(ATTACK2_PATH, 1.5, false))
    Anim.sm_add_state(top, "Attack3", Anim.create_sequence_player(ATTACK3_PATH, 1.5, false))
    Anim.sm_add_state(top, "Attack4", Anim.create_sequence_player(ATTACK4_PATH, 1.5, false))
    Anim.sm_add_state(top, "Attack5", Anim.create_sequence_player(ATTACK5_PATH, 1.5, false))

    Anim.sm_add_state(top, "Dash", Anim.create_sequence_player(DASH_PATH, 3.0, false))
    Anim.sm_add_state(top, "DashCharging", Anim.create_sequence_player(DASH_CHARGING_PATH, 1.0, false))
    Anim.sm_add_state(top, "DashChargeAttack", Anim.create_sequence_player(DASH_CHARGE_ATTACK_PATH, 1.4, false))

    Anim.sm_add_transition(top, "AnyState", "DashCharging",
        function()
            if self.DashChargingPressed
                and not self.DashActive
                and not self.DashChargingActive
                and not self.DashChargeAttackActive
                and not Anim.is_owner_falling()
                and not PlayerCharacter.IsUltimateRunning(self) then
                BeginDashCharging(self)
                return true
            end
            return false
        end,
        DASH_CHARGING_BLEND_IN
    )

    Anim.sm_add_transition(top, "AnyState", "Dash",
        function()
            if self.DashPressed
                and not self.DashActive
                and not self.DashChargingActive
                and not self.DashChargeAttackActive
                and not Anim.is_owner_falling()
                and not PlayerCharacter.IsUltimateRunning(self) then
                BeginDash(self)
                return true
            end
            return false
        end,
        DASH_BLEND_IN
    )

    Anim.sm_add_transition(top, "Dash", "Locomotion",
        function()
            if self.DashEnd then
                EndDash(self)
                return true
            end
            return false
        end,
        DASH_BLEND_OUT
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
        DASH_CHARGING_TO_ATTACK_BLEND
    )

    Anim.sm_add_transition(top, "DashChargeAttack", "Locomotion",
        function()
            if self.DashChargeAttackEnd or (self.DashChargeAttackElapsed or 0.0) >= DASH_CHARGE_ATTACK_FALLBACK_DURATION then
                EndDashChargeAttack(self)
                return true
            end
            return false
        end,
        DASH_CHARGE_ATTACK_BLEND_OUT
    )

    Anim.sm_add_state(top, "UltimateAttack", Anim.create_sequence_player(ULTIMATE_ATTACK_PATH, 1.2, false))

    Anim.sm_add_transition(top, "AnyState", "UltimateAttack",
        function()
            return PlayerCharacter.IsInUltimateMode(self) == true
        end,
        ULTIMATE_ATTACK_BLEND_IN
    )

    Anim.sm_add_transition(top, "UltimateAttack", "Locomotion",
        function()
            return PlayerCharacter.IsInUltimateMode(self) ~= true
        end,
        ULTIMATE_ATTACK_BLEND_OUT
    )

    Anim.sm_add_transition(top, "Locomotion", "Jump",
        function()
            return Anim.is_owner_falling()
        end,
        0.1
    )

    Anim.sm_add_transition(top, "Jump", "Locomotion",
        function()
            return not Anim.is_owner_falling()
        end,
        0.2
    )

    Anim.sm_add_transition(top, "Locomotion", "Attack1",
        function()
            if self.AttackPressed then
                BeginAttack(self, 1)
                return true
            end
            return false
        end,
        ATTACK_BLEND_IN
    )

    Anim.sm_add_transition(top, "Attack1", "Attack2",
        function()
            if self.AttackEnd and self.ComboQueued then
                BeginAttack(self, 2)
                return true
            end
            return false
        end,
        ATTACK_BLEND_IN
    )

    Anim.sm_add_transition(top, "Attack1", "Locomotion",
        function()
            if self.AttackEnd then
                ResetAttack(self)
                return true
            end
            return false
        end,
        ATTACK_BLEND_OUT
    )

    Anim.sm_add_transition(top, "Attack2", "Attack3",
        function()
            if self.AttackEnd and self.ComboQueued then
                BeginAttack(self, 3)
                return true
            end
            return false
        end,
        ATTACK_BLEND_IN
    )

    Anim.sm_add_transition(top, "Attack2", "Locomotion",
        function()
            if self.AttackEnd then
                ResetAttack(self)
                return true
            end
            return false
        end,
        ATTACK_BLEND_OUT
    )

    Anim.sm_add_transition(top, "Attack3", "Attack4",
        function()
            if self.AttackEnd and self.ComboQueued then
                BeginAttack(self, 4)
                return true
            end
            return false
        end,
        ATTACK_BLEND_IN
    )

    Anim.sm_add_transition(top, "Attack3", "Locomotion",
        function()
            if self.AttackEnd then
                ResetAttack(self)
                return true
            end
            return false
        end,
        ATTACK_BLEND_OUT
    )

    Anim.sm_add_transition(top, "Attack4", "Attack5",
        function()
            if self.AttackEnd and self.ComboQueued then
                BeginAttack(self, 5)
                return true
            end
            return false
        end,
        ATTACK_BLEND_IN
    )

    Anim.sm_add_transition(top, "Attack4", "Locomotion",
        function()
            if self.AttackEnd then
                ResetAttack(self)
                return true
            end
            return false
        end,
        ATTACK_BLEND_OUT
    )

    Anim.sm_add_transition(top, "Attack5", "Locomotion",
        function()
            if self.AttackEnd then
                ResetAttack(self)
                return true
            end
            return false
        end,
        ATTACK_BLEND_OUT
    )

    Anim.sm_set_initial_state(top, "Locomotion")

    local root = Anim.create_slot("DefaultSlot", top)
    Anim.set_root_node(root)
end

function update(self, dt)
    self.PlayerCtx = GetPlayerCtx(self)
    PlayerAction.UpdateActionInput(self, dt)

    self.Speed = Anim.get_owner_speed()
    local blendAlpha = math.min(dt * LOCOMOTION_SPEED_RESPONSE, 1.0)
    self.BlendSpeed = self.BlendSpeed + (self.Speed - self.BlendSpeed) * blendAlpha
    Anim.blend_space_1d_set_input(self.LocomotionBlendSpace, self.BlendSpeed)

    if self.AttackPressed and self.AttackIndex > 0 and self.ComboWindow then
        self.ComboQueued = true
    end

    if self.DashActive then
        PlayerCharacter.UpdateDash(self, dt)
    elseif self.DashChargingActive then
        PlayerCharacter.UpdateDashCharging(self, dt)
    elseif self.DashChargeAttackActive then
        PlayerCharacter.UpdateDashChargeAttack(self, dt)
    elseif self.AttackIndex == 0 then
        PlayerCharacter.ApplyMoveInput(self)
    else
        local dir = PlayerCharacter.GetMoveInputWorldDirection(self)
        if dir ~= nil then
            PlayerCharacter.SmoothFaceOwnerToDirection(self, dir, dt)
        end
    end
end

function on_notify(self, name)
    print("[LuaAnim] notify: " .. name)

    if name == "ComboWindowOpen" then
        self.ComboWindow = true
        return
    end

    if name == "ComboWindowClose" then
        self.ComboWindow = false
        return
    end

    if name == "AttackEnd" then
        self.ComboWindow = false
        if self.DashChargeAttackActive then
            self.DashChargeAttackEnd = true
        else
            self.AttackEnd = true
        end
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
