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

-- 공격 코루틴 중단 사유: 피격으로 인한 캔슬 요청, 또는 사망.
local function IsAttackAborted(mobContext)
    return mobContext.Combat.CancelAttack == true or mobContext.Combat.IsDead == true
end

local function WaitForNotify(mobContext, flag, timeout)
    local elapsed = 0.0
    local attack = mobContext.Attack
    while not attack[flag] and elapsed < timeout do
        if IsAttackAborted(mobContext) then
            return   -- 캔슬/사망 시 즉시 빠져나간다 (호출부가 IsAttackAborted 로 정리)
        end
        elapsed = elapsed + WaitFrame()
    end
    attack[flag] = false
    if elapsed >= timeout and mobContext.Config.DEBUG then
        print("[MobAttacks] WaitForNotify timeout: " .. flag
            .. " (" .. string.format("%.1f", timeout) .. "s)")
    end
end

local function ClearAttackNotifyFlags(attack)
    if attack == nil then return end

    attack.ZoneShow    = false
    attack.ZoneFlash   = false
    attack.ZoneHide    = false
    attack.HitboxOpen  = false
    attack.HitboxClose = false
    attack.TrackEnd    = false
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
local function SpawnPiece(feedback, centerX, centerY, centerZ, yaw, length, width, color)
    local decal = VFX.SpawnGroundCrackDecal(
        feedback.DECAL_MATERIAL,
        Vector(centerX, centerY, centerZ),
        Vector(length, width, feedback.ZONE_HEIGHT),
        feedback.NO_FADE_DELAY,
        0.2
    )
    if decal then
        decal:SetRotation(Vector(0.0, 0.0, yaw))
        local c = color or feedback.ZONE_COLOR_IDLE
        decal:SetColorRGBA(c[1], c[2], c[3], c[4])
    end
    return decal
end

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
    local centerX = mobPos.X + dirX * (length * 0.5)
    local centerY = mobPos.Y + dirY * (length * 0.5)

    -- 전체 범위를 아주 흐릿하게 미리 보여주는 윤곽 데칼 (차오름과 무관하게 고정 크기) — 보스와 동일
    local outlineDecal = SpawnPiece(
        feedback, centerX, centerY, spawnZ, yaw, length, width,
        feedback.ZONE_COLOR_OUTLINE
    )

    -- 그 위로 origin 에서부터 점점 차오르는 불투명 데칼 (FillZone 이 스케일 조절)
    local decal = SpawnPiece(
        feedback, centerX, centerY, spawnZ, yaw, length, width,
        feedback.ZONE_COLOR_IDLE
    )

    if decal == nil and config.DEBUG then
        print("[MobAttacks] ShowZone decal spawn failed")
    end

    return {
        decal = decal,
        outlineDecal = outlineDecal,
        origin = Vector(mobPos.X, mobPos.Y, mobPos.Z),
        yaw = yaw,
        length = length,
        width = width,
    }
end

-- 장판을 origin 기준으로 length * ratio 만큼만 채워서 보여준다 (0 → 점점 차오름, 1 → 완전히 참).
local function FillZone(mobContext, zone, ratio)
    if zone == nil or zone.decal == nil then return end

    local feedback = mobContext.Config.FEEDBACK
    local length = math.max(0.01, zone.length * ratio)
    local rad = zone.yaw * math.pi / 180.0
    local dx, dy = math.cos(rad), math.sin(rad)
    local cx = zone.origin.X + dx * (length * 0.5)
    local cy = zone.origin.Y + dy * (length * 0.5)
    local cz = zone.decal.Location.Z or (zone.origin.Z + feedback.ZONE_Z_OFFSET)

    zone.decal:SetLocation(Vector(cx, cy, cz))
    zone.decal:SetRelativeScale(Vector(length, zone.width, feedback.ZONE_HEIGHT))
end

-- ZoneShow 시점부터 장판이 사라질 때까지 점점 차오르는 연출을 굴린다.
-- ZoneFlash 시점에 FillZone(zone, 1.0) 으로 강제로 100%를 맞추므로, 여기서는 0.99 까지만 채운다.
local function RunZoneFill(mobContext, zone)
    local config = mobContext.Config
    StartCoroutine(function()
        local t = 0.0
        while zone.decal ~= nil do
            t = t + WaitFrame()
            FillZone(mobContext, zone, math.min(t / config.FEEDBACK.FILL_DURATION, 0.99))
        end
    end)
end

local function FlashZone(mobContext, zone)
    if zone == nil or zone.decal == nil then return end
    local color = mobContext.Config.FEEDBACK.ZONE_COLOR_FLASH
    zone.decal:SetColorRGBA(color[1], color[2], color[3], color[4])
end

local function HideZone(mobContext, zone)
    if zone == nil then return end
    if zone.outlineDecal ~= nil then
        zone.outlineDecal:SetFadeOut(0.0, 0.15)
        zone.outlineDecal = nil
    end
    if zone.decal == nil then return end
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

-- 공격 종료 정리 — 정상 종료/캔슬 공용.
-- 장판을 치우고 추적 재개 + 락/캔슬 플래그 해제 → 애니는 ActionLock 해제로 Locomotion(or 피격) 복귀.
local function EndAttack(mobContext, zone)
    HideZone(mobContext, zone)

    local attack = mobContext.Attack
    if attack ~= nil and attack.ActiveZone == zone then
        attack.ActiveZone = nil
    end
    ClearAttackNotifyFlags(attack)

    mobContext.Brain.IsTracking = true
    mobContext.Combat.ActionLock = false
    mobContext.Combat.CancelAttack = false
end

local function MeleeAttack(mobContext)
    local config = mobContext.Config
    local attack = mobContext.Attack
    local zone = nil

    -- 지난 공격에서 남았을 수 있는 notify 플래그를 초기화한다.
    -- 공격 애니의 ZoneFlash/ZoneHide/HitboxOpen/HitboxClose 가 다음 공격까지 잔류하면
    -- WaitForNotify 가 곧장 통과해 판정 단계가 한 프레임에 뭉개질 수 있으므로 시작 시 비운다.
    ClearAttackNotifyFlags(attack)
    attack.ActiveZone = nil

    if mobContext.Runtime.MovementComp then
        mobContext.Runtime.MovementComp:StopMovementImmediately()
    end

    -- 각 단계 사이에서 피격 캔슬(IsAttackAborted)을 감지하면 즉시 정리하고 빠져나간다.
    -- ── [준비동작 없이 장판 리드 타임] (보스와 동일) ───────────────
    -- 준비 모션(Idle1)을 없애고, 코드가 먼저 장판을 띄워 리드 타임(ZONE_LEAD)동안 차오르게 한 뒤
    -- 공격 애니를 트리거한다. 리드 타임 동안 mob 은 Locomotion(서있기)으로 장판만 띄운다.
    zone = ShowZone(mobContext)
    attack.ActiveZone = zone
    FillZone(mobContext, zone, 0.0)
    RunZoneFill(mobContext, zone)

    local lead = config.ZONE_LEAD or 0.35
    local leadElapsed = 0.0
    while leadElapsed < lead do
        if IsAttackAborted(mobContext) then return EndAttack(mobContext, zone) end
        leadElapsed = leadElapsed + WaitFrame()
    end

    -- 리드 타임 종료 → 조준 고정(IsTracking=false). 이 신호로 애니가 Locomotion → Attack 으로 바로 넘어간다.
    mobContext.Brain.IsTracking = false

    -- ── [공격 Attack 애니] ────────────────────────────────────────
    WaitForNotify(mobContext, "ZoneFlash", 1.5)
    if IsAttackAborted(mobContext) then return EndAttack(mobContext, zone) end
    FillZone(mobContext, zone, 1.0)
    FlashZone(mobContext, zone)

    WaitForNotify(mobContext, "ZoneHide", 1.5)
    if IsAttackAborted(mobContext) then return EndAttack(mobContext, zone) end
    HideZone(mobContext, zone)

    WaitForNotify(mobContext, "HitboxOpen", 1.5)
    if IsAttackAborted(mobContext) then return EndAttack(mobContext, zone) end
    local hasHit = false
    local hitElapsed = 0.0
    -- HitboxClose 노티파이가 오면 즉시, 안 오면 HITBOX_MAX_DURATION 후 닫는다.
    -- (타임아웃이 없으면 노티파이 미연결 시 ActionLock 이 영구 true 로 굳어버림)
    while not attack.HitboxClose and hitElapsed < HITBOX_MAX_DURATION do
        if IsAttackAborted(mobContext) then return EndAttack(mobContext, zone) end
        hitElapsed = hitElapsed + WaitFrame()
        if not hasHit then
            hasHit = ResolveHit(mobContext, zone)
        end
    end
    attack.HitboxClose = false

    local elapsed = 0.0
    while elapsed < config.RECOVERY do
        if IsAttackAborted(mobContext) then return EndAttack(mobContext, zone) end
        elapsed = elapsed + WaitFrame()
    end

    -- 정상 종료: 다음 추격/공격을 위해 추적 재개 + 락 해제
    EndAttack(mobContext, zone)
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
---@return nil
function MobAttacks.CleanupActiveAttack(mobContext)
    MobContext.Assert(mobContext, "MobAttacks.CleanupActiveAttack")

    local attack = mobContext.Attack
    if attack ~= nil and attack.ActiveZone ~= nil then
        HideZone(mobContext, attack.ActiveZone)
        attack.ActiveZone = nil
    end

    ClearAttackNotifyFlags(attack)

    mobContext.Brain.IsTracking = true
    mobContext.Combat.ActionLock = false
    mobContext.Combat.CancelAttack = false
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
    mobContext.Brain.IsTracking = true   -- 리드 타임 동안 조준 유지(코루틴이 끝에서 false 로 고정)
    StartCoroutine(function() MeleeAttack(mobContext) end)

    if mobContext.Config.DEBUG then
        print("[MobAttacks] -- " .. ATTACK_ID .. " START -- @ "
            .. string.format("%.3f", World.GetGameTime()))
    end
end

return MobAttacks
