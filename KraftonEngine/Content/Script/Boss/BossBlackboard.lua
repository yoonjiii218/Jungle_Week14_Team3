-- BossBlackboard.lua
-- 모든 수치 조절은 이 파일에서만 한다.
-- 개발 중 이 파일만 건드리면 BB 전체 수치가 반영된다.

local BB = {}

-- ── 거리 임계값 ──────────────────────────────
BB.CHASE_DISTANCE  = 10.0   -- 이 이상이면 추격
BB.ATTACK_DISTANCE = 7.0   -- 이 이하이면 공격 가능

-- ── LookAt 회전 속도 (도/초) ─────────────────
BB.LOOK_AT_SPEED = 540.0   -- 너무 작으면 허공 칼질, 너무 크면 스냅

-- ── 글로벌 쿨타임 (패턴 종료 후 추가 대기) ───
BB.PATTERN_COOLDOWN = {
    AFTER_P1 = 1.0,
    AFTER_P2 = 1.2,
    AFTER_P3 = 0.5,   -- P3는 후딜이 이미 길어서 짧게
}
BB.HEAVY_ATTACK_COOLDOWN = 8.0   -- P3 개별 쿨타임 (난사 방지)

-- ── 패턴 선택 확률 ───────────────────────────
BB.PROB_HEAVY  = 0.40   -- 패턴3 선택 확률 (HeavyAttackCooldown <= 0 일 때)
BB.PROB_DOUBLE = 0.30   -- 패턴2 선택 확률 (누적: 0.40 + 0.30)
-- 나머지 0.30 → 패턴1

-- ── 패턴 1: 기본 베기 타임라인 ──────────────
BB.P1 = {
    WINDUP = 0.4,   -- 장판 번쩍임 (회피 타이밍 가이드)
    HIT    = 0.5,   -- 데미지 판정 시점
    TOTAL  = 1.0,   -- 전체 지속 시간 (후딜 포함)
}

-- ── 패턴 2: 2연속 베기 타임라인 ─────────────
BB.P2 = {
    HIT1        = 0.4,   -- 1타 판정
    SECOND_WIND = 0.5,   -- 2타 예고선 표시
    HIT2        = 0.9,   -- 2타 판정
    TOTAL       = 1.8,   -- 전체 지속 시간
}

-- ── 패턴 3: 강한 내려찍기 타임라인 ──────────
BB.P3 = {
    TRACK_END              = 0.8,    -- 플레이어 추적 멈추는 시점
    FLASH                  = 1.2,    -- 붉은 섬광 + 퍼펙트 회피 신호
    HIT                    = 1.4,    -- 데미지 판정 시점
    TOTAL                  = 3.0,    -- 전체 지속 시간 (긴 후딜 포함)
    PERFECT_WINDOW         = 0.2,    -- FLASH ~ HIT 사이 퍼펙트 회피 창 (초)
    PERFECT_SLOMO_DURATION = 1.5,    -- 퍼펙트 회피 슬로우모션 지속 시간
    PERFECT_SLOMO_SCALE    = 0.1,    -- 퍼펙트 회피 타임스케일 (0.1 = 10% 속도)
}

-- ── 장판(텔레그래프) 연출 수치 ──────────────
BB.FEEDBACK = {
    DECAL_MATERIAL = "Content/Material/VFX/M_GroundCrack.mat",

    -- P3 직사각형 장판 크기 (데칼 볼륨 OBB)
    ZONE_LENGTH   = 8.0,    -- 보스 앞으로 뻗는 길이
    ZONE_WIDTH    = 2.5,    -- 폭
    ZONE_HEIGHT   = 2.0,    -- 위아래 볼륨 (바닥 투영용)
    ZONE_Z_OFFSET = -2.5,   -- 보스 위치 기준 Z 보정 (발밑으로) — 띄워보고 조절

    -- 색 (R,G,B,A)
    ZONE_COLOR_IDLE  = { 1.0, 0.0, 0.0, 0.4 },   -- 평소 흐릿한 빨강
    ZONE_COLOR_FLASH = { 1.0, 0.0, 0.0, 0.9 },   -- 번쩍임 (진해짐)

    -- P1 부채꼴 장판 (가는 데칼 조각을 방사형으로 펼쳐서 근사)
    FAN_ANGLE    = 80.0,   -- 총 중심각 (도)
    FAN_SEGMENTS = 7,      -- 조각 개수 (많을수록 매끈, 무거움)
    FAN_RADIUS   = 6.0,    -- 부채꼴 반지름 (조각 길이)
    FAN_SEG_WIDTH = 1.6,   -- 조각 폭 (인접 조각과 겹치게 넉넉히 → 빈틈 방지)

    -- 자동 페이드 방지용 큰 값 (HideZone 에서 직접 제거)
    NO_FADE_DELAY = 9999.0,
}

-- ── 디버그 ───────────────────────────────────
BB.DEBUG = true   -- false 로 바꾸면 print 전부 꺼짐

return BB
