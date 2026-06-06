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

local bossRef      = nil   -- 보스 액터
local bossBB       = nil   -- 보스 런타임 Blackboard
local bossBBConfig = nil   -- 보스 수치 Blackboard

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

-- 보스 런타임 Blackboard 조회 (BossAnimation 이 공격 신호를 읽기 위해 사용)
-- AI(BossAttacks)가 bb 에 쓴 AnimAttack 신호를 AnimInstance 가 폴링한다.
function CombatContext.GetBossBlackboard()
    return bossBB
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
    if not bossBB or bossBB.HP == nil then return end
    if bossBB.IsDead then return end   -- 이미 죽었으면 무시
    amount = amount or 0
    if amount <= 0 then return end

    bossBB.HP = math.max(0.0, bossBB.HP - amount)

    print(string.format("[Boss] 피격! -%.0f   HP: %.0f / %.0f",
          amount, bossBB.HP, bossBB.MaxHP or 0.0))

    -- TODO(2단계): 슈퍼아머(ActionLock 중 경직 무시) / 피격 연출

    if bossBB.HP <= 0.0 then
        HandleBossDeath()
    end
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

-- [플레이어팀 조회] 생존 여부
function CombatContext.IsBossAlive()
    return bossBB ~= nil and (bossBB.HP or 0.0) > 0.0
end

return CombatContext
