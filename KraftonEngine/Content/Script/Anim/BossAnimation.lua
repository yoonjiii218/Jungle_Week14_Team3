-- BossAnimation.lua
-- 보스 사무라이 애니메이션 상태 머신.
-- BossAction.lua 의 AI 패턴이 아래 플래그를 설정해 공격을 트리거한다.
--
-- 외부에서 설정하는 플래그:
--   self.LightAttackPressed  = true   -- 라이트 콤보 시작 (P1 / P2)
--   self.MaxLightComboHits   = 1 or 2 -- P1=1, P2=2 (기본 1)
--   self.HeavyAttackPressed  = true   -- 헤비 콤보 시작 (P3)
--   self.MaxHeavyComboHits   = 1..5   -- 헤비 콤보 최대 단수 (기본 3)
--   self.DashSlashPressed    = true   -- 대시 슬래시 시작
--
-- 애니메이션 에셋의 Notify 이름 → on_notify 핸들러:
--   "AttackEnd"       -- 현재 공격 애니메이션 종료 신호
--   "DashEnd"         -- 대시 슬래시 종료 신호
--   "TrailActivate"   -- 검광 이펙트 켜기
--   "TrailDeactivate" -- 검광 이펙트 끄기
--   "HitboxOpen"      -- 히트박스 활성화 (BossHitbox 연동)
--   "HitboxClose"     -- 히트박스 비활성화

local CombatContext = require("Combat/CombatContext")
local BossContext = require("Boss/BossContext")
local BossConfig = require("Boss/BossBlackboard")

local ANIM_BASE = "Content/Animation/Samurai_Boss/"

local IDLE1_PATH  = ANIM_BASE .. "SamuraiAttack_Idle1.uasset"
local IDLE2_PATH  = ANIM_BASE .. "SamuraiAttack_Idle2.uasset"  -- 대기 중 idle 루프 변형
local WALK_PATH   = ANIM_BASE .. "SamuraiAttack_Walk.uasset"
local SPRINT_PATH = ANIM_BASE .. "SamuraiAttack_Sprint.uasset"

local LIGHT_COMBO_PATHS = {
    ANIM_BASE .. "SamuraiAttack_LightCombo1.uasset",
    ANIM_BASE .. "SamuraiAttack_LightCombo2.uasset",
    ANIM_BASE .. "SamuraiAttack_DashStart.uasset",
    ANIM_BASE .. "SamuraiAttack_LightCombo4.uasset",
}

local HEAVY_COMBO_PATHS = {
    ANIM_BASE .. "SamuraiAttack_HeavyCombo1.uasset",
    ANIM_BASE .. "SamuraiAttack_HeavyCombo2.uasset",
    ANIM_BASE .. "SamuraiAttack_HeavyCombo3.uasset",
    ANIM_BASE .. "SamuraiAttack_HeavyCombo4.uasset",
    ANIM_BASE .. "SamuraiAttack_HeavyCombo5.uasset",
}

local DASH_START_PATH = ANIM_BASE .. "SamuraiAttack_DashStart.uasset"
local DASH_SLASH_PATH = ANIM_BASE .. "SamuraiAttack_DashSlash.uasset"

-- 사망 모션 (피격 방향에 따라 둘 중 하나만 재생, 좌/우 구분 없음)
local DEATH_FRONT_PATH = ANIM_BASE .. "SamuraiDeath_Front.uasset"
local DEATH_BACK_PATH  = ANIM_BASE .. "SamuraiDeath_Back.uasset"
local DEATH_BLEND_IN   = 0.15

-- 속도 임계값.
-- get_owner_speed() 는 cm/s 가 아니라 ~10 스케일의 작은 값을 반환한다.
-- (PlayerConfig: RunThreshold=8.0, RunSampleSpeed=10.0 와 동일 스케일)
local WALK_SPEED   = 8.0
local SPRINT_SPEED = 15.0

-- 블렌드 시간 (초)
local ATTACK_BLEND_IN  = 0.12   -- 공격 진입 / 콤보 단 사이 전환
local ATTACK_BLEND_OUT = 0.25   -- 공격 → idle 복귀 (어색하면 0.2~0.35 사이 조정)
local DASH_BLEND_IN    = 0.08

-- 기본 재생 속도 (BossBlackboard.ANIM 으로 콤보 단별 오버라이드 가능 — PlayerConfig.Animation.Samurai 구조 참고)
local PLAY_RATE = 1.0

local function GetComboPlayRate(rates, index, defaultRate)
    if rates ~= nil and rates[index] ~= nil then
        return rates[index]
    end
    return defaultRate
end

-- 현재(끝나는) 단 기준으로 다음 단으로 넘어가기 전 멈춰있을 시간(초). 설정 없으면 0.
local function GetComboGap(gaps, index)
    if gaps ~= nil and gaps[index] ~= nil then
        return gaps[index]
    end
    return 0.0
end

-- 준비 모션(Idle1) fallback 최대 시간 — AttackEnd notify 누락 시 강제 전환
local ATTACK_PREP_DURATION = 2.0

-- 콤보 단별 애니메이션 길이 (초) — 실측값.
-- "AttackEnd" notify 가 없을 때 이 길이만큼 재생 후 다음 단/복귀시키는 fallback.
-- (notify 가 심어지면 notify 가 우선; 아래서 PLAY_RATE 로 나눠 실제 재생시간 보정)
-- 인덱스 = 콤보 단수: LightCombo1..4 / HeavyCombo1..5
local LIGHT_STAGE_DURATIONS = { 0.817, 0.967, 0.867, 1.150 }
local HEAVY_STAGE_DURATIONS = { 0.967, 1.050, 0.967, 1.050, 1.217 }

-- ──────────────────────────────────────────────────────────────────
-- 내부 헬퍼
-- ──────────────────────────────────────────────────────────────────

local function BeginLightCombo(self, index)
    self.LightComboIndex  = index
    self.AttackEnd        = false
    self.AttackTimer      = 0.0   -- fallback 타이머 리셋
    self.ComboGapElapsed  = 0.0   -- 단 사이 호흡(BB.ANIM.*_COMBO_GAPS) 타이머 리셋
end

local function BeginHeavyCombo(self, index)
    self.HeavyComboIndex  = index
    self.AttackEnd        = false
    self.AttackTimer      = 0.0   -- fallback 타이머 리셋
    self.ComboGapElapsed  = 0.0   -- 단 사이 호흡(BB.ANIM.*_COMBO_GAPS) 타이머 리셋
end

-- bossContext.Brain에 쌓인 공격 신호를 소비해 상태머신 트리거 플래그로 변환
local function ConsumeAnimSignal(self, bossContext)
    local brain = bossContext.Brain
    if brain.AnimAttack == nil then return end

    local kind = brain.AnimAttack
    local start = brain.AnimAttackStart or 1
    local hits  = brain.AnimAttackHits  or 1

    brain.AnimAttack      = nil
    brain.AnimAttackStart = nil
    brain.AnimAttackHits  = nil

    if kind == "dash" then
        self.DashSlashPressed = true
    else
        -- 콤보 직접 진입 대신 AttackPrep(Idle1) 경유
        self.PendingAttackKind  = kind
        self.PendingAttackStart = start
        self.PendingAttackHits  = hits
        self.AttackPrepPressed  = true
    end
end

local function ResetAttack(self)
    self.LightAttackPressed = false
    self.HeavyAttackPressed = false
    self.DashSlashPressed   = false
    self.LightComboIndex    = 0
    self.HeavyComboIndex    = 0
    self.AttackEnd          = false
    self.DashEnd            = false
    self.DashStartDone      = false
    self.AttackTimer        = 0.0
    self.AttackPrepPressed  = false
    self.AttackPrepActive   = false
    self.AttackPrepTimer    = 0.0
    self.PendingAttackKind  = nil
    self.PendingAttackStart = nil
    self.PendingAttackHits  = nil

    -- 슈퍼아머(IsBossAttacking) 가 풀리는 시점 = 여기.
    -- 공격 중 들어와 보류돼 있던 피격 리액션 신호를 함께 비워서,
    -- 슈퍼아머가 풀린 직후 뒤늦게 피격 모션이 재생되는 것을 막는다.
    self.HitReactPending    = false
    self.HitReactDirection  = nil
end

-- ──────────────────────────────────────────────────────────────────
function init(self)
    -- 보스 공격 애니(mixamo)는 루트본(Hips)에 전진/체중이동 모션이 들어있다.
    -- 엔진 기본 모드 RootMotionFromEverything 은 이 루트모션을 캡슐에 누적 적용해
    -- (+ HasYawDrivenByRootMotion 으로 회전까지) 공격할 때 몸이 앞으로 기울어 보인다.
    -- 보스는 제자리 공격 + 이동/회전을 AI(BossAction)가 직접 제어하므로 루트모션을 끈다.
    -- (플레이어도 루트모션 대신 PlayerAction.StepAttackForward 로 코드 전진하는 것과 동일 철학)
    Anim.set_root_motion_mode("IgnoreRootMotion")

    self.Speed      = 0.0
    self.BlendSpeed = 0.0
    self.BossContext = nil

    -- 외부 트리거 플래그
    self.LightAttackPressed = false
    self.HeavyAttackPressed = false
    self.DashSlashPressed   = false
    self.MaxLightComboHits  = 1   -- BossAttacks.lua 에서 패턴별로 덮어씀
    self.MaxHeavyComboHits  = 3   -- P3 기본값: HeavyCombo 1→2→3

    -- 방향별 피격 리액션 상태 플래그
    self.HitReactPending   = false   -- CombatContext 신호 소비 후 진입 대기
    self.HitReactActive    = false   -- 피격 모션 재생 중
    self.HitReactDirection = nil     -- "Front"/"Back"/"Left"/"Right"
    self.HitReactElapsed   = 0.0
    self.HitReactEnd       = false   -- "HitReactEnd" notify 수신

    ResetAttack(self)

    -- ── 이동 블렌드스페이스 (Idle → Walk → Sprint) ─────────────────
    local loco = Anim.create_blend_space_1d(0.0)
    Anim.blend_space_1d_add_sample(loco, IDLE2_PATH,  0.0,          1.0, true)
    Anim.blend_space_1d_add_sample(loco, WALK_PATH,   WALK_SPEED,   1.0, true)
    Anim.blend_space_1d_add_sample(loco, SPRINT_PATH, SPRINT_SPEED, 1.0, true)
    self.LocoBlendSpace = loco

    -- ── 최상위 상태 머신 ────────────────────────────────────────────
    local top = Anim.create_state_machine("BossTop")

    -- 이동
    Anim.sm_add_state(top, "Locomotion", loco)

    -- 콤보 단별 재생 속도 (BossBlackboard.ANIM — PlayerConfig.Animation.Samurai.AttackPlayRate(s) 구조 참고)
    local animConfig = BossConfig.ANIM or {}
    local defaultPlayRate = animConfig.DEFAULT_PLAY_RATE or PLAY_RATE
    self.LightPlayRates = animConfig.LIGHT_PLAY_RATES or {}
    self.HeavyPlayRates = animConfig.HEAVY_PLAY_RATES or {}
    self.DefaultPlayRate = defaultPlayRate

    -- 콤보 단 사이 호흡 (AttackEnd 후 다음 단으로 넘어가기 전 실제로 멈춰있는 시간)
    self.LightComboGaps = animConfig.LIGHT_COMBO_GAPS or {}
    self.HeavyComboGaps = animConfig.HEAVY_COMBO_GAPS or {}
    self.ComboGapElapsed = 0.0

    -- ── 콤보 상태 생성 (이게 있어야 아래 진입/체인 transition 이 참조할 상태가 존재) ──
    for i = 1, 4 do
        Anim.sm_add_state(top, "LightCombo" .. i,
            Anim.create_sequence_player(LIGHT_COMBO_PATHS[i], GetComboPlayRate(self.LightPlayRates, i, defaultPlayRate), false))
    end
    for i = 1, 5 do
        Anim.sm_add_state(top, "HeavyCombo" .. i,
            Anim.create_sequence_player(HEAVY_COMBO_PATHS[i], GetComboPlayRate(self.HeavyPlayRates, i, defaultPlayRate), false))
    end

    -- ── 공격 준비 모션 (Idle1): ZoneShow 노티파이로 장판 스폰 타이밍 고정 ──
    Anim.sm_add_state(top, "AttackPrep",
        Anim.create_sequence_player(IDLE1_PATH, PLAY_RATE, false))

    -- Locomotion → AttackPrep
    Anim.sm_add_transition(top, "Locomotion", "AttackPrep",
        function()
            if self.AttackPrepPressed then
                self.AttackPrepPressed = false
                self.AttackPrepActive  = true
                self.AttackPrepTimer   = 0.0
                self.AttackEnd         = false
                return true
            end
            return false
        end, ATTACK_BLEND_IN)

    -- AttackPrep → LightCombo_i
    for i = 1, 4 do
        Anim.sm_add_transition(top, "AttackPrep", "LightCombo" .. i,
            function()
                if self.AttackEnd
                    and self.PendingAttackKind  == "light"
                    and self.PendingAttackStart == i then
                    self.MaxLightComboHits  = self.PendingAttackHits
                    self.PendingAttackKind  = nil
                    self.AttackPrepActive   = false
                    BeginLightCombo(self, i)
                    return true
                end
                return false
            end, ATTACK_BLEND_IN)
    end

    -- AttackPrep → HeavyCombo_i
    for i = 1, 5 do
        Anim.sm_add_transition(top, "AttackPrep", "HeavyCombo" .. i,
            function()
                if self.AttackEnd
                    and self.PendingAttackKind  == "heavy"
                    and self.PendingAttackStart == i then
                    self.MaxHeavyComboHits  = self.PendingAttackHits
                    self.PendingAttackKind  = nil
                    self.AttackPrepActive   = false
                    BeginHeavyCombo(self, i)
                    return true
                end
                return false
            end, ATTACK_BLEND_IN)
    end

    -- AttackPrep → Locomotion: 이상 상태 안전 복귀
    Anim.sm_add_transition(top, "AttackPrep", "Locomotion",
        function()
            if self.AttackEnd then
                self.AttackPrepActive  = false
                self.PendingAttackKind = nil
                ResetAttack(self)
                return true
            end
            return false
        end, ATTACK_BLEND_OUT)

    -- 대시
    Anim.sm_add_state(top, "DashStart",
        Anim.create_sequence_player(DASH_START_PATH, PLAY_RATE, false))
    Anim.sm_add_state(top, "DashSlash",
        Anim.create_sequence_player(DASH_SLASH_PATH, PLAY_RATE, false))

    -- 라이트 콤보 체인: LightCombo_i → LightCombo_{i+1} or Locomotion
    for i = 1, 3 do
        local cur  = "LightCombo" .. i
        local next = "LightCombo" .. (i + 1)

        -- 다음 단으로 진행 (MaxLightComboHits 가 허용하는 경우)
        -- AttackEnd 가 떠도 곧장 넘어가지 않고, BB.ANIM.LIGHT_COMBO_GAPS[i] 만큼 실제로 멈췄다가 전환한다.
        Anim.sm_add_transition(top, cur, next,
            function()
                if self.AttackEnd and self.LightComboIndex < self.MaxLightComboHits
                    and (self.ComboGapElapsed or 0.0) >= GetComboGap(self.LightComboGaps, i) then
                    BeginLightCombo(self, i + 1)
                    return true
                end
                return false
            end, ATTACK_BLEND_IN)

        -- 최대 단 도달 → Locomotion 복귀
        Anim.sm_add_transition(top, cur, "Locomotion",
            function()
                if self.AttackEnd and self.LightComboIndex >= self.MaxLightComboHits then
                    ResetAttack(self)
                    return true
                end
                return false
            end, ATTACK_BLEND_OUT)
    end

    -- LightCombo4 → Locomotion (마지막 단, 항상 복귀)
    Anim.sm_add_transition(top, "LightCombo4", "Locomotion",
        function()
            if self.AttackEnd then
                ResetAttack(self)
                return true
            end
            return false
        end, ATTACK_BLEND_OUT)

    -- 헤비 콤보 체인: HeavyCombo_i → HeavyCombo_{i+1} or Locomotion
    for i = 1, 4 do
        local cur  = "HeavyCombo" .. i
        local next = "HeavyCombo" .. (i + 1)

        -- 다음 단으로 진행
        -- AttackEnd 가 떠도 곧장 넘어가지 않고, BB.ANIM.HEAVY_COMBO_GAPS[i] 만큼 실제로 멈췄다가 전환한다.
        -- (예: P2 = HeavyCombo2 → HeavyCombo3 이므로 [2] 에 BB.P2.HIT_GAP 을 넣으면 1타·2타 사이가 벌어짐)
        Anim.sm_add_transition(top, cur, next,
            function()
                if self.AttackEnd and self.HeavyComboIndex < self.MaxHeavyComboHits
                    and (self.ComboGapElapsed or 0.0) >= GetComboGap(self.HeavyComboGaps, i) then
                    BeginHeavyCombo(self, i + 1)
                    return true
                end
                return false
            end, ATTACK_BLEND_IN)

        -- 최대 단 도달 → Locomotion 복귀
        Anim.sm_add_transition(top, cur, "Locomotion",
            function()
                if self.AttackEnd and self.HeavyComboIndex >= self.MaxHeavyComboHits then
                    ResetAttack(self)
                    return true
                end
                return false
            end, ATTACK_BLEND_OUT)
    end

    -- HeavyCombo5 → Locomotion
    Anim.sm_add_transition(top, "HeavyCombo5", "Locomotion",
        function()
            if self.AttackEnd then
                ResetAttack(self)
                return true
            end
            return false
        end, ATTACK_BLEND_OUT)

    -- ── 대시 슬래시: Locomotion → DashStart → DashSlash → Locomotion
    Anim.sm_add_transition(top, "Locomotion", "DashStart",
        function()
            if self.DashSlashPressed then
                self.DashSlashPressed = false
                self.DashStartDone    = false
                self.AttackEnd        = false
                return true
            end
            return false
        end, DASH_BLEND_IN)

    -- DashStart 종료 → DashSlash 진입
    Anim.sm_add_transition(top, "DashStart", "DashSlash",
        function()
            if self.AttackEnd then
                self.DashStartDone = true
                self.AttackEnd     = false
                return true
            end
            return false
        end, DASH_BLEND_IN)

    -- DashSlash 종료 → Locomotion
    Anim.sm_add_transition(top, "DashSlash", "Locomotion",
        function()
            if self.AttackEnd or self.DashEnd then
                ResetAttack(self)
                return true
            end
            return false
        end, ATTACK_BLEND_OUT)

    -- ── 방향별 피격 리액션 ─────────────────────────────────────────
    -- 플레이어 PlayerAnimation 의 HitFront/Left/Right/Back 구조를 보스로 이식.
    -- CombatContext.ApplyHitToBoss 가 bossContext.Brain.HitReactSignal 에 방향을 써넣고,
    -- update() 가 그걸 소비해 self.HitReactPending/Direction 으로 변환하면 아래 전이가 발동한다.
    local hitReact          = BossConfig.HIT_REACT or {}
    local hitPaths          = hitReact.PATHS or {}
    local hitPlayRate       = hitReact.PLAY_RATE or 1.0
    local hitBlendIn        = hitReact.BLEND_IN or 0.05
    local hitBlendOut       = hitReact.BLEND_OUT or 0.12
    local hitFallbackDur    = hitReact.FALLBACK_DURATION or 0.45
    local hitInterrupt      = hitReact.INTERRUPT_ATTACK ~= false
    local hitFallbackPath   = LIGHT_COMBO_PATHS[1]   -- 경로 누락 시 안전 폴백

    Anim.sm_add_state(top, "HitFront", Anim.create_sequence_player(hitPaths.Front or hitFallbackPath, hitPlayRate, false))
    Anim.sm_add_state(top, "HitLeft",  Anim.create_sequence_player(hitPaths.Left  or hitFallbackPath, hitPlayRate, false))
    Anim.sm_add_state(top, "HitRight", Anim.create_sequence_player(hitPaths.Right or hitFallbackPath, hitPlayRate, false))
    Anim.sm_add_state(top, "HitBack",  Anim.create_sequence_player(hitPaths.Back  or hitFallbackPath, hitPlayRate, false))

    -- INTERRUPT_ATTACK=false 일 때 공격 중이면 피격 모션을 생략(슈퍼아머)하기 위한 판정
    local function IsBossAttacking()
        return self.LightComboIndex > 0
            or self.HeavyComboIndex > 0
            or self.AttackPrepActive == true
    end

    local function AddHitReactionTransitions(direction, stateName)
        -- AnyState → Hit_*: 신호가 들어오고 방향이 일치하면 진입
        Anim.sm_add_transition(top, "AnyState", stateName,
            function()
                if not self.HitReactPending or self.HitReactDirection ~= direction then
                    return false
                end
                if not hitInterrupt and IsBossAttacking() then
                    return false
                end
                self.HitReactPending = false
                self.HitReactActive  = true
                self.HitReactElapsed = 0.0
                self.HitReactEnd     = false
                ResetAttack(self)   -- 진행 중이던 콤보/대시 플래그 정리 (애니 락 잔류 방지)
                return true
            end, hitBlendIn)

        -- Hit_* → Locomotion: notify("HitReactEnd") 또는 fallback 시간 경과 시 복귀
        Anim.sm_add_transition(top, stateName, "Locomotion",
            function()
                if not self.HitReactActive then
                    return false
                end
                if self.HitReactEnd or (self.HitReactElapsed or 0.0) >= hitFallbackDur then
                    self.HitReactActive    = false
                    self.HitReactDirection = nil
                    self.HitReactElapsed   = 0.0
                    self.HitReactEnd       = false
                    return true
                end
                return false
            end, hitBlendOut)
    end

    AddHitReactionTransitions("Front", "HitFront")
    AddHitReactionTransitions("Left",  "HitLeft")
    AddHitReactionTransitions("Right", "HitRight")
    AddHitReactionTransitions("Back",  "HitBack")

    -- ── 사망 모션 ──────────────────────────────────────────────────
    -- CombatContext.HandleBossDeath 가 bossContext.Brain.DeathSignal 에 "Front"/"Back" 을 써넣고,
    -- update() 가 그걸 소비해 self.DeathPending/Direction 으로 변환하면 아래 전이가 발동한다.
    -- 좌/우 구분 없이 치명타가 앞에서 들어왔으면 Front, 뒤에서 들어왔으면 Back 모션으로 죽는다.
    -- 사망 후에는 다른 상태로 돌아가지 않는 종료 상태다.
    Anim.sm_add_state(top, "DeathFront", Anim.create_sequence_player(DEATH_FRONT_PATH, PLAY_RATE, false))
    Anim.sm_add_state(top, "DeathBack",  Anim.create_sequence_player(DEATH_BACK_PATH, PLAY_RATE, false))

    local function AddDeathTransition(direction, stateName)
        Anim.sm_add_transition(top, "AnyState", stateName,
            function()
                if not self.DeathPending or self.DeathDirection ~= direction then
                    return false
                end
                self.DeathPending = false
                return true
            end, DEATH_BLEND_IN)
    end

    AddDeathTransition("Front", "DeathFront")
    AddDeathTransition("Back",  "DeathBack")

    Anim.sm_set_initial_state(top, "Locomotion")

    local root = Anim.create_slot("DefaultSlot", top)
    Anim.set_root_node(root)
end

-- ──────────────────────────────────────────────────────────────────
function update(self, dt)
    if self.BlendSpeed == nil then
        self.BlendSpeed = 0.0
    end

    self.Speed = Anim.get_owner_speed()

    -- 속도를 부드럽게 보간해서 블렌드스페이스 입력으로 전달
    -- (PlayerConfig.LocomotionSpeedResponse = 12.0 과 동일)
    local alpha = math.min(dt * 12.0, 1.0)
    self.BlendSpeed = self.BlendSpeed + (self.Speed - self.BlendSpeed) * alpha
    Anim.blend_space_1d_set_input(self.LocoBlendSpace, self.BlendSpeed)

    -- ── AI(BossAttacks) → 애니메이션 신호 처리 ─────────────────
    self.BossContext = CombatContext.GetBossContext()
    local bossContext = self.BossContext
    if bossContext == nil then return end
    BossContext.Assert(bossContext, "BossAnimation.update")
    ConsumeAnimSignal(self, bossContext)

    -- ── 피격 방향 신호 소비 (CombatContext.ApplyHitToBoss 가 써넣음) ──
    local hitSignal = bossContext.Brain.HitReactSignal
    if hitSignal ~= nil then
        bossContext.Brain.HitReactSignal = nil
        self.HitReactPending   = true
        self.HitReactDirection = hitSignal
        self.HitReactEnd       = false
        self.HitReactElapsed   = 0.0
    end

    -- ── 사망 방향 신호 소비 (CombatContext.HandleBossDeath 가 써넣음) ──
    local deathSignal = bossContext.Brain.DeathSignal
    if deathSignal ~= nil then
        bossContext.Brain.DeathSignal = nil
        self.DeathPending   = true
        self.DeathDirection = deathSignal
    end

    -- 피격 모션 재생 중이면 fallback 복귀용 경과 시간 누적
    if self.HitReactActive then
        self.HitReactElapsed = (self.HitReactElapsed or 0.0) + dt
    end

    -- AttackPrep fallback: AttackEnd notify 누락 시 ATTACK_PREP_DURATION 후 강제 전환
    if self.AttackPrepActive then
        self.AttackPrepTimer = (self.AttackPrepTimer or 0.0) + dt
        if not self.AttackEnd then
            if self.AttackPrepTimer >= ATTACK_PREP_DURATION then
                self.AttackEnd = true
            elseif not bossContext.Brain.ActionLock then
                self.AttackEnd = true
            end
        end
    end

    -- 콤보 진행 중이면 fallback 으로 단 종료/복귀를 보장한다.
    -- (애니 에셋에 "AttackEnd" notify 가 심어져 있으면 notify 가 먼저 와서 우선)
    local comboActive = self.LightComboIndex > 0 or self.HeavyComboIndex > 0
    if comboActive then
        -- ① notify 미수신 시, 현재 단의 애니 길이만큼 재생 후 다음 단/복귀
        self.AttackTimer = (self.AttackTimer or 0.0) + dt

        local stageDur = nil
        local stagePlayRate = self.DefaultPlayRate or PLAY_RATE
        if self.LightComboIndex > 0 then
            stageDur = LIGHT_STAGE_DURATIONS[self.LightComboIndex]
            stagePlayRate = GetComboPlayRate(self.LightPlayRates, self.LightComboIndex, stagePlayRate)
        elseif self.HeavyComboIndex > 0 then
            stageDur = HEAVY_STAGE_DURATIONS[self.HeavyComboIndex]
            stagePlayRate = GetComboPlayRate(self.HeavyPlayRates, self.HeavyComboIndex, stagePlayRate)
        end

        if stageDur ~= nil
            and not self.AttackEnd
            and self.AttackTimer >= stageDur / stagePlayRate then
            self.AttackEnd = true
        end

        -- ② AI 패턴이 이미 끝났는데(ActionLock 해제) 애니가 아직 공격 상태면
        --    강제 종료 → Locomotion 안전 복귀 (영구 락 방지)
        -- 단, 현재 단의 최소 재생 시간(stageDur * 0.5)을 채운 이후에만 발동
        -- → ActionLock이 콤보 전환 직후 잠깐 false인 타이밍에 2타가 즉사하는 것을 방지
        local minPlayed = (stageDur ~= nil) and (self.AttackTimer >= stageDur * 0.5) or true
        if not bossContext.Brain.ActionLock and minPlayed then
            self.AttackEnd = true
        end

        -- 단이 끝난 뒤(AttackEnd) 다음 단 전환까지 실제로 멈춰있는 시간을 누적한다.
        -- (콤보 체인 transition 의 GetComboGap(...) 게이트가 이 값을 본다)
        if self.AttackEnd then
            self.ComboGapElapsed = (self.ComboGapElapsed or 0.0) + dt
        end
    end
end

-- ──────────────────────────────────────────────────────────────────
-- Notify 핸들러
-- 애니메이션 에셋에 심어둔 Notify 이름이 여기로 들어온다.
-- ──────────────────────────────────────────────────────────────────
function on_notify(self, name)
    self.BossContext = CombatContext.GetBossContext()
    local bossContext = self.BossContext
    if bossContext == nil then return end
    BossContext.Assert(bossContext, "BossAnimation.on_notify")

    if name == "AttackEnd" then
        self.AttackEnd = true

    elseif name == "HitReactEnd" or name == "HitEnd" then
        self.HitReactEnd = true

    elseif name == "DashEnd" then
        self.DashEnd = true

    elseif name == "HitboxOpen" then
        bossContext.Attack.HitboxOpen = true

    elseif name == "HitboxClose" then
        bossContext.Attack.HitboxClose = true

    elseif name == "ZoneShow" then
        bossContext.Attack.ZoneShow = true

    elseif name == "ZoneFlash" then
        bossContext.Attack.ZoneFlash = true

    elseif name == "ZoneHide" then
        bossContext.Attack.ZoneHide = true

    elseif name == "TrackEnd" then
        bossContext.Attack.TrackEnd = true

    elseif name == "TrailActivate" or name == "TrailOn" then
        -- TODO: BossFeedback 연동

    elseif name == "TrailDeactivate" or name == "TrailOff" then
        -- TODO: BossFeedback 연동
    end
end
