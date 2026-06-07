-- PlayerCharacter.lua
-- ULuaScriptComponent entry point for the player actor.
-- Owns the PlayerContext instance and orchestrates action -> combat -> feedback event flow.

local PlayerContext = require("Player/PlayerContext")
local PlayerEvents = require("Player/PlayerEvents")
local PlayerAction = require("Player/PlayerAction")
local CombatContext = require("Combat/CombatContext")
local PlayerFeedback = require("Player/PlayerFeedback")

local PlayerCharacter = {}
local player = nil

local function GetPlayer()
    if player ~= nil then
        return player
    end

    if obj ~= nil then
        player = CombatContext.GetPlayerByOwner(obj)
    end

    return player
end

---@param active boolean
---@return nil
function PlayerCharacter.SetKatanaTrailActive(active)
    local currentPlayer = GetPlayer()
    if currentPlayer ~= nil then
        PlayerFeedback.SetKatanaTrailActive(currentPlayer, active)
    end
end

function BeginPlay()
    player = CombatContext.GetPlayerByOwner(obj)
    if player == nil then
        player = PlayerContext.Create(obj, this)
    else
        player.Owner = obj
        player.Component = this
    end

    PlayerAction.Init(player)
    CombatContext.RegisterPlayer(player)
    PlayerFeedback.Init(player)

    print("[BeginPlay] " .. obj.UUID)
end

function EndPlay()
    if player ~= nil then
        CombatContext.UnregisterPlayer(player)
        PlayerFeedback.Shutdown(player)
    end
    player = nil

    print("[EndPlay] " .. obj.UUID)
end

function OnOverlap(OtherActor, OverlappedComponent, OtherComp)
    local currentPlayer = GetPlayer()
    if currentPlayer ~= nil then
        CombatContext.TryResolvePlayerOverlapHit({
            Player = currentPlayer,
            OtherActor = OtherActor,
            OverlappedComponent = OverlappedComponent,
            OtherComponent = OtherComp,
        })
    end
end

function Tick(dt)
    UpdateCoroutines(dt)

    local currentPlayer = GetPlayer()
    if currentPlayer == nil then
        return
    end

    PlayerEvents.BeginFrame(currentPlayer)
    PlayerAction.Update(currentPlayer, dt)

    local events = PlayerEvents.Drain(currentPlayer)
    CombatContext.ProcessPlayerEvents(currentPlayer, events)
    PlayerFeedback.ProcessEvents(currentPlayer, events)
end

return PlayerCharacter
