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

local CombatContext = require("CombatContext")

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

-- 속도 임계값.
-- get_owner_speed() 는 cm/s 가 아니라 ~10 스케일의 작은 값을 반환한다.
-- (PlayerConfig: RunThreshold=8.0, RunSampleSpeed=10.0 와 동일 스케일)
local WALK_SPEED   = 8.0
local SPRINT_SPEED = 10.0

-- 블렌드 시간 (초)
local ATTACK_BLEND_IN  = 0.12   -- 공격 진입 / 콤보 단 사이 전환
local ATTACK_BLEND_OUT = 0.25   -- 공격 → idle 복귀 (어색하면 0.2~0.35 사이 조정)
local DASH_BLEND_IN    = 0.08

-- 기본 재생 속도
local PLAY_RATE = 1.0

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
    self.LightComboIndex = index
    self.AttackEnd       = false
    self.AttackTimer     = 0.0   -- fallback 타이머 리셋
end

local function BeginHeavyCombo(self, index)
    self.HeavyComboIndex = index
    self.AttackEnd       = false
    self.AttackTimer     = 0.0   -- fallback 타이머 리셋
end

-- 보스 Blackboard 를 lazy 하게 가져온다.
-- (BossCharacter.BeginPlay 가 AnimInstance init 보다 늦게 돌 수 있어 update 에서 조회)
local function GetBB(self)
    if self.BB == nil then
        self.BB = CombatContext.GetBossBlackboard()
    end
    return self.BB
end

-- bb 에 쌓인 공격 신호를 소비해 상태머신 트리거 플래그로 변환
local function ConsumeAnimSignal(self, bb)
    if bb == nil or bb.AnimAttack == nil then return end

    local kind = bb.AnimAttack
    local start = bb.AnimAttackStart or 1
    local hits  = bb.AnimAttackHits  or 1

    bb.AnimAttack      = nil
    bb.AnimAttackStart = nil
    bb.AnimAttackHits  = nil

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

    -- 외부 트리거 플래그
    self.LightAttackPressed = false
    self.HeavyAttackPressed = false
    self.DashSlashPressed   = false
    self.MaxLightComboHits  = 1   -- BossAttacks.lua 에서 패턴별로 덮어씀
    self.MaxHeavyComboHits  = 3   -- P3 기본값: HeavyCombo 1→2→3

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

    -- ── 콤보 상태 생성 (이게 있어야 아래 진입/체인 transition 이 참조할 상태가 존재) ──
    for i = 1, 4 do
        Anim.sm_add_state(top, "LightCombo" .. i,
            Anim.create_sequence_player(LIGHT_COMBO_PATHS[i], PLAY_RATE, false))
    end
    for i = 1, 5 do
        Anim.sm_add_state(top, "HeavyCombo" .. i,
            Anim.create_sequence_player(HEAVY_COMBO_PATHS[i], PLAY_RATE, false))
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
        Anim.sm_add_transition(top, cur, next,
            function()
                if self.AttackEnd and self.LightComboIndex < self.MaxLightComboHits then
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
        Anim.sm_add_transition(top, cur, next,
            function()
                if self.AttackEnd and self.HeavyComboIndex < self.MaxHeavyComboHits then
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

    Anim.sm_set_initial_state(top, "Locomotion")

    local root = Anim.create_slot("DefaultSlot", top)
    Anim.set_root_node(root)
end

-- ──────────────────────────────────────────────────────────────────
function update(self, dt)
    self.Speed = Anim.get_owner_speed()

    -- 속도를 부드럽게 보간해서 블렌드스페이스 입력으로 전달
    -- (PlayerConfig.LocomotionSpeedResponse = 12.0 과 동일)
    local alpha = math.min(dt * 12.0, 1.0)
    self.BlendSpeed = self.BlendSpeed + (self.Speed - self.BlendSpeed) * alpha
    Anim.blend_space_1d_set_input(self.LocoBlendSpace, self.BlendSpeed)

    -- ── AI(BossAttacks) → 애니메이션 신호 처리 ─────────────────
    local bb = GetBB(self)
    ConsumeAnimSignal(self, bb)

    -- AttackPrep fallback: AttackEnd notify 누락 시 ATTACK_PREP_DURATION 후 강제 전환
    if self.AttackPrepActive then
        self.AttackPrepTimer = (self.AttackPrepTimer or 0.0) + dt
        if not self.AttackEnd then
            if self.AttackPrepTimer >= ATTACK_PREP_DURATION then
                self.AttackEnd = true
            elseif bb ~= nil and not bb.ActionLock then
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
        if self.LightComboIndex > 0 then
            stageDur = LIGHT_STAGE_DURATIONS[self.LightComboIndex]
        elseif self.HeavyComboIndex > 0 then
            stageDur = HEAVY_STAGE_DURATIONS[self.HeavyComboIndex]
        end

        if stageDur ~= nil
            and not self.AttackEnd
            and self.AttackTimer >= stageDur / PLAY_RATE then
            self.AttackEnd = true
        end

        -- ② AI 패턴이 이미 끝났는데(ActionLock 해제) 애니가 아직 공격 상태면
        --    강제 종료 → Locomotion 안전 복귀 (영구 락 방지)
        -- 단, 현재 단의 최소 재생 시간(stageDur * 0.5)을 채운 이후에만 발동
        -- → ActionLock이 콤보 전환 직후 잠깐 false인 타이밍에 2타가 즉사하는 것을 방지
        local minPlayed = (stageDur ~= nil) and (self.AttackTimer >= stageDur * 0.5) or true
        if bb ~= nil and not bb.ActionLock and minPlayed then
            self.AttackEnd = true
        end
    end
end

-- ──────────────────────────────────────────────────────────────────
-- Notify 핸들러
-- 애니메이션 에셋에 심어둔 Notify 이름이 여기로 들어온다.
-- ──────────────────────────────────────────────────────────────────
function on_notify(self, name)
    if name == "AttackEnd" then
        self.AttackEnd = true

    elseif name == "DashEnd" then
        self.DashEnd = true

    elseif name == "HitboxOpen" then
        local bb = GetBB(self)
        if bb then bb.HitboxOpen = true end

    elseif name == "HitboxClose" then
        local bb = GetBB(self)
        if bb then bb.HitboxClose = true end

    elseif name == "ZoneShow" then
        local bb = GetBB(self)
        if bb then bb.ZoneShow = true end

    elseif name == "ZoneFlash" then
        local bb = GetBB(self)
        if bb then bb.ZoneFlash = true end

    elseif name == "ZoneHide" then
        local bb = GetBB(self)
        if bb then bb.ZoneHide = true end

    elseif name == "TrackEnd" then
        local bb = GetBB(self)
        if bb then bb.TrackEnd = true end

    elseif name == "TrailActivate" or name == "TrailOn" then
        -- TODO: BossFeedback 연동

    elseif name == "TrailDeactivate" or name == "TrailOff" then
        -- TODO: BossFeedback 연동
    end
end
