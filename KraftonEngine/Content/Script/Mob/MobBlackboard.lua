-- Mob/MobBlackboard.lua
-- 모든 수치 조절은 이 파일에서만 한다.
-- 개발 중 이 파일만 건드리면 잡몹 전체 수치가 반영된다.

local MB = {}

-- ── 체력 ─────────────────────────────────────
MB.MAX_HP = 100.0   -- 잡몹 최대 체력
MB.CAPSULE_HALF_HEIGHT = 5.0 -- 잡몹 캡슐 절반 높이 (C++ 스펙인 5.0m 매칭)

-- ── 거리 임계값 ──────────────────────────────
MB.CHASE_DISTANCE  = 12.0   -- 이 이상이면 추격
MB.ATTACK_DISTANCE = 10.0   -- 이 이하이면 공격 가능

-- ── LookAt 회전 속도 (도/초) ─────────────────
MB.LOOK_AT_SPEED = 400.0

-- ── 잡몹 간 겹침 방지(Separation) ────────────
-- 추격 중 이 반경 안에 다른 잡몹이 있으면 멀어지는 반발 벡터를 추격 방향에 섞는다.
MB.SEPARATION_RADIUS = 10.0   -- 이 거리 안의 잡몹끼리 서로 밀어냄 (월드 단위, 잡몹 몸폭 기준)
MB.SEPARATION_WEIGHT = 30.0   -- 추격 방향 대비 반발 강도 (클수록 더 강하게 벌어짐)

-- ── 공격 수치 ────────────────────────────────
MB.ATTACK_COOLDOWN = 3.0    -- 공격 시작 시 충전되는 다음 공격까지의 쿨타임
MB.DAMAGE          = 3      -- 1회 피격 시 데미지
MB.RECOVERY        = 0.5    -- 판정 종료 후 후딜 (ActionLock 해제까지)

-- ── 장판(텔레그래프) 직사각형 규격 ───────────
MB.ZONE_LENGTH = 10.0 -- 잡몹 앞으로 뻗는 길이 (사거리 + 여유)
MB.ZONE_WIDTH  = 7.0                         -- 폭 (좁으면 정면에서 살짝 벗어나도 빗나감)

-- ── 공격 전 장판 리드 타임 (장판 생성 → 공격 모션 시작) ──
-- 준비 모션(Idle1)을 없앤 뒤, 이 값만큼 코드가 미리 장판을 띄우고 차오르게 한 다음
-- 공격 애니를 트리거한다. 클수록 플레이어가 장판 보고 피할 시간이 길어진다. (초) — 보스의 ZONE_LEAD 대응.
MB.ZONE_LEAD = 0.35

-- ── 장판 연출 수치 ───────────────────────────
MB.FEEDBACK = {
    DECAL_MATERIAL   = "Content/Material/VFX/M_WhiteZone.mat",
    ZONE_HEIGHT      = 2.0,    -- 위아래 볼륨 (바닥 투영용)
    ZONE_Z_OFFSET    = -2.5,   -- 잡몹 위치 기준 Z 보정 (발밑으로)
    ZONE_COLOR_OUTLINE = { 1.0, 0.0, 0.0, 0.12 },  -- 전체 범위 미리보기 (아주 흐릿하게, 배경) — 보스와 동일
    ZONE_COLOR_IDLE  = { 1.0, 0.0, 0.0, 1.0 },    -- 차오르는 장판 (불투명한 빨강) — 보스와 동일
    ZONE_COLOR_FLASH = { 1.0, 0.0, 0.0, 1.0 },    -- 번쩍임 (완전 불투명)
    NO_FADE_DELAY    = 9999.0, -- 자동 페이드 방지용 큰 값 (HideZone 에서 직접 제거)
    FILL_DURATION    = 0.5,   -- ZoneShow → ZoneFlash 까지 장판이 점점 차오르는 연출 기준 시간 (VFX 튜닝용)
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

-- ── 사망 모션 ─────────────────────────────────
-- 치명타(HP 0)가 들어온 방향에 따라 둘 중 하나만 재생한다 (좌/우 구분 없음, 보스와 동일 철학).
-- 방향 판정은 CombatContext.HandleMobDeath 가 하고, 재생은 MobAnimation 상태머신이 한다.
-- 앞에서 공격이 들어와 죽으면 Forward, 뒤에서 들어와 죽으면 Backward 모션으로 죽는다.
-- 사망 후에는 다른 상태로 돌아가지 않는 종료 상태다.
MB.DEATH = {
    PATHS = {
        Front = "Content/Animation/Samurai_Mob/ARPG_Samurai_Anim_UE_Death_Forward_Unreal_Take.uasset",
        Back  = "Content/Animation/Samurai_Mob/ARPG_Samurai_Anim_UE_Death_Backward_Unreal_Take.uasset",
    },
    BLEND_IN  = 0.15,
    PLAY_RATE = 1.0,
}

-- ── 디버그 ───────────────────────────────────
MB.DEBUG = false   -- false 로 바꾸면 print 전부 꺼짐

return MB
