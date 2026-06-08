-- Tutorial/TutorialDirector.lua
-- Event-driven tutorial state machine for TrainingMap.
-- This module intentionally does not poll PlayerContext. Steps subscribe to
-- GameplayEventBus events and advance only when the expected gameplay result
-- is published.

local GameplayEventBus = require("Core/GameplayEventBus")
local PlayerEvents = require("Player/PlayerEvents")
local BossEvents = require("Boss/BossEvents")
local CombatContext = require("Combat/CombatContext")
local TutorialSpawner = require("Tutorial/TutorialSpawner")

local TutorialDirector = {}

local OWNER = { Name = "TutorialDirector" }
local queuedTrainingSceneName = nil
local active = false
local freePlay = false
local activeLabel = "TrainingMap"
local currentStepIndex = 0
local currentStep = nil
local stepCompleted = false
local stepState = {}
local advanceDelay = 0.0
local messageTitle = ""
local messageBody = ""
local messageStatus = ""
local lastHud = nil
local exitConfirmVisible = false

local COMPLETE_ADVANCE_DELAY = 1.20
local AUTO_COMPLETE_DELAY = 0.80
local EXIT_CONFIRM_TITLE = "훈련장을 나가시겠습니까?"
local EXIT_CONFIRM_BODY = "진행 중인 튜토리얼이 중단되고 시작 메뉴로 돌아갑니다."
local EXIT_CONFIRM_PROMPT = "Enter: 나가기 / Esc: 취소"
local INPUT_LABELS = {
    Move = "W/A/S/D",
    Attack = "좌클릭",
    Dash = "Shift",
    Ultimate = "Q",
}

local function SafeText(value)
    if value == nil then
        return ""
    end
    return tostring(value)
end

local function SetHudText(hud, elementId, text)
    if hud ~= nil and hud.SetText ~= nil then
        hud:SetText(elementId, SafeText(text))
    end
end

local function ApplyHudText(hud)
    if hud == nil then
        return
    end

    -- TutorialHUD is intentionally separate from BossHUD. A custom tutorial HUD
    -- only needs to expose these three element ids.
    if exitConfirmVisible == true then
        SetHudText(hud, "tutorial-title", EXIT_CONFIRM_TITLE)
        SetHudText(hud, "tutorial-body", EXIT_CONFIRM_BODY)
        SetHudText(hud, "tutorial-status", EXIT_CONFIRM_PROMPT)
        return
    end

    SetHudText(hud, "tutorial-title", messageTitle)
    SetHudText(hud, "tutorial-body", messageBody)
    SetHudText(hud, "tutorial-status", messageStatus)
end

local function SetMessage(title, body, status)
    messageTitle = SafeText(title)
    messageBody = SafeText(body)
    messageStatus = SafeText(status)
    ApplyHudText(lastHud)
    print("[Tutorial] " .. messageTitle .. " / " .. messageBody .. " / " .. messageStatus)
end

local function ActionLabel(actionName)
    if Input ~= nil and Input.GetActionLabel ~= nil then
        return Input.GetActionLabel(actionName)
    end

    return INPUT_LABELS[actionName] or tostring(actionName or "")
end

local function MoveInputText()
    if ActionLabel("Move") == "왼쪽 스틱" then
        return ActionLabel("Move") .. "으로"
    end

    return ActionLabel("Move") .. "로"
end

local function UseInputText(actionName)
    return ActionLabel(actionName) .. "으로"
end

local function HoldInputText(actionName)
    return ActionLabel(actionName) .. "를"
end

local function PressInputText(actionName)
    if ActionLabel(actionName) == "Y 버튼" then
        return ActionLabel(actionName) .. "을"
    end

    return ActionLabel(actionName) .. "를"
end

local function ClearStepSubscriptions()
    GameplayEventBus.ClearOwner(OWNER)
end

local function CompleteCurrentStep(reason, delay)
    if active ~= true or currentStep == nil or stepCompleted == true then
        return
    end

    stepCompleted = true
    advanceDelay = delay or COMPLETE_ADVANCE_DELAY

    if currentStep.OnComplete ~= nil then
        currentStep.OnComplete({ Reason = reason })
    else
        SetMessage("튜토리얼 완료", "단계를 완료했습니다.", "NEXT")
    end

    print("[Tutorial] step complete id=" .. tostring(currentStep.Id) .. " reason=" .. tostring(reason or "event"))
end

local function CompleteCurrentStepSoon(reason)
    CompleteCurrentStep(reason, AUTO_COMPLETE_DELAY)
end

local function EventTypeName(event, fallback)
    return event ~= nil and event.Type or fallback or "event"
end

local function UpdateProgressStatus(prefix, current, target)
    SetMessage(messageTitle, messageBody, tostring(prefix or "PROGRESS") .. " " .. tostring(current or 0) .. "/" .. tostring(target or 0))
end

local function GiveFullUltimateGauge()
    if CombatContext == nil or CombatContext.GetPlayerUltimate == nil or CombatContext.SetPlayerUltimate == nil then
        print("[Tutorial] CombatContext ultimate API unavailable")
        return false
    end

    local current, maxGauge = CombatContext.GetPlayerUltimate()
    maxGauge = maxGauge or 0.0
    if maxGauge <= 0.001 then
        maxGauge = 100.0
    end

    local ok = CombatContext.SetPlayerUltimate(maxGauge, maxGauge)
    print("[Tutorial] set ultimate gauge full current=" .. tostring(current or 0.0) .. " max=" .. tostring(maxGauge) .. " ok=" .. tostring(ok))
    return ok == true
end

local TutorialSteps = {
    {
        Id = "Move",
        Title = "이동",
        Body = "W/A/S/D로 캐릭터를 이동해보세요.",
        Status = "MOVE",

        OnEnter = function()
            SetMessage("튜토리얼 1 - 이동", MoveInputText() .. " 캐릭터를 이동하세요.", "MOVE")
        end,

        BindEvents = function()
            GameplayEventBus.Subscribe(PlayerEvents.Type.MoveStarted, OWNER, function(event)
                CompleteCurrentStep(EventTypeName(event, PlayerEvents.Type.MoveStarted))
            end)
        end,

        OnComplete = function()
            SetMessage("이동 완료", "좋습니다. 이동 입력이 확인됐습니다.", "COMPLETE")
        end,
    },

    {
        Id = "BasicAttack",
        Title = "기본 공격",
        Body = "앞의 훈련 대상을 기본 공격으로 맞혀보세요.",
        Status = "ATTACK",

        OnEnter = function()
            TutorialSpawner.PrepareBasicAttackTarget()
            SetMessage("튜토리얼 2 - 기본 공격", UseInputText("Attack") .. " 훈련 대상을 기본 공격하세요.", "ATTACK")
        end,

        BindEvents = function()
            GameplayEventBus.Subscribe(PlayerEvents.Type.AttackHit, OWNER, function(event)
                CompleteCurrentStep(EventTypeName(event, PlayerEvents.Type.AttackHit))
            end)
        end,

        OnComplete = function()
            SetMessage("공격 완료", "공격이 실제로 적중했습니다.", "COMPLETE")
        end,
    },

    {
        Id = "Combo",
        Title = "연속 공격",
        Body = "기본 공격을 연속으로 3회 적중시켜보세요.",
        Status = "COMBO 0/3",

        OnEnter = function()
            stepState.HitCount = 0
            stepState.TargetHitCount = 3
            TutorialSpawner.PrepareComboTarget()
            SetMessage("튜토리얼 3 - 연속 공격", UseInputText("Attack") .. " 기본 공격을 3회 적중시키세요.", "COMBO 0/3")
        end,

        BindEvents = function()
            GameplayEventBus.Subscribe(PlayerEvents.Type.AttackHit, OWNER, function(event)
                stepState.HitCount = math.min((stepState.HitCount or 0) + 1, stepState.TargetHitCount or 3)
                UpdateProgressStatus("COMBO", stepState.HitCount, stepState.TargetHitCount or 3)
                if stepState.HitCount >= (stepState.TargetHitCount or 3) then
                    CompleteCurrentStep(EventTypeName(event, PlayerEvents.Type.AttackHit))
                end
            end)
        end,

        OnComplete = function()
            SetMessage("연속 공격 완료", "3회 적중이 확인됐습니다.", "COMPLETE")
        end,
    },

    {
        Id = "Dash",
        Title = "대시",
        Body = "Shift를 짧게 눌러 대시하세요.",
        Status = "DASH",

        OnEnter = function()
            TutorialSpawner.PrepareDashTarget()
            SetMessage("튜토리얼 4 - 대시", HoldInputText("Dash") .. " 짧게 눌러 적 기준으로 대시하세요.", "DASH")
        end,

        BindEvents = function()
            GameplayEventBus.Subscribe(PlayerEvents.Type.DashStarted, OWNER, function(event)
                CompleteCurrentStep(EventTypeName(event, PlayerEvents.Type.DashStarted))
            end)
        end,

        OnComplete = function()
            SetMessage("대시 완료", "대시 입력이 확인됐습니다.", "COMPLETE")
        end,
    },

    {
        Id = "DashCharge",
        Title = "대시 차징",
        Body = "Shift를 길게 눌러 차징한 뒤, 키를 떼서 차징 공격을 발동하세요.",
        Status = "CHARGE",

        OnEnter = function()
            stepState.ChargingStarted = false
            TutorialSpawner.PrepareDashChargeTarget()
            SetMessage("튜토리얼 5 - 대시 차징", HoldInputText("Dash") .. " 길게 눌러 차징 후 떼서 공격하세요.", "CHARGE")
        end,

        BindEvents = function()
            GameplayEventBus.Subscribe(PlayerEvents.Type.DashChargingStarted, OWNER, function()
                stepState.ChargingStarted = true
                SetMessage("차징 중", "좋습니다. " .. HoldInputText("Dash") .. " 떼서 차징 공격하세요.", "RELEASE")
            end)

            GameplayEventBus.Subscribe(PlayerEvents.Type.DashChargeAttackStarted, OWNER, function(event)
                CompleteCurrentStep(EventTypeName(event, PlayerEvents.Type.DashChargeAttackStarted))
            end)
        end,

        OnComplete = function()
            SetMessage("차징 공격 완료", "대시 차징 공격이 시작됐습니다.", "COMPLETE")
        end,
    },

    {
        Id = "PerfectDodge",
        Title = "퍼펙트 회피",
        Body = "적 공격 타이밍에 맞춰 대시해서 퍼펙트 회피를 발동하세요.",
        Status = "DODGE",

        OnEnter = function()
            TutorialSpawner.PreparePerfectDodgeEnemy()
            SetMessage("튜토리얼 6 - 퍼펙트 회피", "적 공격 타이밍에 " .. HoldInputText("Dash") .. " 눌러 회피하세요.", "DODGE")
        end,

        BindEvents = function()
            GameplayEventBus.Subscribe(BossEvents.Type.AttackTelegraphStarted, OWNER, function()
                if stepCompleted ~= true then
                    SetMessage("공격 예고", "적 공격 타이밍에 " .. HoldInputText("Dash") .. " 눌러 대시하세요.", "DODGE")
                end
            end)

            GameplayEventBus.Subscribe(BossEvents.Type.AttackHitWindowOpened, OWNER, function()
                if stepCompleted ~= true then
                    SetMessage("회피 타이밍", "지금 " .. HoldInputText("Dash") .. " 눌러 공격을 피하세요.", "DODGE")
                end
            end)

            GameplayEventBus.Subscribe(PlayerEvents.Type.Hit, OWNER, function()
                if stepCompleted ~= true then
                    SetMessage("다시 시도", "피격됐습니다. 다음 공격 타이밍에 맞춰 다시 회피하세요.", "RETRY")
                end
            end)

            GameplayEventBus.Subscribe(PlayerEvents.Type.PerfectDodge, OWNER, function(event)
                CompleteCurrentStep(EventTypeName(event, PlayerEvents.Type.PerfectDodge))
            end)
        end,

        OnComplete = function()
            SetMessage("퍼펙트 회피 완료", "퍼펙트 회피 이벤트가 확인됐습니다.", "COMPLETE")
        end,
    },

    {
        Id = "Ultimate",
        Title = "궁극기",
        Body = "궁극기 게이지를 채웠습니다. Q를 눌러 궁극기를 사용하세요.",
        Status = "ULT READY",

        OnEnter = function()
            TutorialSpawner.PrepareUltimateTargets()
            GiveFullUltimateGauge()
            SetMessage("튜토리얼 7 - 궁극기", PressInputText("Ultimate") .. " 눌러 소환된 적에게 궁극기를 쓰세요.", "ULT")
        end,

        BindEvents = function()
            GameplayEventBus.Subscribe(PlayerEvents.Type.UltimateStarted, OWNER, function(event)
                CompleteCurrentStep(EventTypeName(event, PlayerEvents.Type.UltimateStarted))
            end)
        end,

        OnComplete = function()
            SetMessage("궁극기 완료", "궁극기 사용이 확인됐습니다.", "COMPLETE")
        end,
    },

    {
        Id = "Finish",
        Title = "실전 준비",
        Body = "기본 조작 튜토리얼이 끝났습니다.",
        Status = "DONE",

        OnEnter = function()
            SetMessage("튜토리얼 종료", "기본 조작 튜토리얼이 끝났습니다.", "DONE")
            CompleteCurrentStepSoon("Tutorial.Finish")
        end,

        OnComplete = function()
            SetMessage("튜토리얼 완료", "자유롭게 진행하세요.", "FREE")
        end,
    },
}

local function EnterFreePlay()
    ClearStepSubscriptions()
    active = false
    freePlay = true
    currentStep = nil
    currentStepIndex = 0
    stepCompleted = false
    stepState = {}
    advanceDelay = 0.0

    TutorialSpawner.EndSession()
    SetMessage("튜토리얼 완료", "자유롭게 진행하세요.", "FREE")
    print("[Tutorial] enter free play label=" .. tostring(activeLabel))
end

local function StartStep(index)
    ClearStepSubscriptions()

    currentStepIndex = index
    currentStep = TutorialSteps[currentStepIndex]
    stepCompleted = false
    stepState = {}
    advanceDelay = 0.0

    if currentStep == nil then
        EnterFreePlay()
        return
    end

    print("[Tutorial] step enter index=" .. tostring(currentStepIndex) .. " id=" .. tostring(currentStep.Id))

    if currentStep.OnEnter ~= nil then
        currentStep.OnEnter()
    else
        SetMessage(currentStep.Title, currentStep.Body, currentStep.Status)
    end

    if currentStep.BindEvents ~= nil then
        currentStep.BindEvents()
    end
end

---@param sceneName string|nil
---@return nil
function TutorialDirector.QueueTrainingSession(sceneName)
    queuedTrainingSceneName = sceneName or "TrainingMap"
    print("[Tutorial] queued training tutorial for scene=" .. tostring(queuedTrainingSceneName))
end

---@return boolean
function TutorialDirector.HasQueuedTrainingSession()
    return queuedTrainingSceneName ~= nil
end

---@param label string|nil
---@param hud any|nil
---@return nil
function TutorialDirector.Begin(label, hud)
    TutorialDirector.End()

    lastHud = hud
    active = true
    freePlay = false
    exitConfirmVisible = false
    activeLabel = label or queuedTrainingSceneName or "TrainingMap"
    queuedTrainingSceneName = nil

    print("[Tutorial] begin label=" .. tostring(activeLabel) .. " stepCount=" .. tostring(#TutorialSteps))
    StartStep(1)
end

---@param label string|nil
---@param hud any|nil
---@return boolean
function TutorialDirector.BeginIfQueued(label, hud)
    if queuedTrainingSceneName == nil then
        return false
    end

    TutorialDirector.Begin(label or queuedTrainingSceneName, hud)
    return true
end

---@param hud any|nil
---@return nil
function TutorialDirector.SetHud(hud)
    lastHud = hud
    ApplyHudText(lastHud)
end

---@param dt number
---@param hud any|nil
---@return nil
function TutorialDirector.Tick(dt, hud)
    lastHud = hud

    if active ~= true and freePlay ~= true then
        return
    end

    ApplyHudText(hud)

    if active ~= true or stepCompleted ~= true then
        return
    end

    if exitConfirmVisible == true then
        return
    end

    advanceDelay = advanceDelay - (dt or 0.0)
    if advanceDelay <= 0.0 then
        StartStep(currentStepIndex + 1)
    end
end

---@return boolean
function TutorialDirector.ShowExitConfirm()
    if active ~= true and freePlay ~= true then
        return false
    end

    exitConfirmVisible = true
    ApplyHudText(lastHud)
    print("[Tutorial] exit confirm shown")
    return true
end

---@return boolean
function TutorialDirector.HideExitConfirm()
    if exitConfirmVisible ~= true then
        return false
    end

    exitConfirmVisible = false
    ApplyHudText(lastHud)
    print("[Tutorial] exit confirm hidden")
    return true
end

---@return boolean
function TutorialDirector.IsExitConfirmVisible()
    return exitConfirmVisible == true
end

---@return nil
function TutorialDirector.EndSession()
    if active == true or freePlay == true then
        print("[Tutorial] end session label=" .. tostring(activeLabel))
    end

    ClearStepSubscriptions()
    TutorialSpawner.EndSession(true)
    active = false
    freePlay = false
    exitConfirmVisible = false
    currentStepIndex = 0
    currentStep = nil
    stepCompleted = false
    stepState = {}
    advanceDelay = 0.0
    lastHud = nil
    messageTitle = ""
    messageBody = ""
    messageStatus = ""
end

---@return nil
function TutorialDirector.End()
    if active == true or freePlay == true then
        print("[Tutorial] end label=" .. tostring(activeLabel))
    end

    ClearStepSubscriptions()
    active = false
    freePlay = false
    exitConfirmVisible = false
    currentStepIndex = 0
    currentStep = nil
    stepCompleted = false
    stepState = {}
    advanceDelay = 0.0
    lastHud = nil
    messageTitle = ""
    messageBody = ""
    messageStatus = ""
end

---@return boolean
function TutorialDirector.IsRunning()
    return active == true
end

---@return boolean
function TutorialDirector.IsFreePlay()
    return freePlay == true
end

return TutorialDirector
