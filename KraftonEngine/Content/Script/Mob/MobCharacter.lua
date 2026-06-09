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
        -- 죽은 잡몹은 아래의 일반 Tick 경로를 더 이상 돌지 않는다.
        -- 따라서 공격 코루틴이 HideZone 까지 자연스럽게 진행되기를 기다리면
        -- NO_FADE_DELAY 로 만든 장판 Decal 이 맵에 계속 남는다.
        -- 사망 진입 첫 프레임에 공격 VFX/코루틴을 명시적으로 정리한다.
        if mobContext.Runtime.DeathAttackCleanupDone ~= true then
            MobAttacks.CleanupActiveAttack(mobContext)
            CoroutineManager.Destroy(obj.UUID)
            mobContext.Runtime.DeathAttackCleanupDone = true
        end

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
    mobContext.Runtime.ElapsedTime = (mobContext.Runtime.ElapsedTime or 0.0) + scaledDt
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
            -- 몹의 실제 캡슐 높이(CAPSULE_HALF_HEIGHT)와 액터 스케일을 고려하여 정확한 발바닥 지면 높이를 계산한 뒤 0.15m 위에 띄움.
            local halfHeight = mobContext.Config.CAPSULE_HALF_HEIGHT or 5.0
            local feetWorldPos = obj.Location + Vector(0.0, 0.0, -halfHeight * obj.Scale.Z + 0.15)
            local isProjected = camera:ProjectWorldToScreen(feetWorldPos, screenPos, width, height)

            if isProjected then
                widget:SetProperty("hp-container", "display", "block")
                widget:SetProperty("hp-container", "left", string.format("%.0fpx", screenPos.X - 40.0))
                widget:SetProperty("hp-container", "top", string.format("%.0fpx", screenPos.Y))
                
                local combat = mobContext.Combat
                local hpRatio = 0.0
                if combat.MaxHP > 0 then
                    hpRatio = combat.HP / combat.MaxHP
                end
                local fillWidth = math.max(0.0, hpRatio * 76.0)
                widget:SetProperty("hp-fill", "width", string.format("%.0fpx", fillWidth))

                -- 주목표(TargetActor) 식별 및 강렬한 시각적 점멸 강조 연출 (글자 없이 강조 효과만)
                local targetActor = mobContext.Brain.TargetActor
                local isTargetingPlayer = false
                if targetActor and targetActor:IsValid() then
                    local actorName = targetActor.Name or "UNKNOWN"
                    if string.find(string.lower(actorName), "player") then
                        isTargetingPlayer = true
                    end
                end

                if isTargetingPlayer then
                    -- 몹이 플레이어(나)를 노릴 때, 빠른 사인파 점멸로 테두리(2px)/바/느낌표 마크를 매우 티나게 경고 점멸시킴
                    local pulseSpeed = 16.0
                    local pulse = math.abs(math.sin((mobContext.Runtime.ElapsedTime or 0.0) * pulseSpeed))
                    local alpha = 0.10 + 0.90 * pulse
                    local glowColor = string.format("rgba(255, 0, 85, %.2f)", alpha)
                    
                    widget:SetProperty("hp-bg", "border-color", glowColor)
                    widget:SetProperty("hp-bg", "border-width", "2px")
                    widget:SetProperty("hp-fill", "background-color", glowColor)
                    widget:SetProperty("warning-marker", "display", "block")
                    widget:SetProperty("warning-marker", "opacity", string.format("%.2f", alpha))
                else
                    -- 평상시에는 기본 차분한 시안 컬러 테마
                    widget:SetProperty("hp-bg", "border-color", "#00eaff44")
                    widget:SetProperty("hp-bg", "border-width", "1px")
                    widget:SetProperty("hp-fill", "background-color", "#00eaff")
                    widget:SetProperty("warning-marker", "display", "none")
                    widget:SetProperty("warning-marker", "opacity", "1.0")
                end

                -- 내가(플레이어가) 이 몹을 타겟팅하고 있는지 체크 및 락온 마커 업데이트
                local isTargetedByPlayer = false
                local playerActor = World.FindFirstActorByTag("Player")
                if playerActor and playerActor:IsValid() then
                    local playerContext = CombatContext.GetPlayerByOwner(playerActor)
                    if playerContext ~= nil and playerContext.Runtime ~= nil then
                        if playerContext.Runtime.TargetAssistTarget == obj or playerContext.Runtime.CurrentTarget == obj then
                            isTargetedByPlayer = true
                        end
                    end
                end

                if isTargetedByPlayer then
                    widget:SetProperty("player-lock-marker", "display", "block")
                    local time = mobContext.Runtime.ElapsedTime or 0.0
                    local hover = math.sin(time * 12.0) * 2.0
                    widget:SetProperty("player-lock-marker", "top", string.format("%.0fpx", -6.0 + hover))
                    
                    -- 조준 마커에 은은한 알파 점멸 펄스를 넣어 타게팅 효과 극대화
                    local pulse = 0.70 + 0.30 * math.abs(math.sin(time * 16.0))
                    widget:SetProperty("player-lock-marker", "opacity", string.format("%.2f", pulse))
                else
                    widget:SetProperty("player-lock-marker", "display", "none")
                    widget:SetProperty("player-lock-marker", "opacity", "1.0")
                end
            else
                widget:SetProperty("hp-container", "display", "none")
            end
        else
            widget:SetProperty("hp-container", "display", "none")
        end
    end
end

function EndPlay()
    if mobContext ~= nil then
        MobAttacks.CleanupActiveAttack(mobContext)
    end
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
