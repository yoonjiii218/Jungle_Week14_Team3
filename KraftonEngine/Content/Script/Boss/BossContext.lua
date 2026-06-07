-- Boss/BossContext.lua
-- Defines the BossContext contract shared by boss action, attack, and feedback modules.

local Strict = require("Core/Strict")

local BossContext = {}

---@class BossBrainState
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

---@class BossCombatState
---@field HP number
---@field MaxHP number
---@field IsDead boolean
---@field RecentHitIds table

---@class BossAttackState
---@field ZoneShow boolean
---@field ZoneFlash boolean
---@field ZoneHide boolean
---@field HitboxOpen boolean
---@field HitboxClose boolean
---@field TrackEnd boolean
---@field ActiveZone table|nil

---@class BossRuntimeState
---@field MovementComp any
---@field ActionComp any
---@field PlayerRef any

---@class BossContext
---@field Kind string
---@field Owner any
---@field Component any
---@field Brain BossBrainState
---@field Attack BossAttackState
---@field Combat BossCombatState
---@field Feedback table
---@field Runtime BossRuntimeState
---@field BB table
---@field bb table Legacy blackboard compatibility view
---@field obj any Legacy owner alias
---@field movComp any Legacy movement component alias
---@field actionComp any Legacy action component alias
---@field playerRef any Legacy player actor alias

local BB_PROXY_FIELDS = {
    ActionLock = { "Brain", "ActionLock" },
    IsTracking = { "Brain", "IsTracking" },
    PatternCooldown = { "Brain", "PatternCooldown" },
    HeavyAttackCooldown = { "Brain", "HeavyAttackCooldown" },
    Distance = { "Brain", "Distance" },
    LastPattern = { "Brain", "LastPattern" },
    TimeScale = { "Brain", "TimeScale" },
    SlomoRemaining = { "Brain", "SlomoRemaining" },
    AnimAttack = { "Brain", "AnimAttack" },
    AnimAttackStart = { "Brain", "AnimAttackStart" },
    AnimAttackHits = { "Brain", "AnimAttackHits" },

    HP = { "Combat", "HP" },
    MaxHP = { "Combat", "MaxHP" },
    IsDead = { "Combat", "IsDead" },
    RecentHitIds = { "Combat", "RecentHitIds" },

    ZoneShow = { "Attack", "ZoneShow" },
    ZoneFlash = { "Attack", "ZoneFlash" },
    ZoneHide = { "Attack", "ZoneHide" },
    HitboxOpen = { "Attack", "HitboxOpen" },
    HitboxClose = { "Attack", "HitboxClose" },
    TrackEnd = { "Attack", "TrackEnd" },
    ActiveZone = { "Attack", "ActiveZone" },
}

local function CreateBlackboardProxy(boss)
    return setmetatable({}, {
        __index = function(_, key)
            local map = BB_PROXY_FIELDS[key]
            if map ~= nil then
                return boss[map[1]][map[2]]
            end
            return nil
        end,
        __newindex = function(_, key, value)
            local map = BB_PROXY_FIELDS[key]
            if map ~= nil then
                boss[map[1]][map[2]] = value
                return
            end
            rawset(_, key, value)
        end,
    })
end

local BossContextMetatable = {
    __index = function(boss, key)
        if key == "obj" then return rawget(boss, "Owner") end
        if key == "movComp" then return boss.Runtime and boss.Runtime.MovementComp or nil end
        if key == "actionComp" then return boss.Runtime and boss.Runtime.ActionComp or nil end
        if key == "playerRef" then return boss.Runtime and boss.Runtime.PlayerRef or nil end
        return nil
    end,
    __newindex = function(boss, key, value)
        if key == "obj" then rawset(boss, "Owner", value); return end
        if key == "movComp" then boss.Runtime.MovementComp = value; return end
        if key == "actionComp" then boss.Runtime.ActionComp = value; return end
        if key == "playerRef" then boss.Runtime.PlayerRef = value; return end
        rawset(boss, key, value)
    end,
}

-- =========================================================
-- Public API
-- =========================================================

---@param owner any
---@param component any
---@param config table
---@return BossContext
function BossContext.Create(owner, component, config)
    Strict.AssertNotNil(owner, "owner", "BossContext.Create")
    Strict.AssertTable(config, "config", "BossContext.Create")

    local boss = {
        Kind = "BossContext",
        Owner = owner,
        Component = component,
        BB = config,
        Brain = {
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
        },
        Attack = {
            ZoneShow = false,
            ZoneFlash = false,
            ZoneHide = false,
            HitboxOpen = false,
            HitboxClose = false,
            TrackEnd = false,
            ActiveZone = nil,
        },
        Combat = {
            HP = config.MAX_HP,
            MaxHP = config.MAX_HP,
            IsDead = false,
            RecentHitIds = {},
        },
        Feedback = {},
        Runtime = {
            MovementComp = owner.GetCharacterMovement and owner:GetCharacterMovement() or nil,
            ActionComp = owner.GetActionComponent and owner:GetActionComponent() or nil,
            PlayerRef = nil,
        },
    }

    boss.bb = CreateBlackboardProxy(boss)
    return setmetatable(boss, BossContextMetatable)
end

---@param boss BossContext
---@param caller string
---@return BossContext
function BossContext.Assert(boss, caller)
    Strict.AssertKind(boss, "BossContext", "boss", caller or "BossContext.Assert")
    Strict.AssertTable(boss.Brain, "boss.Brain", caller or "BossContext.Assert")
    Strict.AssertTable(boss.Attack, "boss.Attack", caller or "BossContext.Assert")
    Strict.AssertTable(boss.Combat, "boss.Combat", caller or "BossContext.Assert")
    Strict.AssertTable(boss.Runtime, "boss.Runtime", caller or "BossContext.Assert")
    return boss
end

return BossContext
