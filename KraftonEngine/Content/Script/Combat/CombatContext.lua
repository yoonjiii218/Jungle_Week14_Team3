-- Combat/CombatContext.lua
-- CombatContext owns hit resolution, HP/gauge changes, and combat registries.
-- It consumes/produces typed HitRequest and PlayerEvent tables.

local CombatContext = {}

local PlayerContext = require("Player/PlayerContext")
local PlayerEvents = require("Player/PlayerEvents")
local HitTypes = require("Combat/HitTypes")
local BossContext = require("Boss/BossContext")
local BossEvents = require("Boss/BossEvents")
local Strict = require("Core/Strict")

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

local function PruneRecentHits(recentHitIds, now)
    for key, expireAt in pairs(recentHitIds) do
        if expireAt ~= true and expireAt <= now then
            recentHitIds[key] = nil
        end
    end
end

local function MarkHitIfNew(recentHitIds, hit, now, lifetime)
    PruneRecentHits(recentHitIds, now)

    local key = MakeHitKey(hit)
    if recentHitIds[key] ~= nil then
        return false
    end

    recentHitIds[key] = now + lifetime
    return true
end

local function AddGauge(playerContext, amount)
    local combatConfig = playerContext.Config.Combat
    local maxGauge = combatConfig.MaxUltimateGauge
    local gauge = playerContext.Combat.UltimateGauge + amount
    if gauge < 0 then gauge = 0 end
    if gauge > maxGauge then gauge = maxGauge end
    playerContext.Combat.UltimateGauge = gauge
    playerContext.Combat.MaxUltimateGauge = maxGauge
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

-- Perfect dodge slomo is gameplay time control, not just visual feedback.
-- Keep it in CombatContext so boss coroutine/cooldown scaling is always synchronized.
local function ApplyCombatSlomo(actor, duration, scale)
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

---@param playerContext PlayerContext
---@return nil
-- =========================================================
-- Public API
-- =========================================================

function CombatContext.RegisterPlayer(playerContext)
    PlayerContext.Assert(playerContext, "CombatContext.RegisterPlayer")
    local combatConfig = playerContext.Config.Combat
    playerContext.Combat.MaxHP = combatConfig.MaxHP
    playerContext.Combat.MaxUltimateGauge = combatConfig.MaxUltimateGauge

    playersByOwner[GetOwnerKey(playerContext.Owner)] = playerContext
end

---@param playerContext PlayerContext
---@return nil
function CombatContext.UnregisterPlayer(playerContext)
    PlayerContext.Assert(playerContext, "CombatContext.UnregisterPlayer")
    local key = GetOwnerKey(playerContext.Owner)
    if playersByOwner[key] == playerContext then
        playersByOwner[key] = nil
    end
end

function CombatContext.GetPlayerByOwner(owner)
    return playersByOwner[GetOwnerKey(owner)]
end

---@param playerContext PlayerContext
---@param threat any
---@return nil
function CombatContext.SetCurrentThreat(playerContext, threat)
    PlayerContext.Assert(playerContext, "CombatContext.SetCurrentThreat")
    playerContext.Combat.CurrentThreat = threat
end

---@param playerContext PlayerContext
---@return any
function CombatContext.GetCurrentThreat(playerContext)
    PlayerContext.Assert(playerContext, "CombatContext.GetCurrentThreat")
    return playerContext.Combat.CurrentThreat
end

---@param playerContext PlayerContext
---@param events PlayerEvent[]
---@return nil
function CombatContext.ProcessPlayerEvents(playerContext, events)
    PlayerContext.Assert(playerContext, "CombatContext.ProcessPlayerEvents")
    Strict.AssertTable(events, "events", "CombatContext.ProcessPlayerEvents")

    local now = Now()
    local combatConfig = playerContext.Config.Combat

    for _, event in ipairs(events) do
        if PlayerEvents.Is(event, PlayerEvents.Type.PerfectDodge) then
            CombatContext.SetCurrentThreat(playerContext, event.Threat)
            AddGauge(playerContext, event.GaugeDelta or 0)
        elseif PlayerEvents.Is(event, PlayerEvents.Type.AttackHit) then
            AddGauge(playerContext, event.GaugeDelta or 0)
        elseif PlayerEvents.Is(event, PlayerEvents.Type.UltimateStarted) then
            playerContext.Combat.UltimateGauge = 0
        elseif PlayerEvents.Is(event, PlayerEvents.Type.GaugeChanged) then
            playerContext.Combat.UltimateGauge = event.Value
            playerContext.Combat.MaxUltimateGauge = event.MaxValue or combatConfig.MaxUltimateGauge
        elseif PlayerEvents.Is(event, PlayerEvents.Type.DashStarted) then
            local duration = combatConfig.DashPerfectDodgeDuration
            playerContext.Combat.DodgeInvincibleUntil = math.max(playerContext.Combat.DodgeInvincibleUntil or 0.0, now + duration)
            playerContext.Combat.CombatDodgeActive = true
            -- 대시 시작 순간의 위치를 기록한다. 회피로 장판을 벗어나도 "대시를 시작한 위치가
            -- 장판 안이었으면" 퍼펙트 회피를 인정하기 위해 보스 ResolveHit 이 이 좌표로 재검사한다.
            if playerContext.Owner ~= nil and playerContext.Owner.Location ~= nil then
                local loc = playerContext.Owner.Location
                playerContext.Combat.DodgeStartLocation = Vector(loc.X, loc.Y, loc.Z)
            end
            print(string.format("[PerfectDodge] 대시무적 ON: now=%.3f ~ until=%.3f (dur=%.3f)",
                now, playerContext.Combat.DodgeInvincibleUntil, duration))
        elseif PlayerEvents.Is(event, PlayerEvents.Type.DashEnded) then
            local grace = combatConfig.PerfectDodgeGraceAfterDash
            playerContext.Combat.DodgeInvincibleUntil = math.max(playerContext.Combat.DodgeInvincibleUntil or 0.0, now + grace)
            playerContext.Combat.CombatDodgeActive = false
        elseif PlayerEvents.Is(event, PlayerEvents.Type.DashChargingStarted) then
            playerContext.Combat.CombatDodgeActive = false
        elseif PlayerEvents.Is(event, PlayerEvents.Type.DashChargeAttackStarted) then
            playerContext.Combat.CombatDodgeActive = false
        end
    end
end


-- ════════════════════════════════════════════
-- 보스 관련 (Boss/ 에서 호출)
-- ════════════════════════════════════════════

local registeredBossContext = nil
local bossRef = nil

-- ⑥ 재시작/레벨 언로드 시 BossCharacter.EndPlay 에서 호출
function CombatContext.Clear()
    registeredBossContext = nil
    bossRef = nil
    activeEnemyAttackWindows = {}
end

---@param bossContext BossContext
---@return nil
function CombatContext.RegisterBoss(bossContext)
    BossContext.Assert(bossContext, "CombatContext.RegisterBoss")
    registeredBossContext = bossContext
    bossRef = bossContext.Owner
end

-- 보스 런타임 Blackboard 조회 (BossAnimation 이 공격 신호를 읽기 위해 사용)
-- BossAttacks writes AnimAttack signals into bossContext.Brain for BossAnimation to consume.
function CombatContext.GetBossContext()
    return registeredBossContext
end

-- ════════════════════════════════════════════
-- 퍼펙트 회피 / 슬로모
-- ════════════════════════════════════════════

-- [플레이어팀 호출] 글로벌 슬로모를 시작했다고 보스에 알림.
--   ⚠️ 플레이어가 ActionComponent.Slomo 를 부른 직후 반드시 같이 호출.
--      안 그러면 보스 코루틴이 보정 안 돼서 혼자 정상 속도로 폭주함.
function CombatContext.OnSlomoStarted(duration, scale)
    if registeredBossContext == nil then return end
    local perfectConfig = registeredBossContext.Config.PERFECT
    duration = duration or perfectConfig.SLOMO_DURATION
    scale = scale or perfectConfig.SLOMO_SCALE

    -- ⑤ 보스 코루틴/쿨타임/LookAt 보정 → Tick 의 scaledDt 에 반영
    registeredBossContext.Brain.TimeScale = scale
    registeredBossContext.Brain.SlomoRemaining = duration

    print(string.format("[CombatContext] 슬로모 시작 알림 → 보스 보정 (x%.2f / %.1fs)",
          scale, duration))
end

local function IsPerfectDodgeActive(playerContext, now)
    return playerContext.Combat.DodgeInvincibleUntil > now
end

-- [진단용] 특정 플레이어 액터가 지금 대시 무적(퍼펙트 회피 윈도우) 상태인지 조회.
-- 반환: dodging(bool), now, until_  — 보스 ResolveHit 에서 "장판 밖 빗나감" 인데
-- 무적이긴 했는지(=구조적 모순) 를 구분하기 위해 사용.
function CombatContext.DebugPlayerDodgeState(playerActor)
    local playerContext = CombatContext.GetPlayerByOwner(playerActor)
    if playerContext == nil then
        return false, 0.0, 0.0
    end
    local now    = Now()
    local until_ = playerContext.Combat.DodgeInvincibleUntil or 0.0
    return until_ > now, now, until_
end

-- [퍼펙트 회피] 플레이어가 지금 무적인지 + 대시를 시작한 위치를 함께 반환.
-- 보스 ResolveHit 이 "현재는 장판 밖이지만 대시 시작 시 장판 안이었나" 를 판정할 때 사용.
-- 반환: dodging(bool), dodgeStartLocation(Vector or nil)
function CombatContext.GetPlayerDodgeSnapshot(playerActor)
    local playerContext = CombatContext.GetPlayerByOwner(playerActor)
    if playerContext == nil then
        return false, nil
    end
    local now     = Now()
    local dodging = (playerContext.Combat.DodgeInvincibleUntil or 0.0) > now
    return dodging, playerContext.Combat.DodgeStartLocation
end

---@param playerContext PlayerContext
---@param hitRequest HitRequest
---@return nil
function CombatContext.OnPlayerPerfectDodge(playerContext, hit)
    PlayerContext.Assert(playerContext, "CombatContext.OnPlayerPerfectDodge")

    local combatConfig = playerContext.Config.Combat
    local duration = hit.SlomoDuration or combatConfig.PerfectDodgeSlomoDuration
    local scale = hit.SlomoScale or combatConfig.PerfectDodgeSlomoScale

    CombatContext.SetCurrentThreat(playerContext, hit.SourceActor)

    PlayerEvents.EmitPerfectDodge(playerContext, {
        Threat = hit.SourceActor,
        AttackId = hit.AttackId,
        GaugeDelta = combatConfig.PerfectDodgeGaugeDelta,
        SlomoDuration = duration,
        SlomoScale = scale,
    })

    ApplyCombatSlomo(playerContext.Owner, duration, scale)

    print(string.format("[Player] Perfect Dodge! source=%s attack=%s",
        SafeActorName(hit.SourceActor), tostring(hit.AttackId)))
end

-- ════════════════════════════════════════════
-- 통합 Hit Resolution
-- ════════════════════════════════════════════

---@param hitRequest HitRequest
---@return HitResult
function CombatContext.ApplyHit(hitRequest)
    local hit = NormalizeHit(hitRequest)
    if hit.Kind == nil then
        hit.Kind = "HitRequest"
    end
    HitTypes.AssertHitRequest(hit, "CombatContext.ApplyHit")

    if hit.TargetActor == nil then
        return HitTypes.CreateResult({ Applied = false, Reason = "MissingTarget" })
    end

    local targetPlayerContext = CombatContext.GetPlayerByOwner(hit.TargetActor)
    if targetPlayerContext ~= nil then
        return CombatContext.ApplyHitToPlayer(targetPlayerContext, hit)
    end

    if bossRef ~= nil and hit.TargetActor == bossRef then
        return CombatContext.ApplyHitToBoss(hit)
    end

    if hit.TargetActor.HasTag ~= nil and hit.TargetActor:HasTag("Boss") then
        return CombatContext.ApplyHitToBoss(hit)
    end

    return HitTypes.CreateResult({ Applied = false, Reason = "NoCombatTarget" })
end

---@param playerContext PlayerContext
---@param hitRequest HitRequest
---@return HitResult
function CombatContext.ApplyHitToPlayer(playerContext, hitRequest)
    PlayerContext.Assert(playerContext, "CombatContext.ApplyHitToPlayer")
    local hit = NormalizeHit(hitRequest)

    if playerContext.Combat.IsDead == true then
        return HitTypes.CreateResult({ Applied = false, Reason = "PlayerDead" })
    end

    local now = Now()
    local combatConfig = playerContext.Config.Combat

    if MarkHitIfNew(playerContext.Combat.RecentHitIds, hit, now, hit.DuplicateHitLifetime or combatConfig.DuplicateHitLifetime) == false then
        return HitTypes.CreateResult({ Applied = false, Reason = "DuplicateHit" })
    end

    -- [진단] 여기 도달했다 = Hitbox.Check 통과(장판 안) → 퍼펙트 회피 판정 단계.
    -- dodging=false 면 "장판 안에 있었지만 무적 타이밍이 안 맞음"(윈도우 미겹침).
    print(string.format("[PerfectDodge] ApplyHit 도달: now=%.3f until=%.3f dodging=%s attack=%s",
        now, playerContext.Combat.DodgeInvincibleUntil or 0.0,
        tostring(IsPerfectDodgeActive(playerContext, now)), tostring(hit.AttackId)))

    if hit.CanPerfectDodge ~= false and IsPerfectDodgeActive(playerContext, now) then
        -- 같은 회피 윈도우에서 여러 타가 한꺼번에 들어와도 첫 타만 슬로모를 건다.
        if (playerContext.Combat.PerfectDodgeConsumedUntil or 0.0) < now then
            playerContext.Combat.PerfectDodgeConsumedUntil = playerContext.Combat.DodgeInvincibleUntil or now
            CombatContext.OnPlayerPerfectDodge(playerContext, hit)
        end
        return HitTypes.CreateResult({ Applied = false, Reason = "PerfectDodge" })
    end

    if (playerContext.Combat.InvincibleUntil or 0.0) > now then
        return HitTypes.CreateResult({ Applied = false, Reason = "Invincible" })
    end

    local damage = hit.Damage or 0
    if damage <= 0 then
        return HitTypes.CreateResult({ Applied = false, Reason = "NoDamage" })
    end

    playerContext.Combat.MaxHP = combatConfig.MaxHP
    playerContext.Combat.HP = Clamp(playerContext.Combat.HP - damage, 0.0, playerContext.Combat.MaxHP)
    playerContext.Combat.LastHitTime = now
    playerContext.Combat.InvincibleUntil = now + (hit.InvincibleDuration or combatConfig.HitInvincibleDuration)
    CombatContext.SetCurrentThreat(playerContext, hit.SourceActor)

    ApplyLocalHitStop(playerContext.Owner, hit.HitStopDuration or combatConfig.HitStopDuration)
    ApplyLocalHitStop(hit.SourceActor, hit.HitStopDuration or combatConfig.EnemyHitStopDuration)

    PlayerEvents.EmitHit(playerContext, {
        SourceActor = hit.SourceActor,
        AttackId = hit.AttackId,
        Damage = damage,
        HP = playerContext.Combat.HP,
        MaxHP = playerContext.Combat.MaxHP,
    })

    print(string.format("[Player] 피격! -%.0f   HP: %.0f / %.0f   attack=%s",
        damage, playerContext.Combat.HP, playerContext.Combat.MaxHP, tostring(hit.AttackId)))

    if playerContext.Combat.HP <= 0.0 then
        playerContext.Combat.IsDead = true
        PlayerEvents.EmitDead(playerContext, {
            SourceActor = hit.SourceActor,
            AttackId = hit.AttackId,
        })
        print("[Player] ☠ 사망!")
    end

    return HitTypes.CreateResult({ Applied = true, Target = "Player", Damage = damage, HP = playerContext.Combat.HP, MaxHP = playerContext.Combat.MaxHP })
end

-- 보스 사망 처리 (HP 0 도달 시 1회만)
local function HandleBossDeath(bossContext, hit)
    if bossContext == nil or bossContext.Combat.IsDead then return end

    bossContext.Combat.IsDead = true
    bossContext.Brain.ActionLock = false

    -- 이동 정지
    if bossRef and bossRef:IsValid() then
        local mov = bossRef:GetCharacterMovement()
        if mov then mov:StopMovementImmediately() end
    end

    BossEvents.EmitDead(bossContext, {
        SourceActor = hit and hit.SourceActor or nil,
        AttackId = hit and hit.AttackId or nil,
    })

    print("[Boss] ☠ 사망!")
    -- TODO: 사망 애니메이션, 전투 종료 이벤트, 보상 등 (에셋/연출 단계)
end

function CombatContext.ApplyHitToBoss(hit)
    hit = NormalizeHit(hit)
    local bossContext = registeredBossContext

    if bossContext == nil then
        return HitTypes.CreateResult({ Applied = false, Reason = "BossMissing" })
    end
    if bossContext.Combat.IsDead then
        return HitTypes.CreateResult({ Applied = false, Reason = "BossDead" })
    end

    local now = Now()
    PruneRecentHits(bossContext.Combat.RecentHitIds, now)

    local key = MakeHitKey(hit)
    if bossContext.Combat.RecentHitIds[key] ~= nil then
        return HitTypes.CreateResult({ Applied = false, Reason = "DuplicateHit" })
    end
    bossContext.Combat.RecentHitIds[key] = now + (hit.DuplicateHitLifetime or 1.0)

    local damage = hit.Damage or 0
    if damage <= 0 then
        return HitTypes.CreateResult({ Applied = false, Reason = "NoDamage" })
    end

    bossContext.Combat.HP = math.max(0.0, bossContext.Combat.HP - damage)

    BossEvents.EmitHit(bossContext, {
        SourceActor = hit.SourceActor,
        AttackId = hit.AttackId,
        Damage = damage,
        HP = bossContext.Combat.HP,
        MaxHP = bossContext.Combat.MaxHP,
    })

    local sourcePlayerContext = CombatContext.GetPlayerByOwner(hit.SourceActor)
    if sourcePlayerContext ~= nil then
        local combatConfig = sourcePlayerContext.Config.Combat
        ApplyLocalHitStop(hit.SourceActor, hit.HitStopDuration or combatConfig.HitStopDuration)
        ApplyLocalHitStop(bossRef, hit.HitStopDuration or combatConfig.EnemyHitStopDuration)

        PlayerEvents.EmitAttackHit(sourcePlayerContext, {
            AttackId = hit.AttackId,
            AttackIndex = hit.AttackIndex,
            TargetActor = bossRef,
            Damage = damage,
            GaugeDelta = hit.GaugeDelta or 0,
            HP = bossContext.Combat.HP,
            MaxHP = bossContext.Combat.MaxHP,
        })
    end

    print(string.format("[Boss] 피격! -%.0f   HP: %.0f / %.0f   attack=%s",
          damage, bossContext.Combat.HP, bossContext.Combat.MaxHP, tostring(hit.AttackId)))

    if bossContext.Combat.HP <= 0.0 then
        HandleBossDeath(bossContext, hit)
    end

    return HitTypes.CreateResult({ Applied = true, Target = "Boss", Damage = damage, HP = bossContext.Combat.HP, MaxHP = bossContext.Combat.MaxHP })
end

-- [플레이어팀 호출] 플레이어가 보스를 때렸을 때
function CombatContext.ApplyDamageToBoss(amount)
    return CombatContext.ApplyHit({
        SourceActor = World.FindFirstActorByTag("Player") or bossRef,
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

---@param args table
---@return HitResult
function CombatContext.TryResolvePlayerOverlapHit(args)
    Strict.AssertTable(args, "args", "CombatContext.TryResolvePlayerOverlapHit")
    local playerContext = PlayerContext.Assert(args.PlayerContext, "CombatContext.TryResolvePlayerOverlapHit")
    local otherActor = args.OtherActor
    if otherActor == nil then
        return HitTypes.CreateResult({ Applied = false, Reason = "InvalidOverlap" })
    end

    local active = activeEnemyAttackWindows[GetOwnerKey(otherActor)]
    if active == nil then
        return HitTypes.CreateResult({ Applied = false, Reason = "NoActiveEnemyAttackWindow" })
    end

    local hit = {}
    for key, value in pairs(active) do
        hit[key] = value
    end

    hit.TargetActor = playerContext.Owner
    hit.OverlappedComponent = args.OverlappedComponent
    hit.OtherComponent = args.OtherComponent

    return CombatContext.ApplyHit(hit)
end

---@param bossContext BossContext
---@param events BossEvent[]
---@return nil
function CombatContext.ProcessBossEvents(bossContext, events)
    BossContext.Assert(bossContext, "CombatContext.ProcessBossEvents")
    Strict.AssertTable(events, "events", "CombatContext.ProcessBossEvents")
end

-- [플레이어팀 조회] HP 바 UI 용 (0.0 ~ 1.0)
function CombatContext.GetBossHPRatio()
    if registeredBossContext == nil or registeredBossContext.Combat.MaxHP <= 0 then return 0.0 end
    return registeredBossContext.Combat.HP / registeredBossContext.Combat.MaxHP
end

-- [플레이어팀 조회] 현재/최대 체력 (current, max)
function CombatContext.GetBossHP()
    if registeredBossContext == nil then return 0.0, 0.0 end
    return registeredBossContext.Combat.HP, registeredBossContext.Combat.MaxHP
end

-- [플레이어팀 조회] 생존 여부
function CombatContext.IsBossAlive()
    return registeredBossContext ~= nil and registeredBossContext.Combat.HP > 0.0
end

---@param playerContext PlayerContext
---@return number, number
function CombatContext.GetPlayerHP(playerContext)
    PlayerContext.Assert(playerContext, "CombatContext.GetPlayerHP")
    return playerContext.Combat.HP, playerContext.Combat.MaxHP
end

---@param playerContext PlayerContext
---@return number
function CombatContext.GetPlayerHPRatio(playerContext)
    local hp, maxHP = CombatContext.GetPlayerHP(playerContext)
    if maxHP <= 0.0 then
        return 0.0
    end

    return hp / maxHP
end

return CombatContext
