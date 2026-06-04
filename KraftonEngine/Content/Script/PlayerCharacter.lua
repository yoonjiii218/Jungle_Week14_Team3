-- Actor 별 ULuaScriptComponent 에 붙는 Lua 객체라고 볼 수 있음


-- 전역 객체라고 볼 수 있음
-- 호출자가 ctx 를 보내야만 전역 객체에서 구분해서 처리 가능
local PlayerAction = require("PlayerAction")
local CombatContext = require("CombatContext")
local PlayerFeedback = require("PlayerFeedback")

local PlayerCharacter = {}
local ctx = nil

local function GetPlayerCtx(fallbackCtx)
    if fallbackCtx ~= nil and fallbackCtx.PlayerCtx ~= nil then
        return fallbackCtx.PlayerCtx
    end

    if fallbackCtx ~= nil and fallbackCtx.Owner ~= nil then
        local registered = CombatContext.GetPlayerByOwner(fallbackCtx.Owner)
        if registered ~= nil then
            return registered
        end
    end

    if obj ~= nil then
        local registered = CombatContext.GetPlayerByOwner(obj)
        if registered ~= nil then
            return registered
        end
    end

    return ctx or fallbackCtx
end

function PlayerCharacter.Initialize(actionCtx, owner)
    PlayerAction.Init(actionCtx, owner)
    actionCtx.PlayerCtx = CombatContext.GetPlayerByOwner(owner)
end

function PlayerCharacter.SetMovementInputEnabled(actionCtx, enabled)
    PlayerAction.SetMovementInputEnabled(actionCtx, enabled)
end

function PlayerCharacter.StopMovementImmediately(actionCtx)
    PlayerAction.StopMovementImmediately(actionCtx)
end

function PlayerCharacter.StepAttackForward(actionCtx)
    PlayerAction.StepAttackForward(actionCtx)
end

function PlayerCharacter.GetMoveInputWorldDirection(actionCtx)
    return PlayerAction.GetMoveInputWorldDirection(actionCtx)
end

function PlayerCharacter.GetOwnerForward2D(actionCtx)
    return PlayerAction.GetOwnerForward2D(actionCtx)
end

function PlayerCharacter.ResolveDashDirection(actionCtx)
    return PlayerAction.ResolveDashDirection(actionCtx)
end

function PlayerCharacter.FaceOwnerToDirection(actionCtx, dir)
    PlayerAction.FaceOwnerToDirection(actionCtx, dir)
end

function PlayerCharacter.SmoothFaceOwnerToDirection(actionCtx, dir, dt)
    PlayerAction.SmoothFaceOwnerToDirection(actionCtx, dir, dt)
end

function PlayerCharacter.ApplyMoveInput(actionCtx)
    PlayerAction.ApplyMoveInput(actionCtx)
end

function PlayerCharacter.BeginDash(actionCtx)
    actionCtx.PlayerCtx = GetPlayerCtx(actionCtx)
    PlayerAction.BeginDash(actionCtx)
end

function PlayerCharacter.EndDash(actionCtx)
    actionCtx.PlayerCtx = GetPlayerCtx(actionCtx)
    PlayerAction.EndDash(actionCtx)
end

function PlayerCharacter.UpdateDash(actionCtx, dt)
    PlayerAction.UpdateDash(actionCtx, dt)
end

function PlayerCharacter.BeginDashCharging(actionCtx)
    actionCtx.PlayerCtx = GetPlayerCtx(actionCtx)
    PlayerAction.BeginDashCharging(actionCtx)
end

function PlayerCharacter.EndDashCharging(actionCtx, unlockMovement)
    actionCtx.PlayerCtx = GetPlayerCtx(actionCtx)
    PlayerAction.EndDashCharging(actionCtx, unlockMovement)
end

function PlayerCharacter.UpdateDashCharging(actionCtx, dt)
    PlayerAction.UpdateDashCharging(actionCtx, dt)
end

function PlayerCharacter.BeginDashChargeAttack(actionCtx)
    actionCtx.PlayerCtx = GetPlayerCtx(actionCtx)
    PlayerAction.BeginDashChargeAttack(actionCtx)
end

function PlayerCharacter.EndDashChargeAttack(actionCtx)
    actionCtx.PlayerCtx = GetPlayerCtx(actionCtx)
    PlayerAction.EndDashChargeAttack(actionCtx)
end

function PlayerCharacter.UpdateDashChargeAttack(actionCtx, dt)
    PlayerAction.UpdateDashChargeAttack(actionCtx, dt)
end

-- Compatibility wrappers for older scripts.
function PlayerCharacter.BeginDashSlash(actionCtx)
    PlayerCharacter.BeginDash(actionCtx)
end

function PlayerCharacter.EndDashSlash(actionCtx)
    PlayerCharacter.EndDash(actionCtx)
end

function PlayerCharacter.UpdateDashSlash(actionCtx, dt)
    PlayerCharacter.UpdateDash(actionCtx, dt)
end

function PlayerCharacter.SetKatanaTrailActive(active)
    PlayerFeedback.SetKatanaTrailActive(GetPlayerCtx(nil), active)
end

function PlayerCharacter.IsUltimateRunning(actionCtx)
    return PlayerAction.IsUltimateRunning(GetPlayerCtx(actionCtx))
end

function PlayerCharacter.IsInUltimateMode(actionCtx)
    return PlayerAction.IsInUltimateMode(GetPlayerCtx(actionCtx))
end

function BeginPlay()
    -- 여러 ULuaScriptComponent 의 PlayerCharacter.lua 를 구분할 수 있는 데이터
    ctx = {
        Owner = obj,  -- Actor
        Component = this,
        State = "Locomotion",
        UltimateGauge = 0,
        MaxUltimateGauge = 100,
        CurrentThreat = nil,
        IsUltimateRunning = false,
        IsInUltimateMode = false,
        PendingActionEvents = {}
    }

    PlayerAction.Init(ctx, obj)
    CombatContext.RegisterPlayer(ctx)  -- Boss, Player 를 모두 등록해서 사용하는 객체
    PlayerFeedback.Init(ctx)

    print("[BeginPlay] " .. obj.UUID)
end

function EndPlay()
    CombatContext.UnregisterPlayer(ctx)
    PlayerFeedback.Shutdown(ctx)
    ctx = nil

    print("[EndPlay] " .. obj.UUID)
end

function OnOverlap(OtherActor)
end

function Tick(dt)
    -- 코루틴 쓰려면 꼭 넣어야 함
    UpdateCoroutines(dt)

    -- 입력에 대한 결과 받아옴
    local result = PlayerAction.Update(ctx, dt)

    -- 결과 기반 처리
    CombatContext.HandlePlayerResult(ctx, result)
    PlayerFeedback.HandlePlayerResult(ctx, result)
end

return PlayerCharacter
