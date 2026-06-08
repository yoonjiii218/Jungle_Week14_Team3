local CombatContext = require("Combat/CombatContext")
local TutorialDirector = require("Tutorial/TutorialDirector")

local widgets = {}
local director = nil
local currentScreen = "None"
local currentFlowBgmKey = nil
local loadedFlowBgm = {}
local TEST_HOTKEYS_ENABLED = true
local TEST_PLAYER_DAMAGE = 10.0
local TEST_BOSS_DAMAGE = 10.0
local TEST_ULTIMATE_DELTA = 25.0
local START_MENU_BOOT_REPLAY_KEY_NAME = "F9"
local KEY_ENTER = 13
local START_MENU_BOOT_DURATION = 1.50
local START_MENU_BOOT_BASE_WIDTH = 1280.0
local START_MENU_BOOT_BASE_HEIGHT = 720.0
local FILM_COUNTDOWN_WIDGET_FALLBACK = "Content/UI/GameFlow/FilmCountdown.uasset"
local FILM_COUNTDOWN_DURATION = 3.35
local FILM_COUNTDOWN_PLAY_SECONDS = 3.0
local FILM_SPROCKET_COUNT = 11
local FILM_SPROCKET_SPACING = 86.0
local FILM_SPROCKET_SPEED = 210.0
local FILM_SWEEP_SECTOR_FRAME_COUNT = 33
local CLEAR_TO_CREDITS_DELAY = 2.35
local CREDITS_ROLL_DURATION = 18.0
local CREDITS_ROLL_START_PADDING = 120.0
local CREDITS_ROLL_END_OFFSET = 1080.0
local START_MENU_BOOT_ELEMENT_IDS = {
    "boot-black",
    "boot-shutter-top",
    "boot-shutter-bottom",
    "boot-shutter-left",
    "boot-shutter-right",
    "boot-static-a",
    "boot-static-b",
    "boot-slit-glow",
    "boot-glow-cyan",
    "boot-glow-pink",
    "boot-cross-h-cyan",
    "boot-cross-v-cyan",
    "boot-cross-h-pink",
    "boot-cross-v-pink",
    "boot-cross-h",
    "boot-cross-v",
    "boot-core",
    "boot-sweep",
    "boot-noise-a",
    "boot-noise-b",
    "boot-noise-c",
}
local startMenuBootTime = START_MENU_BOOT_DURATION + 1.0
local filmCountdownTime = FILM_COUNTDOWN_DURATION + 1.0
local clearToCreditsTime = 0.0
local creditsRollTime = CREDITS_ROLL_DURATION + 1.0
local startHudFlow = nil
local showCredits = nil
local FLOW_BGM = {
    StartMenu = {
        key = "BGM_StartMenu",
        path = "BGM/Start Menu BGM.mp3",
        volume = 0.6,
    },
    TrainingMap = {
        key = "BGM_TrainingMap",
        path = "BGM/TrainingMap BGM.mp3",
        volume = 0.2,
    },
}

local function getDirector()
    if director ~= nil and director.IsValid ~= nil and director:IsValid() then
        return director
    end

    director = GameFlow.GetDirector()
    if director == nil and obj ~= nil then
        director = obj
    end
    return director
end

local function getCurrentSceneName(d)
    if d ~= nil and d.GetCurrentSceneName ~= nil then
        return d:GetCurrentSceneName()
    end
    return ""
end

local function playFlowBGM(config)
    if config == nil or AudioManager == nil or AudioManager.Load == nil or AudioManager.PlayBGM == nil then
        return
    end
    if currentFlowBgmKey == config.key then
        return
    end

    if loadedFlowBgm[config.key] ~= true then
        if AudioManager.Load(config.key, config.path, true) ~= true then
            print("[GameFlow] Failed to load BGM: " .. tostring(config.path))
            return
        end
        loadedFlowBgm[config.key] = true
    end

    AudioManager.PlayBGM(config.key, config.volume or 0.6)
    currentFlowBgmKey = config.key
end

local function stopFlowBGM()
    if AudioManager ~= nil and AudioManager.StopBGM ~= nil then
        AudioManager.StopBGM()
    end
    currentFlowBgmKey = nil
end

local function isTrainingMapFlow(d, bTrainingQueued)
    if bTrainingQueued == true then
        return true
    end
    return getCurrentSceneName(d) == "TrainingMap"
end

local function removeWidget(name)
    local widget = widgets[name]
    if widget ~= nil then
        widget:RemoveFromParent()
        widgets[name] = nil
    end
end

local function removeAllWidgets()
    for name, _ in pairs(widgets) do
        removeWidget(name)
    end
end

local function createWidget(name, path, wantsMouse, zOrder)
    if path == nil or path == "" then
        return nil
    end

    removeWidget(name)

    local widgetFactory = UI.CreateWidgetForPlayer or UI.CreateWidget
    local widget = widgetFactory(path)
    if widget == nil then
        print("[GameFlow] Failed to create widget: " .. tostring(path))
        return nil
    end

    widget:SetWantsMouse(wantsMouse == true)
    widgets[name] = widget
    return widget
end

local function addToViewport(widget, zOrder)
    if widget == nil then
        return
    end
    widget:AddToViewportZ(zOrder or 0)
end

local function setText(widget, id, text)
    if widget ~= nil then
        widget:SetText(id, tostring(text))
    end
end

local function setBar(widget, id, current, maxValue)
    if widget == nil then
        return
    end

    local ratio = 0.0
    if maxValue ~= nil and maxValue > 0 then
        ratio = current / maxValue
    end
    if ratio < 0.0 then ratio = 0.0 end
    if ratio > 1.0 then ratio = 1.0 end

    widget:SetProperty(id, "width", string.format("%.1f%%", ratio * 100.0))
end

local function clamp(value, minValue, maxValue)
    if value < minValue then return minValue end
    if value > maxValue then return maxValue end
    return value
end

local function lerp(a, b, t)
    return a + (b - a) * clamp(t, 0.0, 1.0)
end

local function px(value)
    return string.format("%.0fpx", value)
end

local function scalar(value)
    return string.format("%.3f", clamp(value, 0.0, 1.0))
end

local function whole(value)
    return string.format("%.0f", value or 0.0)
end

local function percent(current, maxValue)
    if maxValue == nil or maxValue <= 0.0 then
        return 0
    end
    return math.floor(clamp((current or 0.0) / maxValue, 0.0, 1.0) * 100.0 + 0.5)
end

local function hasRegisteredPlayer()
    return CombatContext.HasPlayer ~= nil and CombatContext.HasPlayer() == true
end

local function getPlayerStats(d)
    if hasRegisteredPlayer() then
        return CombatContext.GetPlayerHP()
    end
    return d:GetPlayerHP(), d:GetPlayerMaxHP()
end

local function getUltimateStats(d)
    if hasRegisteredPlayer() then
        return CombatContext.GetPlayerUltimate()
    end
    return d:GetUltimateGauge(), d:GetUltimateMaxGauge()
end

local function getComboCount(d)
    if hasRegisteredPlayer() then
        return CombatContext.GetPlayerCombo()
    end
    return d:GetComboCount()
end

local function getDashCooldownStats()
    if hasRegisteredPlayer() and CombatContext.GetPlayerDashCooldown ~= nil then
        return CombatContext.GetPlayerDashCooldown()
    end
    return 0.0, 0.0, 0.0
end

local function dashCooldownText(remaining, duration)
    if duration == nil or duration <= 0.0 then
        return "DASH READY"
    end
    if remaining == nil or remaining <= 0.01 then
        return "DASH READY"
    end
    return string.format("DASH %.1fs", remaining)
end

local function setPlayerHPForTest(d, current, maxValue)
    if CombatContext.SetPlayerHP ~= nil and CombatContext.SetPlayerHP(current, maxValue) == true then
        return
    end
    d:SetPlayerHP(current, maxValue)
end

local function setBossHPForTest(d, current, maxValue)
    if CombatContext.SetBossHP ~= nil and CombatContext.SetBossHP(current, maxValue) == true then
        return
    end
    d:SetBossHP(current, maxValue)
end

local function setUltimateForTest(d, current, maxValue)
    if CombatContext.SetPlayerUltimate ~= nil and CombatContext.SetPlayerUltimate(current, maxValue) == true then
        return
    end
    d:SetUltimateGauge(current, maxValue)
end

local function setComboForTest(d, count)
    if CombatContext.SetPlayerCombo ~= nil and CombatContext.SetPlayerCombo(count) == true then
        return
    end
    d:SetComboCount(count)
end

local function printTestHotkeyHelp()
    print("[GameFlowTest] F1 Player -10 HP | F2 Boss -10 HP | F3 Ultimate +25 | F4 Combo +1 | F5 Clear | F6 GameOver | F7 Reset")
end

local function printStartMenuHotkeyHelp()
    print("[GameFlowTest] F9 Replay start-menu TV boot")
end

local function applyTestHotkeys()
    if TEST_HOTKEYS_ENABLED ~= true or currentScreen ~= "HUD" or Input == nil or Key == nil or Input.GetKeyDown == nil then
        return
    end

    local d = getDirector()
    if d == nil then return end

    if Input.GetKeyDown(Key.F1) then
        local hp, maxHP = getPlayerStats(d)
        setPlayerHPForTest(d, clamp(hp - TEST_PLAYER_DAMAGE, 0.0, maxHP), maxHP)
        print("[GameFlowTest] Player damage")
    elseif Input.GetKeyDown(Key.F2) then
        local hp, maxHP = CombatContext.GetBossHP()
        if maxHP == nil or maxHP <= 0.0 then
            hp = d:GetBossHP()
            maxHP = d:GetBossMaxHP()
        end
        setBossHPForTest(d, clamp(hp - TEST_BOSS_DAMAGE, 0.0, maxHP), maxHP)
        print("[GameFlowTest] Boss damage")
    elseif Input.GetKeyDown(Key.F3) then
        local gauge, maxGauge = getUltimateStats(d)
        setUltimateForTest(d, clamp(gauge + TEST_ULTIMATE_DELTA, 0.0, maxGauge), maxGauge)
        print("[GameFlowTest] Ultimate gauge")
    elseif Input.GetKeyDown(Key.F4) then
        setComboForTest(d, getComboCount(d) + 1)
        print("[GameFlowTest] Combo")
    elseif Input.GetKeyDown(Key.F5) then
        local _, maxHP = CombatContext.GetBossHP()
        if maxHP == nil or maxHP <= 0.0 then
            maxHP = d:GetBossMaxHP()
        end
        setBossHPForTest(d, 0.0, maxHP)
        print("[GameFlowTest] Force clear")
    elseif Input.GetKeyDown(Key.F6) then
        local _, maxHP = getPlayerStats(d)
        setPlayerHPForTest(d, 0.0, maxHP)
        print("[GameFlowTest] Force game over")
    elseif Input.GetKeyDown(Key.F7) then
        setPlayerHPForTest(d, d:GetPlayerMaxHP(), d:GetPlayerMaxHP())
        setBossHPForTest(d, d:GetBossMaxHP(), d:GetBossMaxHP())
        setUltimateForTest(d, 0.0, d:GetUltimateMaxGauge())
        setComboForTest(d, 0)
        print("[GameFlowTest] Reset combat values")
    end
end

local function setBootProperty(widget, id, property, value)
    if widget ~= nil then
        widget:SetProperty(id, property, tostring(value))
    end
end

local function getStartMenuBootViewport()
    local width = START_MENU_BOOT_BASE_WIDTH
    local height = START_MENU_BOOT_BASE_HEIGHT

    if Engine ~= nil and Engine.GetViewportSize ~= nil then
        local size = Engine.GetViewportSize()
        if size ~= nil then
            width = tonumber(size.Width or size["Width"] or width) or width
            height = tonumber(size.Height or size["Height"] or height) or height
        end
    end

    if width <= 0.0 then width = START_MENU_BOOT_BASE_WIDTH end
    if height <= 0.0 then height = START_MENU_BOOT_BASE_HEIGHT end
    return width, height, width * 0.5, height * 0.5
end

local function setBootOpacity(widget, value)
    for _, id in ipairs(START_MENU_BOOT_ELEMENT_IDS) do
        setBootProperty(widget, id, "opacity", value)
    end
end

local function setBootRect(widget, id, left, top, width, height)
    setBootProperty(widget, id, "left", px(left))
    setBootProperty(widget, id, "top", px(top))
    setBootProperty(widget, id, "width", px(width))
    setBootProperty(widget, id, "height", px(height))
end

local function setBootShutters(widget, viewportWidth, viewportHeight, centerX, centerY, apertureWidth, apertureHeight, opacity)
    local halfWidth = clamp(apertureWidth * 0.5, 0.0, viewportWidth * 0.5)
    local halfHeight = clamp(apertureHeight * 0.5, 0.0, viewportHeight * 0.5)
    local leftWidth = clamp(centerX - halfWidth, 0.0, viewportWidth)
    local rightLeft = clamp(centerX + halfWidth, 0.0, viewportWidth)
    local topHeight = clamp(centerY - halfHeight, 0.0, viewportHeight)
    local bottomTop = clamp(centerY + halfHeight, 0.0, viewportHeight)
    local shutterOpacity = scalar(opacity)

    setBootRect(widget, "boot-shutter-top", 0.0, 0.0, viewportWidth, topHeight)
    setBootRect(widget, "boot-shutter-bottom", 0.0, bottomTop, viewportWidth, viewportHeight - bottomTop)
    setBootRect(widget, "boot-shutter-left", 0.0, 0.0, leftWidth, viewportHeight)
    setBootRect(widget, "boot-shutter-right", rightLeft, 0.0, viewportWidth - rightLeft, viewportHeight)
    setBootProperty(widget, "boot-shutter-top", "opacity", shutterOpacity)
    setBootProperty(widget, "boot-shutter-bottom", "opacity", shutterOpacity)
    setBootProperty(widget, "boot-shutter-left", "opacity", "0")
    setBootProperty(widget, "boot-shutter-right", "opacity", "0")
end

local function flashPulse(t, startTime, duration, peak)
    if t < startTime or t > startTime + duration then
        return 0.0
    end

    local phase = (t - startTime) / duration
    if phase < 0.5 then
        return peak * phase * 2.0
    end
    return peak * (1.0 - phase) * 2.0
end

local function setStartMenuBootFinal(widget)
    setBootProperty(widget, "screen", "left", "0px")
    setBootProperty(widget, "screen", "top", "0px")
    setBootProperty(widget, "screen", "width", "100%")
    setBootProperty(widget, "screen", "height", "100%")
    setBootOpacity(widget, "0")
end

local function updateStartMenuBoot(dt)
    local menu = widgets.StartMenu
    if menu == nil then
        startMenuBootTime = START_MENU_BOOT_DURATION + 1.0
        return
    end

    if startMenuBootTime > START_MENU_BOOT_DURATION then
        return
    end

    startMenuBootTime = startMenuBootTime + (dt or 0.0)
    local t = startMenuBootTime

    if t >= START_MENU_BOOT_DURATION then
        setStartMenuBootFinal(menu)
        return
    end

    local viewportWidth, viewportHeight, centerX, centerY = getStartMenuBootViewport()

    local black = 0.0
    if t < 0.07 then
        black = 1.0
    elseif t < 0.26 then
        black = lerp(1.0, 0.0, (t - 0.07) / 0.19)
    end

    local openProgress = 0.0
    local apertureHeight = 2.0
    if t < 0.08 then
        apertureHeight = 2.0
    elseif t < 0.34 then
        local p = (t - 0.08) / 0.26
        openProgress = p * 0.28
        apertureHeight = lerp(2.0, viewportHeight * 0.055, p * p)
    elseif t < 0.98 then
        local p = (t - 0.34) / 0.64
        local smoothOpen = p * p * (3.0 - 2.0 * p)
        openProgress = lerp(0.28, 1.0, smoothOpen)
        apertureHeight = lerp(viewportHeight * 0.055, viewportHeight * 1.12, smoothOpen)
    else
        openProgress = 1.0
        apertureHeight = viewportHeight * 1.12
    end

    local apertureWidth = viewportWidth * 1.12
    local shutterOpacity = t < 1.02 and 1.0 or lerp(1.0, 0.0, (t - 1.02) / 0.12)
    local slitOpacity = 0.0
    if t >= 0.05 and t < 0.82 then
        if t < 0.16 then
            slitOpacity = lerp(0.0, 1.0, (t - 0.05) / 0.11)
        elseif t < 0.52 then
            slitOpacity = lerp(1.0, 0.72, (t - 0.16) / 0.36)
        else
            slitOpacity = lerp(0.72, 0.0, (t - 0.52) / 0.30)
        end
    end

    local slitWidth = lerp(18.0, viewportWidth * 1.14, clamp(t / 0.36, 0.0, 1.0))
    local slitHeight = lerp(2.0, 14.0, openProgress)
    local glowWidth = viewportWidth * 1.18
    local glowHeight = clamp(apertureHeight + 44.0, 18.0, viewportHeight * 1.18)
    local glowOpacity = slitOpacity * lerp(0.38, 0.10, openProgress)
    local slitBloomWidth = clamp(slitWidth + viewportWidth * 0.16, 96.0, viewportWidth * 1.08)
    local slitBloomHeight = clamp(52.0 + apertureHeight * 0.42, 42.0, viewportHeight * 0.24)
    local slitBloomOpacity = slitOpacity * lerp(0.48, 0.16, openProgress) + flashPulse(t, 0.08, 0.16, 0.20)
    local chromaOpacity = slitOpacity * 0.16
    local corePulse = flashPulse(t, 0.04, 0.18, 1.0)
    local coreSize = lerp(5.0, 28.0, clamp(corePulse, 0.0, 1.0))
    local coreOpacity = scalar(corePulse)

    local sweepOpacity = 0.0
    local sweepTop = centerY
    if t >= 0.42 and t < 1.06 then
        local p = (t - 0.42) / 0.64
        sweepTop = lerp(centerY - 12.0, viewportHeight + 18.0, p)
        sweepOpacity = p < 0.20 and lerp(0.36, 0.24, p / 0.20) or lerp(0.24, 0.0, (p - 0.20) / 0.80)
    end

    local staticBase = flashPulse(t, 0.07, 0.30, 0.82)
        + flashPulse(t, 0.29, 0.40, 0.62)
        + flashPulse(t, 0.62, 0.34, 0.36)
        + flashPulse(t, 0.96, 0.18, 0.18)
    local staticPhase = math.floor(t * 38.0) % 2
    local staticA = staticPhase == 0 and staticBase or staticBase * 0.56
    local staticB = staticPhase == 1 and staticBase * 0.92 or staticBase * 0.36
    local noiseA = flashPulse(t, 0.10, 0.10, 0.70) + flashPulse(t, 0.38, 0.14, 0.44) + flashPulse(t, 0.72, 0.12, 0.24)
    local noiseB = flashPulse(t, 0.18, 0.12, 0.58) + flashPulse(t, 0.51, 0.16, 0.34) + flashPulse(t, 0.86, 0.10, 0.20)
    local noiseC = flashPulse(t, 0.28, 0.10, 0.44) + flashPulse(t, 0.61, 0.14, 0.28) + flashPulse(t, 0.98, 0.08, 0.16)
    local noiseSlot = math.floor(t * 64.0)
    local noiseATop = 0.08 * viewportHeight + (noiseSlot % 11) * viewportHeight * 0.065
    local noiseBTop = 0.14 * viewportHeight + ((noiseSlot + 5) % 9) * viewportHeight * 0.075
    local noiseCTop = 0.05 * viewportHeight + ((noiseSlot + 8) % 10) * viewportHeight * 0.070

    setBootProperty(menu, "screen", "left", "0px")
    setBootProperty(menu, "screen", "top", "0px")
    setBootProperty(menu, "screen", "width", "100%")
    setBootProperty(menu, "screen", "height", "100%")
    setBootRect(menu, "boot-black", 0.0, 0.0, viewportWidth, viewportHeight)
    setBootProperty(menu, "boot-black", "opacity", scalar(black))
    setBootShutters(menu, viewportWidth, viewportHeight, centerX, centerY, apertureWidth, apertureHeight, shutterOpacity)
    setBootRect(menu, "boot-static-a", 0.0, 0.0, viewportWidth, viewportHeight)
    setBootRect(menu, "boot-static-b", 0.0, 0.0, viewportWidth, viewportHeight)
    setBootProperty(menu, "boot-static-a", "opacity", scalar(staticA))
    setBootProperty(menu, "boot-static-b", "opacity", scalar(staticB))
    setBootRect(menu, "boot-slit-glow", centerX - slitBloomWidth * 0.5, centerY - slitBloomHeight * 0.5, slitBloomWidth, slitBloomHeight)
    setBootProperty(menu, "boot-slit-glow", "opacity", scalar(slitBloomOpacity))
    setBootRect(menu, "boot-glow-cyan", centerX - glowWidth * 0.5, centerY - glowHeight * 0.5, glowWidth, glowHeight)
    setBootRect(menu, "boot-glow-pink", centerX - glowWidth * 0.5, centerY - glowHeight * 0.5, glowWidth, glowHeight)
    setBootProperty(menu, "boot-glow-cyan", "opacity", scalar(glowOpacity))
    setBootProperty(menu, "boot-glow-pink", "opacity", scalar(glowOpacity * 0.46))
    setBootRect(menu, "boot-cross-h-cyan", centerX - slitWidth * 0.5 + 3.0, centerY - slitHeight * 0.5, slitWidth, slitHeight)
    setBootRect(menu, "boot-cross-h-pink", centerX - slitWidth * 0.5 - 3.0, centerY - slitHeight * 0.5, slitWidth, slitHeight)
    setBootRect(menu, "boot-cross-h", centerX - slitWidth * 0.5, centerY - slitHeight * 0.5, slitWidth, slitHeight * 0.62)
    setBootProperty(menu, "boot-cross-h-cyan", "opacity", scalar(chromaOpacity))
    setBootProperty(menu, "boot-cross-h-pink", "opacity", scalar(chromaOpacity * 0.76))
    setBootProperty(menu, "boot-cross-h", "opacity", scalar(slitOpacity))
    setBootProperty(menu, "boot-cross-v-cyan", "opacity", "0")
    setBootProperty(menu, "boot-cross-v-pink", "opacity", "0")
    setBootProperty(menu, "boot-cross-v", "opacity", "0")
    setBootRect(menu, "boot-core", centerX - coreSize * 0.5, centerY - coreSize * 0.5, coreSize, coreSize)
    setBootProperty(menu, "boot-core", "opacity", coreOpacity)
    setBootProperty(menu, "boot-sweep", "opacity", scalar(sweepOpacity))
    setBootProperty(menu, "boot-sweep", "top", px(sweepTop))
    setBootProperty(menu, "boot-sweep", "height", px(lerp(2.0, 8.0, sweepOpacity)))
    setBootProperty(menu, "boot-sweep", "left", "0px")
    setBootProperty(menu, "boot-sweep", "width", px(viewportWidth))
    setBootProperty(menu, "boot-noise-a", "opacity", scalar(noiseA))
    setBootProperty(menu, "boot-noise-a", "top", px(noiseATop))
    setBootProperty(menu, "boot-noise-a", "height", px(lerp(8.0, 54.0, noiseA)))
    setBootProperty(menu, "boot-noise-a", "left", "0px")
    setBootProperty(menu, "boot-noise-a", "width", px(viewportWidth))
    setBootProperty(menu, "boot-noise-b", "opacity", scalar(noiseB))
    setBootProperty(menu, "boot-noise-b", "top", px(noiseBTop))
    setBootProperty(menu, "boot-noise-b", "height", px(lerp(6.0, 42.0, noiseB)))
    setBootProperty(menu, "boot-noise-b", "left", "0px")
    setBootProperty(menu, "boot-noise-b", "width", px(viewportWidth))
    setBootProperty(menu, "boot-noise-c", "opacity", scalar(noiseC))
    setBootProperty(menu, "boot-noise-c", "top", px(noiseCTop))
    setBootProperty(menu, "boot-noise-c", "height", px(lerp(5.0, 34.0, noiseC)))
    setBootProperty(menu, "boot-noise-c", "left", "0px")
    setBootProperty(menu, "boot-noise-c", "width", px(viewportWidth))
end

local function startStartMenuBoot(widget)
    startMenuBootTime = 0.0
    if widget ~= nil then
        local viewportWidth, viewportHeight, centerX, centerY = getStartMenuBootViewport()
        setBootOpacity(widget, "0")
        setBootRect(widget, "boot-black", 0.0, 0.0, viewportWidth, viewportHeight)
        setBootProperty(widget, "boot-black", "opacity", "1")
        setBootShutters(widget, viewportWidth, viewportHeight, centerX, centerY, viewportWidth * 1.12, 2.0, 1.0)
        setBootRect(widget, "boot-core", centerX - 7.0, centerY - 7.0, 14.0, 14.0)
    end
end

local function showHud()
    local d = getDirector()
    if d == nil then return end

    removeWidget("StartMenu")
    removeWidget("GameOver")
    removeWidget("Clear")
    removeWidget("Credits")
    removeWidget("Countdown")
    removeWidget("TutorialHUD")

    local hud = createWidget("HUD", d:GetHudWidgetPath(), false, 0)
    addToViewport(hud, 0)
    currentScreen = "HUD"
    printTestHotkeyHelp()
end

local function getTutorialHudWidgetPath(d)
    if d ~= nil and d.GetTutorialHudWidgetPath ~= nil then
        local path = d:GetTutorialHudWidgetPath()
        if path ~= nil and path ~= "" then
            return path
        end
    end

    return "Content/UI/GameFlow/TutorialHUD.uasset"
end

local function showTutorialHud()
    local d = getDirector()
    if d == nil then return nil end

    local tutorialHud = createWidget("TutorialHUD", getTutorialHudWidgetPath(d), false, 50)
    addToViewport(tutorialHud, 50)
    if tutorialHud ~= nil then
        print("[GameFlow] Tutorial HUD created: " .. tostring(getTutorialHudWidgetPath(d)))
    else
        print("[GameFlow] Tutorial HUD unavailable. Tutorial will keep logging only.")
    end
    return tutorialHud
end

startHudFlow = function()
    local d = getDirector()
    if d == nil then return end

    local bTrainingQueued = TutorialDirector.HasQueuedTrainingSession ~= nil
        and TutorialDirector.HasQueuedTrainingSession() == true
    local bTrainingMapFlow = isTrainingMapFlow(d, bTrainingQueued)

    d:StartCombat()
    showHud()
    if bTrainingMapFlow == true then
        playFlowBGM(FLOW_BGM.TrainingMap)
    end
    if bTrainingQueued == true then
        showTutorialHud()
    end
    if TutorialDirector.BeginIfQueued("TrainingMap", widgets.TutorialHUD) == true then
        print("[GameFlow] Training tutorial enabled after HUD startup")
    end
end

local function getCountdownWidgetPath(d)
    if d ~= nil and d.GetCountdownWidgetPath ~= nil then
        local path = d:GetCountdownWidgetPath()
        if path ~= nil and path ~= "" then
            return path
        end
    end

    return FILM_COUNTDOWN_WIDGET_FALLBACK
end

local function setCountdownProperty(widget, id, property, value)
    if widget ~= nil then
        widget:SetProperty(id, property, tostring(value))
    end
end

local function setCountdownRect(widget, id, left, top, width, height)
    setCountdownProperty(widget, id, "left", px(left))
    setCountdownProperty(widget, id, "top", px(top))
    setCountdownProperty(widget, id, "width", px(width))
    setCountdownProperty(widget, id, "height", px(height))
end

local function setCountdownOpacity(widget, id, value)
    setCountdownProperty(widget, id, "opacity", scalar(value))
end

local function updateFilmSprockets(widget, t, viewportWidth, viewportHeight, masterOpacity, offsetY, filmScale, filmWidth)
    local spacing = math.max(30.0, FILM_SPROCKET_SPACING * filmScale)
    local speed = math.max(70.0, FILM_SPROCKET_SPEED * filmScale)
    local sprocketWidth = clamp(34.0 * filmScale, 14.0, math.max(14.0, filmWidth * 0.58))
    local sprocketHeight = clamp(52.0 * filmScale, 22.0, math.max(22.0, spacing * 0.72))
    local sprocketInset = clamp(28.0 * filmScale, 6.0, math.max(6.0, filmWidth - sprocketWidth - 6.0))
    local travel = viewportHeight + spacing
    local offset = (t * speed) % spacing
    local sprocketOpacity = scalar(0.80 * masterOpacity)

    for i = 0, FILM_SPROCKET_COUNT - 1 do
        local leftId = "sp-l-" .. tostring(i)
        local rightId = "sp-r-" .. tostring(i)
        local top = ((i * spacing + offset) % travel) - spacing * 0.58 + (offsetY or 0.0)
        setCountdownRect(widget, leftId, sprocketInset, top, sprocketWidth, sprocketHeight)
        setCountdownRect(widget, rightId, viewportWidth - sprocketInset - sprocketWidth, top, sprocketWidth, sprocketHeight)
        setCountdownProperty(widget, leftId, "opacity", sprocketOpacity)
        setCountdownProperty(widget, rightId, "opacity", sprocketOpacity)
    end
end

local function updateSweepSector(widget, centerX, centerY, sectorSize, sweepCycle, sectorOpacity)
    local frameIndex = math.floor(clamp(sweepCycle, 0.0, 1.0) * (FILM_SWEEP_SECTOR_FRAME_COUNT - 1) + 0.5)

    for i = 0, FILM_SWEEP_SECTOR_FRAME_COUNT - 1 do
        local id = "sweep-sector-" .. tostring(i)
        setCountdownRect(widget, id, centerX - sectorSize * 0.5, centerY - sectorSize * 0.5, sectorSize, sectorSize)
        setCountdownOpacity(widget, id, i == frameIndex and sectorOpacity or 0.0)
    end
end

local function setCountdownNumber(widget, text)
    setText(widget, "countdown-number-cyan", text)
    setText(widget, "countdown-number-pink", text)
    setText(widget, "countdown-number-main", text)
end

local function completeFilmCountdown()
    removeWidget("Countdown")
    filmCountdownTime = FILM_COUNTDOWN_DURATION + 1.0
    if startHudFlow ~= nil then
        startHudFlow()
    end
end

local function updateFilmCountdown(dt)
    local countdown = widgets.Countdown
    if countdown == nil then
        completeFilmCountdown()
        return
    end

    filmCountdownTime = filmCountdownTime + (dt or 0.0)
    local t = filmCountdownTime
    if t >= FILM_COUNTDOWN_DURATION then
        completeFilmCountdown()
        return
    end

    local viewportWidth, viewportHeight, centerX, centerY = getStartMenuBootViewport()
    local jitterStep = math.floor(t * 22.0)
    local jitterY = 0.0
    if jitterStep % 19 == 2 then
        jitterY = 3.0
    elseif jitterStep % 23 == 7 then
        jitterY = -2.0
    elseif jitterStep % 31 == 11 then
        jitterY = 2.0
    end

    local activeTime = clamp(t, 0.0, FILM_COUNTDOWN_PLAY_SECONDS - 0.001)
    local digitIndex = math.floor(activeTime)
    local digit = 3 - digitIndex
    local digitTime = activeTime - digitIndex
    local digitText = tostring(digit)
    if t >= FILM_COUNTDOWN_PLAY_SECONDS then
        digitText = "START"
        digitTime = clamp((t - FILM_COUNTDOWN_PLAY_SECONDS) / (FILM_COUNTDOWN_DURATION - FILM_COUNTDOWN_PLAY_SECONDS), 0.0, 1.0)
    end

    local fadeIn = clamp(t / 0.18, 0.0, 1.0)
    local fadeOut = t > 3.08 and (1.0 - clamp((t - 3.08) / 0.27, 0.0, 1.0)) or 1.0
    local masterOpacity = fadeIn * fadeOut
    local digitPulse = 1.0 - clamp(digitTime / 0.92, 0.0, 1.0)
    local flash = flashPulse(digitTime, 0.0, 0.16, 1.0)
    local sweepAngle = digitTime * 360.0
    local grainPulse = 0.08 + 0.08 * (math.floor(t * 18.0) % 2)
    local framePulse = 0.86 + 0.08 * (math.floor(t * 9.0) % 2)
    local scanSlot = math.floor(t * 14.0)
    local scanTop = (scanSlot % 8) * viewportHeight * 0.125
    local scratchSlot = math.floor(t * 7.0)
    local scratchLeftA = viewportWidth * (0.12 + (scratchSlot % 5) * 0.17)
    local scratchLeftB = viewportWidth * (0.28 + ((scratchSlot + 3) % 4) * 0.16)
    local contentCenterY = centerY + jitterY
    local circleSize = math.min(viewportWidth, viewportHeight) * 0.58
    local uiScale = clamp(circleSize / 414.0, 0.35, 1.85)
    local innerCircleSize = circleSize * 0.72
    local sweepLength = circleSize * 0.50
    local sectorSize = math.sqrt(viewportWidth * viewportWidth + viewportHeight * viewportHeight) + 16.0
    local sweepCycle = clamp(digitTime, 0.0, 1.0)
    local sweepGlow = (1.0 - sweepCycle) * (1.0 - sweepCycle)
    local sweepColor = "#4b351d"
    if sweepCycle < 0.16 then
        sweepColor = "#fff1c2"
    elseif sweepCycle < 0.42 then
        sweepColor = "#c99b55"
    elseif sweepCycle < 0.72 then
        sweepColor = "#7a552d"
    end
    local digitWidth = (digitText == "START" and 520.0 or 190.0) * uiScale
    local digitFontSize = (digitText == "START" and 92.0 or 150.0) * uiScale
    local digitBoxHeight = (digitText == "START" and 100.0 or 164.0) * uiScale
    local digitLeft = centerX - digitWidth * 0.5
    local digitTop = contentCenterY - digitBoxHeight * 0.5
    local filmWidth = clamp(92.0 * uiScale, 36.0, math.max(36.0, viewportWidth * 0.12))
    local filmEdgeWidth = clamp(3.0 * uiScale, 1.0, 5.0)
    local frameHeight = clamp(42.0 * uiScale, 16.0, math.max(16.0, viewportHeight * 0.08))
    local crossThickness = clamp(3.0 * uiScale, 1.0, 6.0)
    local sweepGlowWidth = clamp(17.0 * uiScale, 6.0, 28.0)
    local sweepWidth = clamp(7.0 * uiScale, 2.0, 12.0)
    local leaderWidth = 336.0 * uiScale
    local leaderHeight = 28.0 * uiScale
    local leaderTop = math.max(frameHeight + 6.0 * uiScale, contentCenterY - circleSize * 0.5 - 46.0 * uiScale)

    setCountdownProperty(countdown, "screen", "left", "0px")
    setCountdownProperty(countdown, "screen", "top", "0px")
    setCountdownProperty(countdown, "screen", "width", px(viewportWidth))
    setCountdownProperty(countdown, "screen", "height", px(viewportHeight))
    setCountdownNumber(countdown, digitText)
    setCountdownOpacity(countdown, "screen", masterOpacity)
    setCountdownRect(countdown, "gate", 0.0, 0.0, viewportWidth, viewportHeight)
    setCountdownOpacity(countdown, "gate", masterOpacity)
    updateSweepSector(countdown, centerX, contentCenterY, sectorSize, sweepCycle, (0.24 + flash * 0.08) * masterOpacity)
    setCountdownRect(countdown, "flicker", 0.0, 0.0, viewportWidth, viewportHeight)
    setCountdownOpacity(countdown, "flicker", flash * 0.20 + (1.0 - framePulse) * 0.08)
    setCountdownRect(countdown, "film-left", 0.0, 0.0, filmWidth, viewportHeight)
    setCountdownRect(countdown, "film-right", viewportWidth - filmWidth, 0.0, filmWidth, viewportHeight)
    setCountdownRect(countdown, "film-left-edge", filmWidth, 0.0, filmEdgeWidth, viewportHeight)
    setCountdownRect(countdown, "film-right-edge", viewportWidth - filmWidth - filmEdgeWidth, 0.0, filmEdgeWidth, viewportHeight)
    setCountdownOpacity(countdown, "film-left", 0.44 * masterOpacity)
    setCountdownOpacity(countdown, "film-right", 0.44 * masterOpacity)
    setCountdownOpacity(countdown, "film-left-edge", 0.30 * masterOpacity)
    setCountdownOpacity(countdown, "film-right-edge", 0.30 * masterOpacity)
    updateFilmSprockets(countdown, t, viewportWidth, viewportHeight, masterOpacity, jitterY, uiScale, filmWidth)
    setCountdownRect(countdown, "film-noise", 0.0, -24.0 + ((math.floor(t * 18.0) % 5) - 2), viewportWidth, viewportHeight + 48.0)
    setCountdownOpacity(countdown, "film-noise", (0.18 + 0.10 * (math.floor(t * 11.0) % 2)) * masterOpacity)
    setCountdownRect(countdown, "grain-a", 0.0, 0.0, viewportWidth, viewportHeight)
    setCountdownRect(countdown, "grain-b", 0.0, 0.0, viewportWidth, viewportHeight)
    setCountdownOpacity(countdown, "grain-a", grainPulse * masterOpacity)
    setCountdownOpacity(countdown, "grain-b", (0.12 - grainPulse * 0.35) * masterOpacity)
    setCountdownRect(countdown, "vignette", 0.0, 0.0, viewportWidth, viewportHeight)
    setCountdownOpacity(countdown, "vignette", 0.36 * masterOpacity)
    setCountdownRect(countdown, "frame-top", 0.0, 0.0, viewportWidth, frameHeight)
    setCountdownRect(countdown, "frame-bottom", 0.0, viewportHeight - frameHeight, viewportWidth, frameHeight)
    setCountdownOpacity(countdown, "frame-top", 0.46 * masterOpacity)
    setCountdownOpacity(countdown, "frame-bottom", 0.46 * masterOpacity)
    setCountdownRect(countdown, "scanline", 0.0, scanTop, viewportWidth, (3.0 + flash * 8.0) * uiScale)
    setCountdownOpacity(countdown, "scanline", (0.07 + flash * 0.13) * masterOpacity)
    setCountdownRect(countdown, "scratch-a", scratchLeftA, 0.0, math.max(1.0, 2.0 * uiScale), viewportHeight)
    setCountdownRect(countdown, "scratch-b", scratchLeftB, 0.0, math.max(1.0, 1.0 * uiScale), viewportHeight)
    setCountdownOpacity(countdown, "scratch-a", (0.12 + flash * 0.14) * masterOpacity)
    setCountdownOpacity(countdown, "scratch-b", 0.09 * masterOpacity)
    setCountdownRect(countdown, "outer-circle", centerX - circleSize * 0.5, contentCenterY - circleSize * 0.5, circleSize, circleSize)
    setCountdownRect(countdown, "inner-circle", centerX - innerCircleSize * 0.5, contentCenterY - innerCircleSize * 0.5, innerCircleSize, innerCircleSize)
    setCountdownRect(countdown, "cross-h", centerX - circleSize * 0.56, contentCenterY - crossThickness * 0.5, circleSize * 1.12, crossThickness)
    setCountdownRect(countdown, "cross-v", centerX - crossThickness * 0.5, contentCenterY - circleSize * 0.56, crossThickness, circleSize * 1.12)
    setCountdownRect(countdown, "sweep-glow", centerX - sweepGlowWidth * 0.5, contentCenterY - sweepLength, sweepGlowWidth, sweepLength)
    setCountdownProperty(countdown, "sweep-glow", "transform-origin", string.format("%.0fpx %.0fpx", sweepGlowWidth * 0.5, sweepLength))
    setCountdownProperty(countdown, "sweep-glow", "transform", string.format("rotate(%.1fdeg)", sweepAngle))
    setCountdownOpacity(countdown, "sweep-glow", (0.52 * sweepGlow + flash * 0.16) * masterOpacity)
    setCountdownRect(countdown, "sweep", centerX - sweepWidth * 0.5, contentCenterY - sweepLength, sweepWidth, sweepLength)
    setCountdownProperty(countdown, "sweep", "transform-origin", string.format("%.0fpx %.0fpx", sweepWidth * 0.5, sweepLength))
    setCountdownProperty(countdown, "sweep", "transform", string.format("rotate(%.1fdeg)", sweepAngle))
    setCountdownProperty(countdown, "sweep", "background-color", sweepColor)
    setCountdownOpacity(countdown, "sweep", (0.30 + 0.42 * sweepGlow) * masterOpacity)
    setCountdownProperty(countdown, "leader-text", "left", px(centerX - leaderWidth * 0.5))
    setCountdownProperty(countdown, "leader-text", "top", px(leaderTop))
    setCountdownProperty(countdown, "leader-text", "width", px(leaderWidth))
    setCountdownProperty(countdown, "leader-text", "height", px(leaderHeight))
    setCountdownProperty(countdown, "leader-text", "font-size", px(22.0 * uiScale))
    setCountdownProperty(countdown, "leader-text", "line-height", px(leaderHeight))
    setCountdownProperty(countdown, "leader-text", "opacity", scalar(0.84 * masterOpacity))
    setText(countdown, "leader-text", string.format("PICTURE START // %s", digitText))
    setCountdownProperty(countdown, "countdown-number-cyan", "left", px(digitLeft - 2.0))
    setCountdownProperty(countdown, "countdown-number-pink", "left", px(digitLeft + 3.0))
    setCountdownProperty(countdown, "countdown-number-main", "left", px(digitLeft))
    setCountdownProperty(countdown, "countdown-number-cyan", "top", px(digitTop))
    setCountdownProperty(countdown, "countdown-number-pink", "top", px(digitTop + 3.0))
    setCountdownProperty(countdown, "countdown-number-main", "top", px(digitTop))
    setCountdownProperty(countdown, "countdown-number-cyan", "width", px(digitWidth))
    setCountdownProperty(countdown, "countdown-number-pink", "width", px(digitWidth))
    setCountdownProperty(countdown, "countdown-number-main", "width", px(digitWidth))
    setCountdownProperty(countdown, "countdown-number-cyan", "height", px(digitBoxHeight))
    setCountdownProperty(countdown, "countdown-number-pink", "height", px(digitBoxHeight))
    setCountdownProperty(countdown, "countdown-number-main", "height", px(digitBoxHeight))
    setCountdownProperty(countdown, "countdown-number-cyan", "font-size", px(digitFontSize))
    setCountdownProperty(countdown, "countdown-number-pink", "font-size", px(digitFontSize))
    setCountdownProperty(countdown, "countdown-number-main", "font-size", px(digitFontSize))
    setCountdownProperty(countdown, "countdown-number-cyan", "line-height", px(digitBoxHeight))
    setCountdownProperty(countdown, "countdown-number-pink", "line-height", px(digitBoxHeight))
    setCountdownProperty(countdown, "countdown-number-main", "line-height", px(digitBoxHeight))
    setCountdownOpacity(countdown, "countdown-number-cyan", (0.08 + digitPulse * 0.10) * masterOpacity)
    setCountdownOpacity(countdown, "countdown-number-pink", (0.12 + digitPulse * 0.08) * masterOpacity)
    setCountdownOpacity(countdown, "countdown-number-main", (0.82 + flash * 0.10) * masterOpacity)
    setCountdownRect(countdown, "flash", 0.0, 0.0, viewportWidth, viewportHeight)
    setCountdownOpacity(countdown, "flash", flash * 0.22 * masterOpacity)
end

local function showFilmCountdown()
    local d = getDirector()
    if d == nil then return end

    removeAllWidgets()
    d:ResumeGame()

    local countdown = createWidget("Countdown", getCountdownWidgetPath(d), false, 400)
    if countdown == nil then
        print("[GameFlow] Countdown widget unavailable. Starting HUD immediately.")
        if startHudFlow ~= nil then
            startHudFlow()
        end
        return
    end

    addToViewport(countdown, 400)
    currentScreen = "Countdown"
    filmCountdownTime = 0.0
    updateFilmCountdown(0.0)
end

local function showStartMenu()
    local d = getDirector()
    if d == nil then return end

    removeAllWidgets()
    d:ResumeGame()
    playFlowBGM(FLOW_BGM.StartMenu)

    local menu = createWidget("StartMenu", d:GetStartMenuWidgetPath(), true, 100)
    if menu ~= nil then
        menu:bind_click("btn-story-boss", function()
            d:StartStoryBoss()
        end)
        menu:bind_click("btn-training", function()
            local sceneName = "TrainingMap"
            if d.GetTrainingSceneName ~= nil then
                sceneName = d:GetTrainingSceneName()
            end
            print("[GameFlow] Training button clicked -> " .. tostring(sceneName))
            TutorialDirector.QueueTrainingSession(sceneName)
            d:StartTraining()
        end)
        menu:bind_click("btn-credits", function()
            d:RequestCredits()
        end)
        menu:bind_click("btn-exit", function()
            d:ExitGame()
        end)
    end
    addToViewport(menu, 100)
    currentScreen = "StartMenu"
    startStartMenuBoot(menu)
    printStartMenuHotkeyHelp()
end

local function applyStartMenuHotkeys()
    if TEST_HOTKEYS_ENABLED ~= true or currentScreen ~= "StartMenu" or Input == nil or Key == nil or Input.GetKeyDown == nil then
        return
    end

    local replayKey = Key[START_MENU_BOOT_REPLAY_KEY_NAME]
    if replayKey ~= nil and Input.GetKeyDown(replayKey) then
        print("[GameFlowTest] Replay start-menu TV boot")
        showStartMenu()
    end
end

local function isTrainingTutorialActive()
    if currentScreen ~= "HUD" then
        return false
    end
    if TutorialDirector.IsRunning ~= nil and TutorialDirector.IsRunning() == true then
        return true
    end
    return TutorialDirector.IsFreePlay ~= nil and TutorialDirector.IsFreePlay() == true
end

local function showTrainingExitConfirm()
    if isTrainingTutorialActive() ~= true or TutorialDirector.ShowExitConfirm == nil then
        return false
    end
    return TutorialDirector.ShowExitConfirm()
end

local function cancelTrainingExitConfirm()
    if TutorialDirector.HideExitConfirm == nil then
        return false
    end
    return TutorialDirector.HideExitConfirm()
end

local function leaveTrainingForMainMenu()
    local d = getDirector()
    if d == nil then
        return
    end

    if TutorialDirector.EndSession ~= nil then
        TutorialDirector.EndSession()
    else
        TutorialDirector.End()
    end

    removeWidget("TutorialHUD")
    d:ResumeGame()
    d:RequestMainMenu()
end

local function handleTrainingEscape()
    if TutorialDirector.IsExitConfirmVisible ~= nil and TutorialDirector.IsExitConfirmVisible() == true then
        cancelTrainingExitConfirm()
        return true
    end

    return showTrainingExitConfirm()
end

local function applyTrainingExitConfirmHotkeys()
    if TutorialDirector.IsExitConfirmVisible == nil or TutorialDirector.IsExitConfirmVisible() ~= true then
        return false
    end
    if Input == nil or Input.GetKeyDown == nil then
        return true
    end

    if Input.GetKeyDown(KEY_ENTER) then
        leaveTrainingForMainMenu()
    end
    return true
end

local function hidePauseMenu()
    local d = getDirector()
    removeWidget("Pause")
    if d ~= nil then
        d:ResumeGame()
    end
    if widgets.HUD ~= nil then
        currentScreen = "HUD"
    end
end

local function showPauseMenu()
    local d = getDirector()
    if d == nil then return end

    local pause = createWidget("Pause", d:GetPauseMenuWidgetPath(), true, 200)
    if pause ~= nil then
        pause:bind_click("btn-resume", function()
            hidePauseMenu()
        end)
        pause:bind_click("btn-restart", function()
            d:RestartCombatScene()
        end)
        pause:bind_click("btn-main-menu", function()
            d:RequestMainMenu()
        end)
        pause:bind_click("btn-exit", function()
            d:ExitGame()
        end)
    end
    addToViewport(pause, 200)
    d:PauseGame()
    currentScreen = "Pause"
end

local function togglePauseMenu()
    if widgets.Pause ~= nil then
        hidePauseMenu()
    elseif currentScreen == "HUD" then
        showPauseMenu()
    end
end

local function showGameOver()
    local d = getDirector()
    if d == nil then return end

    removeAllWidgets()
    d:ResumeGame()

    local screen = createWidget("GameOver", d:GetGameOverWidgetPath(), true, 100)
    if screen ~= nil then
        screen:bind_click("btn-retry", function()
            d:RestartCombatScene()
        end)
        screen:bind_click("btn-main-menu", function()
            d:RequestMainMenu()
        end)
        screen:bind_click("btn-exit", function()
            d:ExitGame()
        end)
    end
    addToViewport(screen, 100)
    currentScreen = "GameOver"
end

local function showClear()
    local d = getDirector()
    if d == nil then return end

    removeAllWidgets()
    d:ResumeGame()
    clearToCreditsTime = 0.0

    local screen = createWidget("Clear", d:GetClearWidgetPath(), true, 100)
    if screen ~= nil then
        screen:bind_click("btn-credits", function()
            if showCredits ~= nil then
                showCredits()
            else
                d:RequestCredits()
            end
        end)
        screen:bind_click("btn-main-menu", function()
            d:RequestMainMenu()
        end)
        screen:bind_click("btn-exit", function()
            d:ExitGame()
        end)
    end
    addToViewport(screen, 100)
    currentScreen = "Clear"
end

local function updateClearOutro(dt)
    if currentScreen ~= "Clear" then
        return
    end

    clearToCreditsTime = clearToCreditsTime + (dt or 0.0)
    if clearToCreditsTime >= CLEAR_TO_CREDITS_DELAY and showCredits ~= nil then
        showCredits()
    end
end

local function setCreditsRect(widget, id, left, top, width, height)
    setCountdownRect(widget, id, left, top, width, height)
end

local function setCreditsOpacity(widget, id, value)
    setCountdownOpacity(widget, id, value)
end

local function setCreditsProperty(widget, id, property, value)
    setCountdownProperty(widget, id, property, value)
end

local function setCreditsTextBox(widget, id, top, height, fontSize, rollWidth, uiScale)
    setCreditsRect(widget, id, 0.0, top * uiScale, rollWidth, height * uiScale)
    setCreditsProperty(widget, id, "font-size", px(fontSize * uiScale))
    setCreditsProperty(widget, id, "line-height", px(height * uiScale))
end

local function updateCreditsRoll(dt)
    local credits = widgets.Credits
    if credits == nil then
        return
    end

    creditsRollTime = creditsRollTime + (dt or 0.0)
    local viewportWidth, viewportHeight, centerX, _ = getStartMenuBootViewport()
    local uiScale = clamp(math.min(viewportWidth / 1280.0, viewportHeight / 720.0), 0.55, 1.45)
    local rollWidth = clamp(800.0 * uiScale, 430.0, math.max(430.0, viewportWidth * 0.78))
    local rollHeight = CREDITS_ROLL_END_OFFSET * uiScale
    local rollStart = viewportHeight + CREDITS_ROLL_START_PADDING * uiScale
    local rollEnd = viewportHeight * 0.42 - 994.0 * uiScale
    local p = clamp(creditsRollTime / CREDITS_ROLL_DURATION, 0.0, 1.0)
    local eased = p * p * (3.0 - 2.0 * p)
    local rollTop = lerp(rollStart, rollEnd, eased)
    local buttonFade = clamp((creditsRollTime - CREDITS_ROLL_DURATION + 1.2) / 1.2, 0.0, 1.0)
    local scanTop = (math.floor(creditsRollTime * 20.0) % 18) * viewportHeight / 18.0

    setCreditsRect(credits, "screen", 0.0, 0.0, viewportWidth, viewportHeight)
    setCreditsRect(credits, "backdrop", 0.0, 0.0, viewportWidth, viewportHeight)
    setCreditsRect(credits, "shade", 0.0, 0.0, viewportWidth, viewportHeight)
    setCreditsRect(credits, "roll-window", centerX - rollWidth * 0.5, 0.0, rollWidth, viewportHeight)
    setCreditsRect(credits, "roll-track", 0.0, rollTop, rollWidth, rollHeight)
    setCreditsRect(credits, "fade-top", 0.0, 0.0, viewportWidth, 150.0 * uiScale)
    setCreditsRect(credits, "fade-bottom", 0.0, viewportHeight - 180.0 * uiScale, viewportWidth, 180.0 * uiScale)
    setCreditsRect(credits, "scanline", 0.0, scanTop, viewportWidth, math.max(1.0, 3.0 * uiScale))
    setCreditsTextBox(credits, "title-cyan", 0.0, 56.0, 44.0, rollWidth, uiScale)
    setCreditsTextBox(credits, "title-pink", 0.0, 56.0, 44.0, rollWidth, uiScale)
    setCreditsTextBox(credits, "title-main", 0.0, 56.0, 44.0, rollWidth, uiScale)
    setCreditsProperty(credits, "title-cyan", "left", px(-3.0 * uiScale))
    setCreditsProperty(credits, "title-pink", "left", px(3.0 * uiScale))
    setCreditsTextBox(credits, "subtitle", 70.0, 28.0, 20.0, rollWidth, uiScale)
    setCreditsRect(credits, "roll-line-a", rollWidth * 0.5 - 150.0 * uiScale, 126.0 * uiScale, 300.0 * uiScale, math.max(1.0, 2.0 * uiScale))
    setCreditsRect(credits, "roll-line-b", rollWidth * 0.5 - 80.0 * uiScale, 142.0 * uiScale, 160.0 * uiScale, math.max(1.0, 2.0 * uiScale))

    setCreditsTextBox(credits, "role-01", 212.0, 24.0, 17.0, rollWidth, uiScale)
    setCreditsTextBox(credits, "name-01", 240.0, 46.0, 32.0, rollWidth, uiScale)
    setCreditsTextBox(credits, "role-02", 346.0, 24.0, 17.0, rollWidth, uiScale)
    setCreditsTextBox(credits, "name-02", 374.0, 46.0, 32.0, rollWidth, uiScale)
    setCreditsTextBox(credits, "role-03", 480.0, 24.0, 17.0, rollWidth, uiScale)
    setCreditsTextBox(credits, "name-03", 508.0, 46.0, 32.0, rollWidth, uiScale)
    setCreditsTextBox(credits, "role-04", 614.0, 24.0, 17.0, rollWidth, uiScale)
    setCreditsTextBox(credits, "name-04", 642.0, 46.0, 32.0, rollWidth, uiScale)
    setCreditsTextBox(credits, "thanks-a", 800.0, 26.0, 18.0, rollWidth, uiScale)
    setCreditsTextBox(credits, "thanks-b", 832.0, 26.0, 18.0, rollWidth, uiScale)
    setCreditsTextBox(credits, "end-title", 930.0, 58.0, 42.0, rollWidth, uiScale)
    setCreditsTextBox(credits, "end-sub", 994.0, 28.0, 18.0, rollWidth, uiScale)

    setCreditsOpacity(credits, "control-panel", buttonFade)
    setCreditsProperty(credits, "control-panel", "display", buttonFade > 0.02 and "block" or "none")
    setCreditsOpacity(credits, "skip-hint", clamp(1.0 - buttonFade, 0.0, 0.68))
end

showCredits = function()
    local d = getDirector()
    if d == nil then return end

    removeAllWidgets()
    d:ResumeGame()
    creditsRollTime = 0.0

    local screen = createWidget("Credits", d:GetCreditsWidgetPath(), true, 100)
    if screen ~= nil then
        setCreditsOpacity(screen, "control-panel", 0.0)
        setCreditsProperty(screen, "control-panel", "display", "none")
        screen:bind_click("btn-main-menu", function()
            d:RequestMainMenu()
        end)
        screen:bind_click("btn-exit", function()
            d:ExitGame()
        end)
    end
    addToViewport(screen, 100)
    currentScreen = "Credits"
    updateCreditsRoll(0.0)
end

local function updateHud()
    local d = getDirector()
    local hud = widgets.HUD
    if d == nil or hud == nil then
        return
    end

    local bossHP, bossMaxHP = CombatContext.GetBossHP()
    if bossMaxHP ~= nil and bossMaxHP > 0.0 then
        d:SetBossHP(bossHP, bossMaxHP)
    else
        bossHP = d:GetBossHP()
        bossMaxHP = d:GetBossMaxHP()
    end

    if hasRegisteredPlayer() then
        local playerHP, playerMaxHP = CombatContext.GetPlayerHP()
        d:SetPlayerHP(playerHP, playerMaxHP)
    end

    if hasRegisteredPlayer() then
        local ultimate, ultimateMax = CombatContext.GetPlayerUltimate()
        d:SetUltimateGauge(ultimate, ultimateMax)
    end

    if hasRegisteredPlayer() then
        local combo = CombatContext.GetPlayerCombo()
        d:SetComboCount(combo)
    end

    local playerHP = d:GetPlayerHP()
    local playerMaxHP = d:GetPlayerMaxHP()
    local syncedBossHP = d:GetBossHP()
    local syncedBossMaxHP = d:GetBossMaxHP()
    local ultimate = d:GetUltimateGauge()
    local ultimateMax = d:GetUltimateMaxGauge()
    local combo = d:GetComboCount()
    local dashCooldownRemaining, dashCooldownDuration = getDashCooldownStats()

    setText(hud, "player-hp-text", "HP " .. whole(playerHP) .. "/" .. whole(playerMaxHP))
    setText(hud, "player-state", percent(playerHP, playerMaxHP) .. "% STRUCT | " .. dashCooldownText(dashCooldownRemaining, dashCooldownDuration))
    setText(hud, "boss-hp-text", "CORE " .. whole(syncedBossHP) .. "/" .. whole(syncedBossMaxHP))
    setText(hud, "boss-sub", syncedBossHP <= 0.0 and "CORE LOST" or "HOSTILE CORE")
    setText(hud, "ultimate-text", "BURST " .. percent(ultimate, ultimateMax) .. "%")
    setText(hud, "ultimate-sub", ultimate >= ultimateMax and "READY" or "CHARGE")
    local comboText = string.format("%02d CHAIN", combo)
    setText(hud, "combo-cyan", comboText)
    setText(hud, "combo-pink", comboText)
    setText(hud, "combo-text", comboText)
    setText(hud, "combo-readout", combo > 0 and ("x" .. tostring(combo)) or "FLOW")

    setBar(hud, "player-hp-fill", playerHP, playerMaxHP)
    setBar(hud, "boss-hp-fill", syncedBossHP, syncedBossMaxHP)
    setBar(hud, "ultimate-fill", ultimate, ultimateMax)
    setBar(hud, "combo-fill", combo, 12.0)
end

local function updateTerminalFlow()
    if currentScreen ~= "HUD" then
        return
    end

    local d = getDirector()
    if d == nil then
        return
    end

    if d.HasReachedTerminalState ~= nil and d:HasReachedTerminalState() then
        local state = d:GetBossGameState()
        local phase = state ~= nil and state:GetFlowPhase() or ""
        if phase == "GameOver" then
            showGameOver()
        elseif phase == "Clear" then
            showClear()
        end
        return
    end

    if d.IsCombatActive ~= nil and d:IsCombatActive() ~= true then
        return
    end

    if d:GetPlayerHP() <= 0.0 then
        d:RequestGameOver()
        showGameOver()
    elseif d:GetBossHP() <= 0.0 then
        d:RequestClear()
        showClear()
    end
end

function BeginPlay()
    local d = getDirector()
    if d == nil then
        print("[GameFlow] No GameFlowDirector found.")
        return
    end

    Engine.SetOnEscape(function()
        if handleTrainingEscape() ~= true then
            togglePauseMenu()
        end
    end)

    local startup = d:GetStartupScreen()
    if startup == "StartMenu" then
        showStartMenu()
    elseif startup == "HUD" then
        startHudFlow()
    elseif startup == "Countdown" or startup == "FilmCountdown" then
        showFilmCountdown()
    elseif startup == "GameOver" then
        showGameOver()
    elseif startup == "Clear" then
        showClear()
    elseif startup == "Credits" then
        showCredits()
    else
        currentScreen = "None"
    end
end

function Tick(dt)
    if currentScreen == "HUD" then
        if applyTrainingExitConfirmHotkeys() == true then
            TutorialDirector.Tick(dt, widgets.TutorialHUD)
            return
        end
        applyTestHotkeys()
        updateHud()
        TutorialDirector.Tick(dt, widgets.TutorialHUD)
        updateTerminalFlow()
    elseif currentScreen == "StartMenu" then
        applyStartMenuHotkeys()
        updateStartMenuBoot(dt)
    elseif currentScreen == "Countdown" then
        updateFilmCountdown(dt)
    elseif currentScreen == "Clear" then
        updateClearOutro(dt)
    elseif currentScreen == "Credits" then
        updateCreditsRoll(dt)
    end
end

function EndPlay()
    TutorialDirector.End()
    if Engine.ClearOnEscape ~= nil then
        Engine.ClearOnEscape()
    else
        Engine.SetOnEscape(function()
        end)
    end
    removeAllWidgets()
    stopFlowBGM()
    director = nil
    currentScreen = "None"
end
