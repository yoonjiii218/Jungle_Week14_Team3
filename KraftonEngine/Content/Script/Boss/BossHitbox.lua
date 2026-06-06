-- BossHitbox.lua
-- 순수 Lua 기하 판정 — 플레이어 위치가 장판(zone) 영역 안에 있는지 검사
-- 물리/콜라이더/레이캐스트 없음. 좌표 계산만.
--
-- zone 메타 (BossFeedback 이 채움): { kind, origin, yaw, length, width, ... }
--   kind   = "rect" (직사각형, P1·P3) / "fan" (부채꼴, P2)
--   origin = 장판 기준 보스 위치  (rect·fan 공통)
--   yaw    = 장판 방향(도)
--   length = 판정 길이 (없으면 BB.FEEDBACK.ZONE_LENGTH fallback)
--   width  = 판정 폭   (없으면 BB.FEEDBACK.ZONE_WIDTH  fallback)

local BossHitbox = {}

local ctx_ref = nil   -- BossCharacter.lua 에서 Init 으로 주입

-- ────────────────────────────────────────────
function BossHitbox.Init(ctx)
    ctx_ref = ctx
end

-- ────────────────────────────────────────────
-- 좌표(px, py) 기반 코어 판정.
-- 액터의 현재 위치뿐 아니라 "대시 시작 시점에 저장해둔 좌표" 로도 검사할 수 있도록
-- target(액터) 대신 순수 좌표를 받는다. (퍼펙트 회피: 회피로 장판을 벗어나도
-- 대시를 시작한 위치가 장판 안이었으면 인정하기 위함)
-- ────────────────────────────────────────────

-- 직사각형 판정: (px,py) 를 장판 방향(yaw) 기준 로컬좌표로 분해
--   전방거리 0 ~ length  &&  |좌우거리| <= width/2  → HIT
function BossHitbox.CheckRectXY(zone, px, py)
    if zone == nil or zone.origin == nil then return false end
    if ctx_ref == nil then return false end

    local F      = ctx_ref.BB.FEEDBACK
    local length = zone.length or F.ZONE_LENGTH
    local width  = zone.width  or F.ZONE_WIDTH

    local origin = zone.origin
    local dx = px - origin.X
    local dy = py - origin.Y

    -- 장판 방향 단위벡터(forward)와 그 직각(right)
    local rad = zone.yaw * math.pi / 180.0
    local fx, fy = math.cos(rad), math.sin(rad)
    local rx, ry = -fy, fx

    local forwardDist = dx * fx + dy * fy   -- 전방 투영
    local sideDist    = dx * rx + dy * ry   -- 좌우 투영

    return forwardDist >= 0.0
       and forwardDist <= length
       and math.abs(sideDist) <= width * 0.5
end

-- 부채꼴 판정 (P2 횡베기): 거리 <= FAN_RADIUS  &&  각도차 <= FAN_ANGLE/2  → HIT
function BossHitbox.CheckFanXY(zone, px, py)
    if zone == nil or zone.origin == nil then return false end
    if ctx_ref == nil then return false end

    local F = ctx_ref.BB.FEEDBACK
    local origin = zone.origin

    local toPx = px - origin.X
    local toPy = py - origin.Y
    local dist = math.sqrt(toPx * toPx + toPy * toPy)
    if dist > F.FAN_RADIUS then return false end
    if dist < 0.001 then return true end   -- 보스 바로 위 → 무조건 안

    local targetYaw = math.atan2(toPy, toPx) * 180.0 / math.pi
    local diff = targetYaw - zone.yaw
    while diff >  180.0 do diff = diff - 360.0 end
    while diff < -180.0 do diff = diff + 360.0 end

    return math.abs(diff) <= F.FAN_ANGLE * 0.5
end

-- 좌표 통합: zone.kind 보고 자동 분기 (저장된 대시 시작 좌표로 검사할 때 사용)
function BossHitbox.CheckXY(zone, px, py)
    if ctx_ref == nil or zone == nil then return false end
    if zone.kind == "fan" then
        return BossHitbox.CheckFanXY(zone, px, py)
    end
    return BossHitbox.CheckRectXY(zone, px, py)
end

-- ────────────────────────────────────────────
-- 액터(target) 의 현재 위치로 검사 — 기존 호출부 호환 래퍼.
-- ────────────────────────────────────────────
function BossHitbox.CheckRect(zone, target)
    if not (target and target:IsValid()) then return false end
    local pp = target.Location
    return BossHitbox.CheckRectXY(zone, pp.X, pp.Y)
end

function BossHitbox.CheckFan(zone, target)
    if not (target and target:IsValid()) then return false end
    local pp = target.Location
    return BossHitbox.CheckFanXY(zone, pp.X, pp.Y)
end

-- 통합: zone.kind 보고 자동 분기
--   "rect" (P1 종베기, P3 내려찍기) → CheckRect (zone.length/width 우선)
--   "fan"  (P2 횡베기)              → CheckFan
--   그 외                           → CheckRect (안전 fallback)
function BossHitbox.Check(zone, target)
    -- 방어: Init 누락/hot-reload 로 ctx_ref 가 nil 이어도 코루틴이 죽지 않게 한다.
    if ctx_ref == nil then return false end
    if zone == nil then return false end
    if not (target and target:IsValid()) then return false end
    return BossHitbox.CheckXY(zone, target.Location.X, target.Location.Y)
end

return BossHitbox
