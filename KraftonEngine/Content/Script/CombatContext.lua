-- Player, Boss 를 등록해 서로에 대한 이벤트 처리

local CombatContext = {}

local PlayerConfig = require("PlayerConfig")
local PlayerAction = require("PlayerAction")

local playersByOwner = {}
local activeEnemyAttackWindows = {}

local function GetOwnerKey(owner)
    if owner == nil then
        return nil
    end

    return owner.UUID or tostring(owner)
end

local function IsValidActor(actor)
    return actor ~= nil and actor.IsValid ~= nil and actor:IsValid()
end

local function Now()
    if World ~= nil and World.GetGameTime ~= nil then
        return World.GetGameTime() or 0.0
    end

    return 0.0
end

local function SafeActorName(actor)
    if actor == nil then
        return "nil"
    end

    if actor.GetName ~= nil then
        return actor:GetName()
    end

    if actor.Name ~= nil then
        return tostring(actor.Name)
    end

    return tostring(actor)
end

local function Clamp(value, minValue, maxValue)
    if value < minValue then return minValue end
    if value > maxValue then return maxValue end
    return value
end

local function GetCombatConfig(ctx)
    if ctx ~= nil and ctx.Config ~= nil and ctx.Config.Combat ~= nil then
        return ctx.Config.Combat
    end

    return PlayerConfig.Default.Combat
end

local function NormalizeHit(hit)
    hit = hit or {}
    hit.AttackId = hit.AttackId or "UnknownAttack"
    hit.AttackInstanceId = hit.AttackInstanceId or hit.AttackId
    hit.SourceTeam = hit.SourceTeam or "Neutral"
    hit.TargetTeam = hit.TargetTeam or "Neutral"
    hit.Damage = hit.Damage or 0
    hit.GaugeDelta = hit.GaugeDelta or 0
    return hit
end

local function MakeHitKey(hit)
    local sourceKey = GetOwnerKey(hit.SourceActor) or tostring(hit.SourceActor or "nil")
    local targetKey = GetOwnerKey(hit.TargetActor) or tostring(hit.TargetActor or "nil")
    return sourceKey .. ":" .. targetKey .. ":" .. tostring(hit.AttackInstanceId or hit.AttackId)
end

local function PruneRecentHits(ctx, now)
    if ctx == nil or ctx.RecentHitIds == nil then
        return
    end

    for key, expireAt in pairs(ctx.RecentHitIds) do
        if expireAt ~= true and expireAt <= now then
            ctx.RecentHitIds[key] = nil
        end
    end
end

local function MarkHitIfNew(ctx, hit, now, lifetime)
    if ctx == nil then
        return true
    end

    ctx.RecentHitIds = ctx.RecentHitIds or {}
    PruneRecentHits(ctx, now)

    local key = MakeHitKey(hit)
    if ctx.RecentHitIds[key] ~= nil then
        return false
    end

    ctx.RecentHitIds[key] = now + (lifetime or 1.0)
    return true
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

local function GetOrAddActionComponent(actor)
    if not IsValidActor(actor) then
        return nil
    end

    if actor.GetActionComponent ~= nil then
        local action = actor:GetActionComponent()
        if action ~= nil then
            return action
        end
    end

    if actor.AddActionComponent ~= nil then
        return actor:AddActionComponent()
    end

    return nil
end

local function ApplyLocalHitStop(actor, duration)
    duration = duration or 0.0
    if duration <= 0.0 then
        return
    end

    local action = GetOrAddActionComponent(actor)
    if action == nil then
        return
    end

    if action.LocalHitStop ~= nil then
        action:LocalHitStop(duration)
    elseif action.HitStop ~= nil then
        action:HitStop(duration, 0.0)
    end
end

local function ApplySlomo(actor, duration, scale)
    duration = duration or 0.0
    if duration <= 0.0 then
        return
    end

    scale = scale or 0.1

    local action = GetOrAddActionComponent(actor)
    if action ~= nil and action.Slomo ~= nil then
        action:Slomo(duration, scale)
    end

    CombatContext.OnSlomoStarted(duration, scale)
end

function CombatContext.RegisterPlayer(ctx)
    if ctx == nil or ctx.Owner == nil then
        return
    end

    local combatConfig = GetCombatConfig(ctx)
    ctx.MaxHP = ctx.MaxHP or combatConfig.MaxHP or PlayerConfig.Default.Combat.MaxHP
    ctx.HP = ctx.HP or ctx.MaxHP
    ctx.IsDead = ctx.IsDead or false
    ctx.InvincibleUntil = ctx.InvincibleUntil or 0.0
    ctx.DodgeInvincibleUntil = ctx.DodgeInvincibleUntil or 0.0
    ctx.PerfectDodgeConsumedUntil = ctx.PerfectDodgeConsumedUntil or 0.0
    ctx.RecentHitIds = ctx.RecentHitIds or {}
    ctx.MaxUltimateGauge = combatConfig.MaxUltimateGauge or PlayerConfig.Default.Combat.MaxUltimateGauge

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

function CombatContext.HandlePlayerResult(ctx, result)
    if ctx == nil or result == nil or result.Events == nil then
        return
    end

    local now = Now()
    local combatConfig = GetCombatConfig(ctx)

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
            ctx.MaxUltimateGauge = event.MaxValue or combatConfig.MaxUltimateGauge or ctx.MaxUltimateGauge
        elseif event.Type == "DashStart" then
            local duration = combatConfig.DashPerfectDodgeDuration
                or combatConfig.PerfectDodgeWindowDuration
                or PlayerConfig.Default.Action.DashDuration
            ctx.DodgeInvincibleUntil = math.max(ctx.DodgeInvincibleUntil or 0.0, now + duration)
            ctx.CombatDodgeActive = true
        elseif event.Type == "DashEnd" then
            local grace = combatConfig.PerfectDodgeGraceAfterDash or 0.0
            ctx.DodgeInvincibleUntil = math.max(ctx.DodgeInvincibleUntil or 0.0, now + grace)
            ctx.CombatDodgeActive = false
        elseif event.Type == "DashChargingStart" then
            ctx.CombatDodgeActive = false
        elseif event.Type == "DashChargeAttackStart" then
            ctx.CombatDodgeActive = false
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
    activeEnemyAttackWindows = {}
end

-- 보스 등록 (BossCharacter.BeginPlay 에서 호출)
function CombatContext.RegisterBoss(actor, bb, BB)
    bossRef      = actor
    bossBB       = bb
    bossBBConfig = BB
end

-- 보스 런타임 Blackboard 조회 (BossAnimation 이 공격 신호를 읽기 위해 사용)
-- AI(BossAttacks)가 bb 에 쓴 AnimAttack 신호를 AnimInstance 가 폴링한다.
function CombatContext.GetBossBlackboard()
    return bossBB
end

-- ════════════════════════════════════════════
-- 퍼펙트 회피 / 슬로모
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

local function IsPerfectDodgeActive(ctx, now)
    if ctx == nil then
        return false
    end

    return (ctx.DodgeInvincibleUntil or 0.0) > now
end

function CombatContext.OnPlayerPerfectDodge(ctx, hit)
    if ctx == nil then
        return
    end

    local combatConfig = GetCombatConfig(ctx)
    local duration = hit.SlomoDuration or combatConfig.PerfectDodgeSlomoDuration or 1.5
    local scale = hit.SlomoScale or combatConfig.PerfectDodgeSlomoScale or 0.1

    CombatContext.SetCurrentThreat(ctx, hit.SourceActor)

    PlayerAction.PushEvent(ctx, {
        Type = "PerfectDodge",
        Threat = hit.SourceActor,
        AttackId = hit.AttackId,
        GaugeDelta = combatConfig.PerfectDodgeGaugeDelta or hit.GaugeDelta or 0,
    })

    ApplySlomo(ctx.Owner, duration, scale)

    print(string.format("[Player] Perfect Dodge! source=%s attack=%s",
        SafeActorName(hit.SourceActor), tostring(hit.AttackId)))
end

-- ════════════════════════════════════════════
-- 통합 Hit Resolution
-- ════════════════════════════════════════════

function CombatContext.ApplyHit(hit)
    hit = NormalizeHit(hit)

    if hit.TargetActor == nil then
        return { Applied = false, Reason = "MissingTarget" }
    end

    local playerCtx = CombatContext.GetPlayerByOwner(hit.TargetActor)
    if playerCtx ~= nil then
        return CombatContext.ApplyHitToPlayer(playerCtx, hit)
    end

    if bossRef ~= nil and hit.TargetActor == bossRef then
        return CombatContext.ApplyHitToBoss(hit)
    end

    if hit.TargetActor.HasTag ~= nil and hit.TargetActor:HasTag("Boss") then
        return CombatContext.ApplyHitToBoss(hit)
    end

    return { Applied = false, Reason = "NoCombatTarget" }
end

function CombatContext.ApplyHitToPlayer(ctx, hit)
    hit = NormalizeHit(hit)

    if ctx == nil or ctx.IsDead == true then
        return { Applied = false, Reason = "PlayerDead" }
    end

    local now = Now()
    local combatConfig = GetCombatConfig(ctx)

    if MarkHitIfNew(ctx, hit, now, combatConfig.DuplicateHitLifetime or 1.0) == false then
        return { Applied = false, Reason = "DuplicateHit" }
    end

    if hit.CanPerfectDodge ~= false and IsPerfectDodgeActive(ctx, now) then
        -- 같은 회피 윈도우에서 여러 타가 한꺼번에 들어와도 첫 타만 슬로모를 건다.
        if (ctx.PerfectDodgeConsumedUntil or 0.0) < now then
            ctx.PerfectDodgeConsumedUntil = ctx.DodgeInvincibleUntil or now
            CombatContext.OnPlayerPerfectDodge(ctx, hit)
        end
        return { Applied = false, Reason = "PerfectDodge" }
    end

    if (ctx.InvincibleUntil or 0.0) > now then
        return { Applied = false, Reason = "Invincible" }
    end

    local damage = hit.Damage or 0
    if damage <= 0 then
        return { Applied = false, Reason = "NoDamage" }
    end

    ctx.MaxHP = ctx.MaxHP or combatConfig.MaxHP or PlayerConfig.Default.Combat.MaxHP
    ctx.HP = Clamp((ctx.HP or ctx.MaxHP) - damage, 0.0, ctx.MaxHP)
    ctx.LastHitTime = now
    ctx.InvincibleUntil = now + (hit.InvincibleDuration or combatConfig.HitInvincibleDuration or 0.5)
    CombatContext.SetCurrentThreat(ctx, hit.SourceActor)

    ApplyLocalHitStop(ctx.Owner, hit.HitStopDuration or combatConfig.HitStopDuration or 0.0)
    ApplyLocalHitStop(hit.SourceActor, hit.HitStopDuration or combatConfig.EnemyHitStopDuration or 0.0)

    PlayerAction.PushEvent(ctx, {
        Type = "PlayerHit",
        SourceActor = hit.SourceActor,
        AttackId = hit.AttackId,
        Damage = damage,
        HP = ctx.HP,
        MaxHP = ctx.MaxHP,
    })

    print(string.format("[Player] 피격! -%.0f   HP: %.0f / %.0f   attack=%s",
        damage, ctx.HP, ctx.MaxHP, tostring(hit.AttackId)))

    if ctx.HP <= 0.0 then
        ctx.IsDead = true
        PlayerAction.PushEvent(ctx, {
            Type = "PlayerDead",
            SourceActor = hit.SourceActor,
            AttackId = hit.AttackId,
        })
        print("[Player] ☠ 사망!")
    end

    return { Applied = true, Target = "Player", Damage = damage, HP = ctx.HP, MaxHP = ctx.MaxHP }
end

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

function CombatContext.ApplyHitToBoss(hit)
    hit = NormalizeHit(hit)

    if not bossBB or bossBB.HP == nil then
        return { Applied = false, Reason = "BossMissing" }
    end
    if bossBB.IsDead then
        return { Applied = false, Reason = "BossDead" }
    end

    local now = Now()
    if bossBB.RecentHitIds == nil then
        bossBB.RecentHitIds = {}
    end
    PruneRecentHits(bossBB, now)

    local key = MakeHitKey(hit)
    if bossBB.RecentHitIds[key] ~= nil then
        return { Applied = false, Reason = "DuplicateHit" }
    end
    bossBB.RecentHitIds[key] = now + (hit.DuplicateHitLifetime or 1.0)

    local damage = hit.Damage or 0
    if damage <= 0 then
        return { Applied = false, Reason = "NoDamage" }
    end

    bossBB.HP = math.max(0.0, bossBB.HP - damage)

    local combatConfig = PlayerConfig.Default.Combat
    ApplyLocalHitStop(hit.SourceActor, hit.HitStopDuration or combatConfig.HitStopDuration or 0.0)
    ApplyLocalHitStop(bossRef, hit.HitStopDuration or combatConfig.EnemyHitStopDuration or 0.0)

    local sourceCtx = CombatContext.GetPlayerByOwner(hit.SourceActor)
    if sourceCtx ~= nil then
        PlayerAction.PushEvent(sourceCtx, {
            Type = "AttackHit",
            AttackId = hit.AttackId,
            AttackIndex = hit.AttackIndex,
            TargetActor = bossRef,
            Damage = damage,
            GaugeDelta = hit.GaugeDelta or 0,
            HP = bossBB.HP,
            MaxHP = bossBB.MaxHP,
        })
    end

    print(string.format("[Boss] 피격! -%.0f   HP: %.0f / %.0f   attack=%s",
          damage, bossBB.HP, bossBB.MaxHP or 0.0, tostring(hit.AttackId)))

    if bossBB.HP <= 0.0 then
        HandleBossDeath()
    end

    return { Applied = true, Target = "Boss", Damage = damage, HP = bossBB.HP, MaxHP = bossBB.MaxHP }
end

-- [플레이어팀 호출] 플레이어가 보스를 때렸을 때
function CombatContext.ApplyDamageToBoss(amount)
    return CombatContext.ApplyHit({
        SourceActor = nil,
        SourceTeam = "Player",
        TargetActor = bossRef,
        TargetTeam = "Enemy",
        AttackId = "LegacyApplyDamageToBoss",
        AttackInstanceId = "LegacyApplyDamageToBoss_" .. tostring(Now()),
        Damage = amount or 0,
    })
end

-- Collision 기반 적 공격 확장용: 보스/잡몹 공격 윈도우를 열어두고 Player OnOverlap에서 해결한다.
function CombatContext.BeginEnemyAttackWindow(sourceActor, attackInfo)
    if sourceActor == nil or attackInfo == nil then
        return nil
    end

    local key = GetOwnerKey(sourceActor)
    if key == nil then
        return nil
    end

    attackInfo.SourceActor = sourceActor
    attackInfo.SourceTeam = attackInfo.SourceTeam or "Enemy"
    attackInfo.TargetTeam = attackInfo.TargetTeam or "Player"
    attackInfo.AttackId = attackInfo.AttackId or "EnemyAttack"
    attackInfo.AttackInstanceId = attackInfo.AttackInstanceId
        or (attackInfo.AttackId .. "_" .. tostring(Now()))
    activeEnemyAttackWindows[key] = attackInfo
    return attackInfo
end

function CombatContext.EndEnemyAttackWindow(sourceActor, attackId)
    local key = GetOwnerKey(sourceActor)
    if key == nil then
        return
    end

    local active = activeEnemyAttackWindows[key]
    if active == nil then
        return
    end

    if attackId == nil or active.AttackId == attackId then
        activeEnemyAttackWindows[key] = nil
    end
end

function CombatContext.TryResolvePlayerOverlapHit(playerCtx, otherActor, overlappedComponent, otherComp)
    playerCtx = playerCtx or CombatContext.GetPlayerByOwner(obj)
    if playerCtx == nil or otherActor == nil then
        return { Applied = false, Reason = "InvalidOverlap" }
    end

    local active = activeEnemyAttackWindows[GetOwnerKey(otherActor)]
    if active == nil then
        return { Applied = false, Reason = "NoActiveEnemyAttackWindow" }
    end

    local hit = {}
    for key, value in pairs(active) do
        hit[key] = value
    end

    hit.TargetActor = playerCtx.Owner
    hit.OverlappedComponent = overlappedComponent
    hit.OtherComponent = otherComp

    return CombatContext.ApplyHit(hit)
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

function CombatContext.GetPlayerHP(ctx)
    if ctx == nil then
        ctx = CombatContext.GetPlayerByOwner(obj)
    end

    if ctx == nil then
        return 0.0, 0.0
    end

    return ctx.HP or 0.0, ctx.MaxHP or 0.0
end

function CombatContext.GetPlayerHPRatio(ctx)
    local hp, maxHP = CombatContext.GetPlayerHP(ctx)
    if maxHP <= 0.0 then
        return 0.0
    end

    return hp / maxHP
end

return CombatContext
