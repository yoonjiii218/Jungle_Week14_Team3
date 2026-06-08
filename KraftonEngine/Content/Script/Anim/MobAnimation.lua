-- Anim/MobAnimation.lua
-- 잡몹(Rusher) 애니메이션 상태 머신. (BossAnimation 의 경량 버전)
--
-- 상태 흐름 (준비동작 없이 바로 공격 — 보스와 동일):
--   Locomotion → Attack(공격) → Locomotion
--
-- 코루틴(MobAttacks)과의 동기화:
--   1) StartAttack → Combat.ActionLock=true, Brain.IsTracking=true
--      → 코드가 장판을 띄우고 리드 타임(ZONE_LEAD)동안 차오르게 함 (이 동안 mob 은 Locomotion 유지)
--   2) 리드 타임 종료 → 코루틴이 Brain.IsTracking=false (조준 고정)
--      → update 가 이를 보고 Locomotion → Attack 전환 (준비동작 없이 즉시 공격 시작)
--   3) 공격 애니의 ZoneFlash/ZoneHide/HitboxOpen/HitboxClose notify → 코루틴 판정
--   4) 코루틴 종료 시 Combat.ActionLock=false → Attack → Locomotion 복귀
--
-- self 가 아니라 obj(액터)로 컨텍스트를 조회하므로 잡몹이 여러 마리여도 안전.

local MobContext = require("Mob/MobContext")
local MobAction = require("Mob/MobAction")
local MobConfig = require("Mob/MobBlackboard")

local ANIM_BASE = "Content/Animation/Samurai_Mob/"

local IDLE_PATH   = ANIM_BASE .. "SamuraiIdle2.uasset"
local WALK_PATH   = ANIM_BASE .. "SamuraiWalk.uasset"
local SPRINT_PATH = ANIM_BASE .. "SamurSprint.uasset"

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

    -- 코루틴 상태 캐시 (transition 클로저가 읽는다)
    self._mobLocked = false
    self._mobTracking = true

    -- 방향별 피격 리액션 상태 플래그 (BossAnimation 과 동일 패턴)
    self.HitReactPending   = false
    self.HitReactActive    = false
    self.HitReactDirection = nil
    self.HitReactElapsed   = 0.0
    self.HitReactEnd       = false

    -- 사망 모션 상태 플래그 (BossAnimation 과 동일 패턴)
    self.DeathPending   = false
    self.DeathDirection = nil

    -- 이동 블렌드스페이스 (Idle → Walk → Sprint)
    local loco = Anim.create_blend_space_1d(0.0)
    Anim.blend_space_1d_add_sample(loco, IDLE_PATH,   0.0,          1.0, true)
    Anim.blend_space_1d_add_sample(loco, WALK_PATH,   WALK_SPEED,   1.0, true)
    Anim.blend_space_1d_add_sample(loco, SPRINT_PATH, SPRINT_SPEED, 1.0, true)
    self.LocoBlendSpace = loco

    local top = Anim.create_state_machine("MobTop")
    Anim.sm_add_state(top, "Locomotion", loco)
    Anim.sm_add_state(top, "Attack",
        Anim.create_sequence_player(ATTACK_PATH, PLAY_RATE, false))

    -- Locomotion → Attack: 준비동작 없이 바로 공격 (보스와 동일).
    -- MobAttacks 코루틴이 장판 리드 타임(ZONE_LEAD)을 기다린 뒤 IsTracking=false 로 조준을 고정하면
    -- 그 신호로 곧장 공격 애니가 시작된다. 리드 타임 동안 mob 은 Locomotion(서있기)으로 장판만 띄운다.
    Anim.sm_add_transition(top, "Locomotion", "Attack",
        function()
            return self._mobTracking == false
        end, ATTACK_BLEND_IN)

    -- Attack → Locomotion: 코루틴 종료(ActionLock 해제)
    Anim.sm_add_transition(top, "Attack", "Locomotion",
        function()
            return self._mobLocked == false
        end, ATTACK_BLEND_OUT)

    -- ── 방향별 피격 리액션 ─────────────────────────────────────────
    -- CombatContext.ApplyHitToMob 가 mobContext.Combat.HitReactSignal 에 방향을 써넣고,
    -- update() 가 그걸 소비해 self.HitReactPending/Direction 으로 변환하면 아래 전이가 발동한다.
    local hitReact        = MobConfig.HIT_REACT or {}
    local hitPaths        = hitReact.PATHS or {}
    local hitPlayRate     = hitReact.PLAY_RATE or 1.0
    local hitBlendIn      = hitReact.BLEND_IN or 0.05
    local hitBlendOut     = hitReact.BLEND_OUT or 0.12
    local hitFallbackDur  = hitReact.FALLBACK_DURATION or 0.45
    local hitFallbackPath = ATTACK_PATH   -- 경로 누락 시 안전 폴백

    Anim.sm_add_state(top, "HitFront", Anim.create_sequence_player(hitPaths.Front or hitFallbackPath, hitPlayRate, false))
    Anim.sm_add_state(top, "HitLeft",  Anim.create_sequence_player(hitPaths.Left  or hitFallbackPath, hitPlayRate, false))
    Anim.sm_add_state(top, "HitRight", Anim.create_sequence_player(hitPaths.Right or hitFallbackPath, hitPlayRate, false))
    Anim.sm_add_state(top, "HitBack",  Anim.create_sequence_player(hitPaths.Back  or hitFallbackPath, hitPlayRate, false))

    local function AddHitReactionTransitions(direction, stateName)
        -- AnyState → Hit_*: 신호가 들어오고 방향이 일치하면 진입 (공격 중이어도 끊고 진입 = 공격 캔슬)
        Anim.sm_add_transition(top, "AnyState", stateName,
            function()
                if not self.HitReactPending or self.HitReactDirection ~= direction then
                    return false
                end
                self.HitReactPending = false
                self.HitReactActive  = true
                self.HitReactElapsed = 0.0
                self.HitReactEnd     = false
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
    -- CombatContext.HandleMobDeath 가 mobContext.Combat.DeathSignal 에 "Front"/"Back" 을 써넣고,
    -- update() 가 그걸 소비해 self.DeathPending/Direction 으로 변환하면 아래 전이가 발동한다.
    -- 좌/우 구분 없이 치명타가 앞에서 들어왔으면 Front(Forward), 뒤에서 들어왔으면 Back(Backward) 모션으로 죽는다.
    -- 사망 후에는 다른 상태로 돌아가지 않는 종료 상태다. (BossAnimation 과 동일 패턴)
    local death          = MobConfig.DEATH or {}
    local deathPaths     = death.PATHS or {}
    local deathPlayRate  = death.PLAY_RATE or 1.0
    local deathBlendIn   = death.BLEND_IN or 0.15
    local deathFallback  = ATTACK_PATH   -- 경로 누락 시 안전 폴백

    Anim.sm_add_state(top, "DeathFront", Anim.create_sequence_player(deathPaths.Front or deathFallback, deathPlayRate, false))
    Anim.sm_add_state(top, "DeathBack",  Anim.create_sequence_player(deathPaths.Back  or deathFallback, deathPlayRate, false))

    local function AddDeathTransition(direction, stateName)
        Anim.sm_add_transition(top, "AnyState", stateName,
            function()
                if not self.DeathPending or self.DeathDirection ~= direction then
                    return false
                end
                self.DeathPending = false
                return true
            end, deathBlendIn)
    end

    AddDeathTransition("Front", "DeathFront")
    AddDeathTransition("Back",  "DeathBack")

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

    -- transition 클로저가 참조할 코루틴 상태 캐싱.
    -- (준비동작 제거 후: Locomotion→Attack 은 IsTracking=false(조준 고정) 신호로만 발동한다)
    self._mobLocked = mobContext.Combat.ActionLock
    self._mobTracking = mobContext.Brain.IsTracking

    -- ── 피격 방향 신호 소비 (CombatContext.ApplyHitToMob 가 써넣음) ──
    local hitSignal = mobContext.Combat.HitReactSignal
    if hitSignal ~= nil then
        mobContext.Combat.HitReactSignal = nil
        self.HitReactPending   = true
        self.HitReactDirection = hitSignal
        self.HitReactEnd       = false
        self.HitReactElapsed   = 0.0
    end

    -- ── 사망 방향 신호 소비 (CombatContext.HandleMobDeath 가 써넣음) ──
    local deathSignal = mobContext.Combat.DeathSignal
    if deathSignal ~= nil then
        mobContext.Combat.DeathSignal = nil
        self.DeathPending   = true
        self.DeathDirection = deathSignal
    end

    -- 피격 모션 재생 중이면 fallback 복귀용 경과 시간 누적
    if self.HitReactActive then
        self.HitReactElapsed = (self.HitReactElapsed or 0.0) + dt
    end

    -- MobAction 이 "피격 중 행동 억제" 를 읽도록 컨텍스트에 미러링
    mobContext.Combat.HitReactActive = self.HitReactActive
end

-- ──────────────────────────────────────────────────────────────────
-- Notify 핸들러: prep(Idle1) / 공격 애니에 심어둔 Notify 가 여기로 들어온다.
-- ZoneShow/ZoneFlash/ZoneHide/HitboxOpen/HitboxClose/TrackEnd → mobContext.Attack 플래그
-- ──────────────────────────────────────────────────────────────────
function on_notify(self, name)
    local mobContext = MobContext.GetByOwner(obj)
    if mobContext == nil then return end

    if name == "HitReactEnd" or name == "HitEnd" then
        self.HitReactEnd = true
        return
    end

    MobAction.OnAnimNotify(mobContext, name)
end
