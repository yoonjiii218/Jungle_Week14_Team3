-- Player/PlayerAction.lua
-- PlayerAction owns playerContext.Action state transitions.
-- Do not pass AnimInstance self as playerContext.

local PlayerAction = {}

local PlayerTargeting = require("Player/PlayerTargeting")
local PlayerProjectile = require("Player/PlayerProjectile")
local PlayerContext = require("Player/PlayerContext")
local PlayerEvents = require("Player/PlayerEvents")

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

local function ResolveActionName(playerContext, actionName)
    local inputConfig = playerContext.Config.Input
    local fieldName = actionName .. "Action"
    local resolved = inputConfig[fieldName]
    if resolved == nil then
        error("[PlayerAction] Missing input config field: " .. fieldName)
    end
    return resolved
end

local function ResolveAxisName(playerContext, axisName)
    local inputConfig = playerContext.Config.Input
    local fieldName = axisName .. "Axis"
    local resolved = inputConfig[fieldName]
    if resolved == nil then
        error("[PlayerAction] Missing input config field: " .. fieldName)
    end
    return resolved
end

local function ActionDown(playerContext, actionName)
    RequireSemanticInputApi()
    return Input.IsActionDown(ResolveActionName(playerContext, actionName)) == true
end

local function ActionStarted(playerContext, actionName)
    RequireSemanticInputApi()
    return Input.WasActionStarted(ResolveActionName(playerContext, actionName)) == true
end

local function ActionCompleted(playerContext, actionName)
    RequireSemanticInputApi()
    return Input.WasActionCompleted(ResolveActionName(playerContext, actionName)) == true
end

local function Axis2D(playerContext, axisName)
    RequireSemanticInputApi()
    local axis = Input.GetAxis2D(ResolveAxisName(playerContext, axisName))
    if axis == nil then
        error("[PlayerAction] Input.GetAxis2D returned nil")
    end
    return axis
end

local function SetMovementInputEnabled(playerContext, enabled)
    if playerContext.Runtime.MovementComp ~= nil then
        Reflection.Call(playerContext.Runtime.MovementComp, "SetMovementInputEnabled", enabled)
    end
end

local function StopMovementImmediately(playerContext)
    if playerContext.Runtime.MovementComp ~= nil then
        Reflection.Call(playerContext.Runtime.MovementComp, "StopMovementImmediately")
    end
end

local function SetOrientRotationToMovement(playerContext, enabled)
    if playerContext.Runtime.MovementComp ~= nil then
        Reflection.SetProperty(playerContext.Runtime.MovementComp, "bOrientRotationToMovement", enabled)
    end
end

local function ClearAttackBuffer(playerContext)
    playerContext.Input.AttackBuffered = false
    playerContext.Input.AttackBufferTimer = 0.0
    if playerContext.Input.LastBufferedAction == "Attack" then
        playerContext.Input.LastBufferedAction = nil
    end
end

local function ClearDashBuffer(playerContext)
    playerContext.Input.DashBuffered = false
    playerContext.Input.DashBufferTimer = 0.0
    if playerContext.Input.LastBufferedAction == "Dash" then
        playerContext.Input.LastBufferedAction = nil
    end
end

local function ClearInputBuffers(playerContext)
    ClearAttackBuffer(playerContext)
    ClearDashBuffer(playerContext)
end

local function ResetDashInput(playerContext)
    playerContext.Input.DashHoldTime = 0.0
    playerContext.Input.DashConsumedInput = false
    playerContext.Input.DashChargingConsumedInput = false
    playerContext.Input.DashBlockedUntilReleased = false

    playerContext.Input.DashPressed = false
    playerContext.Input.DashChargingPressed = false
    playerContext.Input.DashChargingReleased = false
    ClearDashBuffer(playerContext)
end

---@param playerContext PlayerContext
---@return nil
-- =========================================================
-- Public API
-- =========================================================

function PlayerAction.Init(playerContext)
    PlayerContext.Assert(playerContext, "PlayerAction.Init")
    RequireSemanticInputApi()

    playerContext.Runtime.LastMoveInputDirection = nil
    playerContext.Runtime.DashPrevOrientRotationToMovement = nil
    playerContext.Runtime.DashMoveDirection = nil
    playerContext.Runtime.DashPreserveFacing = false
    playerContext.Runtime.HitKnockbackDirection = nil
    playerContext.Runtime.HitKnockbackAppliedDistance = 0.0
    playerContext.Runtime.EventQueue = {}
    playerContext.Runtime.LastActionInputUpdateTime = nil
    playerContext.Input.AttackDown = false
    playerContext.Input.AttackPressed = false
    playerContext.Input.AttackHoldTime = 0.0
    ClearAttackBuffer(playerContext)
    playerContext.Runtime.StepForwardActive = false
    playerContext.Runtime.StepForwardElapsed = 0.0
    playerContext.Runtime.StepForwardDuration = 0.0
    playerContext.Runtime.StepForwardDistance = 0.0
    playerContext.Runtime.StepForwardAppliedDistance = 0.0
    playerContext.Runtime.StepForwardDirection = nil

    playerContext.Runtime.TargetAssistMode = nil
    playerContext.Runtime.TargetAssistTarget = nil
    playerContext.Runtime.TargetAssistDirection = nil
    playerContext.Runtime.TargetAssistDistance = nil
    playerContext.Runtime.TargetAssistLockedDirection = nil
    playerContext.Runtime.TargetAssistEndTime = 0.0
    playerContext.Runtime.TargetAssistKeepUntil = 0.0

    ResetDashInput(playerContext)

    playerContext.Action.DashActive = false
    playerContext.Action.DashElapsed = 0.0
    playerContext.Action.DashEnd = false

    playerContext.Action.DashChargingActive = false
    playerContext.Action.DashChargingElapsed = 0.0
    playerContext.Action.DashChargingEnd = false

    playerContext.Action.DashChargeAttackActive = false
    playerContext.Action.DashChargeAttackElapsed = 0.0
    playerContext.Action.DashChargeAttackEnd = false

    playerContext.Action.HitReactActive = false
    playerContext.Action.HitReactPending = false
    playerContext.Action.HitReactDirection = nil
    playerContext.Action.HitReactElapsed = 0.0
    playerContext.Action.HitReactEnd = false

    playerContext.Runtime.MovementComp = nil
    if playerContext.Owner ~= nil then
        Reflection.SetProperty(playerContext.Owner, "bUseControllerRotationYaw", false)

        if playerContext.Owner.GetCharacterMovement ~= nil then
            playerContext.Runtime.MovementComp = playerContext.Owner:GetCharacterMovement()
        end
        if playerContext.Runtime.MovementComp == nil and playerContext.Owner.GetFloatingPawnMovement ~= nil then
            playerContext.Runtime.MovementComp = playerContext.Owner:GetFloatingPawnMovement()
        end
    end
end

---@param playerContext PlayerContext
---@param event PlayerEvent
---@return nil
function PlayerAction.PushEvent(playerContext, event)
    PlayerContext.Assert(playerContext, "PlayerAction.PushEvent")
    if event == nil then
        return
    end

    PlayerEvents.Push(playerContext, event)
end

---@param playerContext PlayerContext
---@return nil
function PlayerAction.SetMovementInputEnabled(playerContext, enabled)
    PlayerContext.Assert(playerContext, "PlayerAction.SetMovementInputEnabled")
    SetMovementInputEnabled(playerContext, enabled)
end

---@param playerContext PlayerContext
---@return nil
function PlayerAction.StopMovementImmediately(playerContext)
    PlayerContext.Assert(playerContext, "PlayerAction.StopMovementImmediately")
    StopMovementImmediately(playerContext)
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

local function BeginStepForward(playerContext, distance, duration, direction)
    local owner = playerContext.Owner
    if owner == nil then
        return
    end

    local forward = direction or PlayerAction.GetOwnerForward2D(playerContext)
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

    playerContext.Runtime.StepForwardActive = true
    playerContext.Runtime.StepForwardElapsed = 0.0
    playerContext.Runtime.StepForwardDuration = duration
    playerContext.Runtime.StepForwardDistance = distance
    playerContext.Runtime.StepForwardAppliedDistance = 0.0
    playerContext.Runtime.StepForwardDirection = forward
end

---@param playerContext PlayerContext
---@return nil
function PlayerAction.StepAttackForward(playerContext, attackIndex)
    PlayerContext.Assert(playerContext, "PlayerAction.StepAttackForward")
    local actionConfig = playerContext.Config.Action
    BeginStepForward(
        playerContext,
        GetAttackStepForwardDistance(actionConfig, attackIndex),
        GetAttackStepForwardDuration(actionConfig, attackIndex)
    )
end

---@param playerContext PlayerContext
---@return nil
function PlayerAction.StepDashChargeAttackForward(playerContext)
    PlayerContext.Assert(playerContext, "PlayerAction.StepDashChargeAttackForward")
    local actionConfig = playerContext.Config.Action
    BeginStepForward(
        playerContext,
        actionConfig.DashChargeAttackStepForwardDistance,
        actionConfig.DashChargeAttackStepForwardDuration,
        PlayerTargeting.GetAssistDirection(playerContext)
    )
end

---@param playerContext PlayerContext
---@return nil
function PlayerAction.UpdateStepForward(playerContext, dt)
    PlayerContext.Assert(playerContext, "PlayerAction.UpdateStepForward")
    if playerContext.Runtime.StepForwardActive ~= true then
        return
    end

    local owner = playerContext.Owner
    local dir = playerContext.Runtime.StepForwardDirection
    if owner == nil or dir == nil then
        playerContext.Runtime.StepForwardActive = false
        return
    end

    local duration = playerContext.Runtime.StepForwardDuration or 0.0
    if duration <= 0.0 then
        playerContext.Runtime.StepForwardActive = false
        return
    end

    playerContext.Runtime.StepForwardElapsed = (playerContext.Runtime.StepForwardElapsed or 0.0) + (dt or 0.0)

    local alpha = playerContext.Runtime.StepForwardElapsed / duration
    if alpha > 1.0 then
        alpha = 1.0
    end

    local targetDistance = (playerContext.Runtime.StepForwardDistance or 0.0) * alpha
    local deltaDistance = targetDistance - (playerContext.Runtime.StepForwardAppliedDistance or 0.0)

    if math.abs(deltaDistance) > 0.001 then
        Reflection.Call(owner, "AddActorWorldOffset", dir * deltaDistance)
        playerContext.Runtime.StepForwardAppliedDistance = targetDistance
    end

    if alpha >= 1.0 then
        playerContext.Runtime.StepForwardActive = false
        playerContext.Runtime.StepForwardDirection = nil
    end
end

---@param playerContext PlayerContext
---@return any
function PlayerAction.GetMoveInputWorldDirection(playerContext)
    PlayerContext.Assert(playerContext, "PlayerAction.GetMoveInputWorldDirection")
    local owner = playerContext.Owner
    if owner == nil then
        return nil
    end

    local moveForward = 0.0
    local moveRight = 0.0

    local moveAxis = Axis2D(playerContext, "Move")
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

---@param playerContext PlayerContext
---@return any
function PlayerAction.GetOwnerForward2D(playerContext)
    PlayerContext.Assert(playerContext, "PlayerAction.GetOwnerForward2D")
    local owner = playerContext.Owner
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

local function GetActorLocation2D(actor)
    if actor == nil then
        return nil
    end

    local location = Reflection.Call(actor, "GetActorLocation")
    if location == nil then
        return nil
    end

    location.Z = 0.0
    return location
end

local function GetOwnerRight2D(playerContext)
    local owner = playerContext.Owner
    if owner == nil then
        return nil
    end

    local dir = Reflection.Call(owner, "GetActorRight")
    if dir == nil then
        return nil
    end

    dir.Z = 0.0
    if dir:Length() <= 0.001 then
        return nil
    end

    return dir:Normalized()
end

local function Dot2D(a, b)
    if a == nil or b == nil then
        return 0.0
    end

    return (a.X or 0.0) * (b.X or 0.0) + (a.Y or 0.0) * (b.Y or 0.0)
end

---@param playerContext PlayerContext
---@return any
function PlayerAction.ResolveDashDirection(playerContext)
    PlayerContext.Assert(playerContext, "PlayerAction.ResolveDashDirection")
    local dir = PlayerAction.GetMoveInputWorldDirection(playerContext)

    if dir ~= nil then
        return dir
    end

    local forward = PlayerAction.GetOwnerForward2D(playerContext)
    if forward == nil then
        return nil
    end

    -- No movement input: evasive back dash. Preserve current facing.
    return forward * -1.0
end

---@param playerContext PlayerContext
---@return any, boolean
function PlayerAction.ResolveDashDirectionAndFacing(playerContext)
    PlayerContext.Assert(playerContext, "PlayerAction.ResolveDashDirectionAndFacing")
    local dir = PlayerAction.GetMoveInputWorldDirection(playerContext)

    if dir ~= nil then
        return dir, true
    end

    local forward = PlayerAction.GetOwnerForward2D(playerContext)
    if forward == nil then
        return nil, false
    end

    -- No movement input: move backward while keeping the actor looking forward.
    return forward * -1.0, false
end

---@param playerContext PlayerContext
---@return nil
function PlayerAction.FaceOwnerToDirection(playerContext, dir)
    PlayerContext.Assert(playerContext, "PlayerAction.FaceOwnerToDirection")
    local owner = playerContext.Owner
    if owner == nil or dir == nil then
        return
    end

    local targetYaw = math.atan2(dir.Y, dir.X) * 180.0 / math.pi
    Reflection.Call(owner, "SetActorRotation", Vector(0.0, 0.0, targetYaw))
end

---@param playerContext PlayerContext
---@return nil
function PlayerAction.SmoothFaceOwnerToDirection(playerContext, dir, dt, turnSpeed)
    PlayerContext.Assert(playerContext, "PlayerAction.SmoothFaceOwnerToDirection")
    local owner = playerContext.Owner
    if owner == nil or dir == nil or dt == nil then
        return
    end

    local currentRot = Reflection.Call(owner, "GetActorRotation")
    if currentRot == nil then
        PlayerAction.FaceOwnerToDirection(playerContext, dir)
        return
    end

    local targetYaw = math.atan2(dir.Y, dir.X) * 180.0 / math.pi
    local deltaYaw = (targetYaw - currentRot.Z + 180.0) % 360.0 - 180.0
    local actionConfig = playerContext.Config.Action
    local alpha = dt * (turnSpeed or actionConfig.AttackTurnSpeed)
    if alpha > 1.0 then
        alpha = 1.0
    end
    local nextYaw = currentRot.Z + deltaYaw * alpha

    Reflection.Call(owner, "SetActorRotation", Vector(currentRot.X, currentRot.Y, nextYaw))
end

local function IsUsableActor(actor)
    return actor ~= nil and actor.IsValid ~= nil and actor:IsValid()
end

local function GetDirectionToActor2D(fromActor, toActor)
    local from = GetActorLocation2D(fromActor)
    local to = GetActorLocation2D(toActor)
    if from == nil or to == nil then
        return nil
    end

    local dir = to - from
    dir.Z = 0.0
    if dir:Length() <= 0.001 then
        return nil
    end

    return dir:Normalized()
end

local function ResolveDashChargingTargetDirection(playerContext)
    local owner = playerContext.Owner
    if owner == nil then
        return nil
    end

    local target = playerContext.Runtime.TargetAssistTarget
    if IsUsableActor(target) then
        local stickyDir = GetDirectionToActor2D(owner, target)
        if stickyDir ~= nil then
            return stickyDir
        end
    end

    local aimDir = PlayerAction.GetOwnerForward2D(playerContext)
    local foundTarget = PlayerTargeting.FindTarget(playerContext, "DashChargeAttack", aimDir)
    if IsUsableActor(foundTarget) then
        return GetDirectionToActor2D(owner, foundTarget)
    end

    return nil
end

---@param playerContext PlayerContext
---@return nil
function PlayerAction.BeginAttackAssist(playerContext, attackIndex)
    PlayerContext.Assert(playerContext, "PlayerAction.BeginAttackAssist")
    PlayerTargeting.BeginAssist(playerContext, "Attack")
end

---@param playerContext PlayerContext
---@return boolean
function PlayerAction.UpdateAttackAssist(playerContext, dt)
    PlayerContext.Assert(playerContext, "PlayerAction.UpdateAttackAssist")
    if PlayerTargeting.IsAssistTurnActive(playerContext) ~= true then
        return false
    end

    local dir = PlayerTargeting.GetAssistDirection(playerContext)
    if dir == nil then
        return false
    end

    PlayerAction.SmoothFaceOwnerToDirection(playerContext, dir, dt, PlayerTargeting.GetTurnSpeed(playerContext))
    return true
end

---@param playerContext PlayerContext
---@return nil
function PlayerAction.EndAttackAssist(playerContext)
    PlayerContext.Assert(playerContext, "PlayerAction.EndAttackAssist")
    PlayerTargeting.ClearAssist(playerContext, false)
end

---@param playerContext PlayerContext
---@return boolean
function PlayerAction.IsAttackBusy(playerContext)
    PlayerContext.Assert(playerContext, "PlayerAction.IsAttackBusy")
    return (playerContext.Action.AttackIndex or 0) > 0
end

---@param playerContext PlayerContext
---@return nil
function PlayerAction.CancelAttack(playerContext, unlockMovement)
    PlayerContext.Assert(playerContext, "PlayerAction.CancelAttack")
    local attackIndex = playerContext.Action.AttackIndex or 0

    playerContext.Action.AttackIndex = 0
    playerContext.Action.AttackInstanceId = nil
    playerContext.Action.ComboWindow = false
    playerContext.Action.ComboQueued = false
    playerContext.Action.AttackEnd = false
    playerContext.Runtime.StepForwardActive = false
    playerContext.Runtime.StepForwardDirection = nil
    PlayerTargeting.ClearAssist(playerContext, false)

    if unlockMovement ~= false then
        SetMovementInputEnabled(playerContext, true)
    end

    if attackIndex > 0 then
        PlayerEvents.EmitAttackEnded(playerContext, { AttackIndex = attackIndex, Canceled = true })
    end
end

local function ResolveHitReaction(playerContext, sourceActor)
    local owner = playerContext.Owner
    local ownerLocation = GetActorLocation2D(owner)
    local sourceLocation = GetActorLocation2D(sourceActor)
    local ownerForward = PlayerAction.GetOwnerForward2D(playerContext)
    local ownerRight = GetOwnerRight2D(playerContext)

    local sourceToOwner = nil
    local ownerToSource = nil
    if ownerLocation ~= nil and sourceLocation ~= nil then
        sourceToOwner = ownerLocation - sourceLocation
        sourceToOwner.Z = 0.0
        if sourceToOwner:Length() > 0.001 then
            sourceToOwner = sourceToOwner:Normalized()
            ownerToSource = sourceToOwner * -1.0
        end
    end

    local hitDirection = "Front"
    if ownerToSource ~= nil and ownerForward ~= nil and ownerRight ~= nil then
        local frontDot = Dot2D(ownerForward, ownerToSource)
        local rightDot = Dot2D(ownerRight, ownerToSource)

        if math.abs(rightDot) > math.abs(frontDot) then
            if rightDot >= 0.0 then
                hitDirection = "Right"
            else
                hitDirection = "Left"
            end
        elseif frontDot >= 0.0 then
            hitDirection = "Front"
        else
            hitDirection = "Back"
        end
    end

    if sourceToOwner == nil then
        if ownerForward ~= nil then
            sourceToOwner = ownerForward * -1.0
        else
            sourceToOwner = Vector(0.0, 0.0, 0.0)
        end
    end

    return hitDirection, sourceToOwner
end

---@param playerContext PlayerContext
---@param hit table
---@return nil
function PlayerAction.BeginHitReaction(playerContext, hit)
    PlayerContext.Assert(playerContext, "PlayerAction.BeginHitReaction")
    hit = hit or {}

    local hitDirection, knockbackDirection = ResolveHitReaction(playerContext, hit.SourceActor)

    PlayerAction.CancelAttack(playerContext, false)
    PlayerAction.CancelDashActions(playerContext, false)
    StopMovementImmediately(playerContext)
    SetMovementInputEnabled(playerContext, false)

    playerContext.Action.HitReactActive = true
    playerContext.Action.HitReactPending = true
    playerContext.Action.HitReactDirection = hitDirection
    playerContext.Action.HitReactElapsed = 0.0
    playerContext.Action.HitReactEnd = false
    playerContext.Runtime.HitKnockbackDirection = knockbackDirection
    playerContext.Runtime.HitKnockbackAppliedDistance = 0.0
end

---@param playerContext PlayerContext
---@return nil
function PlayerAction.EndHitReaction(playerContext)
    PlayerContext.Assert(playerContext, "PlayerAction.EndHitReaction")

    playerContext.Action.HitReactActive = false
    playerContext.Action.HitReactPending = false
    playerContext.Action.HitReactDirection = nil
    playerContext.Action.HitReactElapsed = 0.0
    playerContext.Action.HitReactEnd = false
    playerContext.Runtime.HitKnockbackDirection = nil
    playerContext.Runtime.HitKnockbackAppliedDistance = 0.0

    SetMovementInputEnabled(playerContext, true)
end

---@param playerContext PlayerContext
---@param dt number
---@return nil
function PlayerAction.UpdateHitReaction(playerContext, dt)
    PlayerContext.Assert(playerContext, "PlayerAction.UpdateHitReaction")
    if playerContext.Action.HitReactActive ~= true then
        return
    end

    local owner = playerContext.Owner
    local actionConfig = playerContext.Config.Action
    local duration = actionConfig.HitKnockbackDuration or 0.0
    local distance = actionConfig.HitKnockbackDistance or 0.0
    local dir = playerContext.Runtime.HitKnockbackDirection

    playerContext.Action.HitReactElapsed = (playerContext.Action.HitReactElapsed or 0.0) + (dt or 0.0)

    if owner ~= nil and dir ~= nil and duration > 0.0 and distance ~= 0.0 then
        local alpha = playerContext.Action.HitReactElapsed / duration
        if alpha > 1.0 then
            alpha = 1.0
        end

        local targetDistance = distance * alpha
        local deltaDistance = targetDistance - (playerContext.Runtime.HitKnockbackAppliedDistance or 0.0)
        if math.abs(deltaDistance) > 0.001 then
            Reflection.Call(owner, "AddActorWorldOffset", dir * deltaDistance)
            playerContext.Runtime.HitKnockbackAppliedDistance = targetDistance
        end
    end

    StopMovementImmediately(playerContext)
end

---@param playerContext PlayerContext
---@return nil
function PlayerAction.ApplyMoveInput(playerContext)
    PlayerContext.Assert(playerContext, "PlayerAction.ApplyMoveInput")
    local owner = playerContext.Owner
    if owner == nil then
        return
    end

    local dir = PlayerAction.GetMoveInputWorldDirection(playerContext)
    if dir ~= nil then
        playerContext.Runtime.LastMoveInputDirection = dir
        Reflection.Call(owner, "AddMovementInput", dir, 1.0)
    end
end

local function GetActionInputFrameTime()
    if World ~= nil and World.GetGameTime ~= nil then
        return World.GetGameTime()
    end

    return nil
end

local function UpdateBufferedInputTimers(playerContext, dt)
    local input = playerContext.Input
    local deltaTime = dt or 0.0

    if input.AttackBuffered == true then
        input.AttackBufferTimer = (input.AttackBufferTimer or 0.0) - deltaTime
        if input.AttackBufferTimer <= 0.0 then
            ClearAttackBuffer(playerContext)
        end
    end

    if input.DashBuffered == true then
        input.DashBufferTimer = (input.DashBufferTimer or 0.0) - deltaTime
        if input.DashBufferTimer <= 0.0 then
            ClearDashBuffer(playerContext)
        end
    end
end

local function IsPlayerDead(playerContext)
    return playerContext.Combat ~= nil and playerContext.Combat.IsDead == true
end

local function IsHardActionLocked(playerContext)
    local action = playerContext.Action
    return action.HitReactActive == true
        or action.IsUltimateRunning == true
        or action.IsInUltimateMode == true
        or IsPlayerDead(playerContext)
end

local function IsDashChargeActionActive(playerContext)
    local action = playerContext.Action
    return action.DashChargingActive == true
        or action.DashChargeAttackActive == true
end

local function CanConsumeAttackForStart(playerContext)
    local action = playerContext.Action
    return IsHardActionLocked(playerContext) ~= true
        and IsDashChargeActionActive(playerContext) ~= true
        and action.DashActive ~= true
        and (action.AttackIndex or 0) == 0
end

local function CanConsumeAttackForCombo(playerContext)
    local action = playerContext.Action
    return IsHardActionLocked(playerContext) ~= true
        and IsDashChargeActionActive(playerContext) ~= true
        and (action.AttackIndex or 0) > 0
        and action.ComboWindow == true
        and action.ComboQueued ~= true
end

local function CanDashCancelAttack(playerContext)
    local action = playerContext.Action
    return (action.AttackIndex or 0) > 0
        and action.ComboWindow == true
        and action.AttackEnd ~= true
end

local function ClearQueuedAttackForDashPriority(playerContext)
    local action = playerContext.Action
    if (action.AttackIndex or 0) > 0 then
        action.ComboQueued = false
        ClearAttackBuffer(playerContext)
    end
end

local function CanConsumeDash(playerContext)
    local action = playerContext.Action
    return IsHardActionLocked(playerContext) ~= true
        and action.DashActive ~= true
        and action.DashChargingActive ~= true
        and action.DashChargeAttackActive ~= true
        and ((action.AttackIndex or 0) == 0 or CanDashCancelAttack(playerContext) == true)
end

local function CanEmitDashChargingPressed(playerContext)
    local action = playerContext.Action
    return IsHardActionLocked(playerContext) ~= true
        and action.DashChargingActive ~= true
        and action.DashChargeAttackActive ~= true
        and (action.AttackIndex or 0) == 0
end

---@param playerContext PlayerContext
---@return boolean
function PlayerAction.ShouldChainDashToCharging(playerContext)
    PlayerContext.Assert(playerContext, "PlayerAction.ShouldChainDashToCharging")
    local input = playerContext.Input
    local action = playerContext.Action

    return IsHardActionLocked(playerContext) ~= true
        and action.DashActive == true
        and action.DashEnd == true
        and action.DashChargingActive ~= true
        and action.DashChargeAttackActive ~= true
        and input.DashDown == true
        and input.DashChargingReleased ~= true
        and (action.AttackIndex or 0) == 0
end

---@param playerContext PlayerContext
---@return nil
function PlayerAction.ConsumeDashChargingInput(playerContext)
    PlayerContext.Assert(playerContext, "PlayerAction.ConsumeDashChargingInput")
    playerContext.Input.DashChargingPressed = false
    playerContext.Input.DashChargingConsumedInput = true
    playerContext.Input.DashConsumedInput = true
    ClearDashBuffer(playerContext)
end

---@param playerContext PlayerContext
---@return boolean
function PlayerAction.ConsumeBufferedAttackForCombo(playerContext)
    PlayerContext.Assert(playerContext, "PlayerAction.ConsumeBufferedAttackForCombo")
    if playerContext.Input.AttackBuffered ~= true then
        return false
    end
    if CanConsumeAttackForCombo(playerContext) ~= true then
        return false
    end

    playerContext.Action.ComboQueued = true
    ClearAttackBuffer(playerContext)
    return true
end

---@param playerContext PlayerContext
---@return nil
function PlayerAction.ClearInputBuffers(playerContext)
    PlayerContext.Assert(playerContext, "PlayerAction.ClearInputBuffers")
    ClearInputBuffers(playerContext)
end

---@param playerContext PlayerContext
---@return nil
function PlayerAction.UpdateActionInput(playerContext, dt)
    PlayerContext.Assert(playerContext, "PlayerAction.UpdateActionInput")

    local frameTime = GetActionInputFrameTime()
    if frameTime ~= nil and playerContext.Runtime.LastActionInputUpdateTime == frameTime then
        return
    end
    playerContext.Runtime.LastActionInputUpdateTime = frameTime

    local input = playerContext.Input
    local actionConfig = playerContext.Config.Action

    -- These are 1-frame pulses consumed by the animation state machine.
    input.AttackPressed = false
    input.DashPressed = false
    input.DashChargingPressed = false
    input.DashChargingReleased = false

    local attackDown = ActionDown(playerContext, "Attack")
    local attackStarted = ActionStarted(playerContext, "Attack")
    local dashDown = ActionDown(playerContext, "Dash")
    local dashStarted = ActionStarted(playerContext, "Dash")
    local dashReleased = ActionCompleted(playerContext, "Dash")
    local secondaryDashStarted = ActionStarted(playerContext, "SecondaryDash")
    local wasDashChargingConsumed = input.DashChargingConsumedInput == true

    input.AttackDown = attackDown
    input.DashDown = dashDown
    input.DashReleased = dashReleased

    -- Debug-only hold time. AttackPressed must never be derived from this value.
    if attackDown then
        input.AttackHoldTime = (input.AttackHoldTime or 0.0) + (dt or 0.0)
    else
        input.AttackHoldTime = 0.0
    end

    if IsPlayerDead(playerContext) then
        input.DashHoldTime = 0.0
        input.DashConsumedInput = false
        input.DashChargingConsumedInput = false
        input.DashBlockedUntilReleased = false
        ClearInputBuffers(playerContext)
        return
    end

    if attackStarted then
        if IsDashChargeActionActive(playerContext) == true then
            ClearAttackBuffer(playerContext)
        elseif playerContext.Action.ComboQueued ~= true then
            input.AttackBuffered = true
            if (playerContext.Action.AttackIndex or 0) > 0 then
                input.AttackBufferTimer = actionConfig.ComboInputBufferTime or actionConfig.AttackInputBufferTime or 0.30
            else
                input.AttackBufferTimer = actionConfig.AttackInputBufferTime or 0.25
            end
            input.LastBufferedAction = "Attack"
        end
    end

    if dashStarted or secondaryDashStarted then
        input.DashBuffered = true
        input.DashBufferTimer = actionConfig.DashInputBufferTime or 0.20
        input.LastBufferedAction = "Dash"
    end

    if dashReleased then
        input.DashHoldTime = 0.0
        input.DashConsumedInput = false
        input.DashChargingConsumedInput = false
        input.DashChargingPressed = false
        input.DashBlockedUntilReleased = false
    elseif dashDown then
        input.DashHoldTime = (input.DashHoldTime or 0.0) + (dt or 0.0)
    else
        input.DashHoldTime = 0.0
    end

    UpdateBufferedInputTimers(playerContext, dt)

    if dashReleased and wasDashChargingConsumed == true and playerContext.Action.DashChargingActive == true then
        input.DashChargingReleased = true
    end

    -- DashCharging / DashChargeAttack intentionally drop attack inputs for game-jam simplicity.
    if IsDashChargeActionActive(playerContext) == true then
        ClearAttackBuffer(playerContext)
    end

    PlayerAction.ConsumeBufferedAttackForCombo(playerContext)

    if input.AttackBuffered == true and CanConsumeAttackForStart(playerContext) == true then
        input.AttackPressed = true
        ClearAttackBuffer(playerContext)
        return
    end

    local shouldChainDashToCharging = PlayerAction.ShouldChainDashToCharging(playerContext)

    if dashDown
        and input.DashChargingConsumedInput ~= true
        and CanEmitDashChargingPressed(playerContext) == true
        and ((input.DashHoldTime or 0.0) >= (actionConfig.DashChargingHoldThreshold or 0.0)
            or shouldChainDashToCharging == true) then
        input.DashChargingPressed = true
        PlayerAction.ConsumeDashChargingInput(playerContext)
        input.DashChargingPressed = true
        return
    end

    if input.DashBuffered == true and CanConsumeDash(playerContext) == true then
        ClearQueuedAttackForDashPriority(playerContext)
        input.DashPressed = true
        input.DashConsumedInput = true
        ClearDashBuffer(playerContext)
    end
end

---@param playerContext PlayerContext
---@return nil
function PlayerAction.BeginDash(playerContext)
    PlayerContext.Assert(playerContext, "PlayerAction.BeginDash")
    if playerContext.Runtime.MovementComp ~= nil then
        playerContext.Runtime.DashPrevOrientRotationToMovement =
            Reflection.GetProperty(playerContext.Runtime.MovementComp, "bOrientRotationToMovement")
        SetOrientRotationToMovement(playerContext, false)
    end

    SetMovementInputEnabled(playerContext, false)

    local dashDir, shouldFaceDashDirection = PlayerAction.ResolveDashDirectionAndFacing(playerContext)
    if dashDir == nil then
        SetMovementInputEnabled(playerContext, true)
        return
    end

    if shouldFaceDashDirection == true then
        local _, assistedDir = PlayerTargeting.BeginAssist(playerContext, "Dash", dashDir)
        if assistedDir ~= nil then
            dashDir = assistedDir
        end

        PlayerAction.FaceOwnerToDirection(playerContext, dashDir)
    else
        PlayerTargeting.ClearAssist(playerContext, false)
    end

    playerContext.Runtime.DashMoveDirection = dashDir
    playerContext.Runtime.DashPreserveFacing = shouldFaceDashDirection ~= true

    playerContext.Action.DashActive = true
    playerContext.Action.DashElapsed = 0.0
    playerContext.Action.DashEnd = false

    PlayerEvents.EmitDashStarted(playerContext, { Dir = dashDir })
end

---@param playerContext PlayerContext
---@return nil
function PlayerAction.EndDash(playerContext)
    PlayerContext.Assert(playerContext, "PlayerAction.EndDash")
    playerContext.Action.DashActive = false
    playerContext.Action.DashElapsed = 0.0
    playerContext.Action.DashEnd = false

    if playerContext.Runtime.DashPrevOrientRotationToMovement ~= nil then
        SetOrientRotationToMovement(playerContext, playerContext.Runtime.DashPrevOrientRotationToMovement)
        playerContext.Runtime.DashPrevOrientRotationToMovement = nil
    end

    playerContext.Runtime.DashMoveDirection = nil
    playerContext.Runtime.DashPreserveFacing = false
    PlayerTargeting.ClearAssist(playerContext, false)

    SetMovementInputEnabled(playerContext, true)
    PlayerEvents.EmitDashEnded(playerContext)
end

---@param playerContext PlayerContext
---@return nil
function PlayerAction.UpdateDash(playerContext, dt)
    PlayerContext.Assert(playerContext, "PlayerAction.UpdateDash")
    local owner = playerContext.Owner
    if owner == nil or playerContext.Runtime.DashMoveDirection == nil then
        return
    end

    playerContext.Action.DashElapsed = playerContext.Action.DashElapsed + dt

    local dir = playerContext.Runtime.DashMoveDirection
    dir.Z = 0.0

    if dir:Length() > 0.001 then
        local actionConfig = playerContext.Config.Action
        local moveSpeed = (actionConfig.DashDistance) / (actionConfig.DashDuration)
        Reflection.Call(owner, "AddActorWorldOffset", dir:Normalized() * moveSpeed * dt)
    end

    local actionConfig = playerContext.Config.Action
    if playerContext.Action.DashElapsed >= (actionConfig.DashDuration) then
        playerContext.Action.DashEnd = true
    end
end

---@param playerContext PlayerContext
---@return nil
function PlayerAction.BeginDashCharging(playerContext)
    PlayerContext.Assert(playerContext, "PlayerAction.BeginDashCharging")
    SetMovementInputEnabled(playerContext, false)
    StopMovementImmediately(playerContext)

    playerContext.Action.DashChargingActive = true
    playerContext.Action.DashChargingElapsed = 0.0
    playerContext.Action.DashChargingEnd = false
    playerContext.Input.DashChargingReleased = false
    playerContext.Runtime.DashChargingTurnTarget = "None"

    PlayerEvents.EmitDashChargingStarted(playerContext)
end

---@param playerContext PlayerContext
---@return nil
function PlayerAction.EndDashCharging(playerContext, unlockMovement)
    PlayerContext.Assert(playerContext, "PlayerAction.EndDashCharging")
    playerContext.Action.DashChargingActive = false
    playerContext.Action.DashChargingElapsed = 0.0
    playerContext.Action.DashChargingEnd = false
    playerContext.Input.DashChargingReleased = false
    playerContext.Runtime.DashChargingTurnTarget = "None"

    if unlockMovement ~= false then
        SetMovementInputEnabled(playerContext, true)
    end

    PlayerEvents.EmitDashChargingEnded(playerContext)
end

---@param playerContext PlayerContext
---@return nil
function PlayerAction.UpdateDashCharging(playerContext, dt)
    PlayerContext.Assert(playerContext, "PlayerAction.UpdateDashCharging")
    playerContext.Action.DashChargingElapsed = (playerContext.Action.DashChargingElapsed or 0.0) + (dt or 0.0)
    StopMovementImmediately(playerContext)

    local actionConfig = playerContext.Config.Action
    local targetDir = ResolveDashChargingTargetDirection(playerContext)
    if targetDir ~= nil then
        playerContext.Runtime.DashChargingTurnTarget = "Target"
        PlayerAction.SmoothFaceOwnerToDirection(playerContext, targetDir, dt, actionConfig.DashChargingTargetTurnSpeed or actionConfig.DashChargingTurnSpeed)
        return
    end

    local moveDir = PlayerAction.GetMoveInputWorldDirection(playerContext)
    if moveDir ~= nil then
        playerContext.Runtime.DashChargingTurnTarget = "Input"
        PlayerAction.SmoothFaceOwnerToDirection(playerContext, moveDir, dt, actionConfig.DashChargingTurnSpeed)
        return
    end

    playerContext.Runtime.DashChargingTurnTarget = "None"
end

---@param playerContext PlayerContext
---@return nil
function PlayerAction.BeginDashChargeAttack(playerContext)
    PlayerContext.Assert(playerContext, "PlayerAction.BeginDashChargeAttack")
    SetMovementInputEnabled(playerContext, false)
    StopMovementImmediately(playerContext)

    local aimDir = PlayerAction.GetOwnerForward2D(playerContext) or PlayerAction.ResolveDashDirection(playerContext)
    local _, assistedDir = PlayerTargeting.BeginAssist(playerContext, "DashChargeAttack", aimDir)
    if assistedDir ~= nil then
        PlayerAction.FaceOwnerToDirection(playerContext, assistedDir)
    end

    PlayerAction.StepDashChargeAttackForward(playerContext)

    playerContext.Action.DashChargeAttackActive = true
    playerContext.Action.DashChargeAttackElapsed = 0.0
    playerContext.Action.DashChargeAttackEnd = false

    PlayerEvents.EmitDashChargeAttackStarted(playerContext)
end

---@param playerContext PlayerContext
---@return nil
function PlayerAction.EndDashChargeAttack(playerContext)
    PlayerContext.Assert(playerContext, "PlayerAction.EndDashChargeAttack")
    playerContext.Action.DashChargeAttackActive = false
    playerContext.Action.DashChargeAttackElapsed = 0.0
    playerContext.Action.DashChargeAttackEnd = false
    PlayerTargeting.ClearAssist(playerContext, false)

    SetMovementInputEnabled(playerContext, true)
    PlayerEvents.EmitDashChargeAttackEnded(playerContext)
end

---@param playerContext PlayerContext
---@return nil
function PlayerAction.CancelDashActions(playerContext, unlockMovement)
    PlayerContext.Assert(playerContext, "PlayerAction.CancelDashActions")
    local wasDashActive = playerContext.Action.DashActive == true
    local wasDashChargingActive = playerContext.Action.DashChargingActive == true
    local wasDashChargeAttackActive = playerContext.Action.DashChargeAttackActive == true

    playerContext.Input.DashPressed = false
    playerContext.Input.DashChargingPressed = false
    playerContext.Input.DashChargingReleased = false

    playerContext.Action.DashActive = false
    playerContext.Action.DashElapsed = 0.0
    playerContext.Action.DashEnd = false
    playerContext.Runtime.DashMoveDirection = nil
    playerContext.Runtime.DashPreserveFacing = false

    playerContext.Action.DashChargingActive = false
    playerContext.Action.DashChargingElapsed = 0.0
    playerContext.Action.DashChargingEnd = false
    playerContext.Runtime.DashChargingTurnTarget = "None"

    playerContext.Action.DashChargeAttackActive = false
    playerContext.Action.DashChargeAttackElapsed = 0.0
    playerContext.Action.DashChargeAttackEnd = false
    PlayerTargeting.ClearAssist(playerContext, true)

    if playerContext.Runtime.DashPrevOrientRotationToMovement ~= nil then
        SetOrientRotationToMovement(playerContext, playerContext.Runtime.DashPrevOrientRotationToMovement)
        playerContext.Runtime.DashPrevOrientRotationToMovement = nil
    end

    if unlockMovement ~= false then
        SetMovementInputEnabled(playerContext, true)
    end

    if wasDashActive then
        PlayerEvents.EmitDashEnded(playerContext)
    end
    if wasDashChargingActive then
        PlayerEvents.EmitDashChargingEnded(playerContext)
    end
    if wasDashChargeAttackActive then
        PlayerEvents.EmitDashChargeAttackEnded(playerContext)
    end
end

---@param playerContext PlayerContext
---@return nil
function PlayerAction.UpdateDashChargeAttack(playerContext, dt)
    PlayerContext.Assert(playerContext, "PlayerAction.UpdateDashChargeAttack")
    playerContext.Action.DashChargeAttackElapsed = (playerContext.Action.DashChargeAttackElapsed or 0.0) + (dt or 0.0)

    local dir = PlayerTargeting.GetAssistDirection(playerContext)
    if dir ~= nil and PlayerTargeting.IsAssistTurnActive(playerContext) == true then
        PlayerAction.SmoothFaceOwnerToDirection(playerContext, dir, dt, PlayerTargeting.GetTurnSpeed(playerContext))
    end

    StopMovementImmediately(playerContext)
end

---@param playerContext PlayerContext
---@param notifyName string
---@return nil
function PlayerAction.OnAnimNotify(playerContext, notifyName)
    PlayerContext.Assert(playerContext, "PlayerAction.OnAnimNotify")
    if notifyName == "ComboWindowOpen" then
        playerContext.Action.ComboWindow = true
        PlayerAction.ConsumeBufferedAttackForCombo(playerContext)
    elseif notifyName == "ComboWindowClose" then
        playerContext.Action.ComboWindow = false
    elseif notifyName == "AttackEnd" then
        if playerContext.Action.HitReactActive == true then
            playerContext.Action.HitReactEnd = true
        else
            playerContext.Action.AttackEnd = true
        end
    elseif notifyName == "DashEnd" then
        playerContext.Action.DashEnd = true
    elseif notifyName == "DashChargeAttackEnd" or notifyName == "DashChargingAttackEnd" then
        playerContext.Action.DashChargeAttackEnd = true
    elseif notifyName == "HitReactEnd" or notifyName == "HitEnd" then
        playerContext.Action.HitReactEnd = true
    end
end

---@param playerContext PlayerContext
---@param args table|nil
---@return nil
function PlayerAction.OnSpawnFlyingSlashNotify(playerContext, args)
    PlayerContext.Assert(playerContext, "PlayerAction.OnSpawnFlyingSlashNotify")
    PlayerProjectile.SpawnFlyingSlash(playerContext, args)
end

---@param playerContext PlayerContext
---@return boolean
function PlayerAction.IsUltimateRunning(playerContext)
    PlayerContext.Assert(playerContext, "PlayerAction.IsUltimateRunning")
    return playerContext.Action.IsUltimateRunning == true
end

---@param playerContext PlayerContext
---@return boolean
function PlayerAction.IsInUltimateMode(playerContext)
    PlayerContext.Assert(playerContext, "PlayerAction.IsInUltimateMode")
    return playerContext.Action.IsInUltimateMode == true
end

---@param playerContext PlayerContext
---@param dt number
---@return nil
function PlayerAction.Update(playerContext, dt)
    PlayerContext.Assert(playerContext, "PlayerAction.Update")

    local maxUltimateGauge = playerContext.Combat.MaxUltimateGauge or playerContext.Config.Combat.MaxUltimateGauge or 0
    local ultimateGauge = playerContext.Combat.UltimateGauge or 0

    if not playerContext.Action.IsUltimateRunning
        and ActionStarted(playerContext, "Ultimate")
        and maxUltimateGauge > 0
        and ultimateGauge >= maxUltimateGauge then
        playerContext.Action.IsUltimateRunning = true
        PlayerEvents.EmitUltimateStarted(playerContext)
    end
end

return PlayerAction
