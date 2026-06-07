-- Attack-time soft lock-on / aim assist.
-- This module does not move the player by itself. It only resolves a target and
-- exposes the 2D direction that PlayerAction should use for yaw/attack dash.

-- Player/PlayerTargeting.lua
-- Target resolution helper. Public functions take PlayerContext.

local PlayerTargeting = {}

local PlayerContext = require("Player/PlayerContext")

local function GetTargetingConfig(player)
    return player.Config.Targeting
end

local function GetOwner(player)
    return player.Owner
end

local function Now()
    if World ~= nil and World.GetGameTime ~= nil then
        return World.GetGameTime() or 0.0
    end

    return 0.0
end

local function Clamp(value, minValue, maxValue)
    if value < minValue then return minValue end
    if value > maxValue then return maxValue end
    return value
end

local function IsValidActor(actor)
    return actor ~= nil and actor.IsValid ~= nil and actor:IsValid()
end

local function GetActorLocation(actor)
    if actor == nil then
        return nil
    end

    return actor.Location
end

local function GetDirection2D(from, to)
    if from == nil or to == nil then
        return nil, 0.0
    end

    local dir = to - from
    dir.Z = 0.0

    local distance = dir:Length()
    if distance <= 0.001 then
        return nil, distance
    end

    return dir:Normalized(), distance
end

local function Dot2D(a, b)
    if a == nil or b == nil then
        return -1.0
    end

    return (a.X or 0.0) * (b.X or 0.0) + (a.Y or 0.0) * (b.Y or 0.0)
end

local function GetForward2D(owner)
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

local function GetProfile(config, mode)
    mode = mode or "Attack"

    if mode == "Dash" then
        return config.Dash
    elseif mode == "DashChargeAttack" then
        return config.DashChargeAttack
    end

    return config.Attack
end

local function ForEachCandidateByTag(config, callback)
    if World == nil or World.FindActorsByTag == nil then
        return
    end

    local tags = config.TargetTags
    local visited = {}

    for _, tag in ipairs(tags) do
        local actors = World.FindActorsByTag(tag)
        if actors ~= nil then
            for _, actor in ipairs(actors) do
                local key = actor.UUID or tostring(actor)
                if visited[key] ~= true then
                    visited[key] = true
                    callback(actor)
                end
            end
        end
    end
end

local function IsCandidateInProfile(owner, actor, aimDir, profile, rangeScale, extraConeDeg)
    if not IsValidActor(actor) or actor == owner then
        return nil
    end

    local ownerLocation = GetActorLocation(owner)
    local actorLocation = GetActorLocation(actor)
    local dir, distance = GetDirection2D(ownerLocation, actorLocation)
    if dir == nil then
        return nil
    end

    local range = (profile.Range or 0.0) * (rangeScale or 1.0)
    if range > 0.0 and distance > range then
        return nil
    end

    local dot = Dot2D(aimDir, dir)
    local coneDeg = (profile.ConeDeg or 360.0) + (extraConeDeg or 0.0)
    if coneDeg < 360.0 then
        local halfRad = (coneDeg * 0.5) * math.pi / 180.0
        if dot < math.cos(halfRad) then
            return nil
        end
    end

    return {
        Actor = actor,
        Direction = dir,
        Distance = distance,
        Dot = dot,
    }
end

local function IsStickyTargetUsable(ctx, owner, aimDir, profile, now)
    local target = ctx.Runtime.TargetAssistTarget
    if target == nil or (ctx.Runtime.TargetAssistKeepUntil or 0.0) < now then
        return nil
    end

    return IsCandidateInProfile(owner, target, aimDir, profile, 1.25, 30.0)
end

---@param player PlayerContext
function PlayerTargeting.FindTarget(player, mode, aimDirection)
    local ctx = PlayerContext.Assert(player, "PlayerTargeting.FindTarget")
    local config = GetTargetingConfig(ctx)
    if config.Enabled == false then
        return nil
    end

    local owner = GetOwner(ctx)
    if owner == nil then
        return nil
    end

    local profile = GetProfile(config, mode)
    if profile.Enabled == false then
        return nil
    end

    local aimDir = aimDirection or GetForward2D(owner)
    if aimDir == nil then
        return nil
    end
    aimDir.Z = 0.0
    if aimDir:Length() <= 0.001 then
        return nil
    end
    aimDir = aimDir:Normalized()

    local now = Now()
    local sticky = IsStickyTargetUsable(ctx, owner, aimDir, profile, now)
    if sticky ~= nil then
        sticky.Score = sticky.Score or 9999.0
    end

    local best = sticky
    ForEachCandidateByTag(config, function(actor)
        local candidate = IsCandidateInProfile(owner, actor, aimDir, profile, 1.0, 0.0)
        if candidate == nil then
            return
        end

        -- Lower score is better. Angle matters slightly more than distance so
        -- attacks prefer what the player is already facing.
        local maxRange = math.max(profile.Range or candidate.Distance, 0.001)
        local distanceScore = Clamp(candidate.Distance / maxRange, 0.0, 1.0)
        local angleScore = Clamp((1.0 - candidate.Dot) * 0.5, 0.0, 1.0)
        candidate.Score = angleScore * 0.65 + distanceScore * 0.35

        if sticky ~= nil and actor == sticky.Actor then
            candidate.Score = candidate.Score - config.StickyScoreBonus
        end

        if best == nil or candidate.Score < best.Score then
            best = candidate
        end
    end)

    if best == nil then
        return nil
    end

    return best.Actor, best.Direction, best.Distance
end

---@param player PlayerContext
function PlayerTargeting.BeginAssist(player, mode, aimDirection)
    local ctx = PlayerContext.Assert(player, "PlayerTargeting.BeginAssist")
    local config = GetTargetingConfig(ctx)
    local profile = GetProfile(config, mode)
    local target, dir, distance = PlayerTargeting.FindTarget(ctx, mode, aimDirection)
    local now = Now()

    ctx.Runtime.TargetAssistMode = mode
    ctx.Runtime.TargetAssistTarget = target
    ctx.Runtime.TargetAssistDirection = dir
    ctx.Runtime.TargetAssistDistance = distance
    ctx.Runtime.TargetAssistEndTime = now + (profile.TurnDuration or 0.0)
    ctx.Runtime.TargetAssistKeepUntil = now + (config.StickyTime or 0.0)

    if profile.LockDirection == true then
        ctx.Runtime.TargetAssistLockedDirection = dir
    else
        ctx.Runtime.TargetAssistLockedDirection = nil
    end

    return target, dir, distance
end

---@param player PlayerContext
function PlayerTargeting.GetAssistDirection(player)
    local ctx = PlayerContext.Assert(player, "PlayerTargeting.GetAssistDirection")
    if ctx.Runtime.TargetAssistLockedDirection ~= nil then
        return ctx.Runtime.TargetAssistLockedDirection
    end

    local target = ctx.Runtime.TargetAssistTarget
    local owner = GetOwner(ctx)
    if IsValidActor(target) and owner ~= nil then
        local dir, distance = GetDirection2D(GetActorLocation(owner), GetActorLocation(target))
        if dir ~= nil then
            ctx.Runtime.TargetAssistDirection = dir
            ctx.Runtime.TargetAssistDistance = distance
            return dir
        end
    end

    return ctx.Runtime.TargetAssistDirection
end

---@param player PlayerContext
function PlayerTargeting.GetTurnSpeed(player)
    local ctx = PlayerContext.Assert(player, "PlayerTargeting.GetTurnSpeed")
    local config = GetTargetingConfig(ctx)
    local profile = GetProfile(config, ctx.Runtime.TargetAssistMode or "Attack")
    return profile.TurnSpeed
end

---@param player PlayerContext
function PlayerTargeting.IsAssistTurnActive(player)
    local ctx = PlayerContext.Assert(player, "PlayerTargeting.IsAssistTurnActive")
    return (ctx.Runtime.TargetAssistEndTime or 0.0) > Now()
end

---@param player PlayerContext
function PlayerTargeting.ClearAssist(player, clearSticky)
    local ctx = PlayerContext.Assert(player, "PlayerTargeting.ClearAssist")
    ctx.Runtime.TargetAssistMode = nil
    ctx.Runtime.TargetAssistDirection = nil
    ctx.Runtime.TargetAssistDistance = nil
    ctx.Runtime.TargetAssistLockedDirection = nil
    ctx.Runtime.TargetAssistEndTime = 0.0

    if clearSticky == true then
        ctx.Runtime.TargetAssistTarget = nil
        ctx.Runtime.TargetAssistKeepUntil = 0.0
    end
end

return PlayerTargeting
