-- BossFeedback.lua
-- 장판(텔레그래프) / 이펙트 / 연출 담당
-- BossAttacks 코루틴이 호출한다.
--
-- zone 구조: { decals, kind, origin/center, yaw, length, width }
--   rect (P1·P3) = 데칼 1개  /  box (P2) = 데칼 1개

local BossFeedback = {}

local ctx_ref = nil   -- BossCharacter.lua 에서 Init 으로 주입

local KATANA_MESH_PATH  = "Content/Mesh/Katana/source/red cyber katana_StaticMesh.uasset"
local KATANA_SOCKET_NAME = "pinky_01_r_socket"

-- ────────────────────────────────────────────
-- ── 칼 손맞춤 보정값 ── 손에 안 맞으면 여기 숫자만 바꿔서 조정 ──
-- 보스 본 스케일이 플레이어의 약 1/10이라 10배가 플레이어 1배와 같은 크기.
local KATANA_LOCATION = Vector(0.0, 0.0, 0.0)     -- 위치 (X 앞뒤 / Y 좌우 / Z 상하)
local KATANA_ROTATION = Vector(0.0, 0.0, 0.0)     -- 기울기 (Pitch / Roll / Yaw)
local KATANA_SCALE    = Vector(1.0, 1.0, 1.0)  -- 크기

local function AttachKatanaToBoss()
    local owner = ctx_ref.obj
    if owner == nil then return end

    if ctx_ref.KatanaComponent ~= nil and ctx_ref.KatanaComponent:IsValid() then
        return
    end

    local meshComp = owner:GetSkeletalMeshComponent()
    if meshComp == nil then
        print("[BossFeedback] SkeletalMeshComponent not found")
        return
    end

    local katana = owner:AddStaticMeshComponent()
    if katana == nil then
        print("[BossFeedback] Failed to create katana component")
        return
    end

    katana:SetMeshPath(KATANA_MESH_PATH)
    katana:AttachToComponentWithSocket(meshComp, KATANA_SOCKET_NAME)
    katana.RelativeLocation = KATANA_LOCATION
    katana:SetRotation(KATANA_ROTATION)
    katana:SetRelativeScale(KATANA_SCALE)

    ctx_ref.KatanaComponent = katana
end

-- ────────────────────────────────────────────
function BossFeedback.Init(ctx)
    ctx_ref = ctx
    -- 칼 부착 실패가 BeginPlay 전체를 막지 않도록 격리한다.
    -- (보스 스켈레톤에 소켓 pinky_01_r_socket 이 없으면 AttachToComponentWithSocket 이
    --  에러를 던져 BeginPlay 가 중단되고, 뒤따르는 Hitbox.Init / RegisterBoss 가 통째로
    --  건너뛰어진다 → Hitbox.ctx_ref 가 nil 이라 공격 판정 코루틴이 죽는다.)
    local ok, err = pcall(AttachKatanaToBoss)
    if not ok then
        print("[BossFeedback] AttachKatanaToBoss 실패 - 칼 없이 계속: " .. tostring(err))
    end
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

    -- 판정용 영역 메타 — length/width 내장 (CheckRect 가 zone 값 우선 사용)
    return {
        decals = decals,
        kind   = "rect",
        origin = Vector(bossPos.X, bossPos.Y, bossPos.Z),
        yaw    = yaw,
        length = F.ZONE_LENGTH,
        width  = F.ZONE_WIDTH,
    }
end

-- ════════════════════════════════════════════
-- P1: 종베기 장판 (좁은 직사각형 — 옆으로 피해야 회피 성공)
--   P3 ShowRectZone 과 같은 구조지만 P1_LENGTH / P1_WIDTH 로 좁고 짧게.
-- ════════════════════════════════════════════
function BossFeedback.ShowP1Zone(target)
    local F = ctx_ref.BB.FEEDBACK
    local bossPos = ctx_ref.obj.Location
    local dir, yaw = ResolveDirection(bossPos, target)

    local decal = SpawnPiece(F,
        bossPos.X + dir.X * (F.P1_LENGTH * 0.5),
        bossPos.Y + dir.Y * (F.P1_LENGTH * 0.5),
        bossPos.Z + F.ZONE_Z_OFFSET,
        yaw, F.P1_LENGTH, F.P1_WIDTH)

    local decals = {}
    if decal then
        table.insert(decals, decal)
    elseif ctx_ref.BB.DEBUG then
        print("[BossFeedback] ShowP1Zone - 데칼 스폰 실패 (머티리얼 경로 확인)")
    end

    return {
        decals = decals,
        kind   = "rect",
        origin = Vector(bossPos.X, bossPos.Y, bossPos.Z),
        yaw    = yaw,
        length = F.P1_LENGTH,
        width  = F.P1_WIDTH,
    }
end

-- ════════════════════════════════════════════
-- P2: 횡베기 부채꼴 장판 (가는 조각 N개를 방사형으로 펼침)
--   좌우로 넓게 휩쓸리는 느낌 → 뒤로 빠지거나 타이밍 회피
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

    return {
        decals = decals,
        kind   = "fan",
        origin = Vector(bossPos.X, bossPos.Y, bossPos.Z),
        yaw    = baseYaw,
    }
end

-- ════════════════════════════════════════════
-- 차오름(fill-up): 직사각형 장판 길이를 0→full 로 늘림
--   ratio 0.0~1.0. 보스쪽 끝(origin) 고정, 플레이어쪽으로 늘어남.
--   ※ 시각 연출만. 판정(Hitbox)은 가득 찬 full 영역 기준(HIT 시점).
-- ════════════════════════════════════════════
function BossFeedback.FillZone(zone, ratio)
    if zone == nil or zone.decals == nil or #zone.decals == 0 then return end
    if zone.kind ~= "rect" then return end   -- 직사각형만

    local d = zone.decals[1]
    if d == nil then return end

    local F      = ctx_ref.BB.FEEDBACK
    local full   = zone.length or F.ZONE_LENGTH
    local width  = zone.width  or F.ZONE_WIDTH
    local len = math.max(0.01, full * ratio)   -- 0 방지

    -- 방향 단위벡터 (zone.yaw 기준)
    local rad = zone.yaw * math.pi / 180.0
    local dx, dy = math.cos(rad), math.sin(rad)

    -- 중심 = origin(보스쪽 끝)에서 dir 방향으로 len/2
    local cx = zone.origin.X + dx * (len * 0.5)
    local cy = zone.origin.Y + dy * (len * 0.5)
    local cz = zone.origin.Z + F.ZONE_Z_OFFSET

    d:SetLocation(Vector(cx, cy, cz))
    d:SetRelativeScale(Vector(len, width, F.ZONE_HEIGHT))
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
