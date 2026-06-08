-- Tutorial/TutorialSpawner.lua
-- Runtime enemy setup for TrainingMap tutorial steps.
--
-- The actual character templates are created by GameFlow.SpawnTutorialMob /
-- GameFlow.SpawnTutorialBoss in C++. Those helpers mirror the ALuaCharacter
-- actor settings from MobTest.Scene and BossTest.Scene, then run BeginPlay only
-- after the mesh/script/capsule/action components have been initialized.

local CombatContext = require("Combat/CombatContext")

local TutorialSpawner = {}

local spawnedMobs = {}
local spawnedBoss = nil
local spawnSerial = 0

-- Scene-reference heights from the uploaded test scenes.
-- MobTest.Scene:  Player Z 3.103536 -> Mob Z 1.765046  => -1.33849
-- BossTest.Scene: Player Z 3.103536 -> Boss Z 8.617209 => +5.513673
local MOB_Z_OFFSET = -1.33849
local BOSS_Z_OFFSET = 5.513673

local DEFAULT_MOB_FORWARD_DISTANCE = 9.0
local DEFAULT_BOSS_FORWARD_DISTANCE = 12.0
local DEFAULT_SIDE_OFFSET = 0.0
local DEFAULT_TUTORIAL_MOB_HP = 10000.0
local TUTORIAL_MOB_HP_BY_LABEL = {
    BasicAttack = 10000.0,
    Combo = 10000.0,
    Dash = 10000.0,
    DashCharge = 10000.0,
    PerfectDodge = 10000.0,
    UltimateMob = 10000.0,
    UltimateMobLeft = 10000.0,
    UltimateMobCenter = 10000.0,
    UltimateMobRight = 10000.0,
}

local function IsValidActor(actor)
    return actor ~= nil and actor.IsValid ~= nil and actor:IsValid()
end

local function GetPlayerActor()
    local player = World.FindFirstActorByTag("Player")
    if IsValidActor(player) then
        return player
    end
    return World.FindActorByName("PlayerCharacter")
end

local function SafeNormalize2D(v, fallback)
    if v == nil then
        return fallback
    end

    local n = Vector(v.X or 0.0, v.Y or 0.0, 0.0)
    if n:Length() <= 0.001 then
        return fallback
    end
    return n:Normalized()
end

local function ComputeFacingYawFromPlayer(player)
    if not IsValidActor(player) then
        return 180.0
    end

    local f = SafeNormalize2D(player.Forward, Vector(1.0, 0.0, 0.0))
    -- Spawned enemy should look back toward the player.
    return math.deg(math.atan2(-f.Y, -f.X))
end

local function ComputeSpawnLocation(forwardDistance, sideOffset, zOffset)
    local player = GetPlayerActor()
    if not IsValidActor(player) then
        return Vector(5.757998, 15.645119, 1.765046)
    end

    local origin = player.Location
    local forward = SafeNormalize2D(player.Forward, Vector(1.0, 0.0, 0.0))
    local right = SafeNormalize2D(player.Right, Vector(0.0, 1.0, 0.0))

    local loc = origin + forward * (forwardDistance or DEFAULT_MOB_FORWARD_DISTANCE)
    loc = loc + right * (sideOffset or DEFAULT_SIDE_OFFSET)
    loc.Z = origin.Z + (zOffset or MOB_Z_OFFSET)
    return loc
end

local function DestroyActorList(list, label)
    for _, actor in ipairs(list) do
        if IsValidActor(actor) then
            print("[TutorialSpawner] destroy " .. tostring(label or "actor") .. " actor=" .. tostring(actor.Name or actor.UUID or actor))
            actor:Destroy()
        end
    end
end

local function DestroyActorsByTag(tag)
    local actors = World.FindActorsByTag(tag)
    if actors == nil then
        return
    end

    for _, actor in ipairs(actors) do
        if IsValidActor(actor) then
            print("[TutorialSpawner] destroy tagged actor tag=" .. tostring(tag)
                .. " actor=" .. tostring(actor.Name or actor.UUID or actor))
            actor:Destroy()
        end
    end
end

local function GetTutorialMobHP(label)
    return TUTORIAL_MOB_HP_BY_LABEL[tostring(label or "")] or DEFAULT_TUTORIAL_MOB_HP
end

local function ApplyTutorialMobHP(mob, label)
    if CombatContext == nil or CombatContext.GetMobByOwner == nil then
        print("[TutorialSpawner] CombatContext mob API unavailable")
        return
    end

    local mobContext = CombatContext.GetMobByOwner(mob)
    if mobContext == nil or mobContext.Combat == nil then
        print("[TutorialSpawner] mob context unavailable for hp label=" .. tostring(label or "Mob"))
        return
    end

    local hp = GetTutorialMobHP(label)
    mobContext.Combat.MaxHP = hp
    mobContext.Combat.HP = hp
    mobContext.Combat.IsDead = false
    print("[TutorialSpawner] set mob hp label=" .. tostring(label or "Mob") .. " hp=" .. tostring(hp))
end

function TutorialSpawner.ClearMobs()
    DestroyActorList(spawnedMobs, "mob")
    spawnedMobs = {}
    -- Also clean up stale tutorial mobs from an earlier hot reload / retry.
    DestroyActorsByTag("TutorialMob")
end

function TutorialSpawner.FindBoss()
    if IsValidActor(spawnedBoss) then
        return spawnedBoss
    end

    local boss = World.FindFirstActorByTag("TutorialBoss")
    if IsValidActor(boss) then
        spawnedBoss = boss
        return spawnedBoss
    end

    return nil
end

function TutorialSpawner.SpawnMob(label, forwardDistance, sideOffset)
    if GameFlow == nil or GameFlow.SpawnTutorialMob == nil then
        print("[TutorialSpawner] GameFlow.SpawnTutorialMob binding missing")
        return nil
    end

    spawnSerial = spawnSerial + 1
    local player = GetPlayerActor()
    local loc = ComputeSpawnLocation(forwardDistance or DEFAULT_MOB_FORWARD_DISTANCE, sideOffset or DEFAULT_SIDE_OFFSET, MOB_Z_OFFSET)
    local yaw = ComputeFacingYawFromPlayer(player)

    local mob = GameFlow.SpawnTutorialMob(loc, yaw)
    if IsValidActor(mob) then
        mob:AddTag("TutorialStep_" .. tostring(label or "Mob"))
        mob:AddTag("TutorialSpawn_" .. tostring(spawnSerial))
        table.insert(spawnedMobs, mob)
        ApplyTutorialMobHP(mob, label)
        print("[TutorialSpawner] spawned mob label=" .. tostring(label or "Mob")
            .. " loc=(" .. string.format("%.2f,%.2f,%.2f", loc.X, loc.Y, loc.Z) .. ") yaw=" .. tostring(yaw))
    else
        print("[TutorialSpawner] failed to spawn mob label=" .. tostring(label or "Mob"))
    end

    return mob
end

function TutorialSpawner.SpawnFreshMob(label, forwardDistance, sideOffset)
    TutorialSpawner.ClearMobs()
    return TutorialSpawner.SpawnMob(label, forwardDistance, sideOffset)
end

function TutorialSpawner.EnsureMob(label, forwardDistance, sideOffset)
    for _, actor in ipairs(spawnedMobs) do
        if IsValidActor(actor) then
            return actor
        end
    end

    local existing = World.FindFirstActorByTag("TutorialMob")
    if IsValidActor(existing) then
        table.insert(spawnedMobs, existing)
        ApplyTutorialMobHP(existing, label)
        return existing
    end

    return TutorialSpawner.SpawnMob(label, forwardDistance, sideOffset)
end

function TutorialSpawner.EnsureBoss(label, forwardDistance, sideOffset)
    local boss = TutorialSpawner.FindBoss()
    if IsValidActor(boss) then
        return boss
    end

    if GameFlow == nil or GameFlow.SpawnTutorialBoss == nil then
        print("[TutorialSpawner] GameFlow.SpawnTutorialBoss binding missing")
        return nil
    end

    local player = GetPlayerActor()
    local loc = ComputeSpawnLocation(forwardDistance or DEFAULT_BOSS_FORWARD_DISTANCE, sideOffset or DEFAULT_SIDE_OFFSET, BOSS_Z_OFFSET)
    local yaw = ComputeFacingYawFromPlayer(player)

    boss = GameFlow.SpawnTutorialBoss(loc, yaw)
    if IsValidActor(boss) then
        spawnedBoss = boss
        boss:AddTag("TutorialStep_" .. tostring(label or "Boss"))
        print("[TutorialSpawner] spawned boss label=" .. tostring(label or "Boss")
            .. " loc=(" .. string.format("%.2f,%.2f,%.2f", loc.X, loc.Y, loc.Z) .. ") yaw=" .. tostring(yaw))
    else
        print("[TutorialSpawner] failed to spawn boss label=" .. tostring(label or "Boss"))
    end

    return boss
end

function TutorialSpawner.PrepareBasicAttackTarget()
    return TutorialSpawner.SpawnFreshMob("BasicAttack", 8.0, 0.0)
end

function TutorialSpawner.PrepareComboTarget()
    return TutorialSpawner.SpawnFreshMob("Combo", 8.0, 0.0)
end

function TutorialSpawner.PrepareDashTarget()
    return TutorialSpawner.EnsureMob("Dash", 10.0, 0.0)
end

function TutorialSpawner.PrepareDashChargeTarget()
    return TutorialSpawner.SpawnFreshMob("DashCharge", 9.0, 0.0)
end

function TutorialSpawner.PreparePerfectDodgeEnemy()
    TutorialSpawner.ClearMobs()
    return TutorialSpawner.SpawnFreshMob("PerfectDodge", 9.0, 0.0)
end

function TutorialSpawner.PrepareUltimateTargets()
    TutorialSpawner.ClearMobs()
    TutorialSpawner.SpawnMob("UltimateMob", 10.0, 0.0)
end

function TutorialSpawner.EndSession(clearEnemies)
    if clearEnemies == true then
        TutorialSpawner.ClearMobs()
        print("[TutorialSpawner] session ended; spawned tutorial enemies cleared")
        return
    end

    -- Do not destroy the boss here. BossCharacter.EndPlay currently clears the
    -- shared CombatContext, which is fine during scene teardown but surprising
    -- in the middle of TrainingMap free play. Leave spawned actors for practice.
    print("[TutorialSpawner] session ended; spawned enemies remain for free play")
end

return TutorialSpawner
