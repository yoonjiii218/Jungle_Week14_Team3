-- Player/PlayerProjectile.lua
-- Lua-owned gameplay projectiles. Visuals are ParticleSystemComponent-based,
-- but movement, lifetime, distance and hit detection are kept in Lua.

local PlayerProjectile = {}

local PlayerContext = require("Player/PlayerContext")
local PlayerTargeting = require("Player/PlayerTargeting")
local HitTypes = require("Combat/HitTypes")

local cachedCombatContext = nil

local function GetCombatContext()
    if cachedCombatContext == nil then
        cachedCombatContext = require("Combat/CombatContext")
    end
    return cachedCombatContext
end

local function Clamp(value, minValue, maxValue)
    if value < minValue then return minValue end
    if value > maxValue then return maxValue end
    return value
end

local function Now()
    if World ~= nil and World.GetGameTime ~= nil then
        return World.GetGameTime() or 0.0
    end
    return 0.0
end

local function DebugLog(playerContext, message)
    local config = playerContext and playerContext.Config and playerContext.Config.Action
    local flyingSlashConfig = config and config.FlyingSlash or nil
    if flyingSlashConfig ~= nil and flyingSlashConfig.Debug == true then
        print("[PlayerProjectile] " .. tostring(message))
    end
end

local function IsValidObject(object)
    return object ~= nil and (object.IsValid == nil or object:IsValid() == true)
end

local function SafeActorKey(actor)
    if actor == nil then
        return nil
    end
    return actor.UUID or tostring(actor)
end

local function GetActorLocation(actor)
    if actor == nil then
        return nil
    end

    if actor.Location ~= nil then
        return actor.Location
    end

    if Reflection ~= nil and Reflection.Call ~= nil then
        return Reflection.Call(actor, "GetActorLocation")
    end

    return nil
end

local function GetOwnerForward2D(owner)
    if owner == nil then
        return nil
    end

    local dir = nil
    if Reflection ~= nil and Reflection.Call ~= nil then
        dir = Reflection.Call(owner, "GetActorForward")
    end
    if dir == nil and owner.Forward ~= nil then
        dir = owner.Forward
    end
    if dir == nil then
        return nil
    end

    dir.Z = 0.0
    if dir:Length() <= 0.001 then
        return nil
    end

    return dir:Normalized()
end

local function GetOwnerRight2D(owner, fallbackForward)
    if owner == nil then
        return Vector(0.0, 1.0, 0.0)
    end

    local right = nil
    if Reflection ~= nil and Reflection.Call ~= nil then
        right = Reflection.Call(owner, "GetActorRight")
    end
    if right == nil and owner.Right ~= nil then
        right = owner.Right
    end

    if right ~= nil then
        right.Z = 0.0
        if right:Length() > 0.001 then
            return right:Normalized()
        end
    end

    local forward = fallbackForward or GetOwnerForward2D(owner)
    if forward ~= nil then
        return Vector(-forward.Y, forward.X, 0.0)
    end

    return Vector(0.0, 1.0, 0.0)
end

local function Normalize2D(dir)
    if dir == nil then
        return nil
    end

    dir.Z = 0.0
    if dir:Length() <= 0.001 then
        return nil
    end

    return dir:Normalized()
end

local function ResolveFireDirection(playerContext)
    local dir = PlayerTargeting.GetAssistDirection(playerContext)
    dir = Normalize2D(dir)
    if dir ~= nil then
        return dir
    end

    return GetOwnerForward2D(playerContext.Owner)
end

local function ResolveSpawnPosition(playerContext, dir, actionConfig)
    local owner = playerContext.Owner
    local ownerLocation = GetActorLocation(owner)
    if ownerLocation == nil or dir == nil then
        return nil
    end

    local right = GetOwnerRight2D(owner, dir)
    local up = Vector(0.0, 0.0, 1.0)
    return ownerLocation
        + dir * (actionConfig.SpawnForwardOffset or 0.0)
        + right * (actionConfig.SpawnRightOffset or 0.0)
        + up * (actionConfig.SpawnUpOffset or 0.0)
end

local function RotationFromDirection(dir)
    if dir == nil then
        return Vector(0.0, 0.0, 0.0)
    end

    local yaw = math.atan2(dir.Y, dir.X) * 180.0 / math.pi
    return Vector(0.0, 0.0, yaw)
end

local function SetVisualTransform(projectile)
    if projectile == nil or projectile.Position == nil then
        return
    end

    local actor = projectile.Actor
    local psc = projectile.PSC

    if IsValidObject(actor) then
        actor.Location = projectile.Position
        actor.Rotation = projectile.Rotation
        actor.Scale = projectile.Scale
    end

    if IsValidObject(psc) then
        psc:SetLocation(projectile.Position)
        psc:SetRotation(projectile.Rotation)
        psc:SetRelativeScale(projectile.Scale)
    end
end

local function DestroyProjectile(projectile)
    if projectile == nil or projectile.Destroyed == true then
        return
    end

    projectile.Destroyed = true

    if IsValidObject(projectile.PSC) then
        pcall(function()
            projectile.PSC:StopSpawning()
        end)
    end

    if IsValidObject(projectile.Actor) then
        pcall(function()
            projectile.Actor:Destroy()
        end)
    end
end

local function SpawnVisualActor(playerContext, spawnPosition, rotation, scale)
    if World == nil or World.SpawnActor == nil then
        DebugLog(playerContext, "World.SpawnActor API missing; gameplay projectile spawned without PSC")
        return nil, nil
    end

    local actor = World.SpawnActor("AActor")
    if actor == nil then
        DebugLog(playerContext, "World.SpawnActor(AActor) failed; gameplay projectile spawned without PSC")
        return nil, nil
    end

    actor.Location = spawnPosition
    actor.Rotation = rotation
    actor.Scale = scale

    if actor.AddParticleSystemComponent == nil then
        DebugLog(playerContext, "Actor:AddParticleSystemComponent API missing")
        return actor, nil
    end

    local psc = actor:AddParticleSystemComponent()
    if psc == nil then
        DebugLog(playerContext, "Actor:AddParticleSystemComponent failed")
        return actor, nil
    end

    if Reflection ~= nil and Reflection.Call ~= nil then
        pcall(function()
            Reflection.Call(actor, "SetRootComponent", psc)
        end)
    end

    local feedbackConfig = playerContext.Config.Feedback.FlyingSlash or {}
    local particlePath = feedbackConfig.ParticlePath or ""
    local materialPath = feedbackConfig.MaterialPath or ""

    if particlePath ~= "" and particlePath ~= "None" then
        pcall(function()
            psc:SetTemplatePath(particlePath)
        end)
    end

    if materialPath ~= "" and materialPath ~= "None" then
        pcall(function()
            psc:SetMaterialPath(0, materialPath)
        end)
    end

    pcall(function()
        psc:SetAutoDestroyOwnerAfter(feedbackConfig.AutoDestroyDelay or 0.8)
    end)

    psc:SetLocation(spawnPosition)
    psc:SetRotation(rotation)
    psc:SetRelativeScale(scale)
    psc:Activate()

    return actor, psc
end

local function Dot(a, b)
    return (a.X or 0.0) * (b.X or 0.0)
        + (a.Y or 0.0) * (b.Y or 0.0)
        + (a.Z or 0.0) * (b.Z or 0.0)
end

local function DistancePointToSegment(point, a, b)
    if point == nil or a == nil or b == nil then
        return math.huge
    end

    local ab = b - a
    local denom = Dot(ab, ab)
    if denom <= 0.000001 then
        return (point - a):Length()
    end

    local t = Clamp(Dot(point - a, ab) / denom, 0.0, 1.0)
    local closest = a + ab * t
    return (point - closest):Length()
end

local function ResolveBossActor()
    local combatContext = GetCombatContext()
    if combatContext ~= nil and combatContext.GetBossContext ~= nil then
        local bossContext = combatContext.GetBossContext()
        if bossContext ~= nil and bossContext.Owner ~= nil and IsValidObject(bossContext.Owner) then
            return bossContext.Owner
        end
    end

    if World ~= nil and World.FindFirstActorByTag ~= nil then
        local boss = World.FindFirstActorByTag("Boss")
        if IsValidObject(boss) then
            return boss
        end
    end

    return nil
end

local function TrySpawnHitFlash(playerContext, projectile, bossActor)
    if VFX == nil or VFX.SpawnSlashFlash == nil then
        return
    end

    local feedbackConfig = playerContext.Config.Feedback or {}
    local ultimateVfx = feedbackConfig.UltimateVfx or {}
    local templatePath = ultimateVfx.SlashFlashPath
    if templatePath == nil or templatePath == "" or templatePath == "None" then
        return
    end

    pcall(function()
        VFX.SpawnSlashFlash(
            templatePath,
            projectile.Position,
            projectile.Rotation,
            Vector(1.0, 1.2, 1.2),
            0.18,
            ultimateVfx.LightningMaterialPath
        )
    end)
end

local function ApplyBossHit(playerContext, projectile, bossActor)
    if bossActor == nil then
        return false
    end

    local key = SafeActorKey(bossActor)
    if key ~= nil and projectile.HitActors[key] == true then
        return false
    end

    if key ~= nil then
        projectile.HitActors[key] = true
    end

    local hit = HitTypes.CreatePlayerAttack({
        SourceActor = playerContext.Owner,
        TargetActor = bossActor,
        AttackId = projectile.AttackId,
        AttackInstanceId = projectile.AttackInstanceId,
        Damage = projectile.Damage,
        GaugeDelta = projectile.GaugeDelta,
        HitStopDuration = projectile.HitStopDuration,
    })

    local result = GetCombatContext().ApplyHit(hit)
    local applied = result ~= nil and result.Applied == true
    if applied == true then
        TrySpawnHitFlash(playerContext, projectile, bossActor)
    end

    DebugLog(playerContext, "hit boss applied=" .. tostring(applied) .. " reason=" .. tostring(result and result.Reason or "None"))
    return applied
end

local function CheckBossHit(playerContext, projectile)
    local bossActor = ResolveBossActor()
    if bossActor == nil then
        return false
    end

    local bossLocation = GetActorLocation(bossActor)
    if bossLocation == nil then
        return false
    end

    local distance = DistancePointToSegment(bossLocation, projectile.PrevPosition, projectile.Position)
    if distance > (projectile.Radius or 0.0) then
        return false
    end

    return ApplyBossHit(playerContext, projectile, bossActor)
end

-- =========================================================
-- Public API
-- =========================================================

---@param playerContext PlayerContext
---@return nil
function PlayerProjectile.Init(playerContext)
    PlayerContext.Assert(playerContext, "PlayerProjectile.Init")
    playerContext.Runtime.FlyingSlashes = {}
    playerContext.Runtime.FlyingSlashSerial = playerContext.Runtime.FlyingSlashSerial or 0
end

---@param playerContext PlayerContext
---@return nil
function PlayerProjectile.Shutdown(playerContext)
    PlayerContext.Assert(playerContext, "PlayerProjectile.Shutdown")
    local projectiles = playerContext.Runtime.FlyingSlashes or {}
    for _, projectile in ipairs(projectiles) do
        DestroyProjectile(projectile)
    end
    playerContext.Runtime.FlyingSlashes = {}
end

---@param playerContext PlayerContext
---@param args table|nil
---@return table|nil
function PlayerProjectile.SpawnFlyingSlash(playerContext, args)
    PlayerContext.Assert(playerContext, "PlayerProjectile.SpawnFlyingSlash")
    args = args or {}

    local owner = playerContext.Owner
    if owner == nil then
        return nil
    end

    local actionConfig = playerContext.Config.Action.FlyingSlash or {}
    local combatConfig = playerContext.Config.Combat or {}
    local dir = Normalize2D(args.Direction) or ResolveFireDirection(playerContext)
    if dir == nil then
        DebugLog(playerContext, "SpawnFlyingSlash aborted: no direction")
        return nil
    end

    local spawnPosition = args.Position or ResolveSpawnPosition(playerContext, dir, actionConfig)
    if spawnPosition == nil then
        DebugLog(playerContext, "SpawnFlyingSlash aborted: no spawn position")
        return nil
    end

    playerContext.Runtime.FlyingSlashes = playerContext.Runtime.FlyingSlashes or {}
    playerContext.Runtime.FlyingSlashSerial = (playerContext.Runtime.FlyingSlashSerial or 0) + 1

    local attackId = args.AttackId or "PlayerFlyingSlash"
    local attackInstanceId = args.AttackInstanceId
        or (attackId .. "_" .. tostring(Now()) .. "_" .. tostring(playerContext.Runtime.FlyingSlashSerial))
    local scale = args.Scale or actionConfig.Scale or Vector(1.0, 1.0, 1.0)
    local rotation = RotationFromDirection(dir)
    local actor, psc = SpawnVisualActor(playerContext, spawnPosition, rotation, scale)

    local projectile = {
        AttackId = attackId,
        AttackInstanceId = attackInstanceId,
        Actor = actor,
        PSC = psc,
        Position = spawnPosition,
        PrevPosition = spawnPosition,
        Direction = dir,
        Rotation = rotation,
        Scale = scale,
        Speed = args.Speed or actionConfig.Speed or 45.0,
        Life = args.Life or actionConfig.Life or 0.5,
        MaxDistance = args.MaxDistance or actionConfig.MaxDistance or 24.0,
        Radius = args.Radius or actionConfig.Radius or 2.5,
        Pierce = args.Pierce,
        Damage = args.Damage or combatConfig.FlyingSlashDamage or 20,
        GaugeDelta = args.GaugeDelta or combatConfig.FlyingSlashGaugeDelta or 8,
        HitStopDuration = args.HitStopDuration or combatConfig.FlyingSlashHitStopDuration or 0.03,
        Age = 0.0,
        TravelDistance = 0.0,
        HitActors = {},
        Destroyed = false,
    }

    if projectile.Pierce == nil then
        projectile.Pierce = actionConfig.Pierce ~= false
    end

    table.insert(playerContext.Runtime.FlyingSlashes, projectile)
    SetVisualTransform(projectile)
    DebugLog(playerContext, "spawn " .. tostring(attackInstanceId))
    return projectile
end

---@param playerContext PlayerContext
---@param dt number
---@return nil
function PlayerProjectile.Update(playerContext, dt)
    PlayerContext.Assert(playerContext, "PlayerProjectile.Update")
    local projectiles = playerContext.Runtime.FlyingSlashes
    if projectiles == nil or #projectiles <= 0 then
        return
    end

    local deltaTime = dt or 0.0
    for index = #projectiles, 1, -1 do
        local projectile = projectiles[index]
        if projectile == nil or projectile.Destroyed == true then
            table.remove(projectiles, index)
        else
            projectile.Age = (projectile.Age or 0.0) + deltaTime
            projectile.PrevPosition = projectile.Position

            local stepDistance = (projectile.Speed or 0.0) * deltaTime
            projectile.Position = projectile.Position + projectile.Direction * stepDistance
            projectile.TravelDistance = (projectile.TravelDistance or 0.0) + math.abs(stepDistance)

            SetVisualTransform(projectile)

            local hit = CheckBossHit(playerContext, projectile)
            if hit == true and projectile.Pierce ~= true then
                DestroyProjectile(projectile)
                table.remove(projectiles, index)
            elseif projectile.Age >= (projectile.Life or 0.0)
                or projectile.TravelDistance >= (projectile.MaxDistance or 0.0) then
                DestroyProjectile(projectile)
                table.remove(projectiles, index)
            end
        end
    end
end

return PlayerProjectile
