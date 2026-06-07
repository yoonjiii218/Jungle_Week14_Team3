-- PlayerCharacter.lua
-- ULuaScriptComponent entry point for the playerContext actor.
-- Owns the PlayerContext instance and orchestrates action -> combat -> feedback event flow.

local PlayerContext = require("Player/PlayerContext")
local PlayerEvents = require("Player/PlayerEvents")
local PlayerAction = require("Player/PlayerAction")
local CombatContext = require("Combat/CombatContext")
local PlayerFeedback = require("Player/PlayerFeedback")

local PlayerCharacter = {}
local playerContext = nil

local function GetPlayerContext()
    if playerContext ~= nil then
        return playerContext
    end

    if obj ~= nil then
        playerContext = CombatContext.GetPlayerByOwner(obj)
    end

    return playerContext
end

---@param active boolean
---@return nil
function PlayerCharacter.SetKatanaTrailActive(active)
    local currentPlayerContext = GetPlayerContext()
    if currentPlayerContext ~= nil then
        PlayerFeedback.SetKatanaTrailActive(currentPlayerContext, active)
    end
end

function BeginPlay()
    playerContext = CombatContext.GetPlayerByOwner(obj)
    if playerContext == nil then
        playerContext = PlayerContext.Create(obj, this)
    else
        playerContext.Owner = obj
        playerContext.Component = this
    end

    PlayerAction.Init(playerContext)
    CombatContext.RegisterPlayer(playerContext)
    PlayerFeedback.Init(playerContext)

    print("[BeginPlay] " .. obj.UUID)
end

function EndPlay()
    if playerContext ~= nil then
        CombatContext.UnregisterPlayer(playerContext)
        PlayerFeedback.Shutdown(playerContext)
    end
    playerContext = nil

    print("[EndPlay] " .. obj.UUID)
end

function OnOverlap(OtherActor, OverlappedComponent, OtherComp)
    local currentPlayerContext = GetPlayerContext()
    if currentPlayerContext ~= nil then
        CombatContext.TryResolvePlayerOverlapHit({
            PlayerContext = currentPlayerContext,
            OtherActor = OtherActor,
            OverlappedComponent = OverlappedComponent,
            OtherComponent = OtherComp,
        })
    end
end

function Tick(dt)
    UpdateCoroutines(dt)

    local currentPlayerContext = GetPlayerContext()
    if currentPlayerContext == nil then
        return
    end

    PlayerEvents.BeginFrame(currentPlayerContext)
    PlayerAction.Update(currentPlayerContext, dt)

    local events = PlayerEvents.Drain(currentPlayerContext)
    CombatContext.ProcessPlayerEvents(currentPlayerContext, events)
    PlayerFeedback.ProcessEvents(currentPlayerContext, events)
end

return PlayerCharacter
