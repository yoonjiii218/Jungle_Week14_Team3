-- Player/PlayerAction.lua
-- PlayerAction owns player.Action state transitions.
-- Do not pass AnimInstance self as player.

local PlayerAction = {}

local PlayerConfig = require("Config/PlayerConfig")
local PlayerTargeting = require("Player/PlayerTargeting")
local PlayerContext = require("Player/PlayerContext")
local PlayerEvents = require("Player/PlayerEvents")

local function GetConfig(player)
    if player ~= nil and player.Config ~= nil then
        return player.Config
    end

    return nil
end

local function GetInputConfig(ctx)
    local config = GetConfig(ctx)
    if config ~= nil and config.Input ~= nil then
        return config.Input
    end

    return PlayerConfig.Default.Input
end

local function GetActionConfig(ctx)
    local config = GetConfig(ctx)
    if config ~= nil and config.Action ~= nil then
        return config.Action
    end

    return PlayerConfig.Default.Action
end

local semanticInputValidated = false

local function RequireSemanticInputApi()
    if semanticInputValidated then
        return
    end

    if Input == nil then
        error("[PlayerAction] Input table is missing")
    end

    local required = {
        "IsActionDown",
        "WasActionStarted",
        "WasActionCompleted",
        "GetAxis2D",
    }

    for _, name in ipairs(required) do
        if Input[name] == nil then
            error("[PlayerAction] Missing semantic input API: Input." .. name)
        end
    end

    semanticInputValidated = true
end

local function ResolveActionName(ctx, actionName)
    local inputConfig = GetInputConfig(ctx)
    local fieldName = actionName .. "Action"
    return inputConfig[fieldName] or PlayerConfig.Default.Input[fieldName] or actionName
end

local function ResolveAxisName(ctx, axisName)
    local inputConfig = GetInputConfig(ctx)
    local fieldName = axisName .. "Axis"
    return inputConfig[fieldName] or PlayerConfig.Default.Input[fieldName] or axisName
end

local function ActionDown(ctx, actionName)
    RequireSemanticInputApi()
    return Input.IsActionDown(ResolveActionName(ctx, actionName)) == true
end

local function ActionStarted(ctx, actionName)
    RequireSemanticInputApi()
    return Input.WasActionStarted(ResolveActionName(ctx, actionName)) == true
end

local function ActionCompleted(ctx, actionName)
    RequireSemanticInputApi()
    return Input.WasActionCompleted(ResolveActionName(ctx, actionName)) == true
end

local function Axis2D(ctx, axisName)
    RequireSemanticInputApi()
    local axis = Input.GetAxis2D(ResolveAxisName(ctx, axisName))
    if axis == nil then
        error("[PlayerAction] Input.GetAxis2D returned nil")
    end
    return axis
end

local function GetOwner(ctx)
    if ctx ~= nil and ctx.Owner ~= nil then
        return ctx.Owner
    end

    return obj
end

local function SetMovementInputEnabled(ctx, enabled)
    if ctx.MovementComp ~= nil then
        Reflection.Call(ctx.MovementComp, "SetMovementInputEnabled", enabled)
    end
end

local function StopMovementImmediately(ctx)
    if ctx.MovementComp ~= nil then
        Reflection.Call(ctx.MovementComp, "StopMovementImmediately")
    end
end

local function SetOrientRotationToMovement(ctx, enabled)
    if ctx.MovementComp ~= nil then
        Reflection.SetProperty(ctx.MovementComp, "bOrientRotationToMovement", enabled)
    end
end

local function ResetDashInput(ctx)
    ctx.DashHoldTime = 0.0
    ctx.DashChargingConsumedInput = false

    ctx.DashPressed = false
    ctx.DashChargingPressed = false
    ctx.DashChargingReleased = false
end

---@param player PlayerContext
---@return nil
-- =========================================================
-- Public API
-- =========================================================

function PlayerAction.Init(player)
    local ctx = PlayerContext.Assert(player, "PlayerAction.Init")
    RequireSemanticInputApi()

    ctx.Owner = ctx.Owner
    ctx.LastMoveInputDirection = nil
    ctx.DashPrevOrientRotationToMovement = nil
    ctx.DashMoveDirection = nil
    ctx.PendingActionEvents = ctx.PendingActionEvents or {}
    ctx.AttackDown = false
    ctx.AttackPressed = false
    ctx.AttackHoldTime = 0.0
    ctx.StepForwardActive = false
    ctx.StepForwardElapsed = 0.0
    ctx.StepForwardDuration = 0.0
    ctx.StepForwardDistance = 0.0
    ctx.StepForwardAppliedDistance = 0.0
    ctx.StepForwardDirection = nil

    ctx.TargetAssistMode = nil
    ctx.TargetAssistTarget = nil
    ctx.TargetAssistDirection = nil
    ctx.TargetAssistDistance = nil
    ctx.TargetAssistLockedDirection = nil
    ctx.TargetAssistEndTime = 0.0
    ctx.TargetAssistKeepUntil = 0.0

    ResetDashInput(ctx)

    ctx.DashActive = false
    ctx.DashElapsed = 0.0
    ctx.DashEnd = false

    ctx.DashChargingActive = false
    ctx.DashChargingElapsed = 0.0
    ctx.DashChargingEnd = false

    ctx.DashChargeAttackActive = false
    ctx.DashChargeAttackElapsed = 0.0
    ctx.DashChargeAttackEnd = false

    -- Old names are cleared as well so stale values do not survive hot reload.
    ctx.DashSlashPressed = false
    ctx.DashSlashActive = false
    ctx.DashSlashElapsed = 0.0
    ctx.DashSlashEnd = false
    ctx.DashSlashPrevOrientRotationToMovement = nil
    ctx.DashSlashMoveDirection = nil

    ctx.MovementComp = nil
    if ctx.Owner ~= nil then
        Reflection.SetProperty(ctx.Owner, "bUseControllerRotationYaw", false)

        if ctx.Owner.GetCharacterMovement ~= nil then
            ctx.MovementComp = ctx.Owner:GetCharacterMovement()
        end
        if ctx.MovementComp == nil and ctx.Owner.GetFloatingPawnMovement ~= nil then
            ctx.MovementComp = ctx.Owner:GetFloatingPawnMovement()
        end
    end
end

---@param player PlayerContext
---@param event PlayerEvent
---@return nil
function PlayerAction.PushEvent(player, event)
    local ctx = PlayerContext.Assert(player, "PlayerAction.PushEvent")
    if event == nil then
        return
    end

    PlayerEvents.Push(ctx, event)
end

---@param player PlayerContext
---@return nil
function PlayerAction.SetMovementInputEnabled(player, enabled)
    local ctx = PlayerContext.Assert(player, "PlayerAction.SetMovementInputEnabled")
    SetMovementInputEnabled(ctx, enabled)
end

---@param player PlayerContext
---@return nil
function PlayerAction.StopMovementImmediately(player)
    local ctx = PlayerContext.Assert(player, "PlayerAction.StopMovementImmediately")
    StopMovementImmediately(ctx)
end

local function GetAttackStepForwardDistance(actionConfig, attackIndex)
    if actionConfig.AttackStepForwardDistances ~= nil and attackIndex ~= nil then
        local distance = actionConfig.AttackStepForwardDistances[attackIndex]
        if distance ~= nil then
            return distance
        end
    end

    return actionConfig.AttackStepForwardDistance or PlayerConfig.Default.Action.AttackStepForwardDistance
end

local function GetAttackStepForwardDuration(actionConfig, attackIndex)
    if actionConfig.AttackStepForwardDurations ~= nil and attackIndex ~= nil then
        local duration = actionConfig.AttackStepForwardDurations[attackIndex]
        if duration ~= nil then
            return duration
        end
    end

    return actionConfig.AttackStepForwardDuration or PlayerConfig.Default.Action.AttackStepForwardDuration
end

local function BeginStepForward(ctx, distance, duration, direction)
    local owner = GetOwner(ctx)
    if owner == nil then
        return
    end

    local forward = direction or PlayerAction.GetOwnerForward2D(ctx)
    if forward == nil then
        return
    end

    forward.Z = 0.0
    if forward:Length() <= 0.001 then
        return
    end
    forward = forward:Normalized()

    if distance == nil or distance == 0.0 then
        return
    end

    if duration == nil or duration <= 0.0 then
        Reflection.Call(owner, "AddActorWorldOffset", forward * distance)
        return
    end

    ctx.StepForwardActive = true
    ctx.StepForwardElapsed = 0.0
    ctx.StepForwardDuration = duration
    ctx.StepForwardDistance = distance
    ctx.StepForwardAppliedDistance = 0.0
    ctx.StepForwardDirection = forward
end

---@param player PlayerContext
---@return nil
function PlayerAction.StepAttackForward(player, attackIndex)
    local ctx = PlayerContext.Assert(player, "PlayerAction.StepAttackForward")
    local actionConfig = GetActionConfig(ctx)
    BeginStepForward(
        ctx,
        GetAttackStepForwardDistance(actionConfig, attackIndex),
        GetAttackStepForwardDuration(actionConfig, attackIndex)
    )
end

---@param player PlayerContext
---@return nil
function PlayerAction.StepDashChargeAttackForward(player)
    local ctx = PlayerContext.Assert(player, "PlayerAction.StepDashChargeAttackForward")
    local actionConfig = GetActionConfig(ctx)
    BeginStepForward(
        ctx,
        actionConfig.DashChargeAttackStepForwardDistance or PlayerConfig.Default.Action.DashChargeAttackStepForwardDistance,
        actionConfig.DashChargeAttackStepForwardDuration or PlayerConfig.Default.Action.DashChargeAttackStepForwardDuration,
        PlayerTargeting.GetAssistDirection(ctx)
    )
end

---@param player PlayerContext
---@return nil
function PlayerAction.UpdateStepForward(player, dt)
    local ctx = PlayerContext.Assert(player, "PlayerAction.UpdateStepForward")
    if ctx == nil or ctx.StepForwardActive ~= true then
        return
    end

    local owner = GetOwner(ctx)
    local dir = ctx.StepForwardDirection
    if owner == nil or dir == nil then
        ctx.StepForwardActive = false
        return
    end

    local duration = ctx.StepForwardDuration or 0.0
    if duration <= 0.0 then
        ctx.StepForwardActive = false
        return
    end

    ctx.StepForwardElapsed = (ctx.StepForwardElapsed or 0.0) + (dt or 0.0)

    local alpha = ctx.StepForwardElapsed / duration
    if alpha > 1.0 then
        alpha = 1.0
    end

    local targetDistance = (ctx.StepForwardDistance or 0.0) * alpha
    local deltaDistance = targetDistance - (ctx.StepForwardAppliedDistance or 0.0)

    if math.abs(deltaDistance) > 0.001 then
        Reflection.Call(owner, "AddActorWorldOffset", dir * deltaDistance)
        ctx.StepForwardAppliedDistance = targetDistance
    end

    if alpha >= 1.0 then
        ctx.StepForwardActive = false
        ctx.StepForwardDirection = nil
    end
end

---@param player PlayerContext
---@return any
function PlayerAction.GetMoveInputWorldDirection(player)
    local ctx = PlayerContext.Assert(player, "PlayerAction.GetMoveInputWorldDirection")
    local owner = GetOwner(ctx)
    if owner == nil then
        return nil
    end

    local moveForward = 0.0
    local moveRight = 0.0

    local moveAxis = Axis2D(ctx, "Move")
    moveRight = moveAxis.X or 0.0
    moveForward = moveAxis.Y or 0.0

    if math.abs(moveForward) < 0.001 and math.abs(moveRight) < 0.001 then
        return nil
    end

    local forward = nil
    local right = nil
    local controlRot = Reflection.Call(owner, "GetControlRotation")

    if controlRot ~= nil then
        local yawRad = controlRot.Z * math.pi / 180.0
        forward = Vector(math.cos(yawRad), math.sin(yawRad), 0.0)
        right = Vector(-math.sin(yawRad), math.cos(yawRad), 0.0)
    else
        forward = Reflection.Call(owner, "GetActorForward")
        right = Reflection.Call(owner, "GetActorRight")

        if forward == nil or right == nil then
            return nil
        end

        forward.Z = 0.0
        right.Z = 0.0
    end

    local dir = forward * moveForward + right * moveRight
    dir.Z = 0.0

    if dir:Length() <= 0.001 then
        return nil
    end

    return dir:Normalized()
end

---@param player PlayerContext
---@return any
function PlayerAction.GetOwnerForward2D(player)
    local ctx = PlayerContext.Assert(player, "PlayerAction.GetOwnerForward2D")
    local owner = GetOwner(ctx)
    if owner == nil then
        return nil
    end

    local dir = Reflection.Call(owner, "GetActorForward")
    if dir == nil then
        return nil
    end

    dir.Z = 0.0

    if dir:Length() <= 0.001 then
        return nil
    end

    return dir:Normalized()
end

---@param player PlayerContext
---@return any
function PlayerAction.ResolveDashDirection(player)
    local ctx = PlayerContext.Assert(player, "PlayerAction.ResolveDashDirection")
    local dir = PlayerAction.GetMoveInputWorldDirection(ctx)

    if dir ~= nil then
        return dir
    end

    if ctx.LastMoveInputDirection ~= nil then
        return ctx.LastMoveInputDirection
    end

    return PlayerAction.GetOwnerForward2D(ctx)
end

---@param player PlayerContext
---@return nil
function PlayerAction.FaceOwnerToDirection(player, dir)
    local ctx = PlayerContext.Assert(player, "PlayerAction.FaceOwnerToDirection")
    local owner = GetOwner(ctx)
    if owner == nil or dir == nil then
        return
    end

    local targetYaw = math.atan2(dir.Y, dir.X) * 180.0 / math.pi
    Reflection.Call(owner, "SetActorRotation", Vector(0.0, 0.0, targetYaw))
end

---@param player PlayerContext
---@return nil
function PlayerAction.SmoothFaceOwnerToDirection(player, dir, dt, turnSpeed)
    local ctx = PlayerContext.Assert(player, "PlayerAction.SmoothFaceOwnerToDirection")
    local owner = GetOwner(ctx)
    if owner == nil or dir == nil or dt == nil then
        return
    end

    local currentRot = Reflection.Call(owner, "GetActorRotation")
    if currentRot == nil then
        PlayerAction.FaceOwnerToDirection(ctx, dir)
        return
    end

    local targetYaw = math.atan2(dir.Y, dir.X) * 180.0 / math.pi
    local deltaYaw = (targetYaw - currentRot.Z + 180.0) % 360.0 - 180.0
    local actionConfig = GetActionConfig(ctx)
    local alpha = dt * (turnSpeed or actionConfig.AttackTurnSpeed or PlayerConfig.Default.Action.AttackTurnSpeed)
    if alpha > 1.0 then
        alpha = 1.0
    end
    local nextYaw = currentRot.Z + deltaYaw * alpha

    Reflection.Call(owner, "SetActorRotation", Vector(currentRot.X, currentRot.Y, nextYaw))
end

---@param player PlayerContext
---@return nil
function PlayerAction.BeginAttackAssist(player, attackIndex)
    local ctx = PlayerContext.Assert(player, "PlayerAction.BeginAttackAssist")
    PlayerTargeting.BeginAssist(ctx, "Attack")
end

---@param player PlayerContext
---@return boolean
function PlayerAction.UpdateAttackAssist(player, dt)
    local ctx = PlayerContext.Assert(player, "PlayerAction.UpdateAttackAssist")
    if PlayerTargeting.IsAssistTurnActive(ctx) ~= true then
        return false
    end

    local dir = PlayerTargeting.GetAssistDirection(ctx)
    if dir == nil then
        return false
    end

    PlayerAction.SmoothFaceOwnerToDirection(ctx, dir, dt, PlayerTargeting.GetTurnSpeed(ctx))
    return true
end

---@param player PlayerContext
---@return nil
function PlayerAction.EndAttackAssist(player)
    local ctx = PlayerContext.Assert(player, "PlayerAction.EndAttackAssist")
    PlayerTargeting.ClearAssist(ctx, false)
end

---@param player PlayerContext
---@return nil
function PlayerAction.ApplyMoveInput(player)
    local ctx = PlayerContext.Assert(player, "PlayerAction.ApplyMoveInput")
    local owner = GetOwner(ctx)
    if owner == nil then
        return
    end

    local dir = PlayerAction.GetMoveInputWorldDirection(ctx)
    if dir ~= nil then
        ctx.LastMoveInputDirection = dir
        Reflection.Call(owner, "AddMovementInput", dir, 1.0)
    end

    if ActionStarted(ctx, "Jump") then
        Reflection.Call(owner, "Jump")
    end
end

---@param player PlayerContext
---@return nil
function PlayerAction.UpdateActionInput(player, dt)
    local ctx = PlayerContext.Assert(player, "PlayerAction.UpdateActionInput")
    if ctx == nil then
        return
    end

    local actionConfig = GetActionConfig(ctx)
    local attackDown = ActionDown(ctx, "Attack")

    if attackDown then
        ctx.AttackHoldTime = (ctx.AttackHoldTime or 0.0) + (dt or 0.0)
    else
        ctx.AttackHoldTime = 0.0
    end

    if ctx.AttackHoldTime > 0.05 then
        ctx.AttackPressed = true
    else
        -- 첫 입력은 적용
        if ctx.AttackIndex == 0 then
            ctx.AttackPressed = true
        end
        ctx.AttackPressed = false
    end

    ctx.AttackDown = attackDown

    ctx.DashPressed = false
    ctx.DashChargingPressed = false
    ctx.DashChargingReleased = false
    ctx.DashSlashPressed = false

    local dashDown = ActionDown(ctx, "Dash")
    local dashPressed = ActionStarted(ctx, "Dash")
    local dashReleased = ActionCompleted(ctx, "Dash")

    if dashDown then
        ctx.DashHoldTime = (ctx.DashHoldTime or 0.0) + (dt or 0.0)

        if dashPressed then
            ctx.DashPressed = true
            ctx.DashSlashPressed = true -- compatibility for older animation scripts
        end

        if ctx.DashChargingConsumedInput == true then
            ctx.DashChargingPressed = true
        elseif ctx.DashHoldTime >= (actionConfig.DashChargingHoldThreshold or PlayerConfig.Default.Action.DashChargingHoldThreshold) then
            ctx.DashChargingPressed = true
            ctx.DashChargingConsumedInput = true
        end
    end

    if dashReleased then
        if ctx.DashChargingConsumedInput == true then
            ctx.DashChargingReleased = true
        end

        ctx.DashHoldTime = 0.0
        ctx.DashChargingConsumedInput = false
    end

    if ActionStarted(ctx, "SecondaryDash") then
        ctx.DashPressed = true
        ctx.DashSlashPressed = true
    end
end

---@param player PlayerContext
---@return nil
function PlayerAction.BeginDash(player)
    local ctx = PlayerContext.Assert(player, "PlayerAction.BeginDash")
    if ctx.MovementComp ~= nil then
        ctx.DashPrevOrientRotationToMovement =
            Reflection.GetProperty(ctx.MovementComp, "bOrientRotationToMovement")
        SetOrientRotationToMovement(ctx, false)
    end

    SetMovementInputEnabled(ctx, false)

    local dashDir = PlayerAction.ResolveDashDirection(ctx)
    local _, assistedDir = PlayerTargeting.BeginAssist(ctx, "Dash", dashDir)
    if assistedDir ~= nil then
        dashDir = assistedDir
    end

    PlayerAction.FaceOwnerToDirection(ctx, dashDir)
    ctx.DashMoveDirection = dashDir

    ctx.DashActive = true
    ctx.DashElapsed = 0.0
    ctx.DashEnd = false

    ctx.DashSlashActive = true
    ctx.DashSlashElapsed = 0.0
    ctx.DashSlashEnd = false
    ctx.DashSlashMoveDirection = dashDir

    PlayerEvents.EmitDashStarted(ctx, { Dir = dashDir })
end

---@param player PlayerContext
---@return nil
function PlayerAction.EndDash(player)
    local ctx = PlayerContext.Assert(player, "PlayerAction.EndDash")
    ctx.DashActive = false
    ctx.DashElapsed = 0.0
    ctx.DashEnd = false

    ctx.DashSlashActive = false
    ctx.DashSlashElapsed = 0.0
    ctx.DashSlashEnd = false

    if ctx.DashPrevOrientRotationToMovement ~= nil then
        SetOrientRotationToMovement(ctx, ctx.DashPrevOrientRotationToMovement)
        ctx.DashPrevOrientRotationToMovement = nil
    end

    ctx.DashMoveDirection = nil
    ctx.DashSlashMoveDirection = nil
    PlayerTargeting.ClearAssist(ctx, false)

    SetMovementInputEnabled(ctx, true)
    PlayerEvents.EmitDashEnded(ctx)
end

---@param player PlayerContext
---@return nil
function PlayerAction.UpdateDash(player, dt)
    local ctx = PlayerContext.Assert(player, "PlayerAction.UpdateDash")
    local owner = GetOwner(ctx)
    if owner == nil or ctx.DashMoveDirection == nil then
        return
    end

    ctx.DashElapsed = ctx.DashElapsed + dt
    ctx.DashSlashElapsed = ctx.DashElapsed

    local dir = ctx.DashMoveDirection
    dir.Z = 0.0

    if dir:Length() > 0.001 then
        local actionConfig = GetActionConfig(ctx)
        local moveSpeed = (actionConfig.DashDistance or PlayerConfig.Default.Action.DashDistance) / (actionConfig.DashDuration or PlayerConfig.Default.Action.DashDuration)
        Reflection.Call(owner, "AddActorWorldOffset", dir:Normalized() * moveSpeed * dt)
    end

    local actionConfig = GetActionConfig(ctx)
    if ctx.DashElapsed >= (actionConfig.DashDuration or PlayerConfig.Default.Action.DashDuration) then
        ctx.DashEnd = true
        ctx.DashSlashEnd = true
    end
end

---@param player PlayerContext
---@return nil
function PlayerAction.BeginDashCharging(player)
    local ctx = PlayerContext.Assert(player, "PlayerAction.BeginDashCharging")
    SetMovementInputEnabled(ctx, false)
    StopMovementImmediately(ctx)

    ctx.DashChargingActive = true
    ctx.DashChargingElapsed = 0.0
    ctx.DashChargingEnd = false
    ctx.DashChargingReleased = false

    PlayerEvents.EmitDashChargingStarted(ctx)
end

---@param player PlayerContext
---@return nil
function PlayerAction.EndDashCharging(player, unlockMovement)
    local ctx = PlayerContext.Assert(player, "PlayerAction.EndDashCharging")
    ctx.DashChargingActive = false
    ctx.DashChargingElapsed = 0.0
    ctx.DashChargingEnd = false
    ctx.DashChargingReleased = false

    if unlockMovement ~= false then
        SetMovementInputEnabled(ctx, true)
    end

    PlayerEvents.EmitDashChargingEnded(ctx)
end

---@param player PlayerContext
---@return nil
function PlayerAction.UpdateDashCharging(player, dt)
    local ctx = PlayerContext.Assert(player, "PlayerAction.UpdateDashCharging")
    ctx.DashChargingElapsed = (ctx.DashChargingElapsed or 0.0) + (dt or 0.0)
    StopMovementImmediately(ctx)
end

---@param player PlayerContext
---@return nil
function PlayerAction.BeginDashChargeAttack(player)
    local ctx = PlayerContext.Assert(player, "PlayerAction.BeginDashChargeAttack")
    SetMovementInputEnabled(ctx, false)
    StopMovementImmediately(ctx)

    local aimDir = PlayerAction.GetOwnerForward2D(ctx) or PlayerAction.ResolveDashDirection(ctx)
    local _, assistedDir = PlayerTargeting.BeginAssist(ctx, "DashChargeAttack", aimDir)
    if assistedDir ~= nil then
        PlayerAction.FaceOwnerToDirection(ctx, assistedDir)
    end

    PlayerAction.StepDashChargeAttackForward(ctx)

    ctx.DashChargeAttackActive = true
    ctx.DashChargeAttackElapsed = 0.0
    ctx.DashChargeAttackEnd = false

    PlayerEvents.EmitDashChargeAttackStarted(ctx)
end

---@param player PlayerContext
---@return nil
function PlayerAction.EndDashChargeAttack(player)
    local ctx = PlayerContext.Assert(player, "PlayerAction.EndDashChargeAttack")
    ctx.DashChargeAttackActive = false
    ctx.DashChargeAttackElapsed = 0.0
    ctx.DashChargeAttackEnd = false
    PlayerTargeting.ClearAssist(ctx, false)

    SetMovementInputEnabled(ctx, true)
    PlayerEvents.EmitDashChargeAttackEnded(ctx)
end

---@param player PlayerContext
---@return nil
function PlayerAction.CancelDashActions(player, unlockMovement)
    local ctx = PlayerContext.Assert(player, "PlayerAction.CancelDashActions")
    if ctx == nil then
        return
    end

    local wasDashActive = ctx.DashActive == true or ctx.DashSlashActive == true
    local wasDashChargingActive = ctx.DashChargingActive == true
    local wasDashChargeAttackActive = ctx.DashChargeAttackActive == true

    ctx.DashPressed = false
    ctx.DashChargingPressed = false
    ctx.DashChargingReleased = false
    ctx.DashSlashPressed = false

    ctx.DashActive = false
    ctx.DashElapsed = 0.0
    ctx.DashEnd = false
    ctx.DashMoveDirection = nil

    ctx.DashSlashActive = false
    ctx.DashSlashElapsed = 0.0
    ctx.DashSlashEnd = false
    ctx.DashSlashMoveDirection = nil

    ctx.DashChargingActive = false
    ctx.DashChargingElapsed = 0.0
    ctx.DashChargingEnd = false

    ctx.DashChargeAttackActive = false
    ctx.DashChargeAttackElapsed = 0.0
    ctx.DashChargeAttackEnd = false
    PlayerTargeting.ClearAssist(ctx, true)

    if ctx.DashPrevOrientRotationToMovement ~= nil then
        SetOrientRotationToMovement(ctx, ctx.DashPrevOrientRotationToMovement)
        ctx.DashPrevOrientRotationToMovement = nil
    end

    if unlockMovement ~= false then
        SetMovementInputEnabled(ctx, true)
    end

    if wasDashActive then
        PlayerEvents.EmitDashEnded(ctx)
    end
    if wasDashChargingActive then
        PlayerEvents.EmitDashChargingEnded(ctx)
    end
    if wasDashChargeAttackActive then
        PlayerEvents.EmitDashChargeAttackEnded(ctx)
    end
end

---@param player PlayerContext
---@return nil
function PlayerAction.UpdateDashChargeAttack(player, dt)
    local ctx = PlayerContext.Assert(player, "PlayerAction.UpdateDashChargeAttack")
    ctx.DashChargeAttackElapsed = (ctx.DashChargeAttackElapsed or 0.0) + (dt or 0.0)

    local dir = PlayerTargeting.GetAssistDirection(ctx)
    if dir ~= nil and PlayerTargeting.IsAssistTurnActive(ctx) == true then
        PlayerAction.SmoothFaceOwnerToDirection(ctx, dir, dt, PlayerTargeting.GetTurnSpeed(ctx))
    end

    StopMovementImmediately(ctx)
end

-- Compatibility wrappers for scripts that still call DashSlash.
---@param player PlayerContext
---@return nil
function PlayerAction.BeginDashSlash(player)
    local ctx = PlayerContext.Assert(player, "PlayerAction.BeginDashSlash")
    PlayerAction.BeginDash(ctx)
end

---@param player PlayerContext
---@return nil
function PlayerAction.EndDashSlash(player)
    local ctx = PlayerContext.Assert(player, "PlayerAction.EndDashSlash")
    PlayerAction.EndDash(ctx)
end

---@param player PlayerContext
---@return nil
function PlayerAction.UpdateDashSlash(player, dt)
    local ctx = PlayerContext.Assert(player, "PlayerAction.UpdateDashSlash")
    PlayerAction.UpdateDash(ctx, dt)
end

---@param player PlayerContext
---@param notifyName string
---@return nil
function PlayerAction.OnAnimNotify(player, notifyName)
    local ctx = PlayerContext.Assert(player, "PlayerAction.OnAnimNotify")
    if notifyName == "ComboWindowOpen" then
        ctx.ComboWindow = true
    elseif notifyName == "ComboWindowClose" then
        ctx.ComboWindow = false
    elseif notifyName == "AttackEnd" then
        ctx.AttackEnd = true
    elseif notifyName == "DashEnd" or notifyName == "DashSlashEnd" then
        ctx.DashEnd = true
        ctx.DashSlashEnd = true
    elseif notifyName == "DashChargeAttackEnd" or notifyName == "DashChargingAttackEnd" then
        ctx.DashChargeAttackEnd = true
    end
end

---@param player PlayerContext
---@return boolean
function PlayerAction.IsUltimateRunning(player)
    local ctx = PlayerContext.Assert(player, "PlayerAction.IsUltimateRunning")
    return ctx ~= nil and ctx.IsUltimateRunning == true
end

---@param player PlayerContext
---@return boolean
function PlayerAction.IsInUltimateMode(player)
    local ctx = PlayerContext.Assert(player, "PlayerAction.IsInUltimateMode")
    return ctx ~= nil and ctx.IsInUltimateMode == true
end

---@param player PlayerContext
---@param dt number
---@return nil
function PlayerAction.Update(player, dt)
    local ctx = PlayerContext.Assert(player, "PlayerAction.Update")

    PlayerAction.UpdateActionInput(ctx, dt)

    local maxUltimateGauge = ctx.MaxUltimateGauge or PlayerConfig.Default.Combat.MaxUltimateGauge
    local ultimateGauge = ctx.UltimateGauge or 0

    ultimateGauge = 1000

    if not ctx.IsUltimateRunning
        and ActionStarted(ctx, "Ultimate")
        and ultimateGauge >= maxUltimateGauge then
        ctx.IsUltimateRunning = true
        PlayerEvents.EmitUltimateStarted(ctx)
    end
end

return PlayerAction
