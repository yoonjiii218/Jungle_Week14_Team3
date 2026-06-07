-- Anim/MobAnimation.lua
-- 잡몹(Rusher) 애니메이션 상태 머신. (BossAnimation 의 경량 버전)
--
-- 상태 흐름:
--   Locomotion → AttackPrep(준비동작/Idle1) → Attack(공격/보스 P1) → Locomotion
--
-- 코루틴(MobAttacks)과의 동기화:
--   1) StartAttack → Combat.ActionLock=true, Brain.IsTracking=true
--      → update 가 ActionLock 상승 엣지를 감지해 AttackPrep 진입
--   2) prep 애니(Idle1)의 ZoneShow notify → 장판 예고
--   3) prep 애니의 TrackEnd notify → 코루틴이 Brain.IsTracking=false (조준 고정)
--      → update 가 이를 보고 AttackPrep → Attack 전환
--   4) 공격 애니의 ZoneFlash/ZoneHide/HitboxOpen/HitboxClose notify → 코루틴 판정
--   5) 코루틴 종료 시 Combat.ActionLock=false → Attack → Locomotion 복귀
--
-- self 가 아니라 obj(액터)로 컨텍스트를 조회하므로 잡몹이 여러 마리여도 안전.

local MobContext = require("Mob/MobContext")
local MobAction = require("Mob/MobAction")

local ANIM_BASE = "Content/Animation/Samurai_Mob/"

local IDLE_PATH   = ANIM_BASE .. "SamuraiIdle2.uasset"
local WALK_PATH   = ANIM_BASE .. "SamuraiWalk.uasset"
local SPRINT_PATH = ANIM_BASE .. "SamurSprint.uasset"

local ATTACK_PREP_PATH = ANIM_BASE .. "SamuraiIdle1.uasset"

local ATTACK_PATH = ANIM_BASE .. "SamuraiAttack_Combo1.uasset"

local WALK_SPEED   = 8.0
local SPRINT_SPEED = 10.0

local ATTACK_BLEND_IN  = 0.12
local ATTACK_BLEND_OUT = 0.25
local PLAY_RATE = 1.0

-- ──────────────────────────────────────────────────────────────────
function init(self)
    -- 공격 애니의 루트모션을 끄고 이동/회전은 MobAction 이 코드로 제어 (보스와 동일 철학)
    Anim.set_root_motion_mode("IgnoreRootMotion")

    self.Speed = 0.0
    self.BlendSpeed = 0.0
    self.WasLocked = false
    self.AttackTrigger = false

    -- 코루틴 상태 캐시 (transition 클로저가 읽는다)
    self._mobLocked = false
    self._mobTracking = true

    -- 이동 블렌드스페이스 (Idle → Walk → Sprint)
    local loco = Anim.create_blend_space_1d(0.0)
    Anim.blend_space_1d_add_sample(loco, IDLE_PATH,   0.0,          1.0, true)
    Anim.blend_space_1d_add_sample(loco, WALK_PATH,   WALK_SPEED,   1.0, true)
    Anim.blend_space_1d_add_sample(loco, SPRINT_PATH, SPRINT_SPEED, 1.0, true)
    self.LocoBlendSpace = loco

    local top = Anim.create_state_machine("MobTop")
    Anim.sm_add_state(top, "Locomotion", loco)
    Anim.sm_add_state(top, "AttackPrep",
        Anim.create_sequence_player(ATTACK_PREP_PATH, PLAY_RATE, false))
    Anim.sm_add_state(top, "Attack",
        Anim.create_sequence_player(ATTACK_PATH, PLAY_RATE, false))

    -- Locomotion → AttackPrep: 공격 시작(ActionLock 상승 엣지)
    Anim.sm_add_transition(top, "Locomotion", "AttackPrep",
        function()
            if self.AttackTrigger then
                self.AttackTrigger = false
                return true
            end
            return false
        end, ATTACK_BLEND_IN)

    -- AttackPrep → Attack: 코루틴이 TrackEnd 를 받아 IsTracking=false (조준 고정 = 본 공격 시작)
    Anim.sm_add_transition(top, "AttackPrep", "Attack",
        function()
            return self._mobTracking == false
        end, ATTACK_BLEND_IN)

    -- Attack → Locomotion: 코루틴 종료(ActionLock 해제)
    Anim.sm_add_transition(top, "Attack", "Locomotion",
        function()
            return self._mobLocked == false
        end, ATTACK_BLEND_OUT)

    -- 안전 복귀: prep 도중 코루틴이 끝나버린 비정상 상황 (영구 락 방지)
    Anim.sm_add_transition(top, "AttackPrep", "Locomotion",
        function()
            return self._mobLocked == false
        end, ATTACK_BLEND_OUT)

    Anim.sm_set_initial_state(top, "Locomotion")

    local root = Anim.create_slot("DefaultSlot", top)
    Anim.set_root_node(root)
end

-- ──────────────────────────────────────────────────────────────────
function update(self, dt)
    if self.BlendSpeed == nil then self.BlendSpeed = 0.0 end

    self.Speed = Anim.get_owner_speed()
    local alpha = math.min(dt * 12.0, 1.0)
    self.BlendSpeed = self.BlendSpeed + (self.Speed - self.BlendSpeed) * alpha
    Anim.blend_space_1d_set_input(self.LocoBlendSpace, self.BlendSpeed)

    local mobContext = MobContext.GetByOwner(obj)
    if mobContext == nil then return end

    -- ActionLock 상승 엣지 = 새 공격 시작 → AttackPrep 진입 트리거.
    local locked = mobContext.Combat.ActionLock
    if locked and not self.WasLocked then
        self.AttackTrigger = true
    end
    self.WasLocked = locked

    -- transition 클로저가 참조할 코루틴 상태 캐싱
    self._mobLocked = locked
    self._mobTracking = mobContext.Brain.IsTracking
end

-- ──────────────────────────────────────────────────────────────────
-- Notify 핸들러: prep(Idle1) / 공격 애니에 심어둔 Notify 가 여기로 들어온다.
-- ZoneShow/ZoneFlash/ZoneHide/HitboxOpen/HitboxClose/TrackEnd → mobContext.Attack 플래그
-- ──────────────────────────────────────────────────────────────────
function on_notify(self, name)
    local mobContext = MobContext.GetByOwner(obj)
    if mobContext == nil then return end

    MobAction.OnAnimNotify(mobContext, name)
end
