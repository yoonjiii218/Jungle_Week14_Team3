-- Player, Boss 를 등록해 서로에 대한 이벤트 처리

local CombatContext = {}

local PlayerConfig = require("PlayerConfig")

local playersByOwner = {}
local bossRef      = nil   -- 보스 액터
local bossBB       = nil   -- 보스 런타임 Blackboard
local bossBBConfig = nil   -- 보스 수치 Blackboard

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

function CombatContext.GetFirstPlayer()
    for _, ctx in pairs(playersByOwner) do
        return ctx
    end
    return nil
end

function CombatContext.HasPlayer()
    return CombatContext.GetFirstPlayer() ~= nil
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

local PushUltimateToGameFlow

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
    PushUltimateToGameFlow(ctx)
end

local function Clamp(value, minValue, maxValue)
    if value < minValue then return minValue end
    if value > maxValue then return maxValue end
    return value
end

local function GetGameFlowDirector()
    if GameFlow ~= nil and GameFlow.GetDirector ~= nil then
        return GameFlow.GetDirector()
    end
    return nil
end

local function PushPlayerHPToGameFlow(player)
    local director = GetGameFlowDirector()
    if director == nil or player == nil then return end
    local maxHP = player.MaxHP or GetCombatConfig(player).MaxHP or 100.0
    director:SetPlayerHP(player.HP or maxHP, maxHP)
end

local function PushBossHPToGameFlow()
    local director = GetGameFlowDirector()
    if director == nil or bossBB == nil then return end
    director:SetBossHP(bossBB.HP or 0.0, bossBB.MaxHP or 1.0)
end

PushUltimateToGameFlow = function(player)
    local director = GetGameFlowDirector()
    if director == nil or player == nil then return end
    local maxGauge = player.MaxUltimateGauge or GetCombatConfig(player).MaxUltimateGauge or PlayerConfig.Default.Combat.MaxUltimateGauge
    director:SetUltimateGauge(player.UltimateGauge or 0.0, maxGauge)
end

local function PushComboToGameFlow(player)
    local director = GetGameFlowDirector()
    if director == nil or player == nil then return end
    director:SetComboCount(player.ComboCount or 0)
end

local function IsBossTarget(targetActor)
    if targetActor == nil then
        return false
    end

    if bossRef ~= nil and targetActor == bossRef then
        return true
    end

    if targetActor.HasTag ~= nil and targetActor:HasTag("Boss") then
        return true
    end

    return false
end

local function ResolveAttackDamage(ctx, event)
    if event ~= nil and event.Damage ~= nil then
        return event.Damage
    end

    local combatConfig = GetCombatConfig(ctx)
    local attackIndex = event ~= nil and event.AttackIndex or nil
    if attackIndex ~= nil and combatConfig.AttackDamages ~= nil and combatConfig.AttackDamages[attackIndex] ~= nil then
        return combatConfig.AttackDamages[attackIndex]
    end

    return combatConfig.AttackDamage or PlayerConfig.Default.Combat.AttackDamage or 10.0
end

local function ResolveAttackGaugeDelta(ctx, event)
    if event ~= nil and event.GaugeDelta ~= nil then
        return event.GaugeDelta
    end

    local combatConfig = GetCombatConfig(ctx)
    return combatConfig.AttackGaugeGain or PlayerConfig.Default.Combat.AttackGaugeGain or 0.0
end

local function ResolveAttackComboDelta(ctx, event)
    if event ~= nil and event.ComboDelta ~= nil then
        return event.ComboDelta
    end

    local combatConfig = GetCombatConfig(ctx)
    return combatConfig.AttackComboGain or PlayerConfig.Default.Combat.AttackComboGain or 1
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
            if IsBossTarget(event.TargetActor) then
                local damaged = CombatContext.ApplyDamageToBoss(ResolveAttackDamage(ctx, event))
                if damaged == true then
                    AddGauge(ctx, ResolveAttackGaugeDelta(ctx, event))
                    ctx.ComboCount = math.max(0, (ctx.ComboCount or 0) + ResolveAttackComboDelta(ctx, event))
                    PushComboToGameFlow(ctx)
                end
            elseif event.GaugeDelta ~= nil then
                AddGauge(ctx, event.GaugeDelta)
            end
        elseif event.Type == "UltimateStart" then
            ctx.UltimateGauge = 0
            PushUltimateToGameFlow(ctx)
        elseif event.Type == "GaugeChanged" then
            ctx.UltimateGauge = event.Value
            local combatConfig = GetCombatConfig(ctx)
            ctx.MaxUltimateGauge = event.MaxValue or combatConfig.MaxUltimateGauge or ctx.MaxUltimateGauge
            PushUltimateToGameFlow(ctx)
        end
    end
end

-- ════════════════════════════════════════════
-- 보스 관련 (Boss/ 에서 호출)
-- ════════════════════════════════════════════

-- ⑥ 재시작/레벨 언로드 시 BossCharacter.EndPlay 에서 호출
function CombatContext.Clear()
    bossRef      = nil
    bossBB       = nil
    bossBBConfig = nil
end

-- 보스 등록 (BossCharacter.BeginPlay 에서 호출)
function CombatContext.RegisterBoss(obj, bb, BB)
    bossRef      = obj
    bossBB       = bb
    bossBBConfig = BB
end

-- ════════════════════════════════════════════
-- 퍼펙트 회피 / 슬로모 (★ 플레이어팀이 호출 ★)
--   퍼펙트 회피 판정은 플레이어가 함 (회피 무적 중 피격 = 퍼펙트).
--   슬로모는 글로벌이라 플레이어가 직접 Slomo 호출.
--   단, 보스 코루틴/쿨타임 보정(bb.TimeScale)을 위해 보스도 알아야 한다.
-- ════════════════════════════════════════════

-- [플레이어팀 호출] 글로벌 슬로모를 시작했다고 보스에 알림.
--   ⚠️ 플레이어가 ActionComponent.Slomo 를 부른 직후 반드시 같이 호출.
--      안 그러면 보스 코루틴이 보정 안 돼서 혼자 정상 속도로 폭주함.
function CombatContext.OnSlomoStarted(duration, scale)
    if not bossBB then return end
    duration = duration or (bossBBConfig and bossBBConfig.PERFECT.SLOMO_DURATION) or 1.5
    scale    = scale    or (bossBBConfig and bossBBConfig.PERFECT.SLOMO_SCALE)    or 0.1

    -- ⑤ 보스 코루틴/쿨타임/LookAt 보정 → Tick 의 scaledDt 에 반영
    bossBB.TimeScale      = scale
    bossBB.SlomoRemaining = duration

    print(string.format("[CombatContext] 슬로모 시작 알림 → 보스 보정 (x%.2f / %.1fs)",
          scale, duration))
end

-- ════════════════════════════════════════════
-- 보스 HP — 공개 인터페이스 (★ 플레이어팀이 호출/조회 ★)
--   이 함수들의 이름/동작은 팀 간 계약이므로 함부로 바꾸지 않는다.
-- ════════════════════════════════════════════

-- 보스 사망 처리 (HP 0 도달 시 1회만)
local function HandleBossDeath()
    if bossBB == nil or bossBB.IsDead then return end

    bossBB.IsDead    = true
    bossBB.ActionLock = false   -- 락 해제 (진행 중 코루틴은 IsDead 로 무력화됨)

    -- 이동 정지
    if bossRef and bossRef:IsValid() then
        local mov = bossRef:GetCharacterMovement()
        if mov then mov:StopMovementImmediately() end
    end

    print("[Boss] ☠ 사망!")
    -- TODO: 사망 애니메이션, 전투 종료 이벤트, 보상 등 (에셋/연출 단계)
end

-- [플레이어팀 호출] 플레이어가 보스를 때렸을 때
function CombatContext.ApplyDamageToBoss(amount)
    if not bossBB or bossBB.HP == nil then return false end
    if bossBB.IsDead then return false end   -- 이미 죽었으면 무시
    amount = amount or 0
    if amount <= 0 then return false end

    bossBB.HP = math.max(0.0, bossBB.HP - amount)
    PushBossHPToGameFlow()

    print(string.format("[Boss] 피격! -%.0f   HP: %.0f / %.0f",
          amount, bossBB.HP, bossBB.MaxHP or 0.0))

    -- TODO(2단계): 슈퍼아머(ActionLock 중 경직 무시) / 피격 연출

    if bossBB.HP <= 0.0 then
        HandleBossDeath()
    end

    return true
end

-- [플레이어팀 조회] HP 바 UI 용 (0.0 ~ 1.0)
function CombatContext.GetBossHPRatio()
    if not bossBB or not bossBB.MaxHP or bossBB.MaxHP <= 0 then return 0.0 end
    return (bossBB.HP or 0.0) / bossBB.MaxHP
end

-- [플레이어팀 조회] 현재/최대 체력 (current, max)
function CombatContext.GetBossHP()
    if not bossBB then return 0.0, 0.0 end
    return bossBB.HP or 0.0, bossBB.MaxHP or 0.0
end

function CombatContext.HasBoss()
    return bossBB ~= nil
end

function CombatContext.SetBossHP(current, maxHP)
    if bossBB == nil then return false end

    local resolvedMax = maxHP or bossBB.MaxHP or 100.0
    if resolvedMax <= 0.0 then resolvedMax = 1.0 end

    bossBB.MaxHP = resolvedMax
    bossBB.HP = Clamp(current or bossBB.HP or resolvedMax, 0.0, resolvedMax)
    PushBossHPToGameFlow()
    if bossBB.HP > 0.0 then
        bossBB.IsDead = false
    else
        HandleBossDeath()
    end
    return true
end

-- [플레이어팀 조회] 생존 여부
function CombatContext.IsBossAlive()
    return bossBB ~= nil and (bossBB.HP or 0.0) > 0.0
end

function CombatContext.GetPlayerHP()
    local player = CombatContext.GetFirstPlayer()
    if not player then return 100.0, 100.0 end
    local maxHP = player.MaxHP or GetCombatConfig(player).MaxHP or 100.0
    return player.HP or maxHP, maxHP
end

function CombatContext.SetPlayerHP(current, maxHP)
    local player = CombatContext.GetFirstPlayer()
    if player == nil then return false end

    local resolvedMax = maxHP or player.MaxHP or GetCombatConfig(player).MaxHP or 100.0
    if resolvedMax <= 0.0 then resolvedMax = 1.0 end

    player.MaxHP = resolvedMax
    player.HP = Clamp(current or player.HP or resolvedMax, 0.0, resolvedMax)
    PushPlayerHPToGameFlow(player)
    return true
end

function CombatContext.ApplyDamageToPlayer(amount)
    local hp, maxHP = CombatContext.GetPlayerHP()
    return CombatContext.SetPlayerHP(hp - math.max(0.0, amount or 0.0), maxHP)
end

function CombatContext.GetPlayerUltimate()
    local player = CombatContext.GetFirstPlayer()
    if not player then return 0.0, PlayerConfig.Default.Combat.MaxUltimateGauge end
    local maxGauge = player.MaxUltimateGauge or GetCombatConfig(player).MaxUltimateGauge or PlayerConfig.Default.Combat.MaxUltimateGauge
    return player.UltimateGauge or 0.0, maxGauge
end

function CombatContext.SetPlayerUltimate(current, maxGauge)
    local player = CombatContext.GetFirstPlayer()
    if player == nil then return false end

    local resolvedMax = maxGauge or player.MaxUltimateGauge or GetCombatConfig(player).MaxUltimateGauge or PlayerConfig.Default.Combat.MaxUltimateGauge
    if resolvedMax <= 0.0 then resolvedMax = 1.0 end

    player.MaxUltimateGauge = resolvedMax
    player.UltimateGauge = Clamp(current or player.UltimateGauge or 0.0, 0.0, resolvedMax)
    PushUltimateToGameFlow(player)
    return true
end

function CombatContext.AddPlayerUltimate(amount)
    local gauge, maxGauge = CombatContext.GetPlayerUltimate()
    return CombatContext.SetPlayerUltimate(gauge + (amount or 0.0), maxGauge)
end

function CombatContext.GetPlayerCombo()
    local player = CombatContext.GetFirstPlayer()
    if not player then return 0 end
    return player.ComboCount or 0
end

function CombatContext.SetPlayerCombo(count)
    local player = CombatContext.GetFirstPlayer()
    if player == nil then return false end
    player.ComboCount = math.max(0, count or 0)
    PushComboToGameFlow(player)
    return true
end

function CombatContext.AddPlayerCombo(delta)
    return CombatContext.SetPlayerCombo(CombatContext.GetPlayerCombo() + (delta or 0))
end

return CombatContext
