-- Mob/MobCharacter.lua
-- ULuaScriptComponent entry point for the rusher mob actor.
-- Owns MobContext and wires explicit mob module calls (mirrors Boss/BossCharacter).

local MobConfig  = require("Mob/MobBlackboard")
local MobContext = require("Mob/MobContext")
local MobAction  = require("Mob/MobAction")
local MobAttacks = require("Mob/MobAttacks")
local CombatContext = require("Combat/CombatContext")

local mobContext = nil

-- 보스(BossFeedback.AttachKatanaToBoss)와 동일한 칼 장착. 같은 Samurai 스켈레톤이라 소켓 이름도 동일.
local KATANA_MESH_PATH = "Content/Data/scifi-katana_extracted/source/KatanaSwordSketch_StaticMesh.uasset"
local KATANA_SOCKET_NAME = "pinky_01_r_socket"

local function AttachKatanaToMob(mobContext)
    local ownerActor = mobContext.Owner
    if ownerActor == nil then return end

    if mobContext.Runtime.KatanaComponent ~= nil
        and mobContext.Runtime.KatanaComponent:IsValid() then
        return
    end

    local meshComp = mobContext.Runtime.SkeletalMeshComp
    if meshComp == nil then
        print("[MobCharacter] SkeletalMeshComponent not found for katana")
        return
    end

    local katana = ownerActor:AddStaticMeshComponent()
    if katana == nil then
        print("[MobCharacter] Failed to create katana component")
        return
    end

    katana:SetMeshPath(KATANA_MESH_PATH)
    katana:AttachToComponentWithSocket(meshComp, KATANA_SOCKET_NAME)
    katana.RelativeLocation = Vector(0.0, 0.0, 0.0)
    katana:SetRotation(Vector(0.0, 0.0, 0.0))
    katana:SetRelativeScale(Vector(1.0, 1.0, 1.0))

    mobContext.Runtime.KatanaComponent = katana
end

function BeginPlay()
    mobContext = MobContext.Create(obj, this, MobConfig)

    if not obj:HasTag("Mob") then
        obj:AddTag("Mob")
    end

    -- 플레이어 공격/타게팅이 인식하는 "피격 가능 대상" 표식 (보스 BossCharacter 와 동일 규약).
    -- PlayerConfig.Targeting.TargetTags = { "HitTarget", "Enemy", "Boss" } 가 이 태그로 스캔한다.
    if not obj:HasTag("HitTarget") then
        obj:AddTag("HitTarget")
    end

    mobContext.Brain.TargetActor = World.FindFirstActorByTag("Player")

    mobContext.Runtime.MovementComp = obj.GetCharacterMovement and obj:GetCharacterMovement() or nil
    mobContext.Runtime.SkeletalMeshComp = obj.GetSkeletalMeshComponent and obj:GetSkeletalMeshComponent() or nil

    if mobContext.Runtime.MovementComp then
        Reflection.Call(mobContext.Runtime.MovementComp, "SetMovementInputEnabled", true)
    end

    local katanaOk, katanaErr = pcall(function()
        AttachKatanaToMob(mobContext)
    end)
    if not katanaOk then
        print("[MobCharacter] AttachKatanaToMob failed: " .. tostring(katanaErr))
    end

    if MobConfig.DEBUG then
        local found = mobContext.Brain.TargetActor ~= nil and mobContext.Brain.TargetActor:IsValid()
        print("[MobCharacter] BeginPlay - playerRef found: " .. tostring(found)
            .. " / movComp: " .. tostring(mobContext.Runtime.MovementComp ~= nil))
    end

    MobAction.Init(mobContext)
    MobAttacks.Init(mobContext)
    MobContext.Register(mobContext)   -- MobAnimation 이 obj 로 컨텍스트를 찾도록 등록
    CombatContext.RegisterMob(mobContext)   -- 피격/데미지 해결 대상으로 등록 (ApplyHitToMob)
end

function Tick(dt)
    if mobContext == nil then
        return
    end

    local brain = mobContext.Brain
    local scaledDt = dt * brain.TimeScale
    brain.PatternCooldown = math.max(0.0, brain.PatternCooldown - scaledDt)

    local targetActor = brain.TargetActor
    if targetActor and targetActor:IsValid() then
        local d = obj.Location - targetActor.Location
        d.Z = 0.0
        brain.Distance = d:Length()
    end

    UpdateCoroutines(scaledDt)
    MobAction.Update(mobContext, dt)
    MobAttacks.Update(mobContext, scaledDt)
end

function EndPlay()
    if mobContext ~= nil then
        MobContext.Unregister(mobContext)
        CombatContext.UnregisterMob(mobContext)
    end
    mobContext = nil
    if MobConfig.DEBUG then
        print("[MobCharacter] EndPlay")
    end
end
