-- Player, Boss 를 등록해 서로에 대한 이벤트 처리

local CombatContext = {}

local PlayerConfig = require("PlayerConfig")

local playersByOwner = {}

local function GetOwnerKey(owner)
    if owner == nil then
        return nil
    end

    return owner.UUID or tostring(owner)
end

local function GetCombatConfig(ctx)
    if ctx ~= nil and ctx.Config ~= nil and ctx.Config.Combat ~= nil then
        return ctx.Config.Combat
    end

    return PlayerConfig.Default.Combat
end

function CombatContext.RegisterPlayer(ctx)
    if ctx == nil or ctx.Owner == nil then
        return
    end

    ctx.MaxUltimateGauge = GetCombatConfig(ctx).MaxUltimateGauge or PlayerConfig.Default.Combat.MaxUltimateGauge
    playersByOwner[GetOwnerKey(ctx.Owner)] = ctx
end

function CombatContext.UnregisterPlayer(ctx)
    if ctx == nil or ctx.Owner == nil then
        return
    end

    local key = GetOwnerKey(ctx.Owner)
    if playersByOwner[key] == ctx then
        playersByOwner[key] = nil
    end
end

function CombatContext.GetPlayerByOwner(owner)
    return playersByOwner[GetOwnerKey(owner)]
end

function CombatContext.SetCurrentThreat(ctx, threat)
    if ctx ~= nil then
        ctx.CurrentThreat = threat
    end
end

function CombatContext.GetCurrentThreat(ctx)
    if ctx == nil then
        return nil
    end

    return ctx.CurrentThreat
end

local function AddGauge(ctx, amount)
    if ctx == nil or amount == nil then
        return
    end

    local combatConfig = GetCombatConfig(ctx)
    local maxGauge = combatConfig.MaxUltimateGauge or ctx.MaxUltimateGauge or PlayerConfig.Default.Combat.MaxUltimateGauge
    local gauge = (ctx.UltimateGauge or 0) + amount
    if gauge < 0 then gauge = 0 end
    if gauge > maxGauge then gauge = maxGauge end
    ctx.UltimateGauge = gauge
    ctx.MaxUltimateGauge = maxGauge
end

function CombatContext.HandlePlayerResult(ctx, result)
    if ctx == nil or result == nil or result.Events == nil then
        return
    end

    for _, event in ipairs(result.Events) do
        if event.Type == "PerfectDodge" then
            CombatContext.SetCurrentThreat(ctx, event.Threat)
            AddGauge(ctx, event.GaugeDelta or 0)
        elseif event.Type == "AttackHit" then
            AddGauge(ctx, event.GaugeDelta or 0)
        elseif event.Type == "UltimateStart" then
            ctx.UltimateGauge = 0
        elseif event.Type == "GaugeChanged" then
            ctx.UltimateGauge = event.Value
            local combatConfig = GetCombatConfig(ctx)
            ctx.MaxUltimateGauge = event.MaxValue or combatConfig.MaxUltimateGauge or ctx.MaxUltimateGauge
        end
    end
end

-- ════════════════════════════════════════════
-- 보스 관련 (Boss/ 에서 호출)
-- ════════════════════════════════════════════

local bossRef             = nil   -- 보스 액터
local bossBB              = nil   -- 보스 런타임 Blackboard
local bossBBConfig        = nil   -- 보스 수치 Blackboard
local perfectDodgeActive  = false -- 퍼펙트 회피 윈도우 활성 여부

-- ⑥ 재시작/레벨 언로드 시 BossCharacter.EndPlay 에서 호출
function CombatContext.Clear()
    bossRef            = nil
    bossBB             = nil
    bossBBConfig       = nil
    perfectDodgeActive = false
end

-- 보스 등록 (BossCharacter.BeginPlay 에서 호출)
function CombatContext.RegisterBoss(obj, bb, BB)
    bossRef      = obj
    bossBB       = bb
    bossBBConfig = BB
end

-- 퍼펙트 회피 윈도우 열기 (BossAttacks.Pattern3 에서 호출)
function CombatContext.BeginPerfectDodgeWindow(duration)
    perfectDodgeActive = true
    StartCoroutine(function()
        Wait(duration)
        if perfectDodgeActive then
            perfectDodgeActive = false
        end
    end)
end

-- 플레이어 회피 입력 시 호출 (PlayerAction.lua 연동 - 2단계)
function CombatContext.OnPlayerDodge()
    if perfectDodgeActive then
        CombatContext.TriggerPerfectDodge()
    end
end

-- 퍼펙트 회피 발동: Slomo 적용
function CombatContext.TriggerPerfectDodge()
    perfectDodgeActive = false

    -- ⑥ bossRef 유효성 검증 (재시작 시 dangling 참조 방지)
    if not bossRef or not bossRef:IsValid() then return end
    if not bossBB or not bossBBConfig then return end

    local cfg = bossBBConfig.P3
    if cfg == nil then return end

    -- ActionComponent 로 실제 Slomo 걸기 (시각/물리 효과)
    local actionComp = bossRef:GetActionComponent()
    if actionComp then
        actionComp:Slomo(cfg.PERFECT_SLOMO_DURATION, cfg.PERFECT_SLOMO_SCALE)
    end

    -- ⑤ Lua TimeScale 도 동기화 → Tick 의 scaledDt 에 반영
    bossBB.TimeScale      = cfg.PERFECT_SLOMO_SCALE
    bossBB.SlomoRemaining = cfg.PERFECT_SLOMO_DURATION

    print("[CombatContext] 퍼펙트 회피 발동! Slomo x"
          .. cfg.PERFECT_SLOMO_SCALE
          .. " / " .. cfg.PERFECT_SLOMO_DURATION .. "s")
end

return CombatContext
