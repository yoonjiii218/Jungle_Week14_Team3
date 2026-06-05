-- BossHitbox.lua
-- 순수 Lua 기하 판정 — 플레이어 위치가 장판(zone) 영역 안에 있는지 검사
-- 물리/콜라이더/레이캐스트 없음. 좌표 계산만.
--
-- zone 메타 (BossFeedback 이 채움): { kind, origin, yaw, ... }
--   kind = "rect" (직사각형, P3) / "fan" (부채꼴, P1)
--   origin = 장판 기준 보스 위치
--   yaw    = 장판 방향(도)

local BossHitbox = {}

local ctx_ref = nil   -- BossCharacter.lua 에서 Init 으로 주입

-- ────────────────────────────────────────────
function BossHitbox.Init(ctx)
    ctx_ref = ctx
end

-- 직사각형 판정: 보스→플레이어를 장판 방향(yaw) 기준 로컬좌표로 분해
--   전방거리 0 ~ LENGTH  &&  |좌우거리| <= WIDTH/2  → HIT
function BossHitbox.CheckRect(zone, target)
    if zone == nil or zone.origin == nil then return false end
    if not (target and target:IsValid()) then return false end

    local F = ctx_ref.BB.FEEDBACK
    local origin = zone.origin
    local pp = target.Location

    local dx = pp.X - origin.X
    local dy = pp.Y - origin.Y

    -- 장판 방향 단위벡터(forward)와 그 직각(right)
    local rad = zone.yaw * math.pi / 180.0
    local fx, fy = math.cos(rad), math.sin(rad)
    local rx, ry = -fy, fx

    local forwardDist = dx * fx + dy * fy   -- 전방 투영
    local sideDist    = dx * rx + dy * ry   -- 좌우 투영

    return forwardDist >= 0.0
       and forwardDist <= F.ZONE_LENGTH
       and math.abs(sideDist) <= F.ZONE_WIDTH * 0.5
end

-- 부채꼴 판정: 거리 <= RADIUS  &&  각도차 <= ANGLE/2  → HIT
function BossHitbox.CheckFan(zone, target)
    if zone == nil or zone.origin == nil then return false end
    if not (target and target:IsValid()) then return false end

    local F = ctx_ref.BB.FEEDBACK
    local origin = zone.origin
    local pp = target.Location

    local toP = Vector(pp.X - origin.X, pp.Y - origin.Y, 0.0)
    local dist = toP:Length()
    if dist > F.FAN_RADIUS then return false end
    if dist < 0.001 then return true end   -- 보스 바로 위 → 무조건 안

    local targetYaw = math.atan2(toP.Y, toP.X) * 180.0 / math.pi
    local diff = targetYaw - zone.yaw
    while diff >  180.0 do diff = diff - 360.0 end
    while diff < -180.0 do diff = diff + 360.0 end

    return math.abs(diff) <= F.FAN_ANGLE * 0.5
end

-- 중심 기준 박스 판정 (P2 가로 베기): center 기준 로컬좌표
--   |로컬X| <= LENGTH/2  &&  |로컬Y| <= WIDTH/2  → HIT
function BossHitbox.CheckBox(zone, target)
    if zone == nil or zone.center == nil then return false end
    if not (target and target:IsValid()) then return false end

    local F = ctx_ref.BB.FEEDBACK
    local c  = zone.center
    local pp = target.Location

    local dx = pp.X - c.X
    local dy = pp.Y - c.Y

    local rad = zone.yaw * math.pi / 180.0
    local fx, fy = math.cos(rad), math.sin(rad)
    local rx, ry = -fy, fx

    local localX = dx * fx + dy * fy   -- 길이축(가로)
    local localY = dx * rx + dy * ry   -- 두께축(전후)

    return math.abs(localX) <= F.P2_LENGTH * 0.5
       and math.abs(localY) <= F.P2_WIDTH * 0.5
end

-- 통합: zone.kind 보고 자동 분기
function BossHitbox.Check(zone, target)
    if zone == nil then return false end
    if zone.kind == "fan" then
        return BossHitbox.CheckFan(zone, target)
    end
    if zone.kind == "box" then
        return BossHitbox.CheckBox(zone, target)
    end
    return BossHitbox.CheckRect(zone, target)
end

return BossHitbox
