-- BossFeedback.lua
-- 장판(텔레그래프) / 이펙트 / 연출 담당
-- BossAttacks 코루틴이 호출한다.
--
-- zone 구조: { decals = { 데칼1, 데칼2, ... }, locked = bool }
--   직사각형(P3) = 데칼 1개, 부채꼴(P1) = 데칼 N개

local BossFeedback = {}

local ctx_ref = nil   -- BossCharacter.lua 에서 Init 으로 주입

-- ────────────────────────────────────────────
function BossFeedback.Init(ctx)
    ctx_ref = ctx
end

-- 보스 → 타겟 방향 단위벡터 + yaw(도) 반환
-- 타겟 없으면 보스 forward 사용
local function ResolveDirection(bossPos, target)
    if target and target:IsValid() then
        local toTarget = Vector(target.Location.X - bossPos.X,
                                target.Location.Y - bossPos.Y, 0.0)
        if toTarget:Length() > 0.001 then
            local dir = toTarget:Normalized()
            local yaw = math.atan2(dir.Y, dir.X) * 180.0 / math.pi
            return dir, yaw
        end
    end

    local f = ctx_ref.obj.Forward
    local yaw = math.atan2(f.Y, f.X) * 180.0 / math.pi
    return f, yaw
end

-- 데칼 한 조각 스폰 (중심, 회전yaw, 길이, 폭)
local function SpawnPiece(F, centerX, centerY, centerZ, yaw, length, width)
    local decal = VFX.SpawnGroundCrackDecal(
        F.DECAL_MATERIAL,
        Vector(centerX, centerY, centerZ),
        Vector(length, width, F.ZONE_HEIGHT),
        F.NO_FADE_DELAY,   -- 자동 페이드 막기 (HideZone 에서 직접 제거)
        0.2
    )
    if decal then
        decal:SetRotation(Vector(0.0, 0.0, yaw))
        local c = F.ZONE_COLOR_IDLE
        decal:SetColorRGBA(c[1], c[2], c[3], c[4])
    end
    return decal
end

-- ════════════════════════════════════════════
-- P3: 직사각형 장판 (보스 앞으로 뻗고, 타겟 방향 정렬)
-- ════════════════════════════════════════════
function BossFeedback.ShowRectZone(target)
    local F = ctx_ref.BB.FEEDBACK
    local bossPos = ctx_ref.obj.Location
    local dir, yaw = ResolveDirection(bossPos, target)

    local decal = SpawnPiece(F,
        bossPos.X + dir.X * (F.ZONE_LENGTH * 0.5),
        bossPos.Y + dir.Y * (F.ZONE_LENGTH * 0.5),
        bossPos.Z + F.ZONE_Z_OFFSET,
        yaw, F.ZONE_LENGTH, F.ZONE_WIDTH)

    local decals = {}
    if decal then
        table.insert(decals, decal)
    elseif ctx_ref.BB.DEBUG then
        print("[BossFeedback] ShowRectZone - 데칼 스폰 실패 (머티리얼 경로 확인)")
    end

    -- 판정용 영역 메타 (히트박스가 그대로 참조 → 보이는 대로 맞음)
    return {
        decals = decals, locked = false,
        kind   = "rect",
        origin = Vector(bossPos.X, bossPos.Y, bossPos.Z),
        yaw    = yaw,
    }
end

-- ════════════════════════════════════════════
-- P1: 부채꼴 장판 (가는 조각 N개를 방사형으로 펼침)
-- ════════════════════════════════════════════
function BossFeedback.ShowFanZone(target)
    local F = ctx_ref.BB.FEEDBACK
    local bossPos = ctx_ref.obj.Location
    local _, baseYaw = ResolveDirection(bossPos, target)

    local decals = {}
    local n    = F.FAN_SEGMENTS
    local half = F.FAN_ANGLE * 0.5

    for i = 0, n - 1 do
        -- 조각 중앙 각도 offset: -half ~ +half 를 n등분, 각 칸의 중앙
        local offset = -half + F.FAN_ANGLE * ((i + 0.5) / n)
        local segYaw = baseYaw + offset
        local rad    = segYaw * math.pi / 180.0
        local dx, dy = math.cos(rad), math.sin(rad)

        -- 조각 중심 = 보스에서 반지름의 절반 거리 (조각이 보스→바깥으로 뻗음)
        local decal = SpawnPiece(F,
            bossPos.X + dx * (F.FAN_RADIUS * 0.5),
            bossPos.Y + dy * (F.FAN_RADIUS * 0.5),
            bossPos.Z + F.ZONE_Z_OFFSET,
            segYaw, F.FAN_RADIUS, F.FAN_SEG_WIDTH)

        if decal then
            table.insert(decals, decal)
        end
    end

    if #decals == 0 and ctx_ref.BB.DEBUG then
        print("[BossFeedback] ShowFanZone - 데칼 스폰 실패 (머티리얼 경로 확인)")
    end

    -- 판정용 영역 메타 (부채꼴: 중심 방향 = baseYaw)
    return {
        decals = decals, locked = false,
        kind   = "fan",
        origin = Vector(bossPos.X, bossPos.Y, bossPos.Z),
        yaw    = baseYaw,
    }
end

-- ════════════════════════════════════════════
-- P2: 가로 베기 예고선 (보스 앞에 좌우로 긴 직사각형)
--   방향 = 보스→플레이어에 수직(90°) → 가로로 베는 궤적
-- ════════════════════════════════════════════
function BossFeedback.ShowSlashLine(target)
    local F = ctx_ref.BB.FEEDBACK
    local bossPos = ctx_ref.obj.Location
    local dir, baseYaw = ResolveDirection(bossPos, target)

    -- 직사각형 중심 = 보스 앞쪽 P2_DIST 거리
    local cx = bossPos.X + dir.X * F.P2_DIST
    local cy = bossPos.Y + dir.Y * F.P2_DIST
    local cz = bossPos.Z + F.ZONE_Z_OFFSET

    -- 가로 방향: 보스→플레이어에 수직 (데칼 길이축이 좌우를 향함)
    local lineYaw = baseYaw + 90.0

    local decal = SpawnPiece(F, cx, cy, cz, lineYaw, F.P2_LENGTH, F.P2_WIDTH)

    local decals = {}
    if decal then
        table.insert(decals, decal)
    elseif ctx_ref.BB.DEBUG then
        print("[BossFeedback] ShowSlashLine - 데칼 스폰 실패 (머티리얼 경로 확인)")
    end

    -- 판정용 메타 (중심 기준 박스)
    return {
        decals = decals, locked = false,
        kind   = "box",
        center = Vector(cx, cy, cz),
        yaw    = lineYaw,
    }
end

-- ────────────────────────────────────────────
-- 추적: 직사각형(P3) 장판을 플레이어 위치/방향으로 갱신
-- ※ BossCharacter.Tick 에서 매 프레임 호출 예정 (다음 단계 연결)
--    부채꼴은 추적하지 않는다 (P1 은 고정 패턴)
-- ────────────────────────────────────────────
function BossFeedback.TrackZone(zone, target)
    if zone == nil or zone.locked or zone.decals == nil then return end
    if #zone.decals ~= 1 then return end   -- 단일 직사각형만 추적
    if not (target and target:IsValid()) then return end

    local F = ctx_ref.BB.FEEDBACK
    local bossPos = ctx_ref.obj.Location
    local dir, yaw = ResolveDirection(bossPos, target)

    local d = zone.decals[1]
    d:SetLocation(Vector(
        bossPos.X + dir.X * (F.ZONE_LENGTH * 0.5),
        bossPos.Y + dir.Y * (F.ZONE_LENGTH * 0.5),
        bossPos.Z + F.ZONE_Z_OFFSET))
    d:SetRotation(Vector(0.0, 0.0, yaw))
end

-- 추적 정지 (위치/방향 고정)
function BossFeedback.LockZone(zone)
    if zone then zone.locked = true end
end

-- 번쩍임 (모든 조각 색 진해짐)
function BossFeedback.FlashZone(zone)
    if zone == nil or zone.decals == nil then return end
    local c = ctx_ref.BB.FEEDBACK.ZONE_COLOR_FLASH
    for _, d in ipairs(zone.decals) do
        d:SetColorRGBA(c[1], c[2], c[3], c[4])
    end
end

-- 제거 (모든 조각 즉시 페이드아웃 → 자동파괴)
function BossFeedback.HideZone(zone)
    if zone == nil or zone.decals == nil then return end
    for _, d in ipairs(zone.decals) do
        d:SetFadeOut(0.0, 0.15)
    end
    zone.decals = {}
end

return BossFeedback
