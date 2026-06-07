-- Player/PlayerAction.lua
-- PlayerAction owns player.Action state transitions.
-- Do not pass AnimInstance self as player.

local PlayerAction = {}

local PlayerTargeting = require("Player/PlayerTargeting")
local PlayerContext = require("Player/PlayerContext")
local PlayerEvents = require("Player/PlayerEvents")

local function GetInputConfig(player)
    return player.Config.Input
end

local function GetActionConfig(player)
    return player.Config.Action
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

local function ResolveActionName(player, actionName)
    local inputConfig = GetInputConfig(player)
    local fieldName = actionName .. "Action"
    local resolved = inputConfig[fieldName]
    if resolved == nil then
        error("[PlayerAction] Missing input config field: " .. fieldName)
    end
    return resolved
end

local function ResolveAxisName(player, axisName)
    local inputConfig = GetInputConfig(player)
    local fieldName = axisName .. "Axis"
    local resolved = inputConfig[fieldName]
    if resolved == nil then
        error("[PlayerAction] Missing input config field: " .. fieldName)
    end
    return resolved
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

local function GetOwner(player)
    return player.Owner
end

local function SetMovementInputEnabled(ctx, enabled)
    if ctx.Runtime.MovementComp ~= nil then
        Reflection.Call(ctx.Runtime.MovementComp, "SetMovementInputEnabled", enabled)
    end
end

local function StopMovementImmediately(ctx)
    if ctx.Runtime.MovementComp ~= nil then
        Reflection.Call(ctx.Runtime.MovementComp, "StopMovementImmediately")
    end
end

local function SetOrientRotationToMovement(ctx, enabled)
    if ctx.Runtime.MovementComp ~= nil then
        Reflection.SetProperty(ctx.Runtime.MovementComp, "bOrientRotationToMovement", enabled)
    end
end

local function ResetDashInput(ctx)
    ctx.Input.DashHoldTime = 0.0
    ctx.Input.DashChargingConsumedInput = false

    ctx.Input.DashPressed = false
    ctx.Input.DashChargingPressed = false
    ctx.Input.DashChargingReleased = false
end

---@param player PlayerContext
---@return nil
-- =========================================================
-- Public API
-- =========================================================

function PlayerAction.Init(player)
    local ctx = PlayerContext.Assert(player, "PlayerAction.Init")
    RequireSemanticInputApi()

    ctx.Runtime.LastMoveInputDirection = nil
    ctx.Runtime.DashPrevOrientRotationToMovement = nil
    ctx.Runtime.DashMoveDirection = nil
    ctx.Runtime.EventQueue = {}
    ctx.Input.AttackDown = false
    ctx.Input.AttackPressed = false
    ctx.Input.AttackHoldTime = 0.0
    ctx.Runtime.StepForwardActive = false
    ctx.Runtime.StepForwardElapsed = 0.0
    ctx.Runtime.StepForwardDuration = 0.0
    ctx.Runtime.StepForwardDistance = 0.0
    ctx.Runtime.StepForwardAppliedDistance = 0.0
    ctx.Runtime.StepForwardDirection = nil

    ctx.Runtime.TargetAssistMode = nil
    ctx.Runtime.TargetAssistTarget = nil
    ctx.Runtime.TargetAssistDirection = nil
    ctx.Runtime.TargetAssistDistance = nil
    ctx.Runtime.TargetAssistLockedDirection = nil
    ctx.Runtime.TargetAssistEndTime = 0.0
    ctx.Runtime.TargetAssistKeepUntil = 0.0

    ResetDashInput(ctx)

    ctx.Action.DashActive = false
    ctx.Action.DashElapsed = 0.0
    ctx.Action.DashEnd = false

    ctx.Action.DashChargingActive = false
    ctx.Action.DashChargingElapsed = 0.0
    ctx.Action.DashChargingEnd = false

    ctx.Action.DashChargeAttackActive = false
    ctx.Action.DashChargeAttackElapsed = 0.0
    ctx.Action.DashChargeAttackEnd = false


    ctx.Runtime.MovementComp = nil
    if ctx.Owner ~= nil then
        Reflection.SetProperty(ctx.Owner, "bUseControllerRotationYaw", false)

        if ctx.Owner.GetCharacterMovement ~= nil then
            ctx.Runtime.MovementComp = ctx.Owner:GetCharacterMovement()
        end
        if ctx.Runtime.MovementComp == nil and ctx.Owner.GetFloatingPawnMovement ~= nil then
            ctx.Runtime.MovementComp = ctx.Owner:GetFloatingPawnMovement()
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

    return actionConfig.AttackStepForwardDistance
end

local function GetAttackStepForwardDuration(actionConfig, attackIndex)
    if actionConfig.AttackStepForwardDurations ~= nil and attackIndex ~= nil then
        local duration = actionConfig.AttackStepForwardDurations[attackIndex]
        if duration ~= nil then
            return duration
        end
    end

    return actionConfig.AttackStepForwardDuration
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

    ctx.Runtime.StepForwardActive = true
    ctx.Runtime.StepForwardElapsed = 0.0
    ctx.Runtime.StepForwardDuration = duration
    ctx.Runtime.StepForwardDistance = distance
    ctx.Runtime.StepForwardAppliedDistance = 0.0
    ctx.Runtime.StepForwardDirection = forward
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
        actionConfig.DashChargeAttackStepForwardDistance,
        actionConfig.DashChargeAttackStepForwardDuration,
        PlayerTargeting.GetAssistDirection(ctx)
    )
end

---@param player PlayerContext
---@return nil
function PlayerAction.UpdateStepForward(player, dt)
    local ctx = PlayerContext.Assert(player, "PlayerAction.UpdateStepForward")
    if ctx.Runtime.StepForwardActive ~= true then
        return
    end

    local owner = GetOwner(ctx)
    local dir = ctx.Runtime.StepForwardDirection
    if owner == nil or dir == nil then
        ctx.Runtime.StepForwardActive = false
        return
    end

    local duration = ctx.Runtime.StepForwardDuration or 0.0
    if duration <= 0.0 then
        ctx.Runtime.StepForwardActive = false
        return
    end

    ctx.Runtime.StepForwardElapsed = (ctx.Runtime.StepForwardElapsed or 0.0) + (dt or 0.0)

    local alpha = ctx.Runtime.StepForwardElapsed / duration
    if alpha > 1.0 then
        alpha = 1.0
    end

    local targetDistance = (ctx.Runtime.StepForwardDistance or 0.0) * alpha
    local deltaDistance = targetDistance - (ctx.Runtime.StepForwardAppliedDistance or 0.0)

    if math.abs(deltaDistance) > 0.001 then
        Reflection.Call(owner, "AddActorWorldOffset", dir * deltaDistance)
        ctx.Runtime.StepForwardAppliedDistance = targetDistance
    end

    if alpha >= 1.0 then
        ctx.Runtime.StepForwardActive = false
        ctx.Runtime.StepForwardDirection = nil
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

    if ctx.Runtime.LastMoveInputDirection ~= nil then
        return ctx.Runtime.LastMoveInputDirection
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
    local alpha = dt * (turnSpeed or actionConfig.AttackTurnSpeed)
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
        ctx.Runtime.LastMoveInputDirection = dir
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
    local actionConfig = GetActionConfig(ctx)
    local attackDown = ActionDown(ctx, "Attack")

    if attackDown then
        ctx.Input.AttackHoldTime = (ctx.Input.AttackHoldTime or 0.0) + (dt or 0.0)
    else
        ctx.Input.AttackHoldTime = 0.0
    end

    if ctx.Input.AttackHoldTime > 0.05 then
        ctx.Input.AttackPressed = true
    else
        -- 첫 입력은 적용
        if ctx.Action.AttackIndex == 0 then
            ctx.Input.AttackPressed = true
        end
        ctx.Input.AttackPressed = false
    end

    ctx.Input.AttackDown = attackDown

    ctx.Input.DashPressed = false
    ctx.Input.DashChargingPressed = false
    ctx.Input.DashChargingReleased = false

    local dashDown = ActionDown(ctx, "Dash")
    local dashPressed = ActionStarted(ctx, "Dash")
    local dashReleased = ActionCompleted(ctx, "Dash")

    if dashDown then
        ctx.Input.DashHoldTime = (ctx.Input.DashHoldTime or 0.0) + (dt or 0.0)

        if dashPressed then
            ctx.Input.DashPressed = true
        end

        if ctx.Input.DashChargingConsumedInput == true then
            ctx.Input.DashChargingPressed = true
        elseif ctx.Input.DashHoldTime >= (actionConfig.DashChargingHoldThreshold) then
            ctx.Input.DashChargingPressed = true
            ctx.Input.DashChargingConsumedInput = true
        end
    end

    if dashReleased then
        if ctx.Input.DashChargingConsumedInput == true then
            ctx.Input.DashChargingReleased = true
        end

        ctx.Input.DashHoldTime = 0.0
        ctx.Input.DashChargingConsumedInput = false
    end

    if ActionStarted(ctx, "SecondaryDash") then
        ctx.Input.DashPressed = true
    end
end

---@param player PlayerContext
---@return nil
function PlayerAction.BeginDash(player)
    local ctx = PlayerContext.Assert(player, "PlayerAction.BeginDash")
    if ctx.Runtime.MovementComp ~= nil then
        ctx.Runtime.DashPrevOrientRotationToMovement =
            Reflection.GetProperty(ctx.Runtime.MovementComp, "bOrientRotationToMovement")
        SetOrientRotationToMovement(ctx, false)
    end

    SetMovementInputEnabled(ctx, false)

    local dashDir = PlayerAction.ResolveDashDirection(ctx)
    local _, assistedDir = PlayerTargeting.BeginAssist(ctx, "Dash", dashDir)
    if assistedDir ~= nil then
        dashDir = assistedDir
    end

    PlayerAction.FaceOwnerToDirection(ctx, dashDir)
    ctx.Runtime.DashMoveDirection = dashDir

    ctx.Action.DashActive = true
    ctx.Action.DashElapsed = 0.0
    ctx.Action.DashEnd = false

    PlayerEvents.EmitDashStarted(ctx, { Dir = dashDir })
end

---@param player PlayerContext
---@return nil
function PlayerAction.EndDash(player)
    local ctx = PlayerContext.Assert(player, "PlayerAction.EndDash")
    ctx.Action.DashActive = false
    ctx.Action.DashElapsed = 0.0
    ctx.Action.DashEnd = false

    if ctx.Runtime.DashPrevOrientRotationToMovement ~= nil then
        SetOrientRotationToMovement(ctx, ctx.Runtime.DashPrevOrientRotationToMovement)
        ctx.Runtime.DashPrevOrientRotationToMovement = nil
    end

    ctx.Runtime.DashMoveDirection = nil
    PlayerTargeting.ClearAssist(ctx, false)

    SetMovementInputEnabled(ctx, true)
    PlayerEvents.EmitDashEnded(ctx)
end

---@param player PlayerContext
---@return nil
function PlayerAction.UpdateDash(player, dt)
    local ctx = PlayerContext.Assert(player, "PlayerAction.UpdateDash")
    local owner = GetOwner(ctx)
    if owner == nil or ctx.Runtime.DashMoveDirection == nil then
        return
    end

    ctx.Action.DashElapsed = ctx.Action.DashElapsed + dt

    local dir = ctx.Runtime.DashMoveDirection
    dir.Z = 0.0

    if dir:Length() > 0.001 then
        local actionConfig = GetActionConfig(ctx)
        local moveSpeed = (actionConfig.DashDistance) / (actionConfig.DashDuration)
        Reflection.Call(owner, "AddActorWorldOffset", dir:Normalized() * moveSpeed * dt)
    end

    local actionConfig = GetActionConfig(ctx)
    if ctx.Action.DashElapsed >= (actionConfig.DashDuration) then
        ctx.Action.DashEnd = true
    end
end

---@param player PlayerContext
---@return nil
function PlayerAction.BeginDashCharging(player)
    local ctx = PlayerContext.Assert(player, "PlayerAction.BeginDashCharging")
    SetMovementInputEnabled(ctx, false)
    StopMovementImmediately(ctx)

    ctx.Action.DashChargingActive = true
    ctx.Action.DashChargingElapsed = 0.0
    ctx.Action.DashChargingEnd = false
    ctx.Input.DashChargingReleased = false

    PlayerEvents.EmitDashChargingStarted(ctx)
end

---@param player PlayerContext
---@return nil
function PlayerAction.EndDashCharging(player, unlockMovement)
    local ctx = PlayerContext.Assert(player, "PlayerAction.EndDashCharging")
    ctx.Action.DashChargingActive = false
    ctx.Action.DashChargingElapsed = 0.0
    ctx.Action.DashChargingEnd = false
    ctx.Input.DashChargingReleased = false

    if unlockMovement ~= false then
        SetMovementInputEnabled(ctx, true)
    end

    PlayerEvents.EmitDashChargingEnded(ctx)
end

---@param player PlayerContext
---@return nil
function PlayerAction.UpdateDashCharging(player, dt)
    local ctx = PlayerContext.Assert(player, "PlayerAction.UpdateDashCharging")
    ctx.Action.DashChargingElapsed = (ctx.Action.DashChargingElapsed or 0.0) + (dt or 0.0)
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

    ctx.Action.DashChargeAttackActive = true
    ctx.Action.DashChargeAttackElapsed = 0.0
    ctx.Action.DashChargeAttackEnd = false

    PlayerEvents.EmitDashChargeAttackStarted(ctx)
end

---@param player PlayerContext
---@return nil
function PlayerAction.EndDashChargeAttack(player)
    local ctx = PlayerContext.Assert(player, "PlayerAction.EndDashChargeAttack")
    ctx.Action.DashChargeAttackActive = false
    ctx.Action.DashChargeAttackElapsed = 0.0
    ctx.Action.DashChargeAttackEnd = false
    PlayerTargeting.ClearAssist(ctx, false)

    SetMovementInputEnabled(ctx, true)
    PlayerEvents.EmitDashChargeAttackEnded(ctx)
end

---@param player PlayerContext
---@return nil
function PlayerAction.CancelDashActions(player, unlockMovement)
    local ctx = PlayerContext.Assert(player, "PlayerAction.CancelDashActions")
    local wasDashActive = ctx.Action.DashActive == true
    local wasDashChargingActive = ctx.Action.DashChargingActive == true
    local wasDashChargeAttackActive = ctx.Action.DashChargeAttackActive == true

    ctx.Input.DashPressed = false
    ctx.Input.DashChargingPressed = false
    ctx.Input.DashChargingReleased = false

    ctx.Action.DashActive = false
    ctx.Action.DashElapsed = 0.0
    ctx.Action.DashEnd = false
    ctx.Runtime.DashMoveDirection = nil

    ctx.Action.DashChargingActive = false
    ctx.Action.DashChargingElapsed = 0.0
    ctx.Action.DashChargingEnd = false

    ctx.Action.DashChargeAttackActive = false
    ctx.Action.DashChargeAttackElapsed = 0.0
    ctx.Action.DashChargeAttackEnd = false
    PlayerTargeting.ClearAssist(ctx, true)

    if ctx.Runtime.DashPrevOrientRotationToMovement ~= nil then
        SetOrientRotationToMovement(ctx, ctx.Runtime.DashPrevOrientRotationToMovement)
        ctx.Runtime.DashPrevOrientRotationToMovement = nil
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
    ctx.Action.DashChargeAttackElapsed = (ctx.Action.DashChargeAttackElapsed or 0.0) + (dt or 0.0)

    local dir = PlayerTargeting.GetAssistDirection(ctx)
    if dir ~= nil and PlayerTargeting.IsAssistTurnActive(ctx) == true then
        PlayerAction.SmoothFaceOwnerToDirection(ctx, dir, dt, PlayerTargeting.GetTurnSpeed(ctx))
    end

    StopMovementImmediately(ctx)
end

---@param player PlayerContext
---@param notifyName string
---@return nil
function PlayerAction.OnAnimNotify(player, notifyName)
    local ctx = PlayerContext.Assert(player, "PlayerAction.OnAnimNotify")
    if notifyName == "ComboWindowOpen" then
        ctx.Action.ComboWindow = true
    elseif notifyName == "ComboWindowClose" then
        ctx.Action.ComboWindow = false
    elseif notifyName == "AttackEnd" then
        ctx.Action.AttackEnd = true
    elseif notifyName == "DashEnd" then
        ctx.Action.DashEnd = true
    elseif notifyName == "DashChargeAttackEnd" or notifyName == "DashChargingAttackEnd" then
        ctx.Action.DashChargeAttackEnd = true
    end
end

---@param player PlayerContext
---@return boolean
function PlayerAction.IsUltimateRunning(player)
    local ctx = PlayerContext.Assert(player, "PlayerAction.IsUltimateRunning")
    return ctx.Action.IsUltimateRunning == true
end

---@param player PlayerContext
---@return boolean
function PlayerAction.IsInUltimateMode(player)
    local ctx = PlayerContext.Assert(player, "PlayerAction.IsInUltimateMode")
    return ctx.Action.IsInUltimateMode == true
end

---@param player PlayerContext
---@param dt number
---@return nil
function PlayerAction.Update(player, dt)
    local ctx = PlayerContext.Assert(player, "PlayerAction.Update")

    PlayerAction.UpdateActionInput(ctx, dt)

    local maxUltimateGauge = ctx.Combat.MaxUltimateGauge
    local ultimateGauge = ctx.Combat.UltimateGauge or 0

    ultimateGauge = 1000

    if not ctx.Action.IsUltimateRunning
        and ActionStarted(ctx, "Ultimate")
        and ultimateGauge >= maxUltimateGauge then
        ctx.Action.IsUltimateRunning = true
        PlayerEvents.EmitUltimateStarted(ctx)
    end
end

return PlayerAction
