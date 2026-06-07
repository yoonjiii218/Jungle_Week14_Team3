-- Mob/MobAttacks.lua
-- Owns mobContext.Attack zone telegraph + hitbox timing via a single coroutine.
-- Reuses Combat/CombatContext for damage application (duplicate-hit guard included).

local MobAttacks = {}

local MobContext = require("Mob/MobContext")
local CombatContext = require("Combat/CombatContext")
local HitTypes = require("Combat/HitTypes")
local Strict = require("Core/Strict")

local ATTACK_ID = "RusherAttack"

-- HitboxClose 노티파이가 연결되지 않은 환경에서도 히트 윈도우가 닫히도록 하는 상한 시간(초).
local HITBOX_MAX_DURATION = 0.3

local function WaitForNotify(mobContext, flag, timeout)
    local elapsed = 0.0
    local attack = mobContext.Attack
    while not attack[flag] and elapsed < timeout do
        elapsed = elapsed + WaitFrame()
    end
    attack[flag] = false
    if elapsed >= timeout and mobContext.Config.DEBUG then
        print("[MobAttacks] WaitForNotify timeout: " .. flag
            .. " (" .. string.format("%.1f", timeout) .. "s)")
    end
end

local function ResolveYaw(mobContext)
    local ownerActor = mobContext.Owner
    local targetActor = mobContext.Brain.TargetActor
    local mobPos = ownerActor.Location

    if targetActor and targetActor:IsValid() then
        local toTarget = Vector(targetActor.Location.X - mobPos.X, targetActor.Location.Y - mobPos.Y, 0.0)
        if toTarget:Length() > 0.001 then
            local dir = toTarget:Normalized()
            return math.atan2(dir.Y, dir.X) * 180.0 / math.pi
        end
    end

    local forward = ownerActor.Forward
    return math.atan2(forward.Y, forward.X) * 180.0 / math.pi
end

-- 장판 연출은 별도 Feedback 모듈 없이 여기서 직접 호출한다 (가상 함수 호출 구조).
-- 추후 비주얼 교체가 필요하면 ShowZone/FlashZone/HideZone 세 곳만 바꾸면 된다.
local function ShowZone(mobContext)
    local config = mobContext.Config
    local feedback = config.FEEDBACK
    local ownerActor = mobContext.Owner
    local mobPos = ownerActor.Location
    local yaw = ResolveYaw(mobContext)
    local rad = yaw * math.pi / 180.0
    local dirX, dirY = math.cos(rad), math.sin(rad)
    local length = config.ZONE_LENGTH
    local width = config.ZONE_WIDTH
    local spawnZ = mobPos.Z + feedback.ZONE_Z_OFFSET

    local decal = VFX.SpawnGroundCrackDecal(
        feedback.DECAL_MATERIAL,
        Vector(mobPos.X + dirX * (length * 0.5), mobPos.Y + dirY * (length * 0.5), spawnZ),
        Vector(length, width, feedback.ZONE_HEIGHT),
        feedback.NO_FADE_DELAY,
        0.2
    )

    if decal then
        decal:SetRotation(Vector(0.0, 0.0, yaw))
        local color = feedback.ZONE_COLOR_IDLE
        decal:SetColorRGBA(color[1], color[2], color[3], color[4])
    elseif config.DEBUG then
        print("[MobAttacks] ShowZone decal spawn failed")
    end

    return {
        decal = decal,
        origin = Vector(mobPos.X, mobPos.Y, mobPos.Z),
        yaw = yaw,
        length = length,
        width = width,
    }
end

local function FlashZone(mobContext, zone)
    if zone == nil or zone.decal == nil then return end
    local color = mobContext.Config.FEEDBACK.ZONE_COLOR_FLASH
    zone.decal:SetColorRGBA(color[1], color[2], color[3], color[4])
end

local function HideZone(mobContext, zone)
    if zone == nil or zone.decal == nil then return end
    zone.decal:SetFadeOut(0.0, 0.15)
    zone.decal = nil
end

-- BossHitbox.CheckRect 는 bossContext.Kind == "BossContext" 를 강제하므로
-- mobContext 로는 그대로 호출할 수 없다. 동일한 OBB 직사각형 판정을 그대로 옮겨온다.
local function CheckRect(zone, targetActor)
    if zone == nil or not (targetActor and targetActor:IsValid()) then return false end

    local targetPos = targetActor.Location
    local origin = zone.origin
    local dx = targetPos.X - origin.X
    local dy = targetPos.Y - origin.Y
    local rad = zone.yaw * math.pi / 180.0
    local fx, fy = math.cos(rad), math.sin(rad)
    local rx, ry = -fy, fx
    local forwardDist = dx * fx + dy * fy
    local sideDist = dx * rx + dy * ry

    return forwardDist >= 0.0
        and forwardDist <= zone.length
        and math.abs(sideDist) <= zone.width * 0.5
end

local function ResolveHit(mobContext, zone)
    if mobContext.Combat.IsDead then return false end

    local targetActor = mobContext.Brain.TargetActor
    if not (targetActor and targetActor:IsValid()) then return false end

    if not CheckRect(zone, targetActor) then
        if mobContext.Config.DEBUG then
            -- 진단: 플레이어가 장판의 어느 축에서 벗어났는지 출력.
            -- fwd > len  → 사거리(ZONE_LENGTH) 밖 (ATTACK_DISTANCE 가 더 크면 여기 걸림)
            -- |side| > halfW → 폭(ZONE_WIDTH) 밖 (정면에서 벗어남)
            local origin = zone.origin
            local dx = targetActor.Location.X - origin.X
            local dy = targetActor.Location.Y - origin.Y
            local rad = zone.yaw * math.pi / 180.0
            local fx, fy = math.cos(rad), math.sin(rad)
            local fwd = dx * fx + dy * fy
            local side = dx * (-fy) + dy * fx
            print(string.format(
                "[MobAttacks] MISS (장판 밖): fwd=%.2f / len=%.2f, side=%.2f / halfW=%.2f",
                fwd, zone.length, side, zone.width * 0.5))
        end
        return false
    end

    local hitRequest = HitTypes.CreateBossAttack({
        SourceActor = mobContext.Owner,
        TargetActor = targetActor,
        AttackId = ATTACK_ID,
        AttackInstanceId = ATTACK_ID .. "_" .. tostring(World.GetGameTime()),
        Damage = mobContext.Config.DAMAGE,
        CanPerfectDodge = true,
    })

    local hitResult = CombatContext.ApplyHit(hitRequest)

    if mobContext.Config.DEBUG then
        if hitResult.Applied == true then
            print("[MobAttacks] HIT damage=" .. tostring(hitResult.Damage))
        else
            print("[MobAttacks] HIT resolved as " .. tostring(hitResult.Reason))
        end
    end

    return hitResult.Applied == true or hitRequest.Reason == "PerfectDodge"
end

local function MeleeAttack(mobContext)
    local config = mobContext.Config
    local attack = mobContext.Attack

    if mobContext.Runtime.MovementComp then
        mobContext.Runtime.MovementComp:StopMovementImmediately()
    end

    -- ── [준비동작 Prep / Idle1 애니] ──────────────────────────────
    -- prep 애니(Idle1)에 심어둔 ZoneShow → 장판 예고 생성
    WaitForNotify(mobContext, "ZoneShow", 1.5)
    local zone = ShowZone(mobContext)

    -- prep 애니의 TrackEnd → 추적 종료(조준 고정). 이 신호로 애니가 Attack 상태로 넘어간다.
    WaitForNotify(mobContext, "TrackEnd", 1.5)
    mobContext.Brain.IsTracking = false

    -- ── [공격 Attack 애니] ────────────────────────────────────────
    WaitForNotify(mobContext, "ZoneFlash", 1.5)
    FlashZone(mobContext, zone)

    WaitForNotify(mobContext, "ZoneHide", 1.5)
    HideZone(mobContext, zone)

    WaitForNotify(mobContext, "HitboxOpen", 1.5)
    local hasHit = false
    local hitElapsed = 0.0
    -- HitboxClose 노티파이가 오면 즉시, 안 오면 HITBOX_MAX_DURATION 후 닫는다.
    -- (타임아웃이 없으면 노티파이 미연결 시 ActionLock 이 영구 true 로 굳어버림)
    while not attack.HitboxClose and hitElapsed < HITBOX_MAX_DURATION do
        hitElapsed = hitElapsed + WaitFrame()
        if not hasHit then
            hasHit = ResolveHit(mobContext, zone)
        end
    end
    attack.HitboxClose = false

    local elapsed = 0.0
    while elapsed < config.RECOVERY do
        elapsed = elapsed + WaitFrame()
    end

    -- 다음 추격/공격을 위해 추적 재개 + 락 해제 (애니는 ActionLock 해제로 Locomotion 복귀)
    mobContext.Brain.IsTracking = true
    mobContext.Combat.ActionLock = false
end

-- =========================================================
-- Public API
-- =========================================================

---@param mobContext MobContext
---@return nil
function MobAttacks.Init(mobContext)
    MobContext.Assert(mobContext, "MobAttacks.Init")
end

---@param mobContext MobContext
---@param dt number
---@return nil
function MobAttacks.Update(mobContext, dt)
    MobContext.Assert(mobContext, "MobAttacks.Update")
    Strict.AssertNumber(dt, "dt", "MobAttacks.Update")
end

---@param mobContext MobContext
---@return nil
function MobAttacks.StartAttack(mobContext)
    MobContext.Assert(mobContext, "MobAttacks.StartAttack")

    mobContext.Combat.ActionLock = true
    mobContext.Brain.IsTracking = true   -- prep 동안 TrackEnd notify 가 올 때까지 추적 상태
    StartCoroutine(function() MeleeAttack(mobContext) end)

    if mobContext.Config.DEBUG then
        print("[MobAttacks] -- " .. ATTACK_ID .. " START -- @ "
            .. string.format("%.3f", World.GetGameTime()))
    end
end

return MobAttacks
