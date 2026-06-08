-- Mob/MobContext.lua
-- Defines the explicit MobContext contract shared by mob modules.
-- Use mobContext.Brain / Attack / Combat / Runtime directly. No globals.

local Strict = require("Core/Strict")

local MobContext = {}

---@class MobBrainState
---@field State string                "Chase" | "Attack"
---@field TargetActor any
---@field Distance number
---@field PatternCooldown number
---@field IsTracking boolean
---@field TimeScale number

---@class MobAttackState
---@field ZoneShow boolean
---@field ZoneFlash boolean
---@field ZoneHide boolean
---@field HitboxOpen boolean
---@field HitboxClose boolean
---@field TrackEnd boolean

---@class MobCombatState
---@field HP number
---@field MaxHP number
---@field IsDead boolean
---@field ActionLock boolean
---@field RecentHitIds table
---@field HitReactSignal string|nil   피격 방향 1회성 신호 (CombatContext → MobAnimation)
---@field HitReactActive boolean      피격 모션 재생 중 (MobAnimation → MobAction 행동 억제)
---@field CancelAttack boolean        진행 중인 공격 코루틴 취소 요청
---@field DeathSignal string|nil      사망 방향 1회성 신호 "Front"/"Back" (CombatContext → MobAnimation)

---@class MobRuntimeState
---@field MovementComp any
---@field SkeletalMeshComp any
---@field KatanaComponent any

---@class MobContext
---@field Kind string
---@field Owner any
---@field Component any
---@field Config table
---@field Brain MobBrainState
---@field Attack MobAttackState
---@field Combat MobCombatState
---@field Runtime MobRuntimeState

local function CreateBrainState()
    return {
        State = "Chase",
        TargetActor = nil,
        Distance = 999.0,
        PatternCooldown = 0.0,
        IsTracking = true,
        TimeScale = 1.0,
    }
end

local function CreateAttackState()
    return {
        ZoneShow = false,
        ZoneFlash = false,
        ZoneHide = false,
        HitboxOpen = false,
        HitboxClose = false,
        TrackEnd = false,
    }
end

local function CreateCombatState(config)
    Strict.AssertNumber(config.MAX_HP, "config.MAX_HP", "MobContext.Create")
    return {
        HP = config.MAX_HP,
        MaxHP = config.MAX_HP,
        IsDead = false,
        ActionLock = false,
        RecentHitIds = {},
        HitReactSignal = nil,
        HitReactActive = false,
        CancelAttack = false,
        DeathSignal = nil,
    }
end

local function CreateRuntimeState()
    return {}
end

-- =========================================================
-- Public API
-- =========================================================

---@param ownerActor any
---@param component any
---@param config table
---@return MobContext
function MobContext.Create(ownerActor, component, config)
    Strict.AssertNotNil(ownerActor, "ownerActor", "MobContext.Create")
    Strict.AssertTable(config, "config", "MobContext.Create")

    return {
        Kind = "MobContext",
        Owner = ownerActor,
        Component = component,
        Config = config,
        Brain = CreateBrainState(),
        Attack = CreateAttackState(),
        Combat = CreateCombatState(config),
        Runtime = CreateRuntimeState(),
    }
end

-- =========================================================
-- 액터별 레지스트리
-- AnimInstance(MobAnimation)는 self 가 아니라 obj(액터)로 자기 컨텍스트를 찾는다.
-- 잡몹이 여러 마리여도 액터 키로 정확히 매칭된다 (보스 싱글톤과 달리 다중 인스턴스).
-- =========================================================

local registry = {}

local function OwnerKey(owner)
    if owner == nil then return nil end
    return owner.UUID or tostring(owner)
end

---@param mobContext MobContext
---@return nil
function MobContext.Register(mobContext)
    MobContext.Assert(mobContext, "MobContext.Register")
    registry[OwnerKey(mobContext.Owner)] = mobContext
end

---@param mobContext MobContext
---@return nil
function MobContext.Unregister(mobContext)
    MobContext.Assert(mobContext, "MobContext.Unregister")
    local key = OwnerKey(mobContext.Owner)
    if registry[key] == mobContext then
        registry[key] = nil
    end
end

---@param owner any
---@return MobContext|nil
function MobContext.GetByOwner(owner)
    return registry[OwnerKey(owner)]
end

---@param mobContext MobContext
---@param caller string
---@return MobContext
function MobContext.Assert(mobContext, caller)
    Strict.AssertKind(mobContext, "MobContext", "mobContext", caller or "MobContext.Assert")
    Strict.AssertTable(mobContext.Config, "mobContext.Config", caller or "MobContext.Assert")
    Strict.AssertTable(mobContext.Brain, "mobContext.Brain", caller or "MobContext.Assert")
    Strict.AssertTable(mobContext.Attack, "mobContext.Attack", caller or "MobContext.Assert")
    Strict.AssertTable(mobContext.Combat, "mobContext.Combat", caller or "MobContext.Assert")
    Strict.AssertTable(mobContext.Runtime, "mobContext.Runtime", caller or "MobContext.Assert")
    return mobContext
end

return MobContext
