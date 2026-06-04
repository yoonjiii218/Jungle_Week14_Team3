-- Player, Boss 를 등록해 서로에 대한 이벤트 처리

local CombatContext = {}

local playersByOwner = {}

local function GetOwnerKey(owner)
    if owner == nil then
        return nil
    end

    return owner.UUID or tostring(owner)
end

function CombatContext.RegisterPlayer(ctx)
    if ctx == nil or ctx.Owner == nil then
        return
    end

    playersByOwner[GetOwnerKey(ctx.Owner)] = ctx
end

function CombatContext.UnregisterPlayer(ctx)
    if ctx == nil or ctx.Owner == nil then
        return
    end

    local key = GetOwnerKey(ctx.Owner)
    if playersByOwner[key] == ctx then
        playersByOwner[key] = nil
    end
end

function CombatContext.GetPlayerByOwner(owner)
    return playersByOwner[GetOwnerKey(owner)]
end

function CombatContext.SetCurrentThreat(ctx, threat)
    if ctx ~= nil then
        ctx.CurrentThreat = threat
    end
end

function CombatContext.GetCurrentThreat(ctx)
    if ctx == nil then
        return nil
    end

    return ctx.CurrentThreat
end

local function AddGauge(ctx, amount)
    if ctx == nil or amount == nil then
        return
    end

    local maxGauge = ctx.MaxUltimateGauge or 100
    local gauge = (ctx.UltimateGauge or 0) + amount
    if gauge < 0 then gauge = 0 end
    if gauge > maxGauge then gauge = maxGauge end
    ctx.UltimateGauge = gauge
end

function CombatContext.HandlePlayerResult(ctx, result)
    if ctx == nil or result == nil or result.Events == nil then
        return
    end

    for _, event in ipairs(result.Events) do
        if event.Type == "PerfectDodge" then
            CombatContext.SetCurrentThreat(ctx, event.Threat)
            AddGauge(ctx, event.GaugeDelta or 0)
        elseif event.Type == "AttackHit" then
            AddGauge(ctx, event.GaugeDelta or 0)
        elseif event.Type == "UltimateStart" then
            ctx.UltimateGauge = 0
        elseif event.Type == "GaugeChanged" then
            ctx.UltimateGauge = event.Value
            ctx.MaxUltimateGauge = event.MaxValue or ctx.MaxUltimateGauge
        end
    end
end

return CombatContext
