-- Combat/HitTypes.lua
-- Defines HitRequest / HitResult contracts and constructors.

local Strict = require("Core/Strict")
local PlayerContext = require("Player/PlayerContext")
local PlayerConfig = require("Config/PlayerConfig")

local HitTypes = {}

---@class HitRequest
---@field Kind string
---@field SourceActor any
---@field SourceTeam string
---@field TargetActor any
---@field TargetTeam string
---@field AttackId string
---@field AttackInstanceId string|nil
---@field AttackIndex integer|nil
---@field Damage number
---@field GaugeDelta number
---@field CanPerfectDodge boolean|nil
---@field HitStopDuration number|nil
---@field HitboxComponent any
---@field TargetComponent any
---@field HitResult any

---@class HitResult
---@field Kind string
---@field Applied boolean
---@field Reason string|nil
---@field Target string|nil
---@field Damage number|nil
---@field HP number|nil
---@field MaxHP number|nil

local function Now()
    if World ~= nil and World.GetGameTime ~= nil then
        return World.GetGameTime() or 0.0
    end
    return 0.0
end

local function Create(args, caller)
    Strict.AssertTable(args, "args", caller)
    Strict.AssertNotNil(args.SourceActor, "args.SourceActor", caller)
    Strict.AssertNotNil(args.TargetActor, "args.TargetActor", caller)
    Strict.AssertString(args.SourceTeam, "args.SourceTeam", caller)
    Strict.AssertString(args.TargetTeam, "args.TargetTeam", caller)
    Strict.AssertString(args.AttackId, "args.AttackId", caller)

    local hitRequest = {
        Kind = "HitRequest",
        SourceActor = args.SourceActor,
        SourceTeam = args.SourceTeam,
        TargetActor = args.TargetActor,
        TargetTeam = args.TargetTeam,
        AttackId = args.AttackId,
        AttackInstanceId = args.AttackInstanceId or (args.AttackId .. "_" .. tostring(Now())),
        AttackIndex = args.AttackIndex,
        Damage = args.Damage or 0,
        GaugeDelta = args.GaugeDelta or 0,
        CanPerfectDodge = args.CanPerfectDodge,
        HitStopDuration = args.HitStopDuration,
        HitboxComponent = args.HitboxComponent,
        TargetComponent = args.TargetComponent,
        HitResult = args.HitResult,
        SlomoDuration = args.SlomoDuration,
        SlomoScale = args.SlomoScale,
        InvincibleDuration = args.InvincibleDuration,
        DuplicateHitLifetime = args.DuplicateHitLifetime,
    }

    return hitRequest
end

-- =========================================================
-- Public API
-- =========================================================

---@param args table
---@return HitRequest
function HitTypes.CreatePlayerAttack(args)
    args = args or {}
    args.SourceTeam = args.SourceTeam or "Player"
    args.TargetTeam = args.TargetTeam or "Enemy"
    return Create(args, "HitTypes.CreatePlayerAttack")
end

---@param args table
---@return HitRequest
function HitTypes.CreateBossAttack(args)
    args = args or {}
    args.SourceTeam = args.SourceTeam or "Enemy"
    args.TargetTeam = args.TargetTeam or "Player"
    args.CanPerfectDodge = args.CanPerfectDodge ~= false
    return Create(args, "HitTypes.CreateBossAttack")
end


---@param args table
---@return HitRequest
function HitTypes.CreatePlayerAttackFromState(args)
    Strict.AssertTable(args, "args", "HitTypes.CreatePlayerAttackFromState")
    local player = PlayerContext.Assert(args.Player, "HitTypes.CreatePlayerAttackFromState")
    local action = player.Action
    local combatConfig = player.Config and player.Config.Combat or PlayerConfig.Default.Combat

    local attackIndex = action.AttackIndex or 0
    local attackId = "PlayerAttack" .. tostring(attackIndex)
    local attackInstanceId = action.AttackInstanceId or (attackId .. "_" .. tostring(Now()))
    local damage = combatConfig.AttackDamages and combatConfig.AttackDamages[attackIndex] or 10
    local gaugeDelta = combatConfig.AttackHitGaugeDelta or 0

    if action.DashChargeAttackActive == true then
        attackId = "PlayerDashChargeAttack"
        attackInstanceId = action.DashChargeAttackInstanceId or (attackId .. "_" .. tostring(Now()))
        damage = combatConfig.DashChargeAttackDamage or damage
        gaugeDelta = combatConfig.DashChargeAttackGaugeDelta or gaugeDelta
    elseif action.IsInUltimateMode == true then
        attackId = "PlayerUltimate"
        attackInstanceId = action.UltimateAttackInstanceId or (attackId .. "_" .. tostring(Now()))
        damage = combatConfig.UltimateDamage or damage
        gaugeDelta = 0
    end

    return HitTypes.CreatePlayerAttack({
        SourceActor = player.Owner,
        TargetActor = args.TargetActor,
        AttackId = attackId,
        AttackInstanceId = attackInstanceId,
        AttackIndex = attackIndex,
        Damage = damage,
        GaugeDelta = gaugeDelta,
        HitStopDuration = args.HitStopDuration,
        HitboxComponent = args.HitboxComponent,
        TargetComponent = args.TargetComponent,
        HitResult = args.HitResult,
    })
end

---@param hitRequest HitRequest
---@param caller string
---@return HitRequest
function HitTypes.AssertHitRequest(hitRequest, caller)
    Strict.AssertKind(hitRequest, "HitRequest", "hitRequest", caller or "HitTypes.AssertHitRequest")
    Strict.AssertNotNil(hitRequest.SourceActor, "hitRequest.SourceActor", caller or "HitTypes.AssertHitRequest")
    Strict.AssertNotNil(hitRequest.TargetActor, "hitRequest.TargetActor", caller or "HitTypes.AssertHitRequest")
    Strict.AssertString(hitRequest.SourceTeam, "hitRequest.SourceTeam", caller or "HitTypes.AssertHitRequest")
    Strict.AssertString(hitRequest.TargetTeam, "hitRequest.TargetTeam", caller or "HitTypes.AssertHitRequest")
    Strict.AssertString(hitRequest.AttackId, "hitRequest.AttackId", caller or "HitTypes.AssertHitRequest")
    if type(hitRequest.Damage) ~= "number" then
        hitRequest.Damage = 0
    end
    if type(hitRequest.GaugeDelta) ~= "number" then
        hitRequest.GaugeDelta = 0
    end
    return hitRequest
end

---@param args table
---@return HitResult
function HitTypes.Result(args)
    args = args or {}
    args.Kind = "HitResult"
    args.Applied = args.Applied == true
    return args
end

return HitTypes
