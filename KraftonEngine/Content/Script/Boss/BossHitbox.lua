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

-- 직사각형 판정: 보스→플레이어를 장판 방향(yaw) 기준 로컬좌표로 분해
--   전방거리 0 ~ length  &&  |좌우거리| <= width/2  → HIT
--   zone.length / zone.width 를 우선 사용 (P1·P3 크기가 다르므로).
--   없으면 BB.FEEDBACK.ZONE_LENGTH / ZONE_WIDTH 를 fallback.
function BossHitbox.CheckRect(zone, target)
    if zone == nil or zone.origin == nil then return false end
    if not (target and target:IsValid()) then return false end

    local F      = ctx_ref.BB.FEEDBACK
    local length = zone.length or F.ZONE_LENGTH
    local width  = zone.width  or F.ZONE_WIDTH

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
       and forwardDist <= length
       and math.abs(sideDist) <= width * 0.5
end

-- 부채꼴 판정 (P2 횡베기): 거리 <= FAN_RADIUS  &&  각도차 <= FAN_ANGLE/2  → HIT
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


-- 통합: zone.kind 보고 자동 분기
--   "rect" (P1 종베기, P3 내려찍기) → CheckRect (zone.length/width 우선)
--   "fan"  (P2 횡베기)              → CheckFan
--   그 외                           → CheckRect (안전 fallback)
function BossHitbox.Check(zone, target)
    -- 방어: Init 누락/hot-reload 로 ctx_ref 가 nil 이어도 코루틴이 죽지 않게 한다.
    -- (정상 상황이면 BossHitbox.Init 에서 주입됨)
    if ctx_ref == nil then return false end
    if zone == nil then return false end
    if zone.kind == "fan" then
        return BossHitbox.CheckFan(zone, target)
    end
    return BossHitbox.CheckRect(zone, target)
end

return BossHitbox
