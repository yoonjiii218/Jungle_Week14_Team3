-- Combat/CombatContext.lua
-- CombatContext owns hit resolution, HP/gauge changes, and combat registries.
-- It consumes/produces typed HitRequest and PlayerEvent tables.

local CombatContext = {}

local CoroutineManager = require("CoroutineManager")
local PlayerContext = require("Player/PlayerContext")
local PlayerEvents = require("Player/PlayerEvents")
local PlayerAction = require("Player/PlayerAction")
local HitTypes = require("Combat/HitTypes")
local BossContext = require("Boss/BossContext")
local BossEvents = require("Boss/BossEvents")
local BossFeedback = require("Boss/BossFeedback")
local MobContext = require("Mob/MobContext")
local Strict = require("Core/Strict")
local GameplayEventBus = require("Core/GameplayEventBus")

local playersByOwner = {}
local mobsByOwner = {}
local activeEnemyAttackWindows = {}
local COLLISION_NO = 0

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

local function GetFirstPlayerContext()
    for _, playerContext in pairs(playersByOwner) do
        return playerContext
    end
    return nil
end

local function GetGameFlowDirector()
    if GameFlow == nil or GameFlow.GetDirector == nil then
        return nil
    end
    return GameFlow.GetDirector()
end

local function SyncPlayerToGameFlow(playerContext)
    if playerContext == nil then
        return
    end

    local director = GetGameFlowDirector()
    if director == nil then
        return
    end

    if director.SetPlayerHP ~= nil then
        director:SetPlayerHP(playerContext.Combat.HP or 0.0, playerContext.Combat.MaxHP or 0.0)
    end
    if director.SetUltimateGauge ~= nil then
        director:SetUltimateGauge(playerContext.Combat.UltimateGauge or 0.0, playerContext.Combat.MaxUltimateGauge or 0.0)
    end
    if director.SetComboCount ~= nil then
        director:SetComboCount(playerContext.Combat.ComboCount or 0)
    end
end

local function SyncBossToGameFlow(bossContext)
    if bossContext == nil then
        return
    end

    local director = GetGameFlowDirector()
    if director ~= nil and director.SetBossHP ~= nil then
        director:SetBossHP(bossContext.Combat.HP or 0.0, bossContext.Combat.MaxHP or 0.0)
    end
end

local function ResetPlayerCombatState(playerContext)
    local combatConfig = playerContext.Config.Combat
    playerContext.Combat.MaxHP = combatConfig.MaxHP
    playerContext.Combat.HP = combatConfig.MaxHP
    playerContext.Combat.MaxUltimateGauge = combatConfig.MaxUltimateGauge
    playerContext.Combat.UltimateGauge = 0
    playerContext.Combat.ComboCount = 0
    playerContext.Combat.IsDead = false
    playerContext.Combat.InvincibleUntil = 0.0
    playerContext.Combat.DodgeInvincibleUntil = 0.0
    playerContext.Combat.PerfectDodgeConsumedUntil = 0.0
    playerContext.Combat.RecentHitIds = {}
    playerContext.Combat.CurrentThreat = nil
    playerContext.Combat.CombatDodgeActive = false
    playerContext.Combat.DodgeStartLocation = nil
    playerContext.Combat.LastHitTime = 0.0
end

local function ResetBossCombatState(bossContext)
    local maxHP = bossContext.Config.MAX_HP or bossContext.Combat.MaxHP or 1.0
    bossContext.Combat.MaxHP = maxHP
    bossContext.Combat.HP = maxHP
    bossContext.Combat.IsDead = false
    bossContext.Combat.InvincibleUntil = 0.0
    bossContext.Combat.StaggerUntil = 0.0
    bossContext.Combat.RecentHitIds = {}

    bossContext.Brain.ActionLock = false
    bossContext.Brain.PatternCooldown = 0.0
    bossContext.Brain.HeavyAttackCooldown = 0.0
    bossContext.Brain.SlomoRemaining = 0.0
    bossContext.Brain.TimeScale = 1.0
    bossContext.Brain.HitReactSignal = nil

    bossContext.Attack.HitWindowOpen = false
    bossContext.Attack.ActiveZones = {}
    bossContext.Attack.RecentHitIds = {}
    bossContext.Attack.ActiveZone = nil
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
    local oldGauge = playerContext.Combat.UltimateGauge or 0.0
    local gauge = oldGauge + (amount or 0.0)
    if gauge < 0 then gauge = 0 end
    if gauge > maxGauge then gauge = maxGauge end
    playerContext.Combat.UltimateGauge = gauge
    playerContext.Combat.MaxUltimateGauge = maxGauge
    SyncPlayerToGameFlow(playerContext)

    if math.abs(gauge - oldGauge) > 0.001 then
        PlayerEvents.EmitGaugeChanged(playerContext, {
            Value = gauge,
            MaxValue = maxGauge,
            Delta = gauge - oldGauge,
        })
    end
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

local function RemoveActorTargetingTags(actor)
    if not IsValidActor(actor) or actor.RemoveTag == nil then
        return
    end

    actor:RemoveTag("HitTarget")
    actor:RemoveTag("Enemy")
    actor:RemoveTag("Mob")
end

local function ClearPlayerTargetAssistForActor(targetActor)
    if targetActor == nil then
        return
    end

    for _, playerContext in pairs(playersByOwner) do
        if playerContext.Runtime ~= nil and playerContext.Runtime.TargetAssistTarget == targetActor then
            playerContext.Runtime.TargetAssistTarget = nil
            playerContext.Runtime.TargetAssistDirection = nil
            playerContext.Runtime.TargetAssistDistance = nil
            playerContext.Runtime.TargetAssistLockedDirection = nil
            playerContext.Runtime.TargetAssistEndTime = 0.0
            playerContext.Runtime.TargetAssistKeepUntil = 0.0
        end
    end
end

-- Perfect dodge is gameplay time control, not just visual feedback.
-- TimeRush = world slomo + player custom time dilation compensation.
local function ApplyCombatTimeRush(actor, duration, worldScale, playerSpeedScale, enemyBrainScale)
    duration = duration or 0.0
    if duration <= 0.0 then
        return
    end

    worldScale = worldScale or 0.1
    playerSpeedScale = playerSpeedScale or 1.0
    enemyBrainScale = enemyBrainScale or 1.0

    local action = GetOrAddActionComponent(actor)
    if action ~= nil then
        if action.TimeRush ~= nil then
            action:TimeRush(duration, worldScale, playerSpeedScale)
        elseif action.Slomo ~= nil then
            action:Slomo(duration, worldScale)
        end
    end

    -- GlobalTimeDilation already slows enemy Tick dt. Keep the extra brain scale
    -- separately tunable so boss AI is not accidentally slowed twice.
    CombatContext.OnSlomoStarted(duration, enemyBrainScale)
end

---@param playerContext PlayerContext
---@return nil
-- =========================================================
-- Public API
-- =========================================================

function CombatContext.RegisterPlayer(playerContext)
    PlayerContext.Assert(playerContext, "CombatContext.RegisterPlayer")
    ResetPlayerCombatState(playerContext)

    playersByOwner[GetOwnerKey(playerContext.Owner)] = playerContext
    SyncPlayerToGameFlow(playerContext)
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
            local comboDelta = event.ComboDelta or combatConfig.AttackComboGain or 1
            playerContext.Combat.ComboCount = math.max(0, (playerContext.Combat.ComboCount or 0) + comboDelta)
        elseif PlayerEvents.Is(event, PlayerEvents.Type.UltimateStarted) then
            local oldGauge = playerContext.Combat.UltimateGauge or 0.0
            playerContext.Combat.UltimateGauge = 0
            if oldGauge > 0.001 then
                PlayerEvents.EmitGaugeChanged(playerContext, {
                    Value = 0.0,
                    MaxValue = playerContext.Combat.MaxUltimateGauge or combatConfig.MaxUltimateGauge,
                    Delta = -oldGauge,
                })
            end
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

    SyncPlayerToGameFlow(playerContext)
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
    playersByOwner = {}
    mobsByOwner = {}
    activeEnemyAttackWindows = {}
end

---@param bossContext BossContext
---@return nil
function CombatContext.RegisterBoss(bossContext)
    BossContext.Assert(bossContext, "CombatContext.RegisterBoss")
    ResetBossCombatState(bossContext)
    registeredBossContext = bossContext
    bossRef = bossContext.Owner
    SyncBossToGameFlow(bossContext)
end

-- 보스 런타임 Blackboard 조회 (BossAnimation 이 공격 신호를 읽기 위해 사용)
-- BossAttacks writes AnimAttack signals into bossContext.Brain for BossAnimation to consume.
function CombatContext.GetBossContext()
    return registeredBossContext
end

-- ════════════════════════════════════════════
-- 잡몹 등록 (Mob/ 에서 호출)
-- 보스는 싱글톤(단일 변수)이지만 잡몹은 여러 마리라 액터 키 테이블로 관리한다.
-- (플레이어 레지스트리와 동일한 방식)
-- ════════════════════════════════════════════

---@param mobContext MobContext
---@return nil
function CombatContext.RegisterMob(mobContext)
    MobContext.Assert(mobContext, "CombatContext.RegisterMob")
    mobContext.Combat.MaxHP = mobContext.Combat.MaxHP or mobContext.Config.MAX_HP
    mobContext.Combat.RecentHitIds = mobContext.Combat.RecentHitIds or {}
    mobsByOwner[GetOwnerKey(mobContext.Owner)] = mobContext
end

---@param mobContext MobContext
---@return nil
function CombatContext.UnregisterMob(mobContext)
    MobContext.Assert(mobContext, "CombatContext.UnregisterMob")
    local key = GetOwnerKey(mobContext.Owner)
    if mobsByOwner[key] == mobContext then
        mobsByOwner[key] = nil
    end
end

---@param owner any
---@return MobContext|nil
function CombatContext.GetMobByOwner(owner)
    return mobsByOwner[GetOwnerKey(owner)]
end

-- ════════════════════════════════════════════
-- 퍼펙트 회피 / 슬로모
-- ════════════════════════════════════════════

-- [플레이어팀 호출] 글로벌 슬로모/TimeRush를 시작했다고 보스에 알림.
--   enemyBrainScale은 GlobalTimeDilation 위에 추가로 곱할 AI/쿨타임 보정값이다.
function CombatContext.OnSlomoStarted(duration, scale)
    if registeredBossContext == nil then return end
    duration = duration or 0.0
    scale = scale or 1.0

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
    local playerSpeedScale = combatConfig.PerfectDodgePlayerSpeedScale or 1.0
    local enemyBrainScale = combatConfig.PerfectDodgeEnemyBrainScale or 1.0

    CombatContext.SetCurrentThreat(playerContext, hit.SourceActor)

    PlayerEvents.EmitPerfectDodge(playerContext, {
        Threat = hit.SourceActor,
        AttackId = hit.AttackId,
        GaugeDelta = combatConfig.PerfectDodgeGaugeDelta,
        SlomoDuration = duration,
        SlomoScale = scale,
        PlayerSpeedScale = playerSpeedScale,
        EnemyBrainScale = enemyBrainScale,
    })

    ApplyCombatTimeRush(playerContext.Owner, duration, scale, playerSpeedScale, enemyBrainScale)

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

    local targetMobContext = CombatContext.GetMobByOwner(hit.TargetActor)
    if targetMobContext ~= nil then
        return CombatContext.ApplyHitToMob(targetMobContext, hit)
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

    if playerContext.Action.IsUltimateRunning == true or playerContext.Action.IsInUltimateMode == true then
        return HitTypes.CreateResult({ Applied = false, Reason = "UltimateInvincible" })
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
    SyncPlayerToGameFlow(playerContext)
    PlayerAction.BeginHitReaction(playerContext, hit)

    ApplyLocalHitStop(playerContext.Owner, hit.HitStopDuration or combatConfig.HitStopDuration)
    ApplyLocalHitStop(hit.SourceActor, hit.HitStopDuration or combatConfig.EnemyHitStopDuration)

    PlayerEvents.EmitHit(playerContext, {
        SourceActor = hit.SourceActor,
        AttackId = hit.AttackId,
        Damage = damage,
        HP = playerContext.Combat.HP,
        MaxHP = playerContext.Combat.MaxHP,
        HitDirection = playerContext.Action.HitReactDirection,
        KnockbackDirection = playerContext.Runtime.HitKnockbackDirection,
    })

    print(string.format("[Player] 피격! -%.0f   HP: %.0f / %.0f   attack=%s",
        damage, playerContext.Combat.HP, playerContext.Combat.MaxHP, tostring(hit.AttackId)))

    if playerContext.Combat.HP <= 0.0 then
        playerContext.Combat.IsDead = true
        SyncPlayerToGameFlow(playerContext)
        PlayerEvents.EmitDead(playerContext, {
            SourceActor = hit.SourceActor,
            AttackId = hit.AttackId,
        })
        print("[Player] ☠ 사망!")
    end

    return HitTypes.CreateResult({ Applied = true, Target = "Player", Damage = damage, HP = playerContext.Combat.HP, MaxHP = playerContext.Combat.MaxHP })
end

-- ════════════════════════════════════════════
-- 피격 방향 판정 (대상 기준 앞/뒤/좌/우) — 보스/잡몹 공용
-- 플레이어 PlayerAction.ResolveHitReaction 을 적 캐릭터로 이식한 것.
-- 대상의 forward/right 와 "대상→공격자" 반대 벡터를 내적해 4방향 중 하나로 분류한다.
-- ════════════════════════════════════════════

local function Dot2D(a, b)
    if a == nil or b == nil then
        return 0.0
    end
    return (a.X or 0.0) * (b.X or 0.0) + (a.Y or 0.0) * (b.Y or 0.0)
end

local function GetActorForward2DByCall(actor)
    if actor == nil then return nil end
    local dir = Reflection.Call(actor, "GetActorForward")
    if dir == nil then return nil end
    dir.Z = 0.0
    if dir:Length() <= 0.001 then return nil end
    return dir:Normalized()
end

local function GetActorRight2DByCall(actor)
    if actor == nil then return nil end
    local dir = Reflection.Call(actor, "GetActorRight")
    if dir == nil then return nil end
    dir.Z = 0.0
    if dir:Length() <= 0.001 then return nil end
    return dir:Normalized()
end

local function GetActorLocation2DByCall(actor)
    if actor == nil then return nil end
    local location = Reflection.Call(actor, "GetActorLocation")
    if location == nil then return nil end
    location.Z = 0.0
    return location
end

-- @return string  "Front" | "Back" | "Left" | "Right" (정보 부족 시 "Front")
local function ResolveHitDirection(targetOwner, sourceActor)
    local ownerLocation = GetActorLocation2DByCall(targetOwner)
    local sourceLocation = GetActorLocation2DByCall(sourceActor)
    local ownerForward = GetActorForward2DByCall(targetOwner)
    local ownerRight = GetActorRight2DByCall(targetOwner)

    local ownerToSource = nil
    if ownerLocation ~= nil and sourceLocation ~= nil then
        local sourceToOwner = ownerLocation - sourceLocation
        sourceToOwner.Z = 0.0
        if sourceToOwner:Length() > 0.001 then
            ownerToSource = sourceToOwner:Normalized() * -1.0
        end
    end

    local hitDirection = "Front"
    if ownerToSource ~= nil and ownerForward ~= nil and ownerRight ~= nil then
        local frontDot = Dot2D(ownerForward, ownerToSource)
        local rightDot = Dot2D(ownerRight, ownerToSource)

        if math.abs(rightDot) > math.abs(frontDot) then
            -- 엔진 GetActorRight 방향상 화면 기준 좌우가 반대라 스왑한다.
            hitDirection = rightDot >= 0.0 and "Left" or "Right"
        elseif frontDot >= 0.0 then
            hitDirection = "Front"
        else
            hitDirection = "Back"
        end
    end

    return hitDirection
end

-- 사망 모션 선택용 방향 판정. 좌/우는 구분하지 않고 "치명타가 앞에서 들어왔는가/뒤에서 들어왔는가"만 본다.
-- @return string  "Front" | "Back" (정보 부족 시 "Front")
local function ResolveDeathDirection(targetOwner, sourceActor)
    local ownerLocation = GetActorLocation2DByCall(targetOwner)
    local sourceLocation = GetActorLocation2DByCall(sourceActor)
    local ownerForward = GetActorForward2DByCall(targetOwner)

    if ownerLocation ~= nil and sourceLocation ~= nil and ownerForward ~= nil then
        local sourceToOwner = ownerLocation - sourceLocation
        sourceToOwner.Z = 0.0
        if sourceToOwner:Length() > 0.001 then
            local ownerToSource = sourceToOwner:Normalized() * -1.0
            if Dot2D(ownerForward, ownerToSource) < 0.0 then
                return "Back"
            end
        end
    end

    return "Front"
end

-- 보스 사망 처리 (HP 0 도달 시 1회만)
local function HandleBossDeath(bossContext, hit)
    if bossContext == nil or bossContext.Combat.IsDead then return end

    bossContext.Combat.IsDead = true
    bossContext.Brain.ActionLock = false

    -- 사망 즉시 정지: 진행 중이던 공격 패턴 코루틴(장판 표시·히트박스 열기/닫기 등)을 전부 멈추고
    -- 화면에 남아있는 장판(텔레그래프) 데칼을 즉시 지운다.
    -- (코루틴을 안 멈추면 죽은 보스가 계속 장판을 띄우거나 히트박스를 여닫는 등 유령처럼 행동한다.)
    local attackState = bossContext.Attack
    for _, zone in ipairs(attackState.ActiveZones) do
        BossFeedback.HideAttackZone(bossContext, { Zone = zone })
    end
    attackState.CurrentPhase  = nil
    attackState.HitWindowOpen = false
    attackState.HitboxOpen    = false
    attackState.HitboxClose   = false
    attackState.ActiveZone    = nil
    attackState.ActiveZones   = {}

    if bossRef ~= nil then
        CoroutineManager.Destroy(bossRef.UUID)
    end

    -- 사망 모션 방향 신호 (BossAnimation 이 소비해 SamuraiDeath_Front/Back 재생)
    bossContext.Brain.DeathSignal = ResolveDeathDirection(bossRef, hit and hit.SourceActor or nil)

    -- 이동 정지
    if bossRef and bossRef:IsValid() then
        local mov = bossRef:GetCharacterMovement()
        if mov then mov:StopMovementImmediately() end

        if bossRef.RemoveTag ~= nil then
            bossRef:RemoveTag("Boss")
            bossRef:RemoveTag("HitTarget")
        end

        if bossRef.GetRootPrimitiveComponent ~= nil then
            local rootPrimitive = bossRef:GetRootPrimitiveComponent()
            if rootPrimitive ~= nil and rootPrimitive.SetCollisionEnabled ~= nil then
                rootPrimitive:SetCollisionEnabled(COLLISION_NO)
            end
        end
    end

    for _, playerContext in pairs(playersByOwner) do
        if playerContext.Runtime ~= nil and playerContext.Runtime.TargetAssistTarget == bossRef then
            playerContext.Runtime.TargetAssistTarget = nil
            playerContext.Runtime.TargetAssistDirection = nil
            playerContext.Runtime.TargetAssistDistance = nil
            playerContext.Runtime.TargetAssistLockedDirection = nil
            playerContext.Runtime.TargetAssistEndTime = 0.0
            playerContext.Runtime.TargetAssistKeepUntil = 0.0
        end
    end

    BossEvents.EmitDead(bossContext, {
        SourceActor = hit and hit.SourceActor or nil,
        AttackId = hit and hit.AttackId or nil,
    })

    -- 외부 시스템(WaveDirector 등)이 소비하는 사망 신호.
    GameplayEventBus.Publish({ Type = "BossDead", Owner = bossRef })

    print("[Boss] ☠ 사망!")
    -- TODO: 전투 종료 이벤트, 보상 등 (에셋/연출 단계)
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

    -- 넉백은 보스 ActionComponent 에 면역 플래그를 켜서 막는다 (BossCharacter.BeginPlay 참고).
    -- 그래서 여기서 넉백을 따로 취소할 필요가 없다.

    local damage = hit.Damage or 0
    if damage <= 0 then
        return HitTypes.CreateResult({ Applied = false, Reason = "NoDamage" })
    end

    bossContext.Combat.HP = math.max(0.0, bossContext.Combat.HP - damage)
    SyncBossToGameFlow(bossContext)

    -- 피격 방향 판정 → 방향별 피격 모션 신호 (BossAnimation 이 소비)
    -- 치명타(HP 0)면 사망 래그돌로 넘어가므로 피격 모션 신호는 생략한다.
    local hitDirection = ResolveHitDirection(bossRef, hit.SourceActor)
    local hitReactConfig = bossContext.Config.HIT_REACT
    if (hitReactConfig == nil or hitReactConfig.ENABLED ~= false)
        and bossContext.Combat.HP > 0.0 then
        bossContext.Brain.HitReactSignal = hitDirection
    end

    BossEvents.EmitHit(bossContext, {
        SourceActor = hit.SourceActor,
        AttackId = hit.AttackId,
        Damage = damage,
        HP = bossContext.Combat.HP,
        MaxHP = bossContext.Combat.MaxHP,
        HitDirection = hitDirection,
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
            HitResult = hit.HitResult,
            HitLocation = hit.HitResult and hit.HitResult.WorldHitLocation or nil,
            GaugeDelta = hit.GaugeDelta or combatConfig.AttackHitGaugeDelta or 0,
            ComboDelta = hit.ComboDelta or combatConfig.AttackComboGain or 1,
            HP = bossContext.Combat.HP,
            MaxHP = bossContext.Combat.MaxHP,
        })
    end

    print(string.format("[Boss] 피격! -%.0f   HP: %.0f / %.0f   attack=%s",
          damage, bossContext.Combat.HP, bossContext.Combat.MaxHP, tostring(hit.AttackId)))

    if bossContext.Combat.HP <= 0.0 then
        HandleBossDeath(bossContext, hit)
        SyncBossToGameFlow(bossContext)
    end

    return HitTypes.CreateResult({ Applied = true, Target = "Boss", Damage = damage, HP = bossContext.Combat.HP, MaxHP = bossContext.Combat.MaxHP })
end

-- 잡몹 사망 처리 (HP 0 도달 시 1회만). 보스의 HandleBossDeath 대응.
local function HandleMobDeath(mobContext, hit)
    if mobContext == nil or mobContext.Combat.IsDead then return end

    mobContext.Combat.IsDead = true
    -- 락을 풀어 "맞고 굳어버리는" 상태를 방지 (MobAction.Update 는 IsDead 면 어차피 조기 반환).
    mobContext.Combat.ActionLock = false
    mobContext.Combat.CancelAttack = true

    -- 사망한 잡몹은 MobCharacter.Tick 의 일반 업데이트 경로를 더 이상 돌지 않는다.
    -- 그래서 진행 중인 공격 코루틴이 장판 HideZone 까지 자연스럽게 도달하지 못할 수 있다.
    -- 실제 Decal/코루틴 정리는 MobCharacter 의 사망 진입 첫 프레임에서 MobAttacks.CleanupActiveAttack 으로 수행한다.

    -- 사망 모션 방향 신호 (MobAnimation 이 소비해 Death_Forward/Backward 재생)
    -- 보스의 HandleBossDeath 와 동일하게, 치명타가 앞에서 들어왔으면 "Front", 뒤에서 들어왔으면 "Back".
    mobContext.Combat.DeathSignal = ResolveDeathDirection(mobContext.Owner, hit and hit.SourceActor or nil)

    if mobContext.Runtime ~= nil and mobContext.Runtime.MovementComp ~= nil then
        mobContext.Runtime.MovementComp:StopMovementImmediately()
    end

    -- Dead mobs must not be re-selected by attack assist / lock-on.
    -- Do not disable collision here; corpse collision / death animation can be handled separately.
    RemoveActorTargetingTags(mobContext.Owner)
    ClearPlayerTargetAssistForActor(mobContext.Owner)

    print("[Mob] ☠ 사망!  attack=" .. tostring(hit and hit.AttackId or nil))

    -- 외부 시스템(WaveDirector 등)이 소비하는 사망 신호.
    GameplayEventBus.Publish({ Type = "MobDead", Owner = mobContext.Owner })
    -- TODO: 사망 애니메이션 / 디스폰 / 보상 (에셋·연출 단계)
end

-- 보스 ApplyHitToBoss 를 잡몹용으로 옮긴 것. 잡몹은 여러 마리라 mobContext 를 인자로 받는다.
-- (보스는 싱글톤이라 인자 없이 registeredBossContext 를 쓰는 것과 대비)
function CombatContext.ApplyHitToMob(mobContext, hitRequest)
    MobContext.Assert(mobContext, "CombatContext.ApplyHitToMob")
    local hit = NormalizeHit(hitRequest)

    if mobContext.Combat.IsDead then
        return HitTypes.CreateResult({ Applied = false, Reason = "MobDead" })
    end

    local now = Now()
    mobContext.Combat.RecentHitIds = mobContext.Combat.RecentHitIds or {}
    PruneRecentHits(mobContext.Combat.RecentHitIds, now)

    local key = MakeHitKey(hit)
    if mobContext.Combat.RecentHitIds[key] ~= nil then
        return HitTypes.CreateResult({ Applied = false, Reason = "DuplicateHit" })
    end
    mobContext.Combat.RecentHitIds[key] = now + (hit.DuplicateHitLifetime or 1.0)

    local damage = hit.Damage or 0
    if damage <= 0 then
        return HitTypes.CreateResult({ Applied = false, Reason = "NoDamage" })
    end

    local maxHP = mobContext.Combat.MaxHP or mobContext.Config.MAX_HP
    mobContext.Combat.MaxHP = maxHP
    mobContext.Combat.HP = math.max(0.0, mobContext.Combat.HP - damage)

    -- 피격 방향 판정 → 방향별 피격 모션 신호 (MobAnimation 이 소비). 치명타면 사망 처리로 넘기고 생략.
    -- 잡몹은 넉백을 유지하되, 공격 중(ActionLock)에 맞으면 진행 중인 공격 코루틴을 취소한다.
    local hitReactConfig = mobContext.Config.HIT_REACT
    if (hitReactConfig == nil or hitReactConfig.ENABLED ~= false) and mobContext.Combat.HP > 0.0 then
        mobContext.Combat.HitReactSignal = ResolveHitDirection(mobContext.Owner, hit.SourceActor)
        if mobContext.Combat.ActionLock == true
            and (hitReactConfig == nil or hitReactConfig.CANCEL_ATTACK_ON_HIT ~= false) then
            mobContext.Combat.CancelAttack = true
        end
    end

    local sourcePlayerContext = CombatContext.GetPlayerByOwner(hit.SourceActor)
    if sourcePlayerContext ~= nil then
        local combatConfig = sourcePlayerContext.Config.Combat
        ApplyLocalHitStop(hit.SourceActor, hit.HitStopDuration or combatConfig.HitStopDuration)
        ApplyLocalHitStop(mobContext.Owner, hit.HitStopDuration or combatConfig.EnemyHitStopDuration)

        PlayerEvents.EmitAttackHit(sourcePlayerContext, {
            AttackId = hit.AttackId,
            AttackIndex = hit.AttackIndex,
            TargetActor = mobContext.Owner,
            Damage = damage,
            HitResult = hit.HitResult,
            HitLocation = hit.HitResult and hit.HitResult.WorldHitLocation or nil,
            GaugeDelta = hit.GaugeDelta or combatConfig.AttackHitGaugeDelta or 0,
            ComboDelta = hit.ComboDelta or combatConfig.AttackComboGain or 1,
            HP = mobContext.Combat.HP,
            MaxHP = maxHP,
        })
    end

    print(string.format("[Mob] 피격! -%.0f   HP: %.0f / %.0f   attack=%s",
          damage, mobContext.Combat.HP, maxHP, tostring(hit.AttackId)))

    if mobContext.Combat.HP <= 0.0 then
        HandleMobDeath(mobContext, hit)
    end

    return HitTypes.CreateResult({ Applied = true, Target = "Mob", Damage = damage, HP = mobContext.Combat.HP, MaxHP = maxHP })
end

---@param playerContext PlayerContext
---@param centerLocation Vector|nil
---@param forcedTarget any|nil
---@return number
function CombatContext.ApplyPlayerUltimateDamage(playerContext, centerLocation, forcedTarget)
    PlayerContext.Assert(playerContext, "CombatContext.ApplyPlayerUltimateDamage")

    local owner = playerContext.Owner
    if owner == nil then
        return 0
    end

    local combatConfig = playerContext.Config.Combat or {}
    local range = combatConfig.UltimateRange or 0.0
    local damage = combatConfig.UltimateDamage or 0.0
    if damage <= 0.0 then
        return 0
    end

    local center = centerLocation
    if center == nil and forcedTarget ~= nil then
        center = GetActorLocation2DByCall(forcedTarget)
    end
    if center == nil then
        center = GetActorLocation2DByCall(owner)
    end
    if center == nil then
        return 0
    end

    local function IsInRange(actor)
        if not IsValidActor(actor) then
            return false
        end
        if range <= 0.0 then
            return true
        end
        local location = GetActorLocation2DByCall(actor)
        if location == nil then
            return false
        end
        local delta = location - center
        delta.Z = 0.0
        return delta:Length() <= range
    end

    local attackInstanceId = playerContext.Action.UltimateAttackInstanceId
        or ("PlayerUltimate_" .. tostring(Now()))
    playerContext.Action.UltimateAttackInstanceId = attackInstanceId

    local hit = {
        SourceActor = owner,
        SourceTeam = "Player",
        TargetTeam = "Enemy",
        AttackId = "PlayerUltimate",
        AttackInstanceId = attackInstanceId,
        Damage = damage,
        GaugeDelta = 0,
        DuplicateHitLifetime = combatConfig.UltimateDuplicateHitLifetime or combatConfig.DuplicateHitLifetime,
        HitStopDuration = combatConfig.UltimateHitStopDuration or combatConfig.HitStopDuration,
    }

    local appliedCount = 0
    local visited = {}

    local function TryApply(actor)
        local key = GetOwnerKey(actor) or tostring(actor)
        if visited[key] == true or not IsInRange(actor) then
            return
        end
        visited[key] = true
        hit.TargetActor = actor
        local result = CombatContext.ApplyHit(hit)
        if result ~= nil and result.Applied == true then
            appliedCount = appliedCount + 1
        end
    end

    if forcedTarget ~= nil then
        TryApply(forcedTarget)
    end

    if bossRef ~= nil then
        TryApply(bossRef)
    end

    for _, mobContext in pairs(mobsByOwner) do
        if mobContext ~= nil and (mobContext.Combat == nil or mobContext.Combat.IsDead ~= true) then
            TryApply(mobContext.Owner)
        end
    end

    return appliedCount
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

function CombatContext.HasBoss()
    return registeredBossContext ~= nil
end

-- [플레이어팀 조회] 생존 여부
function CombatContext.IsBossAlive()
    return registeredBossContext ~= nil and registeredBossContext.Combat.HP > 0.0
end

function CombatContext.GetFirstPlayer()
    return GetFirstPlayerContext()
end

function CombatContext.HasPlayer()
    return GetFirstPlayerContext() ~= nil
end

---@param playerContext PlayerContext|nil
---@return number, number
function CombatContext.GetPlayerHP(playerContext)
    playerContext = playerContext or GetFirstPlayerContext()
    if playerContext == nil then
        return 0.0, 0.0
    end
    PlayerContext.Assert(playerContext, "CombatContext.GetPlayerHP")
    return playerContext.Combat.HP, playerContext.Combat.MaxHP
end

function CombatContext.SetPlayerHP(current, maxHP, playerContext)
    playerContext = playerContext or GetFirstPlayerContext()
    if playerContext == nil then
        return false
    end

    local resolvedMax = maxHP or playerContext.Combat.MaxHP or playerContext.Config.Combat.MaxHP
    resolvedMax = math.max(1.0, resolvedMax)
    playerContext.Combat.MaxHP = resolvedMax
    playerContext.Combat.HP = Clamp(current or resolvedMax, 0.0, resolvedMax)
    playerContext.Combat.IsDead = playerContext.Combat.HP <= 0.0
    SyncPlayerToGameFlow(playerContext)
    return true
end

function CombatContext.ApplyDamageToPlayer(amount, playerContext)
    playerContext = playerContext or GetFirstPlayerContext()
    if playerContext == nil then
        return false
    end

    amount = math.max(0.0, amount or 0.0)
    return CombatContext.SetPlayerHP((playerContext.Combat.HP or 0.0) - amount, playerContext.Combat.MaxHP, playerContext)
end

function CombatContext.GetPlayerUltimate(playerContext)
    playerContext = playerContext or GetFirstPlayerContext()
    if playerContext == nil then
        return 0.0, 0.0
    end
    PlayerContext.Assert(playerContext, "CombatContext.GetPlayerUltimate")
    return playerContext.Combat.UltimateGauge or 0.0, playerContext.Combat.MaxUltimateGauge or 0.0
end

---@param playerContext PlayerContext|nil
---@return number, number, number
function CombatContext.GetPlayerDashCooldown(playerContext)
    playerContext = playerContext or GetFirstPlayerContext()
    if playerContext == nil then
        return 0.0, 0.0, 0.0
    end
    PlayerContext.Assert(playerContext, "CombatContext.GetPlayerDashCooldown")

    if PlayerAction.GetDashCooldown ~= nil then
        return PlayerAction.GetDashCooldown(playerContext)
    end

    local duration = playerContext.Action.DashCooldownDuration or 0.0
    local remaining = math.max(0.0, playerContext.Action.DashCooldownRemaining or 0.0)
    local ratio = 0.0
    if duration > 0.0 then
        ratio = Clamp(remaining / duration, 0.0, 1.0)
    end
    return remaining, duration, ratio
end

function CombatContext.SetPlayerUltimate(current, maxGauge, playerContext)
    playerContext = playerContext or GetFirstPlayerContext()
    if playerContext == nil then
        return false
    end

    local resolvedMax = maxGauge or playerContext.Combat.MaxUltimateGauge or playerContext.Config.Combat.MaxUltimateGauge
    resolvedMax = math.max(1.0, resolvedMax)
    local oldGauge = playerContext.Combat.UltimateGauge or 0.0
    local newGauge = Clamp(current or 0.0, 0.0, resolvedMax)
    playerContext.Combat.MaxUltimateGauge = resolvedMax
    playerContext.Combat.UltimateGauge = newGauge
    SyncPlayerToGameFlow(playerContext)
    if math.abs(newGauge - oldGauge) > 0.001 then
        PlayerEvents.EmitGaugeChanged(playerContext, {
            Value = newGauge,
            MaxValue = resolvedMax,
            Delta = newGauge - oldGauge,
        })
    end
    return true
end

function CombatContext.AddPlayerUltimate(delta, playerContext)
    playerContext = playerContext or GetFirstPlayerContext()
    if playerContext == nil then
        return false
    end
    return CombatContext.SetPlayerUltimate((playerContext.Combat.UltimateGauge or 0.0) + (delta or 0.0), playerContext.Combat.MaxUltimateGauge, playerContext)
end

function CombatContext.GetPlayerCombo(playerContext)
    playerContext = playerContext or GetFirstPlayerContext()
    if playerContext == nil then
        return 0
    end
    PlayerContext.Assert(playerContext, "CombatContext.GetPlayerCombo")
    return playerContext.Combat.ComboCount or 0
end

function CombatContext.SetPlayerCombo(count, playerContext)
    playerContext = playerContext or GetFirstPlayerContext()
    if playerContext == nil then
        return false
    end
    playerContext.Combat.ComboCount = math.max(0, math.floor((count or 0) + 0.5))
    SyncPlayerToGameFlow(playerContext)
    return true
end

function CombatContext.AddPlayerCombo(delta, playerContext)
    playerContext = playerContext or GetFirstPlayerContext()
    if playerContext == nil then
        return false
    end
    return CombatContext.SetPlayerCombo((playerContext.Combat.ComboCount or 0) + (delta or 0), playerContext)
end

function CombatContext.SetBossHP(current, maxHP)
    if registeredBossContext == nil then
        return false
    end

    local resolvedMax = maxHP or registeredBossContext.Combat.MaxHP or registeredBossContext.Config.MAX_HP
    resolvedMax = math.max(1.0, resolvedMax)
    registeredBossContext.Combat.MaxHP = resolvedMax
    registeredBossContext.Combat.HP = Clamp(current or resolvedMax, 0.0, resolvedMax)
    registeredBossContext.Combat.IsDead = registeredBossContext.Combat.HP <= 0.0
    SyncBossToGameFlow(registeredBossContext)
    return true
end

---@param playerContext PlayerContext|nil
---@return number
function CombatContext.GetPlayerHPRatio(playerContext)
    local hp, maxHP = CombatContext.GetPlayerHP(playerContext)
    if maxHP <= 0.0 then
        return 0.0
    end

    return hp / maxHP
end

return CombatContext
