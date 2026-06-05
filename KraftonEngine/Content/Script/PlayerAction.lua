-- 마우스, 키보드 등 입력 Event 처리 및 결과 보관

local PlayerAction = {}

local PlayerConfig = require("PlayerConfig")

local function GetConfig(ctx)
    if ctx ~= nil and ctx.Config ~= nil then
        return ctx.Config
    end

    if ctx ~= nil and ctx.PlayerCtx ~= nil and ctx.PlayerCtx.Config ~= nil then
        return ctx.PlayerCtx.Config
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

local function IsKeyDown(vk)
    if Input ~= nil and Input.GetKey ~= nil then
        return Input.GetKey(vk)
    end

    if Input ~= nil and Input.is_key_down ~= nil then
        return Input.is_key_down(vk)
    end

    return false
end

local function IsKeyPressed(vk)
    if Input ~= nil and Input.GetKeyDown ~= nil then
        return Input.GetKeyDown(vk)
    end

    if Input ~= nil and Input.is_key_pressed ~= nil then
        return Input.is_key_pressed(vk)
    end

    return false
end

local function IsKeyReleased(vk)
    if Input ~= nil and Input.GetKeyUp ~= nil then
        return Input.GetKeyUp(vk)
    end

    return false
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
    ctx.ShiftHoldTime = 0.0
    ctx.ShiftWasDown = false
    ctx.ShiftChargingConsumed = false

    ctx.DashPressed = false
    ctx.DashChargingPressed = false
    ctx.DashChargingReleased = false
end

function PlayerAction.Init(ctx, owner)
    ctx.Owner = owner or ctx.Owner
    ctx.LastMoveInputDirection = nil
    ctx.DashPrevOrientRotationToMovement = nil
    ctx.DashMoveDirection = nil
    ctx.PendingActionEvents = ctx.PendingActionEvents or {}
    ctx.AttackDown = false
    ctx.AttackPressed = false
    ctx.AttackHoldTime = 0.0

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

function PlayerAction.PushEvent(ctx, event)
    if ctx == nil or event == nil then
        return
    end

    ctx.PendingActionEvents = ctx.PendingActionEvents or {}
    table.insert(ctx.PendingActionEvents, event)
end

local function DrainEvents(ctx, result)
    if ctx.PendingActionEvents == nil then
        return
    end

    for _, event in ipairs(ctx.PendingActionEvents) do
        table.insert(result.Events, event)
    end
    ctx.PendingActionEvents = {}
end

function PlayerAction.SetMovementInputEnabled(ctx, enabled)
    SetMovementInputEnabled(ctx, enabled)
end

function PlayerAction.StopMovementImmediately(ctx)
    StopMovementImmediately(ctx)
end

function PlayerAction.StepAttackForward(ctx)
    local owner = GetOwner(ctx)
    if owner == nil then
        return
    end

    local forward = PlayerAction.GetOwnerForward2D(ctx)
    if forward == nil then
        return
    end

    local actionConfig = GetActionConfig(ctx)
    Reflection.Call(owner, "AddActorWorldOffset", forward * (actionConfig.AttackStepForwardDistance or PlayerConfig.Default.Action.AttackStepForwardDistance))
end

function PlayerAction.GetMoveInputWorldDirection(ctx)
    local owner = GetOwner(ctx)
    if owner == nil then
        return nil
    end

    local moveForward = 0.0
    local moveRight = 0.0

    local inputConfig = GetInputConfig(ctx)

    if IsKeyDown(inputConfig.MoveForwardKey or PlayerConfig.Default.Input.MoveForwardKey) then moveForward = moveForward + 1.0 end
    if IsKeyDown(inputConfig.MoveBackwardKey or PlayerConfig.Default.Input.MoveBackwardKey) then moveForward = moveForward - 1.0 end
    if IsKeyDown(inputConfig.MoveRightKey or PlayerConfig.Default.Input.MoveRightKey) then moveRight = moveRight + 1.0 end
    if IsKeyDown(inputConfig.MoveLeftKey or PlayerConfig.Default.Input.MoveLeftKey) then moveRight = moveRight - 1.0 end

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

function PlayerAction.GetOwnerForward2D(ctx)
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

function PlayerAction.ResolveDashDirection(ctx)
    local dir = PlayerAction.GetMoveInputWorldDirection(ctx)

    if dir ~= nil then
        return dir
    end

    if ctx.LastMoveInputDirection ~= nil then
        return ctx.LastMoveInputDirection
    end

    return PlayerAction.GetOwnerForward2D(ctx)
end

function PlayerAction.FaceOwnerToDirection(ctx, dir)
    local owner = GetOwner(ctx)
    if owner == nil or dir == nil then
        return
    end

    local targetYaw = math.atan2(dir.Y, dir.X) * 180.0 / math.pi
    Reflection.Call(owner, "SetActorRotation", Vector(0.0, 0.0, targetYaw))
end

function PlayerAction.SmoothFaceOwnerToDirection(ctx, dir, dt)
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
    local alpha = dt * (actionConfig.AttackTurnSpeed or PlayerConfig.Default.Action.AttackTurnSpeed)
    if alpha > 1.0 then
        alpha = 1.0
    end
    local nextYaw = currentRot.Z + deltaYaw * alpha

    Reflection.Call(owner, "SetActorRotation", Vector(currentRot.X, currentRot.Y, nextYaw))
end

function PlayerAction.ApplyMoveInput(ctx)
    local owner = GetOwner(ctx)
    if owner == nil then
        return
    end

    local dir = PlayerAction.GetMoveInputWorldDirection(ctx)
    if dir ~= nil then
        ctx.LastMoveInputDirection = dir
        Reflection.Call(owner, "AddMovementInput", dir, 1.0)
    end

    local inputConfig = GetInputConfig(ctx)

    if IsKeyPressed(inputConfig.JumpKey or PlayerConfig.Default.Input.JumpKey) then
        Reflection.Call(owner, "Jump")
    end
end

function PlayerAction.UpdateActionInput(ctx, dt)
    if ctx == nil then
        return
    end

    local inputConfig = GetInputConfig(ctx)
    local actionConfig = GetActionConfig(ctx)
    local attackDown = IsKeyDown(inputConfig.AttackKey or PlayerConfig.Default.Input.AttackKey)

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

    local dashKey = inputConfig.DashKey or PlayerConfig.Default.Input.DashKey
    local shiftDown = IsKeyDown(dashKey)
    local shiftReleased = IsKeyReleased(dashKey)

    if shiftDown then
        ctx.ShiftHoldTime = (ctx.ShiftHoldTime or 0.0) + (dt or 0.0)

        if ctx.ShiftChargingConsumed ~= true and ctx.ShiftHoldTime >= (actionConfig.DashChargingHoldThreshold or PlayerConfig.Default.Action.DashChargingHoldThreshold) then
            ctx.DashChargingPressed = true
            ctx.ShiftChargingConsumed = true
        end
    end

    if (shiftReleased or (ctx.ShiftWasDown == true and not shiftDown)) then
        if ctx.ShiftChargingConsumed == true then
            ctx.DashChargingReleased = true
        else
            ctx.DashPressed = true
            ctx.DashSlashPressed = true -- compatibility for older animation scripts
        end

        ctx.ShiftHoldTime = 0.0
        ctx.ShiftChargingConsumed = false
    end

    ctx.ShiftWasDown = shiftDown
end

function PlayerAction.BeginDash(ctx)
    if ctx.MovementComp ~= nil then
        ctx.DashPrevOrientRotationToMovement =
            Reflection.GetProperty(ctx.MovementComp, "bOrientRotationToMovement")
        SetOrientRotationToMovement(ctx, false)
    end

    SetMovementInputEnabled(ctx, false)

    local dashDir = PlayerAction.ResolveDashDirection(ctx)
    PlayerAction.FaceOwnerToDirection(ctx, dashDir)
    ctx.DashMoveDirection = dashDir

    ctx.DashActive = true
    ctx.DashElapsed = 0.0
    ctx.DashEnd = false

    ctx.DashSlashActive = true
    ctx.DashSlashElapsed = 0.0
    ctx.DashSlashEnd = false
    ctx.DashSlashMoveDirection = dashDir

    PlayerAction.PushEvent(ctx.PlayerCtx or ctx, { Type = "DashStart", Dir = dashDir })
end

function PlayerAction.EndDash(ctx)
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

    SetMovementInputEnabled(ctx, true)
    PlayerAction.PushEvent(ctx.PlayerCtx or ctx, { Type = "DashEnd" })
end

function PlayerAction.UpdateDash(ctx, dt)
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

function PlayerAction.BeginDashCharging(ctx)
    SetMovementInputEnabled(ctx, false)
    StopMovementImmediately(ctx)

    ctx.DashChargingActive = true
    ctx.DashChargingElapsed = 0.0
    ctx.DashChargingEnd = false
    ctx.DashChargingReleased = false

    PlayerAction.PushEvent(ctx.PlayerCtx or ctx, { Type = "DashChargingStart" })
end

function PlayerAction.EndDashCharging(ctx, unlockMovement)
    ctx.DashChargingActive = false
    ctx.DashChargingElapsed = 0.0
    ctx.DashChargingEnd = false
    ctx.DashChargingReleased = false

    if unlockMovement ~= false then
        SetMovementInputEnabled(ctx, true)
    end

    PlayerAction.PushEvent(ctx.PlayerCtx or ctx, { Type = "DashChargingEnd" })
end

function PlayerAction.UpdateDashCharging(ctx, dt)
    ctx.DashChargingElapsed = (ctx.DashChargingElapsed or 0.0) + (dt or 0.0)
    StopMovementImmediately(ctx)
end

function PlayerAction.BeginDashChargeAttack(ctx)
    SetMovementInputEnabled(ctx, false)
    StopMovementImmediately(ctx)

    ctx.DashChargeAttackActive = true
    ctx.DashChargeAttackElapsed = 0.0
    ctx.DashChargeAttackEnd = false

    PlayerAction.PushEvent(ctx.PlayerCtx or ctx, { Type = "DashChargeAttackStart" })
end

function PlayerAction.EndDashChargeAttack(ctx)
    ctx.DashChargeAttackActive = false
    ctx.DashChargeAttackElapsed = 0.0
    ctx.DashChargeAttackEnd = false

    SetMovementInputEnabled(ctx, true)
    PlayerAction.PushEvent(ctx.PlayerCtx or ctx, { Type = "DashChargeAttackEnd" })
end

function PlayerAction.UpdateDashChargeAttack(ctx, dt)
    ctx.DashChargeAttackElapsed = (ctx.DashChargeAttackElapsed or 0.0) + (dt or 0.0)
    StopMovementImmediately(ctx)
end

-- Compatibility wrappers for scripts that still call DashSlash.
function PlayerAction.BeginDashSlash(ctx)
    PlayerAction.BeginDash(ctx)
end

function PlayerAction.EndDashSlash(ctx)
    PlayerAction.EndDash(ctx)
end

function PlayerAction.UpdateDashSlash(ctx, dt)
    PlayerAction.UpdateDash(ctx, dt)
end

function PlayerAction.IsUltimateRunning(ctx)
    return ctx ~= nil and ctx.IsUltimateRunning == true
end

function PlayerAction.IsInUltimateMode(ctx)
    return ctx ~= nil and ctx.IsInUltimateMode == true
end

function PlayerAction.Update(ctx, dt)
    local result = { Events = {} }

    if ctx == nil then
        return result
    end

    PlayerAction.UpdateActionInput(ctx, dt)
    DrainEvents(ctx, result)

    local inputConfig = GetInputConfig(ctx)

    if not ctx.IsUltimateRunning and IsKeyPressed(inputConfig.UltimateKey or PlayerConfig.Default.Input.UltimateKey) then
        ctx.IsUltimateRunning = true
        table.insert(result.Events, { Type = "UltimateStart" })
    end

    return result
end

return PlayerAction
