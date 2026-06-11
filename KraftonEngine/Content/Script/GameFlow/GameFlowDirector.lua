local CombatContext = require("Combat/CombatContext")
local TutorialDirector = require("Tutorial/TutorialDirector")
local GameplayEventBus = require("Core/GameplayEventBus")

local widgets = {}
local director = nil
local currentScreen = "None"
local currentFlowBgmKey = nil
local loadedFlowBgm = {}
TEST_HOTKEYS_ENABLED = true
TEST_PLAYER_DAMAGE = 10.0
TEST_BOSS_DAMAGE = 10.0
TEST_ULTIMATE_DELTA = 25.0
START_MENU_BOOT_REPLAY_KEY_NAME = "F9"
KEY_ENTER = 13
START_MENU_BOOT_DURATION = 1.50
START_MENU_BOOT_BASE_WIDTH = 1280.0
START_MENU_BOOT_BASE_HEIGHT = 720.0
FILM_COUNTDOWN_WIDGET_FALLBACK = "Content/UI/GameFlow/FilmCountdown.uasset"
FILM_COUNTDOWN_START_NUMBER = 5
FILM_COUNTDOWN_PLAY_SECONDS = 5.0
FILM_COUNTDOWN_DURATION = 5.35
pendingTransitionAction = nil
pendingTransitionSceneName = nil
pendingTransitionAsyncStarted = false
pendingTransitionAsyncUnavailable = false
pendingTransitionBeginFrameDelay = 0
isCutsceneWaitingToCommit = false
FILM_SPROCKET_COUNT = 11
FILM_SPROCKET_SPACING = 86.0
FILM_SPROCKET_SPEED = 210.0
FILM_SWEEP_SECTOR_FRAME_COUNT = 33
CLEAR_TO_CREDITS_DELAY = 2.35
CREDITS_ROLL_DURATION = 18.0
CREDITS_ROLL_START_PADDING = 120.0
CREDITS_ROLL_END_OFFSET = 1080.0
BOSS_HP_PANEL_WIDGET_PATH = "Content/UI/GameFlow/BossHPPanel.uasset"
BOSS_DAMAGE_LAG_RATIO_PER_SECOND = 0.72
COMBO_HOLD_DURATION = 3.0
COMBO_IMPACT_DURATION = 0.42
SCOREBOARD_FILE = "GameFlowScoreboard.tsv"
SCOREBOARD_MAX_ENTRIES = 10
TOKYO_AUTOSPAWN_BOSS = false
UI_AUDIO = {
    Hover = { key = "UI_ButtonHover", path = "UI/button_hover.mp3", volume = 0.55 },
    Down = { key = "UI_ButtonDown", path = "UI/button_down.mp3", volume = 0.75 },
    FilmCountdown = { key = "UI_FilmCountdown", path = "UI/Film countdown.mp3", volume = 0.95 },
    Cutscene = { key = "UI_Cutscene", path = "UI/Cutscene_sound.mp3", volume = 0.95 },
}
COMBO_IMPACT_THRESHOLDS = { 10, 30, 50, 99 }
START_MENU_BOOT_ELEMENT_IDS = {
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
local filmCountdownStartRealtime = nil
isRetryTransition = false
local clearToCreditsTime = 0.0
local creditsRollTime = CREDITS_ROLL_DURATION + 1.0
local bossHudWasVisible = false
local bossHudHP = nil
local bossDamageHP = nil
local bossDamageDelayRemaining = 0.0
local bossPanelCreateFailed = false
local comboHoldRemaining = 0.0
local lastComboCount = 0
local comboImpactTime = 0.0
local comboImpactThreshold = 0
local loadedUiAudio = {}
local combatElapsedTime = 0.0
local combatStartWorldTime = nil
local combatTimerStarted = false
local clearTimeSaved = false
local lastClearScore = nil
local lastClearEntries = nil
local wavesFinishedHandle = nil
local startHudFlow = nil
local showCredits = nil
FLOW_BGM = {
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

local function ensureUiAudio(config)
    if config == nil or AudioManager == nil or AudioManager.Load == nil then
        return false
    end
    if loadedUiAudio[config.key] == true then
        return true
    end
    if AudioManager.Load(config.key, config.path, false) ~= true then
        print("[GameFlow] Failed to load UI audio: " .. tostring(config.path))
        return false
    end
    loadedUiAudio[config.key] = true
    return true
end

local function playUiAudio(config)
    if config == nil or AudioManager == nil or AudioManager.Play == nil then
        return
    end
    if ensureUiAudio(config) ~= true then
        return
    end
    AudioManager.Play(config.key, config.volume or 1.0)
end

local function playButtonHover()
    playUiAudio(UI_AUDIO.Hover)
end

local function playButtonDown()
    playUiAudio(UI_AUDIO.Down)
end

local function bindButtonAudio(widget, buttonIds)
    if widget == nil or widget.bind_event == nil or buttonIds == nil then
        return
    end
    for _, buttonId in ipairs(buttonIds) do
        widget:bind_event(buttonId, "mouseover", playButtonHover)
        widget:bind_event(buttonId, "mousedown", playButtonDown)
    end
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

local function isGamepadUiActive()
    return Input ~= nil
        and Input.GetActionLabel ~= nil
        and Input.GetActionLabel("Dash") == "RT"
end

local function padHintLabel(baseLabel, padLabel)
    if isGamepadUiActive() == true then
        return baseLabel .. " [Pad " .. padLabel .. "]"
    end
    return baseLabel
end

local function updateStartMenuPadHints(widget)
    setText(widget, "btn-story-boss", padHintLabel("Start Game", "X"))
    setText(widget, "btn-training", padHintLabel("Training Map", "RT"))
    setText(widget, "btn-credits", padHintLabel("Credits", "Y"))
    setText(widget, "btn-exit", padHintLabel("Exit", "B"))
end

local function updateCreditsPadHints(widget)
    setText(widget, "btn-score", padHintLabel("Score", "Y"))
    setText(widget, "btn-main-menu", padHintLabel("Main Menu", "X"))
    setText(widget, "btn-exit", padHintLabel("Exit", "B"))
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

local function formatClearTime(seconds)
    local safeSeconds = math.max(0.0, seconds or 0.0)
    local minutes = math.floor(safeSeconds / 60.0)
    local remain = safeSeconds - minutes * 60.0
    return string.format("%02d:%05.2f", minutes, remain)
end

local function getWorldTimeSeconds()
    if World ~= nil and World.GetGameTime ~= nil then
        return World.GetGameTime() or nil
    end
    return nil
end

local function getRealtimeSeconds()
    if Engine ~= nil and Engine.GetRealtimeSeconds ~= nil then
        return Engine.GetRealtimeSeconds() or nil
    end
    return nil
end

local function getCombatElapsedTime()
    local elapsed = math.max(combatElapsedTime or 0.0, 0.0)
    if combatStartWorldTime ~= nil then
        local now = getWorldTimeSeconds()
        if now ~= nil then
            elapsed = math.max(elapsed, now - combatStartWorldTime)
        end
    end
    return elapsed
end

local function parseScoreboardLine(line)
    if line == nil or line == "" then
        return nil
    end

    local timeValue = string.match(line, "^%s*([^\t%s]+)")
    local seconds = tonumber(timeValue)
    if seconds == nil or seconds <= 0.0 then
        return nil
    end

    return {
        Time = seconds,
    }
end

local function loadScoreboard()
    local entries = {}
    if Engine == nil or Engine.ReadTextFile == nil then
        return entries
    end

    local content = Engine.ReadTextFile(SCOREBOARD_FILE)
    if content == nil or content == "" then
        return entries
    end

    for line in string.gmatch(content, "([^\r\n]+)") do
        local entry = parseScoreboardLine(line)
        if entry ~= nil then
            table.insert(entries, entry)
        end
    end

    table.sort(entries, function(a, b)
        return (a.Time or 0.0) < (b.Time or 0.0)
    end)
    return entries
end

local function findLatestScore(entries)
    return entries ~= nil and entries[1] or nil
end

local function saveScoreboard(entries)
    if Engine == nil or Engine.WriteTextFile == nil or entries == nil then
        return false
    end

    local lines = {}
    local count = math.min(#entries, SCOREBOARD_MAX_ENTRIES)
    for i = 1, count do
        local entry = entries[i]
        table.insert(lines, string.format("%.3f", entry.Time or 0.0))
    end

    local text = ""
    if #lines > 0 then
        text = table.concat(lines, "\n") .. "\n"
    end
    return Engine.WriteTextFile(SCOREBOARD_FILE, text) == true
end

local function recordClearScore(d)
    if clearTimeSaved == true then
        return lastClearScore, lastClearEntries or loadScoreboard()
    end

    local canRecordCurrentRun = combatTimerStarted == true
        or combatStartWorldTime ~= nil
        or (combatElapsedTime ~= nil and combatElapsedTime > 0.0)

    if canRecordCurrentRun ~= true then
        local storedTime = nil
        if Engine ~= nil and Engine.ReadTextFile ~= nil then
            local content = Engine.ReadTextFile("LastClearScore.txt")
            if content ~= nil and content ~= "" then
                storedTime = tonumber(content)
            end
        end

        local entries = loadScoreboard()
        local score = storedTime ~= nil and storedTime > 0.0 and { Time = storedTime } or nil
        if score == nil then
            print("[GameFlow] Clear time was not saved because no combat timer or stored clear time was available.")
        end

        clearTimeSaved = true
        lastClearScore = score
        lastClearEntries = entries
        return score, entries
    end

    local clearTime = getCombatElapsedTime()
    if clearTime <= 0.0 then
        clearTime = 0.001
    end

    local score = {
        Time = clearTime,
    }
    local entries = loadScoreboard()
    table.insert(entries, score)
    table.sort(entries, function(a, b)
        return (a.Time or 0.0) < (b.Time or 0.0)
    end)
    while #entries > SCOREBOARD_MAX_ENTRIES do
        table.remove(entries)
    end

    if Engine ~= nil and Engine.WriteTextFile ~= nil then
        Engine.WriteTextFile("LastClearScore.txt", string.format("%.3f", clearTime))
    end

    if saveScoreboard(entries) ~= true then
        print("[GameFlow] Failed to save clear scoreboard: " .. SCOREBOARD_FILE)
    else
        print("[GameFlow] Saved clear time: " .. formatClearTime(score.Time))
    end
    clearTimeSaved = true
    lastClearScore = score
    lastClearEntries = entries
    return score, entries
end

local function applyScoreboardToClear(screen, currentScore, entries)
    if screen == nil then
        return
    end

    entries = entries or loadScoreboard()
    setText(screen, "clear-time", "CLEAR TIME  " .. formatClearTime(currentScore ~= nil and currentScore.Time or getCombatElapsedTime()))
    for i = 1, SCOREBOARD_MAX_ENTRIES do
        local entry = entries[i]
        if entry ~= nil then
            setText(screen, "score-rank-" .. tostring(i), string.format("#%d  %s", i, formatClearTime(entry.Time)))
        else
            setText(screen, "score-rank-" .. tostring(i), string.format("#%d  --:--.--", i))
        end
    end
end

local function applyScoreboardToCredits(credits)
    if credits == nil then
        return
    end

    local d = getDirector()
    local clearScore, entries = recordClearScore(d)
    local currentText = clearScore ~= nil and formatClearTime(clearScore.Time) or "--:--.--"
    setText(credits, "score-current", "LAST CLEAR  " .. currentText)

    for i = 1, SCOREBOARD_MAX_ENTRIES do
        local entry = entries[i]
        if entry ~= nil then
            setText(credits, "score-rank-" .. tostring(i), string.format("#%d  %s", i, formatClearTime(entry.Time)))
        else
            setText(credits, "score-rank-" .. tostring(i), string.format("#%d  --:--.--", i))
        end
    end
end

local function showCreditsScoreboard(credits)
    if credits == nil then
        return
    end

    applyScoreboardToCredits(credits)
    credits:SetProperty("score-panel", "display", "block")
    credits:SetProperty("score-panel", "opacity", "1")
end

local function updateBossDamageBar(hud, hp, maxHP, dt)
    local safeMax = math.max(maxHP or 0.0, 1.0)
    local targetHP = clamp(hp or 0.0, 0.0, safeMax)
    local frameDt = math.max(dt or 0.0, 0.0)

    if bossHudWasVisible ~= true or bossHudHP == nil or bossDamageHP == nil then
        bossHudHP = targetHP
        bossDamageHP = targetHP
        bossDamageDelayRemaining = 0.0
    elseif targetHP < bossHudHP - 0.001 then
        bossDamageHP = math.max(bossDamageHP, bossHudHP)
        bossDamageDelayRemaining = 0.65
    elseif targetHP > bossHudHP + 0.001 then
        bossDamageHP = targetHP
        bossDamageDelayRemaining = 0.0
    end

    bossHudHP = targetHP
    if bossDamageHP > targetHP then
        if bossDamageDelayRemaining > 0.0 then
            bossDamageDelayRemaining = bossDamageDelayRemaining - frameDt
        else
            bossDamageHP = math.max(targetHP, bossDamageHP - safeMax * 0.24 * frameDt)
        end
    else
        bossDamageHP = targetHP
        bossDamageDelayRemaining = 0.0
    end

    setBar(hud, "boss-hp-fill", targetHP, safeMax)
    setBar(hud, "boss-hp-damage-fill", bossDamageHP, safeMax)
    bossHudWasVisible = true
end

local function hasRegisteredPlayer()
    return CombatContext.HasPlayer ~= nil and CombatContext.HasPlayer() == true
end

local function hasRegisteredBoss()
    return CombatContext.HasBoss ~= nil and CombatContext.HasBoss() == true
end

local function isValidActor(actor)
    return actor ~= nil and (actor.IsValid == nil or actor:IsValid())
end

local function hasBossActor(d)
    if d == nil or d.GetBossActor == nil then
        return false
    end
    return isValidActor(d:GetBossActor())
end

local function resetBossHudAnimation()
    bossHudWasVisible = false
    bossHudHP = nil
    bossDamageHP = nil
    bossDamageDelayRemaining = 0.0
end

local function resetComboHoldTimer()
    comboHoldRemaining = 0.0
    lastComboCount = 0
    comboImpactTime = 0.0
    comboImpactThreshold = 0
end

local function getComboImpactThreshold(previousCombo, currentCombo)
    local hitThreshold = 0
    for _, threshold in ipairs(COMBO_IMPACT_THRESHOLDS) do
        if previousCombo < threshold and currentCombo >= threshold then
            hitThreshold = threshold
        end
    end
    return hitThreshold
end

local function ensureBossPanelWidget()
    if widgets.BossPanel ~= nil then
        return widgets.BossPanel
    end
    if bossPanelCreateFailed == true then
        return nil
    end

    local panel = createWidget("BossPanel", BOSS_HP_PANEL_WIDGET_PATH, false, 1)
    if panel == nil then
        bossPanelCreateFailed = true
        return nil
    end

    addToViewport(panel, 1)
    return panel
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

local function setComboSynced(d, count)
    local safeCount = math.max(0, math.floor((count or 0) + 0.5))
    local bSetCombatContext = false
    if CombatContext.SetPlayerCombo ~= nil then
        bSetCombatContext = CombatContext.SetPlayerCombo(safeCount) == true
    end
    if d ~= nil then
        d:SetComboCount(safeCount)
    end
    return bSetCombatContext
end

local function setComboForTest(d, count)
    setComboSynced(d, count)
    if count == nil or count <= 0 then
        resetComboHoldTimer()
    end
end

local function updateComboHold(d, combo, dt)
    local currentCombo = math.max(0, math.floor((combo or 0) + 0.5))
    local frameDt = math.max(dt or 0.0, 0.0)

    if currentCombo <= 0 then
        resetComboHoldTimer()
        return 0, 0.0, 0.0
    end

    if currentCombo ~= lastComboCount then
        local impactThreshold = getComboImpactThreshold(lastComboCount, currentCombo)
        if impactThreshold > 0 then
            comboImpactThreshold = impactThreshold
            comboImpactTime = COMBO_IMPACT_DURATION
        end
        comboHoldRemaining = COMBO_HOLD_DURATION
        lastComboCount = currentCombo
    else
        comboHoldRemaining = math.max(0.0, comboHoldRemaining - frameDt)
    end

    comboImpactTime = math.max(0.0, comboImpactTime - frameDt)

    if comboHoldRemaining <= 0.0 then
        setComboSynced(d, 0)
        resetComboHoldTimer()
        return 0, 0.0, 0.0
    end

    return currentCombo, comboHoldRemaining, comboHoldRemaining / COMBO_HOLD_DURATION
end

local function updateComboImpactVisual(hud, combo)
    if hud == nil then
        return
    end

    local impactRatio = 0.0
    if comboImpactTime > 0.0 then
        impactRatio = comboImpactTime / COMBO_IMPACT_DURATION
    end

    if impactRatio > 0.0 and comboImpactThreshold > 0 then
        local pulse = 1.0 - impactRatio
        local fontSize = 36.0 + 12.0 * impactRatio
        local alpha = 0.36 + 0.46 * impactRatio
        setText(hud, "combo-impact", tostring(comboImpactThreshold))
        hud:SetProperty("combo-impact", "display", "block")
        hud:SetProperty("combo-impact", "font-size", px(fontSize))
        hud:SetProperty("combo-impact", "opacity", scalar(alpha))
        hud:SetProperty("combo-impact", "top", px(16.0 - 8.0 * impactRatio))
        hud:SetProperty("combo-impact-flash", "display", "block")
        hud:SetProperty("combo-impact-flash", "opacity", scalar(0.18 + 0.38 * impactRatio))
        hud:SetProperty("combo-impact-flash", "width", string.format("%.1f%%", 100.0 * (1.0 - pulse * 0.16)))
    else
        hud:SetProperty("combo-impact", "display", "none")
        hud:SetProperty("combo-impact-flash", "display", "none")
    end

    if combo >= 99 then
        hud:SetProperty("combo-text", "color", "#d7ff33")
        hud:SetProperty("combo-cyan", "color", "#00eaff")
        hud:SetProperty("combo-pink", "color", "#ff2bd6")
    elseif combo >= 50 then
        hud:SetProperty("combo-text", "color", "#ffffff")
        hud:SetProperty("combo-cyan", "color", "#d7ff33")
        hud:SetProperty("combo-pink", "color", "#ff2bd6")
    elseif combo >= 30 then
        hud:SetProperty("combo-text", "color", "#ffffff")
        hud:SetProperty("combo-cyan", "color", "#00eaff")
        hud:SetProperty("combo-pink", "color", "#d7ff33")
    elseif combo >= 10 then
        hud:SetProperty("combo-text", "color", "#ffffff")
        hud:SetProperty("combo-cyan", "color", "#00eaff")
        hud:SetProperty("combo-pink", "color", "#ff2bd6")
    else
        hud:SetProperty("combo-text", "color", "#ffffff")
        hud:SetProperty("combo-cyan", "color", "#00eaff")
        hud:SetProperty("combo-pink", "color", "#ff2bd6")
    end
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
    removeWidget("BossPanel")
    bossPanelCreateFailed = false
    resetBossHudAnimation()
    resetComboHoldTimer()
    combatElapsedTime = 0.0
    combatStartWorldTime = getWorldTimeSeconds()
    combatTimerStarted = true
    clearTimeSaved = false
    lastClearScore = nil
    lastClearEntries = nil

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

local function ensureTokyoBossSpawned(d)
    if TOKYO_AUTOSPAWN_BOSS ~= true or d == nil then
        return
    end
    if getCurrentSceneName(d) ~= "Tokyo_Current" then
        return
    end
    if hasRegisteredBoss() == true or hasBossActor(d) == true then
        return
    end
    if GameFlow == nil or GameFlow.SpawnTutorialBoss == nil then
        print("[GameFlow] Tokyo boss auto-spawn skipped: binding unavailable.")
        return
    end

    local spawnLocation = Vector(5.0, 0.0, 1.0)
    local player = d:GetPlayerActor()
    if isValidActor(player) then
        spawnLocation = player.Location + Vector(10.0, 0.0, 0.0)
    end

    local boss = GameFlow.SpawnTutorialBoss(spawnLocation, 180.0)
    if boss ~= nil then
        if boss.AddTag ~= nil then
            boss:AddTag("Boss")
            boss:AddTag("HitTarget")
        end
        d:SetBossHP(d:GetBossMaxHP(), d:GetBossMaxHP())
        print("[GameFlow] Tokyo boss auto-spawned for HUD/game-flow.")
    else
        print("[GameFlow] Tokyo boss auto-spawn failed.")
    end
end

startHudFlow = function()
    local d = getDirector()
    if d == nil then return end

    local bTrainingQueued = TutorialDirector.HasQueuedTrainingSession ~= nil
        and TutorialDirector.HasQueuedTrainingSession() == true
    local bTrainingMapFlow = isTrainingMapFlow(d, bTrainingQueued)

    d:StartCombat()
    ensureTokyoBossSpawned(d)
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

local function clearPendingTransition()
    pendingTransitionAction = nil
    pendingTransitionSceneName = nil
    pendingTransitionAsyncStarted = false
    pendingTransitionAsyncUnavailable = false
    pendingTransitionBeginFrameDelay = 0
    filmCountdownStartRealtime = nil
end

local function beginPendingAsyncTransition()
    if pendingTransitionSceneName == nil or pendingTransitionAsyncStarted == true then
        return true
    end

    if pendingTransitionBeginFrameDelay > 0 then
        pendingTransitionBeginFrameDelay = pendingTransitionBeginFrameDelay - 1
        return true
    end

    pendingTransitionAsyncStarted = true
    if GameFlow ~= nil and GameFlow.BeginAsyncOpenScene ~= nil then
        if GameFlow.BeginAsyncOpenScene(pendingTransitionSceneName) == true then
            return true
        end
    end

    pendingTransitionAsyncUnavailable = true
    print("[GameFlow] Async scene load unavailable. Falling back after film countdown.")
    return true
end

local function isPendingTransitionReady()
    if pendingTransitionSceneName == nil then
        return true
    end
    if pendingTransitionAsyncStarted ~= true then
        return false
    end
    if pendingTransitionAsyncUnavailable == true then
        return true
    end
    if GameFlow ~= nil and GameFlow.IsAsyncOpenSceneReady ~= nil then
        return GameFlow.IsAsyncOpenSceneReady() == true
    end
    return true
end

local function completeFilmCountdown()
    if isPendingTransitionReady() ~= true then
        print("[GameFlow-Debug] Cutscene completed but scene loading not finished yet. Waiting to commit...")
        isCutsceneWaitingToCommit = true
        local countdown = widgets.Countdown
        if countdown ~= nil then
            setText(countdown, "skip-hint", "LOADING SCENE...")
            setCountdownProperty(countdown, "skip-hint", "opacity", scalar(1.0))
        end
        return
    end

    local countdown = widgets.Countdown
    if countdown ~= nil then
        setText(countdown, "skip-hint", "LOADING SCENE...")
        setCountdownProperty(countdown, "skip-hint", "opacity", scalar(1.0))
    end

    isCutsceneWaitingToCommit = false
    filmCountdownTime = FILM_COUNTDOWN_DURATION + 1.0
    isRetryTransition = false

    if pendingTransitionSceneName ~= nil then
        local action = pendingTransitionAction
        local committed = pendingTransitionAsyncUnavailable ~= true
            and GameFlow ~= nil
            and GameFlow.CommitAsyncOpenScene ~= nil
            and GameFlow.CommitAsyncOpenScene() == true
        clearPendingTransition()
        if committed ~= true then
            removeWidget("Countdown")
        end
        currentScreen = "SceneTransition"
        if committed == true then
            return
        end
        if action ~= nil then
            action()
        end
        return
    end

    removeWidget("Countdown")

    if startHudFlow ~= nil then
        startHudFlow()
    end
end

local isCutsceneMode = false
local currentCutPage = 1
local currentCutIndex = 0
local totalPages = 2
local pageCuts = { 3, 2 }
local cutsceneCutRects = {}
local cutsceneFinishCallback = nil
local cutsceneInputCooldown = 0.0
local cutsceneRevealTime = 0.0
local cutsceneHoldTime = 0.0
local CUTSCENE_REVEAL_DURATION = 0.52
local CUTSCENE_CUT_HOLD_DURATION = 0.72
local CUTSCENE_PAGE_HOLD_DURATION = 0.92

local function getCutId(pageIndex, cutIndex)
    return string.format("cut-%d-%d", pageIndex, cutIndex)
end

local function getCoverId(pageIndex, cutIndex)
    return string.format("cover-%d-%d", pageIndex, cutIndex)
end

local function getEdgeId(pageIndex, cutIndex)
    return string.format("edge-%d-%d", pageIndex, cutIndex)
end

local function setCutReveal(countdown, pageIndex, cutIndex, progress)
    local cutId = getCutId(pageIndex, cutIndex)
    local coverId = getCoverId(pageIndex, cutIndex)
    local edgeId = getEdgeId(pageIndex, cutIndex)
    local rect = cutsceneCutRects[cutId]
    if rect == nil then
        return
    end

    progress = clamp(progress or 0.0, 0.0, 1.0)
    setCountdownProperty(countdown, cutId, "display", "block")
    setCountdownOpacity(countdown, cutId, 1.0)

    local coverWidth, coverLeft
    if pageIndex == 2 and cutIndex == 2 then
        -- Page 2, Cut 2 (5th cut): reveal starts from middle (50%) to right end (100%)
        coverWidth = rect.Width * 0.5 * (1.0 - progress)
        coverLeft = rect.Width - coverWidth
    else
        -- Default (all other cuts): reveal starts from left (0%) to right end (100%)
        coverWidth = rect.Width * (1.0 - progress)
        coverLeft = rect.Width - coverWidth
    end

    setCountdownRect(countdown, coverId, coverLeft, 0.0, coverWidth, rect.Height)
    setCountdownOpacity(countdown, coverId, progress < 1.0 and (0.96 - progress * 0.18) or 0.0)

    local edgeWidth = math.max(3.0, rect.Width * 0.008)
    local edgeLeft = math.min(rect.Width - edgeWidth, math.max(0.0, coverLeft - edgeWidth * 0.5))
    setCountdownRect(countdown, edgeId, edgeLeft, 0.0, edgeWidth, rect.Height)
    setCountdownOpacity(countdown, edgeId, progress < 1.0 and (0.35 + (1.0 - progress) * 0.45) or 0.0)
end

local function hideCut(countdown, pageIndex, cutIndex)
    local cutId = getCutId(pageIndex, cutIndex)
    local coverId = getCoverId(pageIndex, cutIndex)
    local edgeId = getEdgeId(pageIndex, cutIndex)
    local rect = cutsceneCutRects[cutId]
    setCountdownProperty(countdown, cutId, "display", "none")
    setCountdownOpacity(countdown, cutId, 0.0)
    if rect ~= nil then
        setCountdownRect(countdown, coverId, 0.0, 0.0, rect.Width, rect.Height)
    end
    setCountdownOpacity(countdown, coverId, 1.0)
    setCountdownOpacity(countdown, edgeId, 0.0)
end

local function refreshCutsceneCuts(countdown)
    if countdown == nil then
        return
    end

    for p = 1, totalPages do
        local maxCuts = pageCuts[p] or 0
        for c = 1, maxCuts do
            if p == currentCutPage and c <= currentCutIndex then
                local progress = 1.0
                if c == currentCutIndex then
                    progress = clamp(cutsceneRevealTime / CUTSCENE_REVEAL_DURATION, 0.0, 1.0)
                end
                setCutReveal(countdown, p, c, progress)
            else
                hideCut(countdown, p, c)
            end
        end
    end
end

local function showCutscenePage(countdown, pageIndex)
    for p = 1, totalPages do
        local pageId = string.format("page-%d", p)
        if p == pageIndex then
            setCountdownProperty(countdown, pageId, "display", "block")
            setCountdownProperty(countdown, pageId, "opacity", scalar(1.0))
        else
            setCountdownProperty(countdown, pageId, "display", "none")
            setCountdownProperty(countdown, pageId, "opacity", scalar(0.0))
        end
    end
end

local function finishCutscene()
    isCutsceneMode = false
    -- playUiAudio(UI_AUDIO.Down) -- Removed standard sound
    if cutsceneFinishCallback ~= nil then
        cutsceneFinishCallback()
    end
end

local function beginCutReveal(countdown, pageIndex, cutIndex)
    currentCutPage = pageIndex
    currentCutIndex = cutIndex
    -- Enable reveal transition for all cuts (including page 2, cut 2)
    cutsceneRevealTime = 0.0
    cutsceneHoldTime = 0.0
    showCutscenePage(countdown, currentCutPage)
    refreshCutsceneCuts(countdown)
    -- playUiAudio(UI_AUDIO.Hover) -- Removed cutscene-advancing sound
end

local function advanceCutscene()
    local countdown = widgets.Countdown
    if countdown == nil then
        finishCutscene()
        return
    end

    if currentCutIndex > 0 and cutsceneRevealTime < CUTSCENE_REVEAL_DURATION then
        cutsceneRevealTime = CUTSCENE_REVEAL_DURATION
        cutsceneHoldTime = 0.0
        refreshCutsceneCuts(countdown)
        return
    end

    local nextPage = currentCutPage
    local nextCutIndex = currentCutIndex + 1
    local maxCuts = pageCuts[currentCutPage] or 0

    if nextCutIndex <= maxCuts then
        beginCutReveal(countdown, nextPage, nextCutIndex)
    else
        nextPage = currentCutPage + 1
        if nextPage <= totalPages then
            -- Transition from Page 1 to Page 2 (3rd to 4th cut)
            playUiAudio(UI_AUDIO.Cutscene)
            beginCutReveal(countdown, nextPage, 1)
        else
            -- Transition from 5th cut (Page 2, Cut 2) onwards to complete loading
            playUiAudio(UI_AUDIO.Cutscene)
            finishCutscene()
        end
    end
end

local function updateCutsceneLayout(countdown, viewportWidth, viewportHeight, centerX, centerY)
    cutsceneCutRects = {}

    local maxW = viewportWidth * 0.90
    local maxH = viewportHeight * 0.90

    -- Page 1: Aspect Ratio = 1133 / 576 = 1.9670
    local page1Width = maxW
    local page1Height = maxW / 1.9670
    if page1Height > maxH then
        page1Height = maxH
        page1Width = maxH * 1.9670
    end
    local page1Left = centerX - page1Width * 0.5
    local page1Top = centerY - page1Height * 0.5

    -- Page 2: Aspect Ratio = 1024 / 576 = 1.7778
    local page2Width = maxW
    local page2Height = maxW / 1.7778
    if page2Height > maxH then
        page2Height = maxH
        page2Width = maxH * 1.7778
    end
    local page2Left = centerX - page2Width * 0.5
    local page2Top = centerY - page2Height * 0.5

    setCountdownRect(countdown, "page-1", page1Left, page1Top, page1Width, page1Height)
    setCountdownRect(countdown, "page-2", page2Left, page2Top, page2Width, page2Height)

    -- Page 1 cuts (3 cuts, side-by-side left-to-right)
    -- Widths: cutscene1 (346px), cutscene2 (454px), cutscene3 (333px). Total: 1133px
    local w1_1 = page1Width * (346 / 1133)
    local w1_2 = page1Width * (454 / 1133)
    local w1_3 = page1Width * (333 / 1133)

    setCountdownRect(countdown, "cut-1-1", 0.0, 0.0, w1_1, page1Height)
    setCountdownRect(countdown, "cut-1-2", w1_1, 0.0, w1_2, page1Height)
    setCountdownRect(countdown, "cut-1-3", w1_1 + w1_2, 0.0, w1_3, page1Height)
    cutsceneCutRects["cut-1-1"] = { Width = w1_1, Height = page1Height }
    cutsceneCutRects["cut-1-2"] = { Width = w1_2, Height = page1Height }
    cutsceneCutRects["cut-1-3"] = { Width = w1_3, Height = page1Height }

    -- Page 2 cuts (2 cuts, overlaying completely)
    -- Both occupying full page size, cut-2-2 (cut 5) overlaying cut-2-1 (cut 4)
    setCountdownRect(countdown, "cut-2-1", 0.0, 0.0, page2Width, page2Height)
    setCountdownRect(countdown, "cut-2-2", 0.0, 0.0, page2Width, page2Height)
    cutsceneCutRects["cut-2-1"] = { Width = page2Width, Height = page2Height }
    cutsceneCutRects["cut-2-2"] = { Width = page2Width, Height = page2Height }
end

local function startCutsceneMode()
    print("[GameFlow-Debug] startCutsceneMode initiated.")
    isCutsceneMode = true
    isCutsceneWaitingToCommit = false
    currentCutPage = 1
    currentCutIndex = 0
    cutsceneInputCooldown = 0.5
    cutsceneRevealTime = 0.0
    cutsceneHoldTime = 0.0
    
    local countdown = widgets.Countdown
    if countdown == nil then
        print("[GameFlow-Debug] startCutsceneMode: widgets.Countdown is nil! Bypassing.")
        completeFilmCountdown()
        return
    end

    -- Enable mouse input on the widget to allow clicks
    countdown:SetWantsMouse(true)
    countdown:bind_click("cutscene-root", function()
        print("[GameFlow-Debug] Click on cutscene-root detected.")
        if cutsceneInputCooldown <= 0.0 then
            cutsceneInputCooldown = 0.35
            advanceCutscene()
        end
    end)

    print("[GameFlow-Debug] Hiding countdown-root, showing cutscene-root")
    setCountdownProperty(countdown, "countdown-root", "display", "none")
    setCountdownProperty(countdown, "countdown-root", "opacity", scalar(0.0))

    setCountdownProperty(countdown, "cutscene-root", "display", "block")
    setCountdownProperty(countdown, "cutscene-root", "opacity", scalar(1.0))

    for p = 1, totalPages do
        local pageId = string.format("page-%d", p)
        if p == 1 then
            setCountdownProperty(countdown, pageId, "display", "block")
            setCountdownProperty(countdown, pageId, "opacity", scalar(1.0))
        else
            setCountdownProperty(countdown, pageId, "display", "none")
            setCountdownProperty(countdown, pageId, "opacity", scalar(0.0))
        end

        local maxCuts = pageCuts[p]
        for c = 1, maxCuts do
            local cutId = string.format("cut-%d-%d", p, c)
            setCountdownProperty(countdown, cutId, "display", "none")
            setCountdownProperty(countdown, cutId, "opacity", scalar(0.0))
        end
    end

    -- Apply initial layout before advancing/revealing
    local viewportWidth, viewportHeight, centerX, centerY = getStartMenuBootViewport()
    updateCutsceneLayout(countdown, viewportWidth, viewportHeight, centerX, centerY)

    advanceCutscene()
end

local function updateCutsceneReveal(countdown, dt)
    if countdown == nil then
        return
    end

    local delta = math.max(dt or 0.0, 0.0)
    if currentCutIndex <= 0 then
        advanceCutscene()
        return
    end

    if cutsceneRevealTime < CUTSCENE_REVEAL_DURATION then
        cutsceneRevealTime = math.min(CUTSCENE_REVEAL_DURATION, cutsceneRevealTime + delta)
        refreshCutsceneCuts(countdown)
        return
    end

    cutsceneHoldTime = cutsceneHoldTime + delta
    refreshCutsceneCuts(countdown)

    -- Auto-advance disabled by user request. Must click to advance.
    -- local maxCuts = pageCuts[currentCutPage] or 0
    -- local holdDuration = currentCutIndex >= maxCuts and CUTSCENE_PAGE_HOLD_DURATION or CUTSCENE_CUT_HOLD_DURATION
    -- if cutsceneHoldTime >= holdDuration then
    --     advanceCutscene()
    -- end
end

local function updateFilmCountdown(dt)
    local countdown = widgets.Countdown
    if countdown == nil then
        completeFilmCountdown()
        return
    end

    if beginPendingAsyncTransition() ~= true then
        return
    end

    if isCutsceneWaitingToCommit then
        if isPendingTransitionReady() == true then
            print("[GameFlow-Debug] Scene loading ready during wait. Committing transition now.")
            completeFilmCountdown()
        end
        return
    end

    if isCutsceneMode then
        if cutsceneInputCooldown > 0.0 then
            cutsceneInputCooldown = cutsceneInputCooldown - (dt or 0.0)
        end

        local actionStarted = false
        if cutsceneInputCooldown <= 0.0 and Input ~= nil then
            if Input.GetKeyDown ~= nil and (Input.GetKeyDown(0x01) or Input.GetKeyDown(0x20) or Input.GetKeyDown(0x0D)) then
                print("[GameFlow-Debug] Input action detected (key click).")
                actionStarted = true
            elseif Input.WasActionStarted ~= nil and (Input.WasActionStarted("Attack") or Input.WasActionStarted("Dash")) then
                print("[GameFlow-Debug] Input action detected (action mapping).")
                actionStarted = true
            end
        end

        local viewportWidth, viewportHeight, centerX, centerY = getStartMenuBootViewport()
        updateCutsceneLayout(countdown, viewportWidth, viewportHeight, centerX, centerY)

        if actionStarted then
            cutsceneInputCooldown = 0.35
            advanceCutscene()
        else
            updateCutsceneReveal(countdown, dt)
        end
        return
    end

    local realtimeSeconds = getRealtimeSeconds()
    if filmCountdownStartRealtime ~= nil and realtimeSeconds ~= nil then
        filmCountdownTime = math.max(0.0, realtimeSeconds - filmCountdownStartRealtime)
    else
        local clampedDt = math.max(dt or 0.0, 0.0)
        if clampedDt > 1.0 then
            clampedDt = 1.0
        end
        filmCountdownTime = filmCountdownTime + clampedDt
    end

    local t = filmCountdownTime
    if t >= FILM_COUNTDOWN_DURATION then
        local showCut = false
        local d = getDirector()
        if d ~= nil then
            if pendingTransitionSceneName ~= nil then
                local name = string.lower(pendingTransitionSceneName)
                if string.find(name, "storyboss") ~= nil 
                    or string.find(name, "tokyo_current") ~= nil 
                    or string.find(name, "trainingmap") ~= nil then
                    showCut = true
                end
            else
                local startup = d:GetStartupScreen()
                if startup == "Countdown" or startup == "FilmCountdown" then
                    showCut = true
                end
            end
        end

        if showCut then
            if not isCutsceneMode then
                print("[GameFlow-Debug] Entering cutscene mode immediately during loading.")
                cutsceneFinishCallback = completeFilmCountdown
                startCutsceneMode()
                return
            end
        else
            if isPendingTransitionReady() == true then
                print("[GameFlow-Debug] Countdown elapsed. Transitioning.")
                completeFilmCountdown()
                return
            end
        end
        filmCountdownTime = FILM_COUNTDOWN_DURATION - 0.001
        t = filmCountdownTime
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
    local digit = FILM_COUNTDOWN_START_NUMBER - digitIndex
    local digitTime = activeTime - digitIndex
    local digitText = tostring(digit)
    if t >= FILM_COUNTDOWN_PLAY_SECONDS then
        digitText = "START"
        digitTime = clamp((t - FILM_COUNTDOWN_PLAY_SECONDS) / (FILM_COUNTDOWN_DURATION - FILM_COUNTDOWN_PLAY_SECONDS), 0.0, 1.0)
    end

    local fadeIn = clamp(t / 0.18, 0.0, 1.0)
    local fadeOutStart = math.max(0.0, FILM_COUNTDOWN_DURATION - 0.27)
    local fadeOut = t > fadeOutStart and (1.0 - clamp((t - fadeOutStart) / 0.27, 0.0, 1.0)) or 1.0
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
    -- leader-text disabled by user request (remove PICTURE START)
    -- setCountdownProperty(countdown, "leader-text", "left", px(centerX - leaderWidth * 0.5))
    -- setCountdownProperty(countdown, "leader-text", "top", px(leaderTop))
    -- setCountdownProperty(countdown, "leader-text", "width", px(leaderWidth))
    -- setCountdownProperty(countdown, "leader-text", "height", px(leaderHeight))
    -- setCountdownProperty(countdown, "leader-text", "font-size", px(22.0 * uiScale))
    -- setCountdownProperty(countdown, "leader-text", "line-height", px(leaderHeight))
    -- setCountdownProperty(countdown, "leader-text", "opacity", scalar(0.84 * masterOpacity))
    -- setText(countdown, "leader-text", string.format("PICTURE START // %s", digitText))
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

local function triggerTransitionWithCountdown(sceneName, action)
    local d = getDirector()
    if d == nil then
        action()
        return
    end
    if sceneName == nil or sceneName == "" then
        action()
        return
    end

    stopFlowBGM()
    d:ResumeGame()
    removeWidget("StartMenu")
    removeWidget("Pause")
    removeWidget("GameOver")
    removeWidget("Clear")
    removeWidget("Credits")
    local countdown = createWidget("Countdown", getCountdownWidgetPath(d), false, 400)
    if countdown == nil then
        action()
        return
    end

    addToViewport(countdown, 400)
    widgets.Countdown = countdown
    currentScreen = "Countdown"
    pendingTransitionAction = action
    pendingTransitionSceneName = sceneName
    pendingTransitionAsyncStarted = false
    pendingTransitionBeginFrameDelay = 30
    if isRetryTransition then
        if Engine ~= nil and Engine.WriteTextFile ~= nil then
            Engine.WriteTextFile("GameFlowRetryFlag.txt", "1")
        end
        filmCountdownTime = FILM_COUNTDOWN_DURATION
        filmCountdownStartRealtime = nil
        setCountdownProperty(countdown, "countdown-root", "display", "none")
        setCountdownProperty(countdown, "cutscene-root", "display", "block")
        setCountdownProperty(countdown, "cutscene-root", "opacity", scalar(1.0))
        setText(countdown, "skip-hint", "LOADING SCENE...")
        setCountdownProperty(countdown, "skip-hint", "opacity", scalar(1.0))
    else
        filmCountdownTime = 0.0
        filmCountdownStartRealtime = getRealtimeSeconds()
        playUiAudio(UI_AUDIO.FilmCountdown)
    end
    updateFilmCountdown(0.0)
end

local function showFilmCountdown()
    local d = getDirector()
    if d == nil then return end

    stopFlowBGM()
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
    filmCountdownStartRealtime = getRealtimeSeconds()
    playUiAudio(UI_AUDIO.FilmCountdown)
    updateFilmCountdown(0.0)
end

local startStoryBossFromMenu = nil
local startTrainingFromMenu = nil

local function showStartMenu()
    local d = getDirector()
    if d == nil then return end

    removeAllWidgets()
    d:ResumeGame()
    playFlowBGM(FLOW_BGM.StartMenu)

    local menu = createWidget("StartMenu", d:GetStartMenuWidgetPath(), true, 100)
    if menu ~= nil then
        updateStartMenuPadHints(menu)
        bindButtonAudio(menu, { "btn-story-boss", "btn-training", "btn-credits", "btn-exit" })
        menu:bind_click("btn-story-boss", function()
            startStoryBossFromMenu(d)
        end)
        menu:bind_click("btn-training", function()
            startTrainingFromMenu(d)
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

startStoryBossFromMenu = function(d)
    local sceneName = "Default"
    if d.GetStoryBossSceneName ~= nil then
        sceneName = d:GetStoryBossSceneName()
    end
    triggerTransitionWithCountdown(sceneName, function()
        d:StartStoryBoss()
    end)
end

startTrainingFromMenu = function(d)
    local sceneName = "TrainingMap"
    if d.GetTrainingSceneName ~= nil then
        sceneName = d:GetTrainingSceneName()
    end
    print("[GameFlow] Training button clicked -> " .. tostring(sceneName))
    TutorialDirector.QueueTrainingSession(sceneName)
    triggerTransitionWithCountdown(sceneName, function()
        d:StartTraining()
    end)
end

local function getRetryCombatSceneName(d)
    local sceneName = nil
    if d ~= nil and d.GetRetrySceneName ~= nil then
        sceneName = d:GetRetrySceneName()
    end
    if (sceneName == nil or sceneName == "") and d ~= nil and d.GetStoryBossSceneName ~= nil then
        sceneName = d:GetStoryBossSceneName()
    end
    return sceneName ~= nil and sceneName ~= "" and sceneName or "Default"
end

local function applyStartMenuPadActions()
    if currentScreen ~= "StartMenu" or isGamepadUiActive() ~= true or Input == nil or Input.WasActionStarted == nil then
        return
    end

    local d = getDirector()
    if d == nil then return end

    if Input.WasActionStarted("Attack") then
        playButtonDown()
        startStoryBossFromMenu(d)
    elseif Input.WasActionStarted("Dash") then
        playButtonDown()
        startTrainingFromMenu(d)
    elseif Input.WasActionStarted("Ultimate") then
        playButtonDown()
        d:RequestCredits()
    elseif Input.WasActionStarted("SecondaryDash") then
        playButtonDown()
        d:ExitGame()
    end
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

local function wasPadMenuStarted()
    return isGamepadUiActive() == true
        and Input ~= nil
        and Input.WasActionStarted ~= nil
        and Input.WasActionStarted("Menu")
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
    if Input == nil then
        return true
    end

    if (Input.GetKeyDown ~= nil and Input.GetKeyDown(KEY_ENTER))
        or (isGamepadUiActive() == true and Input.WasActionStarted ~= nil and Input.WasActionStarted("Attack")) then
        playButtonDown()
        leaveTrainingForMainMenu()
    elseif wasPadMenuStarted() == true
        or (isGamepadUiActive() == true and Input.WasActionStarted ~= nil and Input.WasActionStarted("SecondaryDash")) then
        playButtonDown()
        cancelTrainingExitConfirm()
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
        bindButtonAudio(pause, { "btn-resume", "btn-restart", "btn-main-menu", "btn-exit" })
        pause:bind_click("btn-resume", function()
            hidePauseMenu()
        end)
        pause:bind_click("btn-restart", function()
            isRetryTransition = true
            triggerTransitionWithCountdown(getRetryCombatSceneName(d), function()
                d:RestartCombatScene()
            end)
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
        bindButtonAudio(screen, { "btn-retry", "btn-main-menu", "btn-exit" })
        screen:bind_click("btn-retry", function()
            isRetryTransition = true
            triggerTransitionWithCountdown(getRetryCombatSceneName(d), function()
                d:RestartCombatScene()
            end)
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

    local startup = d:GetStartupScreen()
    if startup == "Clear" or startup == "Credits" then
        if showCredits ~= nil then
            showCredits()
        else
            d:RequestCredits()
        end
    else
        currentScreen = "None"
    end
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
        updateCreditsPadHints(screen)
        bindButtonAudio(screen, { "btn-score", "btn-main-menu", "btn-exit" })
        setCreditsOpacity(screen, "control-panel", 0.0)
        setCreditsProperty(screen, "control-panel", "display", "none")
        setCreditsOpacity(screen, "score-panel", 0.0)
        setCreditsProperty(screen, "score-panel", "display", "none")
        applyScoreboardToCredits(screen)
        screen:bind_click("btn-score", function()
            showCreditsScoreboard(screen)
        end)
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

local function applyCreditsPadActions()
    if currentScreen ~= "Credits" or isGamepadUiActive() ~= true or Input == nil or Input.WasActionStarted == nil then
        return
    end
    if creditsRollTime < CREDITS_ROLL_DURATION - 1.2 then
        return
    end

    local d = getDirector()
    if d == nil then return end

    if Input.WasActionStarted("Ultimate") then
        playButtonDown()
        showCreditsScoreboard(widgets.Credits)
    elseif Input.WasActionStarted("Attack") then
        playButtonDown()
        d:RequestMainMenu()
    elseif Input.WasActionStarted("SecondaryDash") then
        playButtonDown()
        d:ExitGame()
    end
end

local function updateHud(dt)
    local d = getDirector()
    local hud = widgets.HUD
    if d == nil or hud == nil then
        return
    end
    combatElapsedTime = combatElapsedTime + math.max(dt or 0.0, 0.0)

    local hasBossInContext = hasRegisteredBoss()
    local hasBoss = hasBossInContext or hasBossActor(d)
    local bossHP = 0.0
    local bossMaxHP = 0.0
    if hasBossInContext then
        bossHP, bossMaxHP = CombatContext.GetBossHP()
        d:SetBossHP(bossHP, bossMaxHP)
    elseif hasBoss then
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
    local syncedBossHP = hasBoss and d:GetBossHP() or 0.0
    local syncedBossMaxHP = hasBoss and d:GetBossMaxHP() or 0.0
    local ultimate = d:GetUltimateGauge()
    local ultimateMax = d:GetUltimateMaxGauge()
    local combo, comboTimeRemaining, comboTimeRatio = updateComboHold(d, d:GetComboCount(), dt)
    local dashCooldownRemaining, dashCooldownDuration = getDashCooldownStats()

    setText(hud, "player-hp-text", "HP " .. whole(playerHP) .. "/" .. whole(playerMaxHP))
    setText(hud, "player-state", percent(playerHP, playerMaxHP) .. "% STRUCT | " .. dashCooldownText(dashCooldownRemaining, dashCooldownDuration))
    setText(hud, "ultimate-text", "BURST " .. percent(ultimate, ultimateMax) .. "%")
    setText(hud, "ultimate-sub", ultimate >= ultimateMax and "READY" or "CHARGE")
    local comboText = string.format("%02d CHAIN", combo)
    setText(hud, "combo-cyan", comboText)
    setText(hud, "combo-pink", comboText)
    setText(hud, "combo-text", comboText)
    setText(hud, "combo-readout", combo > 0 and string.format("%.1fs", comboTimeRemaining) or "FLOW")
    updateComboImpactVisual(hud, combo)

    setBar(hud, "player-hp-fill", playerHP, playerMaxHP)
    if hasBoss and syncedBossMaxHP > 0.0 then
        local bossPanel = ensureBossPanelWidget()
        if bossPanel ~= nil then
            setText(bossPanel, "boss-title-cyan", "ASCENDANT")
            setText(bossPanel, "boss-title-pink", "ASCENDANT")
            setText(bossPanel, "boss-title-main", "ASCENDANT")
            setText(bossPanel, "boss-hp-text", "CORE " .. whole(syncedBossHP) .. "/" .. whole(syncedBossMaxHP))
            setText(bossPanel, "boss-sub", syncedBossHP <= 0.0 and "CORE LOST" or "HOSTILE CORE")
            updateBossDamageBar(bossPanel, syncedBossHP, syncedBossMaxHP, dt)
        end
    else
        removeWidget("BossPanel")
        bossPanelCreateFailed = false
        resetBossHudAnimation()
    end
    setBar(hud, "ultimate-fill", ultimate, ultimateMax)
    setBar(hud, "combo-fill", comboTimeRatio, 1.0)
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
            recordClearScore(d)
            showClear()
        end
        return
    end

    if d.IsCombatActive ~= nil and d:IsCombatActive() ~= true then
        return
    end

    local hasBoss = CombatContext.HasBoss ~= nil and CombatContext.HasBoss()
    if not hasBoss then
        local bossMaxHP = d:GetBossMaxHP()
        hasBoss = bossMaxHP ~= nil and bossMaxHP > 0.0
    end

    if d:GetPlayerHP() <= 0.0 then
        d:RequestGameOver()
        showGameOver()
    elseif hasBoss and d:GetBossHP() <= 0.0 then
        recordClearScore(d)
        d:RequestClear()
        showClear()
    end
end

local function handleWavesFinished(eventData)
    if currentScreen ~= "HUD" then
        return
    end

    local d = getDirector()
    if d == nil then
        return
    end

    print("[GameFlow] Waves finished. Request clear.")
    recordClearScore(d)
    d:RequestClear()
    showClear()
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

    if wavesFinishedHandle == nil then
        wavesFinishedHandle = GameplayEventBus.Subscribe("WavesFinished", obj, handleWavesFinished)
    end

    local isRetry = false
    if Engine ~= nil and Engine.ReadTextFile ~= nil and Engine.WriteTextFile ~= nil then
        local flag = Engine.ReadTextFile("GameFlowRetryFlag.txt")
        if flag == "1" then
            isRetry = true
            Engine.WriteTextFile("GameFlowRetryFlag.txt", "0")
            print("[GameFlow-Debug] Startup: Detected retry flag. Skipping countdown.")
        end
    end

    local startup = d:GetStartupScreen()
    if isRetry then
        startHudFlow()
    elseif startup == "StartMenu" then
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
    if wasPadMenuStarted() == true then
        if handleTrainingEscape() ~= true then
            togglePauseMenu()
        end
        return
    end

    if currentScreen == "HUD" then
        if applyTrainingExitConfirmHotkeys() == true then
            TutorialDirector.Tick(dt, widgets.TutorialHUD)
            return
        end
        applyTestHotkeys()
        updateHud(dt)
        TutorialDirector.Tick(dt, widgets.TutorialHUD)
        updateTerminalFlow()
    elseif currentScreen == "StartMenu" then
        applyStartMenuHotkeys()
        updateStartMenuPadHints(widgets.StartMenu)
        applyStartMenuPadActions()
        updateStartMenuBoot(dt)
    elseif currentScreen == "Countdown" then
        updateFilmCountdown(dt)
    elseif currentScreen == "Clear" then
        updateClearOutro(dt)
    elseif currentScreen == "Credits" then
        updateCreditsPadHints(widgets.Credits)
        applyCreditsPadActions()
        updateCreditsRoll(dt)
    end
end

function EndPlay()
    TutorialDirector.End()
    if wavesFinishedHandle ~= nil then
        GameplayEventBus.Unsubscribe(wavesFinishedHandle)
        wavesFinishedHandle = nil
    end
    if Engine.ClearOnEscape ~= nil then
        Engine.ClearOnEscape()
    else
        Engine.SetOnEscape(function()
        end)
    end
    removeAllWidgets()
    stopFlowBGM()
    clearPendingTransition()
    director = nil
    currentScreen = "None"
end
