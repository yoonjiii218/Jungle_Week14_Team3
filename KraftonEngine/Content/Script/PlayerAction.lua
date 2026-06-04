-- 마우스, 키보드 등 입력 Event 처리 및 결과 보관

local PlayerAction = {}

local VK_W = string.byte("W")
local VK_A = string.byte("A")
local VK_S = string.byte("S")
local VK_D = string.byte("D")
local VK_Q = string.byte("Q")
local VK_SPACE = 0x20

local DASH_SLASH_DISTANCE = 8.0
local DASH_SLASH_DURATION = 0.2
local ATTACK_STEP_FORWARD_DISTANCE = 1.5
local ATTACK_TURN_SPEED = 12.0

local function IsKeyDown(vk)
    if Input ~= nil and Input.GetKey ~= nil then
        return Input.GetKey(vk)
    end

    if Input ~= nil and Input.is_key_down ~= nil then
        return Input.is_key_down(vk)
    end

    if Anim ~= nil and Anim.is_key_down ~= nil then
        return Anim.is_key_down(vk)
    end

    if Anim ~= nil and Anim.is_key_pressed ~= nil then
        return Anim.is_key_pressed(vk)
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

    if Anim ~= nil and Anim.is_key_pressed ~= nil then
        return Anim.is_key_pressed(vk)
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

function PlayerAction.Init(ctx, owner)
    ctx.Owner = owner or ctx.Owner
    ctx.LastMoveInputDirection = nil
    ctx.DashSlashPrevOrientRotationToMovement = nil
    ctx.DashSlashMoveDirection = nil
    ctx.PendingActionEvents = ctx.PendingActionEvents or {}
    ctx.ShiftHoldTime = 0.0
    ctx.ShiftWasDown = false

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

    Reflection.Call(owner, "AddActorWorldOffset", forward * ATTACK_STEP_FORWARD_DISTANCE)
end

function PlayerAction.GetMoveInputWorldDirection(ctx)
    local owner = GetOwner(ctx)
    if owner == nil then
        return nil
    end

    local moveForward = 0.0
    local moveRight = 0.0

    if IsKeyDown(VK_W) then moveForward = moveForward + 1.0 end
    if IsKeyDown(VK_S) then moveForward = moveForward - 1.0 end
    if IsKeyDown(VK_D) then moveRight = moveRight + 1.0 end
    if IsKeyDown(VK_A) then moveRight = moveRight - 1.0 end

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
    local alpha = dt * ATTACK_TURN_SPEED
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

    if IsKeyPressed(VK_SPACE) then
        Reflection.Call(owner, "Jump")
    end
end

function PlayerAction.BeginDashSlash(ctx)
    if ctx.MovementComp ~= nil then
        ctx.DashSlashPrevOrientRotationToMovement =
            Reflection.GetProperty(ctx.MovementComp, "bOrientRotationToMovement")
        SetOrientRotationToMovement(ctx, false)
    end

    SetMovementInputEnabled(ctx, false)

    local dashDir = PlayerAction.ResolveDashDirection(ctx)
    PlayerAction.FaceOwnerToDirection(ctx, dashDir)
    ctx.DashSlashMoveDirection = dashDir

    ctx.DashSlashActive = true
    ctx.DashSlashElapsed = 0.0
    ctx.DashSlashEnd = false

    PlayerAction.PushEvent(ctx.PlayerCtx or ctx, { Type = "DashSlashStart", Dir = dashDir })
end

function PlayerAction.EndDashSlash(ctx)
    ctx.DashSlashActive = false
    ctx.DashSlashElapsed = 0.0
    ctx.DashSlashEnd = false

    if ctx.DashSlashPrevOrientRotationToMovement ~= nil then
        SetOrientRotationToMovement(ctx, ctx.DashSlashPrevOrientRotationToMovement)
        ctx.DashSlashPrevOrientRotationToMovement = nil
    end

    ctx.DashSlashMoveDirection = nil

    SetMovementInputEnabled(ctx, true)
    PlayerAction.PushEvent(ctx.PlayerCtx or ctx, { Type = "DashSlashEnd" })
end

function PlayerAction.UpdateDashSlash(ctx, dt)
    local owner = GetOwner(ctx)
    if owner == nil or ctx.DashSlashMoveDirection == nil then
        return
    end

    ctx.DashSlashElapsed = ctx.DashSlashElapsed + dt

    local dir = ctx.DashSlashMoveDirection
    dir.Z = 0.0

    if dir:Length() > 0.001 then
        local moveSpeed = DASH_SLASH_DISTANCE / DASH_SLASH_DURATION
        Reflection.Call(owner, "AddActorWorldOffset", dir:Normalized() * moveSpeed * dt)
    end

    if ctx.DashSlashElapsed >= DASH_SLASH_DURATION then
        ctx.DashSlashEnd = true
    end
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

    DrainEvents(ctx, result)

    if not ctx.IsUltimateRunning and IsKeyPressed(VK_Q) then
        ctx.IsUltimateRunning = true
        table.insert(result.Events, { Type = "UltimateStart" })
    end

    return result
end

return PlayerAction
