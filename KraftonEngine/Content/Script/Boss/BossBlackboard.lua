-- BossBlackboard.lua
-- 모든 수치 조절은 이 파일에서만 한다.
-- 개발 중 이 파일만 건드리면 BB 전체 수치가 반영된다.

local BB = {}

-- ── 체력 ─────────────────────────────────────
BB.MAX_HP = 100.0   -- 보스 최대 체력

-- ── 거리 임계값 ──────────────────────────────
BB.CHASE_DISTANCE  = 15.0   -- 이 이상이면 추격
BB.ATTACK_DISTANCE = 15.0   -- 이 이하이면 공격 가능

-- ── LookAt 회전 속도 (도/초) ─────────────────
BB.LOOK_AT_SPEED = 400.0   -- 너무 작으면 허공 칼질, 너무 크면 스냅

-- ── 글로벌 쿨타임 (패턴 종료 후 추가 대기) ───
BB.PATTERN_COOLDOWN = {
    AFTER_P1 = 1.3,   -- 패턴 간 숨 돌릴 틈 (연속 압박 완화)
    AFTER_P2 = 1.6,
    AFTER_P3 = 1.0,
}
BB.HEAVY_ATTACK_COOLDOWN = 8.0   -- P3 개별 쿨타임 (난사 방지)

-- ── 패턴 선택 확률 ───────────────────────────
BB.PROB_HEAVY  = 0.35   -- 패턴3(강공격) 선택 확률 — 길고 강하니 약간 낮춤
BB.PROB_DOUBLE = 0.35  -- 패턴2(2연타) 선택 확률 (누적: 0.35 + 0.35)
-- 나머지 0.30 → 패턴1(빠른 견제)

-- ── 패턴 1: 단발 (HeavyCombo1) — 옆으로 피하기
-- 타이밍은 애니 에셋의 FlashWarning / HitboxOpen 노티파이로 제어
BB.P1 = {
    DAMAGE   = 10,
    HITSTOP  = 0.04,
    RECOVERY = 0.60,   -- 피격 판정 후 후딜 (반격 타임)
}

-- ── 패턴 2: 부채꼴 2연타 (HeavyCombo2 → HeavyCombo3) — 뒤/타이밍 회피
-- 각 클립에 FlashWarning + HitboxOpen 노티파이 1쌍씩
BB.P2 = {
    DAMAGE1  = 8,
    DAMAGE2  = 12,
    HITSTOP  = 0.04,
    RECOVERY = 1.75,   -- 2타 판정 후 후딜
}

-- ── 패턴 3: 차오름 강타 (LightCombo3 → LightCombo4) — 차오름 보고 회피
-- 노티파이: TrackEnd(회전 멈춤) → FlashWarning(섬광) → HitboxOpen(판정)
BB.P3 = {
    DAMAGE        = 25,
    HITSTOP       = 0.08,
    RECOVERY      = 1.25,    -- 피격 판정 후 후딜
}

-- ── 장판(텔레그래프) 연출 수치 ──────────────
BB.FEEDBACK = {
    DECAL_MATERIAL = "Content/Material/VFX/M_WhiteZone.mat",

    -- P3 직사각형 장판 크기 (데칼 볼륨 OBB)
    ZONE_LENGTH   = 20.0,    -- 보스 앞으로 뻗는 길이
    ZONE_WIDTH    = 10,    -- 폭
    ZONE_HEIGHT   = 2.0,    -- 위아래 볼륨 (바닥 투영용)
    ZONE_Z_OFFSET = -2.5,   -- 보스 위치 기준 Z 보정 (발밑으로) — 띄워보고 조절

    -- 색 (R,G,B,A)
    ZONE_COLOR_OUTLINE = { 1.0, 0.0, 0.0, 0.12 },   -- 전체 범위 미리보기 (아주 흐릿하게)
    ZONE_COLOR_IDLE  = { 1.0, 0.0, 0.0, 0.4 },   -- 평소 흐릿한 빨강
    ZONE_COLOR_FLASH = { 1.0, 0.0, 0.0, 1.0 },   -- 번쩍임 (진해짐)

    -- ZoneShow 시작 → ZoneFlash 시점까지 장판이 점점 차오르는 연출 기준 시간 (VFX 튜닝용)
    FILL_DURATION = 1.55,

    -- P1 종베기 장판 (좁은 직사각형 → 옆으로 피해야 회피 성공)
    P1_LENGTH = 10.0,   -- 보스 앞으로 뻗는 길이 (P3 8.0보다 짧게)
    P1_WIDTH  = 10,   -- 폭 (좁을수록 옆 회피 유도)

    -- P2 횡베기 부채꼴 장판 (가는 조각 N개를 방사형으로 펼침)
    FAN_ANGLE     = 55.0,   -- 총 중심각 (도) — 80→55, 좌우로 옆 회피 공간 확보
    FAN_SEGMENTS  = 10,      -- 조각 개수 (많을수록 매끈, 무거움)
    FAN_RADIUS    = 10.0,    -- 부채꼴 반지름 (조각 길이)
    FAN_SEG_WIDTH = 5,    -- 조각 폭 (인접 조각과 겹치게 넉넉히 → 빈틈 방지)

    -- 자동 페이드 방지용 큰 값 (HideZone 에서 직접 제거)
    NO_FADE_DELAY = 9999.0,

    -- 플레이어에게 맞았을 때 보스 메시만 잠깐 눌렀다가 복구하는 피격 squash.
    HIT_SQUASH_ENABLED = true,
    HIT_SQUASH_SCALE = Vector(1.06, 1.06, 0.95),
    HIT_SQUASH_IN_DURATION = 0.035,
    HIT_SQUASH_RECOVER_DURATION = 0.09,

    -- 피격 시 collision capsule 은 그대로 두고 mesh local Y 방향으로만 짧게 흔든다.
    HIT_SHAKE_ENABLED = true,
    HIT_SHAKE_AMPLITUDE = 1.0,
    HIT_SHAKE_DURATION = 0.08,
    HIT_SHAKE_FREQUENCY = 70.0,
}

-- ── 방향별 피격 모션 ──────────────────────────
-- 플레이어가 보스를 때린 위치(보스 기준 앞/뒤/좌/우)에 따라 다른 피격 애니메이션을 재생한다.
-- 방향 판정은 CombatContext.ApplyHitToBoss 가 하고, 재생은 BossAnimation 상태머신이 한다.
-- (플레이어 PlayerConfig.Animation.Samurai.HitReactPaths 구조를 보스로 이식한 것)
--
-- 방향 키는 "공격자가 보스 기준 어느 쪽에 있는가" 다. (예: 공격자가 오른쪽 → Right → SamuraiHit_Right)
-- 경로가 nil 이면 BossAnimation 이 기존 콤보 클립(LightCombo1)으로 폴백한다.
BB.HIT_REACT = {
    ENABLED = true,
    PATHS = {
        Front = "Content/Animation/Samurai_Boss/SamuraiHit_Front.uasset",
        Back  = "Content/Animation/Samurai_Boss/SamuraiHit_Back.uasset",
        Left  = "Content/Animation/Samurai_Boss/SamuraiHit_Left.uasset",
        Right = "Content/Animation/Samurai_Boss/SamuraiHit_Right.uasset",
    },
    BLEND_IN          = 0.05,
    BLEND_OUT         = 0.12,
    PLAY_RATE         = 1.0,
    FALLBACK_DURATION = 0.45,   -- "HitReactEnd" notify 누락 시 강제 복귀까지의 시간(초)

    -- true  : 공격/콤보 중에도 피격 모션으로 끊는다 (플레이어와 동일 동작)
    -- false : 공격 중에는 피격 모션을 생략한다 (슈퍼아머)
    INTERRUPT_ATTACK  = false,
}

-- ── 디버그 ───────────────────────────────────
BB.DEBUG = false   -- false 로 바꾸면 print 전부 꺼짐

return BB
