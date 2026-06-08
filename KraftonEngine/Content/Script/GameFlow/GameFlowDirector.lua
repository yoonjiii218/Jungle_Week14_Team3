local CombatContext = require("CombatContext")

local widgets = {}
local director = nil
local currentScreen = "None"
local TEST_HOTKEYS_ENABLED = true
local TEST_PLAYER_DAMAGE = 10.0
local TEST_BOSS_DAMAGE = 10.0
local TEST_ULTIMATE_DELTA = 25.0
local START_MENU_BOOT_REPLAY_KEY_NAME = "F9"
local START_MENU_BOOT_DURATION = 1.35
local START_MENU_BOOT_BASE_WIDTH = 1280.0
local START_MENU_BOOT_BASE_HEIGHT = 720.0
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

    local staticBase = flashPulse(t, 0.08, 0.22, 0.44) + flashPulse(t, 0.28, 0.30, 0.32) + flashPulse(t, 0.60, 0.26, 0.16)
    local staticPhase = math.floor(t * 24.0) % 2
    local staticA = staticPhase == 0 and staticBase or staticBase * 0.38
    local staticB = staticPhase == 1 and staticBase * 0.76 or staticBase * 0.22
    local noiseA = flashPulse(t, 0.12, 0.05, 0.34) + flashPulse(t, 0.39, 0.07, 0.20)
    local noiseB = flashPulse(t, 0.20, 0.07, 0.28) + flashPulse(t, 0.54, 0.08, 0.14)
    local noiseC = flashPulse(t, 0.31, 0.05, 0.20) + flashPulse(t, 0.64, 0.06, 0.12)
    local noiseSlot = math.floor(t * 47.0)
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
    setBootProperty(menu, "boot-noise-a", "height", px(lerp(4.0, 28.0, noiseA)))
    setBootProperty(menu, "boot-noise-a", "left", "0px")
    setBootProperty(menu, "boot-noise-a", "width", px(viewportWidth))
    setBootProperty(menu, "boot-noise-b", "opacity", scalar(noiseB))
    setBootProperty(menu, "boot-noise-b", "top", px(noiseBTop))
    setBootProperty(menu, "boot-noise-b", "height", px(lerp(4.0, 22.0, noiseB)))
    setBootProperty(menu, "boot-noise-b", "left", "0px")
    setBootProperty(menu, "boot-noise-b", "width", px(viewportWidth))
    setBootProperty(menu, "boot-noise-c", "opacity", scalar(noiseC))
    setBootProperty(menu, "boot-noise-c", "top", px(noiseCTop))
    setBootProperty(menu, "boot-noise-c", "height", px(lerp(4.0, 18.0, noiseC)))
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

    local hud = createWidget("HUD", d:GetHudWidgetPath(), false, 0)
    addToViewport(hud, 0)
    currentScreen = "HUD"
    printTestHotkeyHelp()
end

local function showStartMenu()
    local d = getDirector()
    if d == nil then return end

    removeAllWidgets()
    d:ResumeGame()

    local menu = createWidget("StartMenu", d:GetStartMenuWidgetPath(), true, 100)
    if menu ~= nil then
        menu:bind_click("btn-story-boss", function()
            d:StartStoryBoss()
        end)
        menu:bind_click("btn-training", function()
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

    local screen = createWidget("Clear", d:GetClearWidgetPath(), true, 100)
    if screen ~= nil then
        screen:bind_click("btn-credits", function()
            d:RequestCredits()
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

local function showCredits()
    local d = getDirector()
    if d == nil then return end

    removeAllWidgets()
    d:ResumeGame()

    local screen = createWidget("Credits", d:GetCreditsWidgetPath(), true, 100)
    if screen ~= nil then
        screen:bind_click("btn-main-menu", function()
            d:RequestMainMenu()
        end)
        screen:bind_click("btn-exit", function()
            d:ExitGame()
        end)
    end
    addToViewport(screen, 100)
    currentScreen = "Credits"
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

    setText(hud, "player-hp-text", "VITAL FIELD")
    setText(hud, "boss-hp-text", "TARGET INTEGRITY")
    setText(hud, "ultimate-text", "SIGNAL BURST")
    local comboText = "CHAIN"
    setText(hud, "combo-cyan", comboText)
    setText(hud, "combo-pink", comboText)
    setText(hud, "combo-text", comboText)

    setBar(hud, "player-hp-fill", d:GetPlayerHP(), d:GetPlayerMaxHP())
    setBar(hud, "boss-hp-fill", d:GetBossHP(), d:GetBossMaxHP())
    setBar(hud, "ultimate-fill", d:GetUltimateGauge(), d:GetUltimateMaxGauge())
    setBar(hud, "combo-fill", d:GetComboCount(), 12.0)
end

function BeginPlay()
    local d = getDirector()
    if d == nil then
        print("[GameFlow] No GameFlowDirector found.")
        return
    end

    Engine.SetOnEscape(function()
        togglePauseMenu()
    end)

    local startup = d:GetStartupScreen()
    if startup == "StartMenu" then
        showStartMenu()
    elseif startup == "HUD" then
        d:StartCombat()
        showHud()
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
        applyTestHotkeys()
        updateHud()
    elseif currentScreen == "StartMenu" then
        applyStartMenuHotkeys()
        updateStartMenuBoot(dt)
    end
end

function EndPlay()
    if Engine.ClearOnEscape ~= nil then
        Engine.ClearOnEscape()
    else
        Engine.SetOnEscape(function()
        end)
    end
    removeAllWidgets()
    director = nil
    currentScreen = "None"
end
