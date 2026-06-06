-- Actor 별 ULuaScriptComponent 에 붙는 Lua 객체라고 볼 수 있음


-- 전역 객체라고 볼 수 있음
-- 호출자가 ctx 를 보내야만 전역 객체에서 구분해서 처리 가능
local PlayerAction = require("PlayerAction")
local CombatContext = require("CombatContext")
local PlayerFeedback = require("PlayerFeedback")
local PlayerConfig = require("PlayerConfig")

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

function PlayerCharacter.SetKatanaTrailActive(active)
    PlayerFeedback.SetKatanaTrailActive(GetPlayerCtx(nil), active)
end

function BeginPlay()
    -- 여러 ULuaScriptComponent 의 PlayerCharacter.lua 를 구분할 수 있는 데이터
    ctx = {
        Owner = obj,  -- Actor
        Component = this,
        Config = PlayerConfig.Create(),
        State = "Locomotion",
        HP = PlayerConfig.Default.Combat.MaxHP,
        MaxHP = PlayerConfig.Default.Combat.MaxHP,
        UltimateGauge = 0,
        MaxUltimateGauge = PlayerConfig.Default.Combat.MaxUltimateGauge,
        CurrentThreat = nil,
        IsDead = false,
        InvincibleUntil = 0.0,
        DodgeInvincibleUntil = 0.0,
        PerfectDodgeConsumedUntil = 0.0,
        RecentHitIds = {},
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

function OnOverlap(OtherActor, OverlappedComponent, OtherComp)
    CombatContext.TryResolvePlayerOverlapHit(GetPlayerCtx(nil), OtherActor, OverlappedComponent, OtherComp)
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
