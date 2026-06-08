-- Tutorial/TutorialDirector.lua
-- Event-driven tutorial state machine for TrainingMap.
-- This module intentionally does not poll PlayerContext. Steps subscribe to
-- GameplayEventBus events and advance only when the expected gameplay result
-- is published.

local GameplayEventBus = require("Core/GameplayEventBus")
local PlayerEvents = require("Player/PlayerEvents")

local TutorialDirector = {}

local OWNER = { Name = "TutorialDirector" }
local queuedTrainingSceneName = nil
local active = false
local freePlay = false
local activeLabel = "TrainingMap"
local currentStepIndex = 0
local currentStep = nil
local stepCompleted = false
local advanceDelay = 0.0
local messageTitle = ""
local messageBody = ""
local messageStatus = ""
local lastHud = nil

local COMPLETE_ADVANCE_DELAY = 1.20

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

local function ClearStepSubscriptions()
    GameplayEventBus.ClearOwner(OWNER)
end

local function CompleteCurrentStep(reason)
    if active ~= true or currentStep == nil or stepCompleted == true then
        return
    end

    stepCompleted = true
    advanceDelay = COMPLETE_ADVANCE_DELAY

    if currentStep.OnComplete ~= nil then
        currentStep.OnComplete({ Reason = reason })
    else
        SetMessage("튜토리얼 완료", "단계를 완료했습니다.", "NEXT")
    end

    print("[Tutorial] step complete id=" .. tostring(currentStep.Id) .. " reason=" .. tostring(reason or "event"))
end

local TutorialSteps = {
    {
        Id = "Move",
        Title = "이동",
        Body = "W/A/S/D로 캐릭터를 이동해보세요.",
        Status = "MOVE",

        OnEnter = function()
            SetMessage("튜토리얼 1 - 이동", "W/A/S/D로 캐릭터를 이동해보세요.", "MOVE")
        end,

        BindEvents = function()
            GameplayEventBus.Subscribe(PlayerEvents.Type.MoveStarted, OWNER, function(event)
                CompleteCurrentStep(event ~= nil and event.Type or PlayerEvents.Type.MoveStarted)
            end)
        end,

        OnComplete = function()
            SetMessage("이동 완료", "좋습니다. 이동 입력이 확인됐습니다.", "COMPLETE")
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
    advanceDelay = 0.0

    SetMessage("튜토리얼 완료", "다음 튜토리얼 단계가 없습니다. 이제 자유롭게 진행하세요.", "FREE")
    print("[Tutorial] enter free play label=" .. tostring(activeLabel))
end

local function StartStep(index)
    ClearStepSubscriptions()

    currentStepIndex = index
    currentStep = TutorialSteps[currentStepIndex]
    stepCompleted = false
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

    advanceDelay = advanceDelay - (dt or 0.0)
    if advanceDelay <= 0.0 then
        StartStep(currentStepIndex + 1)
    end
end

---@return nil
function TutorialDirector.End()
    if active == true or freePlay == true then
        print("[Tutorial] end label=" .. tostring(activeLabel))
    end

    ClearStepSubscriptions()
    active = false
    freePlay = false
    currentStepIndex = 0
    currentStep = nil
    stepCompleted = false
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
