-- Mob/MobBlackboard.lua
-- 모든 수치 조절은 이 파일에서만 한다.
-- 개발 중 이 파일만 건드리면 잡몹 전체 수치가 반영된다.

local MB = {}

-- ── 체력 ─────────────────────────────────────
MB.MAX_HP = 100.0   -- 잡몹 최대 체력

-- ── 거리 임계값 ──────────────────────────────
MB.CHASE_DISTANCE  = 12.0   -- 이 이상이면 추격
MB.ATTACK_DISTANCE = 10.0   -- 이 이하이면 공격 가능

-- ── LookAt 회전 속도 (도/초) ─────────────────
MB.LOOK_AT_SPEED = 400.0

-- ── 공격 수치 ────────────────────────────────
MB.ATTACK_COOLDOWN = 2.0    -- 공격 시작 시 충전되는 다음 공격까지의 쿨타임
MB.DAMAGE          = 3      -- 1회 피격 시 데미지
MB.RECOVERY        = 0.5    -- 판정 종료 후 후딜 (ActionLock 해제까지)

-- ── 장판(텔레그래프) 직사각형 규격 ───────────
MB.ZONE_LENGTH = 20.0 -- 잡몹 앞으로 뻗는 길이 (사거리 + 여유)
MB.ZONE_WIDTH  = 7.0                         -- 폭 (좁으면 정면에서 살짝 벗어나도 빗나감)

-- ── 장판 연출 수치 ───────────────────────────
MB.FEEDBACK = {
    DECAL_MATERIAL   = "Content/Material/VFX/M_WhiteZone.mat",
    ZONE_HEIGHT      = 2.0,    -- 위아래 볼륨 (바닥 투영용)
    ZONE_Z_OFFSET    = -2.5,   -- 잡몹 위치 기준 Z 보정 (발밑으로)
    ZONE_COLOR_IDLE  = { 1.0, 0.0, 0.0, 0.4 },   -- 평소 흐릿한 빨강
    ZONE_COLOR_FLASH = { 1.0, 0.0, 0.0, 0.9 },   -- 번쩍임 (진해짐)
    NO_FADE_DELAY    = 9999.0, -- 자동 페이드 방지용 큰 값 (HideZone 에서 직접 제거)
    FILL_DURATION    = 1.55,   -- ZoneShow → ZoneFlash 까지 장판이 점점 차오르는 연출 기준 시간 (VFX 튜닝용)
}

-- ── 방향별 피격 모션 ──────────────────────────
-- 플레이어가 잡몹을 때린 위치(잡몹 기준 앞/뒤/좌/우)에 따라 다른 피격 애니메이션을 재생한다.
-- 방향 판정은 CombatContext.ApplyHitToMob 가 하고, 재생은 MobAnimation 상태머신이 한다.
-- 방향 키는 "공격자가 잡몹 기준 어느 쪽에 있는가" (예: 공격자가 오른쪽 → Right → SamuraiHitAnim_Right)
-- 경로가 nil 이면 MobAnimation 이 기존 공격 클립(ATTACK_PATH)으로 폴백한다.
MB.HIT_REACT = {
    ENABLED = true,
    PATHS = {
        Front = "Content/Animation/Samurai_Mob/SamuraiHitAnim_Front.uasset",
        Back  = "Content/Animation/Samurai_Mob/SamuraiHitAnim_Back.uasset",
        Left  = "Content/Animation/Samurai_Mob/SamuraiHitAnim_Left.uasset",
        Right = "Content/Animation/Samurai_Mob/SamuraiHitAnim_Right.uasset",
    },
    BLEND_IN          = 0.05,
    BLEND_OUT         = 0.12,
    PLAY_RATE         = 1.0,
    FALLBACK_DURATION = 0.45,   -- "HitReactEnd" notify 누락 시 강제 복귀까지의 시간(초)

    -- 공격 중 피격 시 진행 중이던 공격 코루틴을 취소한다 (보스의 슈퍼아머와 반대).
    CANCEL_ATTACK_ON_HIT = true,
}

-- ── 디버그 ───────────────────────────────────
MB.DEBUG = false   -- false 로 바꾸면 print 전부 꺼짐

return MB
