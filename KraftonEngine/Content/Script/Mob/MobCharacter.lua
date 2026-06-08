-- Mob/MobCharacter.lua
-- ULuaScriptComponent entry point for the rusher mob actor.
-- Owns MobContext and wires explicit mob module calls (mirrors Boss/BossCharacter).

local CoroutineManager = require("CoroutineManager")
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

    -- 몹 체력바 위젯 생성
    local widget = nil
    if UI ~= nil and (UI.CreateWidgetForPlayer or UI.CreateWidget) then
        local widgetFactory = UI.CreateWidgetForPlayer or UI.CreateWidget
        widget = widgetFactory("Content/UI/GameFlow/MobHPBar.uasset")
        if widget ~= nil then
            widget:SetWantsMouse(false)
            widget:AddToViewportZ(100)
            mobContext.Runtime.HPBarWidget = widget
        end
    end
end

function Tick(dt)
    if mobContext == nil then
        return
    end

    if mobContext.Combat.IsDead then
        if mobContext.Runtime.HPBarWidget ~= nil then
            mobContext.Runtime.HPBarWidget:RemoveFromParent()
            mobContext.Runtime.HPBarWidget = nil
        end
        return
    end

    -- Own coroutine pool: this mob's coroutines must only ever advance by
    -- this mob's scaledDt, never another actor's (see CoroutineManager.lua).
    CoroutineManager.Begin(obj.UUID)

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

    CoroutineManager.End()

    -- 체력바 화면 투영 업데이트
    local widget = mobContext.Runtime.HPBarWidget
    if widget ~= nil then
        local targetActor = mobContext.Brain.TargetActor
        local camera = nil
        if targetActor and targetActor:IsValid() and targetActor.GetCamera then
            camera = targetActor:GetCamera()
        end
        
        if camera == nil then
            local playerRef = World.FindFirstActorByTag("Player")
            if playerRef and playerRef:IsValid() and playerRef.GetCamera then
                camera = playerRef:GetCamera()
            end
        end

        if camera ~= nil then
            local width, height = 1280.0, 720.0
            if Engine ~= nil and Engine.GetViewportSize ~= nil then
                local size = Engine.GetViewportSize()
                if size ~= nil then
                    width = tonumber(size.Width or size["Width"] or width) or width
                    height = tonumber(size.Height or size["Height"] or height) or height
                end
            end

            local screenPos = Vector(0.0, 0.0, 0.0)
            local headWorldPos = obj.Location + Vector(0.0, 0.0, 1.85)
            local isProjected = camera:ProjectWorldToScreen(headWorldPos, screenPos, width, height)

            if isProjected then
                widget:SetProperty("hp-bar", "display", "block")
                widget:SetProperty("hp-bar", "left", string.format("%.0fpx", screenPos.X - 32.0))
                widget:SetProperty("hp-bar", "top", string.format("%.0fpx", screenPos.Y))
                
                local combat = mobContext.Combat
                local hpRatio = 0.0
                if combat.MaxHP > 0 then
                    hpRatio = combat.HP / combat.MaxHP
                end
                widget:SetProperty("hp-fill", "width", string.format("%.1f%%", hpRatio * 100.0))
            else
                widget:SetProperty("hp-bar", "display", "none")
            end
        else
            widget:SetProperty("hp-bar", "display", "none")
        end
    end
end

function EndPlay()
    CoroutineManager.Destroy(obj.UUID)
    if mobContext ~= nil then
        if mobContext.Runtime.HPBarWidget ~= nil then
            mobContext.Runtime.HPBarWidget:RemoveFromParent()
            mobContext.Runtime.HPBarWidget = nil
        end
        MobContext.Unregister(mobContext)
        CombatContext.UnregisterMob(mobContext)
    end
    mobContext = nil
    if MobConfig.DEBUG then
        print("[MobCharacter] EndPlay")
    end
end
