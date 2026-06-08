-- Boss/BossContext.lua
-- Defines the explicit BossContext contract shared by boss modules.
-- Use bossContext.Brain / Attack / Combat / Feedback / Runtime directly.

local Strict = require("Core/Strict")

local BossContext = {}

---@class BossBrainState
---@field State string
---@field TargetActor any
---@field TargetLastKnownPosition any
---@field NextDecisionTime number
---@field ActionLock boolean
---@field IsTracking boolean
---@field PatternCooldown number
---@field HeavyAttackCooldown number
---@field Distance number
---@field LastPattern string|nil
---@field TimeScale number
---@field SlomoRemaining number
---@field AnimAttack string|nil
---@field AnimAttackStart integer|nil
---@field AnimAttackHits integer|nil
---@field HitReactSignal string|nil
---@field DeathSignal string|nil

---@class BossAttackState
---@field CurrentAttackId string|nil
---@field CurrentPhase string|nil
---@field AttackStartedAt number
---@field AttackEndsAt number
---@field HitWindowOpen boolean
---@field ActiveZones table
---@field RecentHitIds table
---@field ZoneShow boolean
---@field ZoneFlash boolean
---@field ZoneHide boolean
---@field HitboxOpen boolean
---@field HitboxClose boolean
---@field TrackEnd boolean
---@field ActiveZone table|nil

---@class BossCombatState
---@field HP number
---@field MaxHP number
---@field IsDead boolean
---@field InvincibleUntil number
---@field StaggerUntil number
---@field RecentHitIds table

---@class BossFeedbackState
---@field CurrentTelegraph any
---@field ActiveVfx table
---@field HitFlashUntil number
---@field KatanaComponent any

---@class BossRuntimeState
---@field MovementComp any
---@field SkeletalMeshComp any
---@field ActionComp any
---@field EventQueue BossEvent[]

---@class BossContext
---@field Kind string
---@field Owner any
---@field Component any
---@field Config table
---@field Brain BossBrainState
---@field Attack BossAttackState
---@field Combat BossCombatState
---@field Feedback BossFeedbackState
---@field Runtime BossRuntimeState

local function CreateBrainState()
    return {
        State = "Idle",
        TargetActor = nil,
        TargetLastKnownPosition = nil,
        NextDecisionTime = 0.0,
        ActionLock = false,
        IsTracking = true,
        PatternCooldown = 0.0,
        HeavyAttackCooldown = 0.0,
        Distance = 999.0,
        LastPattern = nil,
        TimeScale = 1.0,
        SlomoRemaining = 0.0,
        AnimAttack = nil,
        AnimAttackStart = nil,
        AnimAttackHits = nil,
        -- 피격 방향 신호 (CombatContext.ApplyHitToBoss 가 1회성으로 써넣고
        --  BossAnimation 이 소비해 방향별 피격 모션을 트리거한다.) "Front"/"Back"/"Left"/"Right"
        HitReactSignal = nil,
        -- 사망 모션 방향 신호 (CombatContext.HandleBossDeath 가 1회성으로 써넣고
        --  BossAnimation 이 소비해 SamuraiDeath_Front/Back 을 트리거한다.) "Front"/"Back"
        DeathSignal = nil,
    }
end

local function CreateAttackState()
    return {
        CurrentAttackId = nil,
        CurrentPhase = nil,
        AttackStartedAt = 0.0,
        AttackEndsAt = 0.0,
        HitWindowOpen = false,
        ActiveZones = {},
        RecentHitIds = {},
        ZoneShow = false,
        ZoneFlash = false,
        ZoneHide = false,
        HitboxOpen = false,
        HitboxClose = false,
        TrackEnd = false,
        ActiveZone = nil,
    }
end

local function CreateCombatState(config)
    Strict.AssertNumber(config.MAX_HP, "config.MAX_HP", "BossContext.Create")
    return {
        HP = config.MAX_HP,
        MaxHP = config.MAX_HP,
        IsDead = false,
        InvincibleUntil = 0.0,
        StaggerUntil = 0.0,
        RecentHitIds = {},
    }
end

local function CreateFeedbackState()
    return {
        CurrentTelegraph = nil,
        ActiveVfx = {},
        HitFlashUntil = 0.0,
        KatanaComponent = nil,
        -- attackId → 직전 ZoneShow~ZoneFlash 실측 간격(초). 다음 재생 시 장판 차오름 속도를 여기에 맞춘다.
        MeasuredFillDuration = {},
    }
end

local function CreateRuntimeState(owner)
    return {
        MovementComp = owner.GetCharacterMovement and owner:GetCharacterMovement() or nil,
        SkeletalMeshComp = owner.GetSkeletalMeshComponent and owner:GetSkeletalMeshComponent() or nil,
        ActionComp = owner.GetActionComponent and owner:GetActionComponent() or nil,
        EventQueue = {},
    }
end

-- =========================================================
-- Public API
-- =========================================================

---@param ownerActor any
---@param component any
---@param config table
---@return BossContext
function BossContext.Create(ownerActor, component, config)
    Strict.AssertNotNil(ownerActor, "ownerActor", "BossContext.Create")
    Strict.AssertTable(config, "config", "BossContext.Create")

    return {
        Kind = "BossContext",
        Owner = ownerActor,
        Component = component,
        Config = config,
        Brain = CreateBrainState(),
        Attack = CreateAttackState(),
        Combat = CreateCombatState(config),
        Feedback = CreateFeedbackState(),
        Runtime = CreateRuntimeState(ownerActor),
    }
end

---@param bossContext BossContext
---@param caller string
---@return BossContext
function BossContext.Assert(bossContext, caller)
    Strict.AssertKind(bossContext, "BossContext", "bossContext", caller or "BossContext.Assert")
    Strict.AssertTable(bossContext.Config, "bossContext.Config", caller or "BossContext.Assert")
    Strict.AssertTable(bossContext.Brain, "bossContext.Brain", caller or "BossContext.Assert")
    Strict.AssertTable(bossContext.Attack, "bossContext.Attack", caller or "BossContext.Assert")
    Strict.AssertTable(bossContext.Combat, "bossContext.Combat", caller or "BossContext.Assert")
    Strict.AssertTable(bossContext.Feedback, "bossContext.Feedback", caller or "BossContext.Assert")
    Strict.AssertTable(bossContext.Runtime, "bossContext.Runtime", caller or "BossContext.Assert")
    return bossContext
end

return BossContext
