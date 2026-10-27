local ADDON_NAME, ns = ...

local UnitXP, UnitXPMax, UnitLevel, GetXPExhaustion = UnitXP, UnitXPMax, UnitLevel, GetXPExhaustion
local exp, min, max, abs, floor, ceil = math.exp, math.min, math.max, math.abs, math.floor, math.ceil

--------------------------------------------------------------------------------
-- Config (layout matches the Luxthos Experience Bar WeakAura; colours live in Themes.lua)
--------------------------------------------------------------------------------

local barWidth, barHeight = 600, 30 -- current size, follows db.width / db.height
local BASE_HEIGHT = 30 -- text sizes and offsets below are for this height and scale with it
local MIN_WIDTH, MAX_WIDTH, MIN_HEIGHT, MAX_HEIGHT = 200, 1600, 16, 60
local TEX = "Interface\\Buttons\\WHITE8x8"
local FONT = "Fonts\\FRIZQT__.TTF"
local LAYOUT_VERSION = 2 -- bump to reset saved positions when the layout changes

local ANIM = {
    rate      = 6,      -- exponential approach rate, higher = snappier
    hold      = 0.20,   -- seconds the gain highlight shows before the fill chases it
    overshoot = 0.04,   -- aim past 100% on level-up so the ease-out does not crawl into the wrap
    epsilon   = 0.0005, -- snap threshold, in bar fractions
    flash     = 0.6,    -- level-up flash duration
    idleFPS   = 30,     -- update rate once the bar and liquid have settled (idle wobble only)
    bigGain   = 0.08,   -- gain (fraction of a level) that gets the full splash
}

local SESSION_MAX_AGE = 86400 * 3

-- Saved in SmoothExperienceBarDB. Everything except point/layout is on the settings page.
local DEFAULTS = {
    point = { "TOP", "UIParent", "TOP", 0, -40 },
    theme = "luxthos",
    scale = 0.65,
    width = 600,
    height = 30,
    locked = true,
    showMaxLevel = false,
    hideBlizzardBar = false,

    showLevelTime = true,
    showSessionTime = true,
    showXPHour = true,
    showQuestRested = true,
    resetOnReload = false,

    speed = 1,
    waves = true,
    swirl = true,
    bubbles = true,
    sparkles = true,
    flash = true,
}

--------------------------------------------------------------------------------
-- Helpers
--------------------------------------------------------------------------------

local function Round1(v)
    return floor(v * 10 + 0.5) / 10
end

local function FormatNumber(n)
    n = floor(n + 0.5)
    if FormatLargeNumber then return FormatLargeNumber(n) end
    local s = tostring(n)
    local k
    repeat
        s, k = s:gsub("^(-?%d+)(%d%d%d)", "%1,%2")
    until k == 0
    return s
end

local function FormatTime(t)
    if t <= 59 then return "< 1m" end
    local d = floor(t / 86400)
    local h = floor(t % 86400 / 3600)
    local m = floor(t % 3600 / 60)
    if d > 0 then
        return string.format("%dd %dh %dm", d, h, m)
    elseif h > 0 then
        return string.format("%dh %dm", h, m)
    end
    return m .. "m"
end

--------------------------------------------------------------------------------
-- Frame
--------------------------------------------------------------------------------

local db, cdb = DEFAULTS, nil -- db is replaced by the saved variables on ADDON_LOADED
local theme = ns.Themes.Get(DEFAULTS.theme)

local bar = CreateFrame("Frame", "SmoothExperienceBarFrame", UIParent)
bar:SetSize(barWidth, barHeight)
bar:SetScale(DEFAULTS.scale)
bar:SetFrameStrata("LOW")
bar:SetClampedToScreen(true)
bar:SetMovable(true)
bar:SetResizable(true)
if bar.SetResizeBounds then
    bar:SetResizeBounds(MIN_WIDTH, MIN_HEIGHT, MAX_WIDTH, MAX_HEIGHT)
end
bar:EnableMouse(true) -- right-click opens settings even while locked
bar:RegisterForDrag("LeftButton")

local bg = bar:CreateTexture(nil, "BACKGROUND")
bg:SetAllPoints()
bg:SetTexture(TEX)

local function Segment(sublevel)
    local t = bar:CreateTexture(nil, "ARTWORK", nil, sublevel)
    t:SetTexture(TEX)
    t:SetPoint("TOPLEFT")
    t:SetPoint("BOTTOMLEFT")
    return t
end

local restedTex = Segment(0)
local questTex  = Segment(1)
local leadTex   = Segment(2)
local liquid    = ns.Liquid.New(bar, barWidth, barHeight, theme, db)

local flash = bar:CreateTexture(nil, "OVERLAY", nil, 2)
flash:SetAllPoints()
flash:SetTexture(TEX)
flash:SetBlendMode("ADD")
flash:SetAlpha(0)

local texts = {}

-- size and y offset are for BASE_HEIGHT; ApplyTextSize rescales them for the current height.
local function Text(size, point, relPoint, x, y)
    local fs = bar:CreateFontString(nil, "OVERLAY")
    fs:SetDrawLayer("OVERLAY", 7)
    fs:SetShadowColor(0, 0, 0, 1)
    fs:SetShadowOffset(1, -1)
    fs:SetTextColor(1, 1, 1, 1)
    texts[#texts + 1] = { fs = fs, size = size, point = point, relPoint = relPoint, x = x, y = y }
    return fs
end

local function ApplyTextSize()
    local k = min(1.6, max(0.6, barHeight / BASE_HEIGHT))
    for _, t in ipairs(texts) do
        t.fs:SetFont(FONT, floor(t.size * k + 0.5), "OUTLINE")
        t.fs:SetPoint(t.point, bar, t.relPoint, t.x, t.y * k)
    end
end

local levelText   = Text(16, "LEFT", "LEFT", 5, 0)
local xpText      = Text(14, "CENTER", "CENTER", 0, 0)
local pctText     = Text(16, "RIGHT", "RIGHT", -5, 0)
local levelInText = Text(14, "LEFT", "BOTTOMLEFT", 0, -18)
local qrText      = Text(14, "RIGHT", "BOTTOMRIGHT", 0, -18)
local levelTime   = Text(14, "TOPLEFT", "TOPLEFT", 0, 24)
local sessionTime = Text(14, "TOPRIGHT", "TOPRIGHT", 0, 24)
ApplyTextSize()

-- Shown while unlocked: an outline and a corner grip for resizing.
local unlockFrame = CreateFrame("Frame", nil, bar)
unlockFrame:SetAllPoints()
unlockFrame:SetFrameLevel(bar:GetFrameLevel() + 5)
unlockFrame:Hide()

for _, side in ipairs({ { "TOPLEFT", "TOPRIGHT" }, { "BOTTOMLEFT", "BOTTOMRIGHT" },
                        { "TOPLEFT", "BOTTOMLEFT" }, { "TOPRIGHT", "BOTTOMRIGHT" } }) do
    local line = unlockFrame:CreateTexture(nil, "OVERLAY")
    line:SetColorTexture(1, 0.82, 0, 0.8)
    line:SetPoint(side[1])
    line:SetPoint(side[2])
    if side[1]:find("TOP") and side[2]:find("TOP") or side[1]:find("BOTTOM") and side[2]:find("BOTTOM") then
        line:SetHeight(2)
    else
        line:SetWidth(2)
    end
end

local grip = CreateFrame("Frame", nil, unlockFrame)
grip:SetSize(16, 16)
grip:SetPoint("BOTTOMRIGHT", 2, -2)
grip:EnableMouse(true)
local gripTex = grip:CreateTexture(nil, "OVERLAY")
gripTex:SetAllPoints()
gripTex:SetTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up")
grip:SetScript("OnEnter", function() gripTex:SetTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Highlight") end)
grip:SetScript("OnLeave", function() gripTex:SetTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up") end)

local function Place(tex, x, w)
    if w < 0.5 then
        tex:Hide()
        return
    end
    tex:SetPoint("TOPLEFT", x, 0)
    tex:SetPoint("BOTTOMLEFT", x, 0)
    tex:SetWidth(w)
    tex:Show()
end

local function ApplyTheme()
    theme = ns.Themes.Get(db.theme)
    bg:SetVertexColor(unpack(theme.bg))
    restedTex:SetVertexColor(unpack(theme.rested))
    questTex:SetVertexColor(unpack(theme.quest))
    leadTex:SetVertexColor(unpack(theme.lead))
    flash:SetVertexColor(unpack(theme.flash))
    liquid:SetTheme(theme)
end

--------------------------------------------------------------------------------
-- Data
--------------------------------------------------------------------------------

local questXP = 0
local sim -- table while /seb test is active, nil for live data
local maxed = false -- at max level with "Show at Max Level" on

local function GetData()
    if sim then
        return sim.level, sim.cur, sim.max, sim.quest, sim.rested
    end
    return UnitLevel("player"), UnitXP("player"), max(UnitXPMax("player") or 1, 1), questXP, GetXPExhaustion() or 0
end

local function MaxLevel()
    return (GetMaxPlayerLevel and GetMaxPlayerLevel()) or MAX_PLAYER_LEVEL or 70
end

local IsQuestComplete = (C_QuestLog and C_QuestLog.IsComplete) or IsQuestComplete

-- Selecting entries fires QUEST_LOG_UPDATE, so scans we trigger ourselves are ignored briefly.
local ignoreQuestUpdatesUntil = 0

local function ScanQuestXP()
    if not GetQuestLogRewardXP then return 0 end
    local total, reselected = 0, false
    local previous = GetQuestLogSelection and GetQuestLogSelection()
    for i = 1, GetNumQuestLogEntries() do
        local _, _, _, isHeader, _, isComplete, _, questID = GetQuestLogTitle(i)
        local complete = isComplete == 1 or isComplete == true
            or (questID and questID > 0 and IsQuestComplete and IsQuestComplete(questID))
        if not isHeader and complete then
            local xp = questID and GetQuestLogRewardXP(questID)
            if not xp or xp == 0 then
                -- Older signature only reads the selected entry.
                SelectQuestLogEntry(i)
                reselected = true
                xp = GetQuestLogRewardXP()
            end
            total = total + (xp or 0)
        end
    end
    if reselected then
        if previous and previous > 0 then SelectQuestLogEntry(previous) end
        ignoreQuestUpdatesUntil = GetTime() + 0.5
    end
    return total
end

--------------------------------------------------------------------------------
-- Session stats: time this level, time this session, XP/hour
--------------------------------------------------------------------------------

local played = { level = 0, total = 0, at = 0 } -- /played times and when we received them
local requestingPlayed, mutedChatFrames = false, {}

local function ResetSession()
    cdb.startTime = time()
    cdb.gainedXP = 0
    cdb.lastXP = UnitXP("player")
    cdb.maxXP = UnitXPMax("player")
end

-- Ask for /played without printing it to chat.
local function RequestPlayed()
    if requestingPlayed then return end
    requestingPlayed = true
    for i = 1, NUM_CHAT_WINDOWS or 10 do
        local cf = _G["ChatFrame" .. i]
        if cf and cf:IsEventRegistered("TIME_PLAYED_MSG") then
            cf:UnregisterEvent("TIME_PLAYED_MSG")
            mutedChatFrames[cf] = true
        end
    end
    C_Timer.After(0.5, RequestTimePlayed)
end

local function RestoreChatFrames()
    for cf in pairs(mutedChatFrames) do
        cf:RegisterEvent("TIME_PLAYED_MSG")
    end
    wipe(mutedChatFrames)
end

local function UpdateSessionTexts()
    if not (cdb and cdb.startTime) then return end
    local now = time()
    local level, cur, mx = GetData()
    local since = played.at > 0 and now - played.at or 0

    levelTime:SetShown(db.showLevelTime)
    sessionTime:SetShown(db.showSessionTime)
    levelInText:SetShown(db.showXPHour and not maxed)
    qrText:SetShown(db.showQuestRested and not maxed)

    if maxed then
        levelTime:SetText("Time played: " .. FormatTime(played.at > 0 and since + played.total or 0))
    else
        levelTime:SetText("Time this level: " .. FormatTime(played.at > 0 and since + played.level or 0))
    end

    local elapsed = now - cdb.startTime
    sessionTime:SetText("Time this session: " .. FormatTime(elapsed))

    local hourly, toLevel = 0, 0
    if elapsed > 0 and cdb.gainedXP > 0 then
        hourly = ceil(cdb.gainedXP / (elapsed / 3600))
        toLevel = ceil((mx - cur) / hourly * 3600)
    end
    local hourlyText = hourly > 10000 and (Round1(hourly / 1000) .. "K") or FormatNumber(hourly)
    levelInText:SetFormattedText("Leveling in: %s (%s XP/Hour)", toLevel > 0 and FormatTime(toLevel) or "--", hourlyText)
end

--------------------------------------------------------------------------------
-- Animation
--------------------------------------------------------------------------------

-- Displayed state (A) chases target state (T). All bar values are fractions of the displayed level.
local A = { ready = false, fill = 0, lead = 0, quest = 0, rested = 0, wraps = 0, hold = 0, flash = 0, level = 0, maxXP = 1 }
local animating, idleAcc = false, 0
local T = { level = 0, cur = 0, max = 1, quest = 0, rested = 0 }

local function Approach(cur, target, dt, rate)
    local d = target - cur
    if abs(d) < ANIM.epsilon then return target end
    return cur + d * (1 - exp(-rate * dt))
end

local function FillTarget()
    if A.wraps > 0 then return 1 end
    return T.cur / T.max
end

local shown = {}

local function RenderText(force)
    local fill, quest = A.fill, A.quest
    if not force and shown.fill == fill and shown.quest == quest and shown.level == A.level and shown.max == A.maxXP then
        return
    end
    shown.fill, shown.quest, shown.level, shown.max = fill, quest, A.level, A.maxXP

    levelText:SetText("Level " .. A.level)
    if maxed then
        xpText:SetText("Max Level")
        pctText:SetText("")
        return
    end

    local xp = floor(fill * A.maxXP + 0.5)
    xpText:SetFormattedText("%s / %s (%s)", FormatNumber(xp), FormatNumber(A.maxXP), FormatNumber(A.maxXP - xp))

    if quest > 0 then
        pctText:SetFormattedText("%s%% (%s%%)", Round1(fill * 100), Round1((fill + quest) * 100))
    else
        pctText:SetFormattedText("%s%%", Round1(fill * 100))
    end

    qrText:SetFormattedText("Completed: |cFF%s%s%%|r - Rested: |cFF%s%s%%|r",
        theme.questText, Round1(T.quest / T.max * 100), theme.restedText, Round1(T.rested / T.max * 100))
end

local function RenderBar()
    local fillW = A.fill * barWidth
    Place(leadTex, fillW, (A.lead - A.fill) * barWidth)

    -- Overlays sit after the fill and clip at the bar end.
    local questW = min(A.quest, 1 - A.fill) * barWidth
    Place(questTex, fillW, questW)
    Place(restedTex, fillW + questW, min(A.rested, max(0, 1 - A.fill - A.quest)) * barWidth)

    flash:SetAlpha(A.flash * 0.35)
    RenderText()
end

-- Advance the fill toward its target; the liquid reacts to however the fill moves.
local function StepFill(dt)
    local wrapping = A.wraps > 0
    local target = FillTarget()

    if A.hold > 0 then
        A.hold = A.hold - dt
    else
        -- Several pending level-ups speed the sweep up so it never feels stuck.
        local rate = ANIM.rate * db.speed * (1 + max(0, A.wraps - 1) * 0.5)
        A.fill = Approach(A.fill, wrapping and 1 + ANIM.overshoot or target, dt, rate)
    end

    if wrapping and A.fill >= 1 then
        A.wraps = A.wraps - 1
        A.level = A.level + 1
        A.fill, A.flash, A.pourEnd = 0, db.flash and 1 or 0, nil
        if A.wraps == 0 then
            A.level, A.maxXP = T.level, T.max
        end
        A.lead = FillTarget()
        A.hold = 0.08
        wrapping = A.wraps > 0
        target = FillTarget()
        liquid:Snap(0)
        liquid:LevelUp()
    end
    if A.fill > 1 then A.fill = 1 end
    if A.lead < A.fill then A.lead = A.fill end

    local questTarget = wrapping and 0 or T.quest / T.max
    if A.pourEnd then
        -- Turned-in quest XP: the orange is consumed exactly as the liquid flows into it.
        A.quest = max(questTarget, A.pourEnd - A.fill)
        A.pourTime = A.pourTime - dt
        if A.quest == questTarget or (A.pourTime <= 0 and A.fill == target) then A.pourEnd = nil end
    else
        A.quest = Approach(A.quest, questTarget, dt, ANIM.rate * db.speed)
    end
    A.rested = Approach(A.rested, wrapping and 0 or T.rested / T.max, dt, ANIM.rate * db.speed)
    if A.flash > 0 then A.flash = max(0, A.flash - dt / ANIM.flash) end

    if not wrapping and A.hold <= 0 and A.fill == target and A.flash == 0
        and A.quest == T.quest / T.max and A.rested == T.rested / T.max then
        A.lead = A.fill
        animating = false
    end
end

-- Runs while the bar is shown. Once everything has settled only the idle wobble remains,
-- so it drops to ANIM.idleFPS.
local function OnUpdate(self, elapsed)
    if not animating and liquid:IsQuiet() then
        idleAcc = idleAcc + elapsed
        if idleAcc < 1 / ANIM.idleFPS then return end
        elapsed, idleAcc = idleAcc, 0
    end
    if elapsed <= 0 then return end
    local dt = min(elapsed, 0.1) -- loading-screen hitches should not teleport the bar

    if animating then StepFill(dt) end
    liquid:Update(dt, A.fill * barWidth)
    RenderBar()
end

local function Refresh()
    local level, cur, mx, quest, rested = GetData()

    local wasMaxed = maxed
    maxed = not sim and level >= MaxLevel()
    if maxed then
        if not db.showMaxLevel then
            bar:Hide()
            return
        end
        cur, mx, quest, rested = 1, 1, 0, 0 -- a full bottle
    end
    bar:Show()
    if maxed ~= wasMaxed then UpdateSessionTexts() end

    if not A.ready or level < T.level or maxed ~= wasMaxed then
        T.level, T.cur, T.max, T.quest, T.rested = level, cur, mx, quest, rested
        A.level, A.maxXP, A.wraps, A.hold, A.flash = level, mx, 0, 0, 0
        A.fill, A.quest, A.rested = cur / mx, quest / mx, rested / mx
        A.lead = A.fill
        A.ready, animating, A.pourEnd = true, false, nil
        liquid:Snap(A.fill * barWidth)
        RenderBar()
        RenderText(true)
        return
    end

    -- XP already wrapped but UnitLevel has not caught up; the delayed PLAYER_LEVEL_UP refresh handles it.
    if level == T.level and cur < T.cur then return end

    local gained
    if level > T.level then
        gained = (T.max - T.cur) + cur + (level - T.level - 1) * mx
        A.wraps = A.wraps + (level - T.level)
    else
        gained = cur - T.cur
    end
    local questDrop = T.quest - quest
    local questPx = A.quest * barWidth

    T.level, T.cur, T.max, T.quest, T.rested = level, cur, mx, quest, rested
    if A.wraps == 0 then
        A.level, A.maxXP = level, mx
    end

    local target = FillTarget()
    if target > A.lead + ANIM.epsilon then
        A.lead = target
        A.hold = ANIM.hold
    elseif target < A.lead then
        A.lead = max(target, A.fill)
    end

    if gained > 0 then
        -- sqrt so a single mob kill still ripples, while a big turn-in gets the full splash.
        local edge = A.fill * barWidth
        liquid:Splash(min(1, (gained / mx / ANIM.bigGain) ^ 0.5), edge, A.lead * barWidth)
    end

    -- Turn-in XP and the quest log change arrive as separate events in either order, so hold the
    -- orange where it is until the liquid reaches it (or give up, e.g. for an abandoned quest).
    if questDrop > 0 and A.wraps == 0 then
        local edge = A.fill * barWidth
        liquid:Absorb(edge, edge + questPx, min(1, questDrop / mx / ANIM.bigGain))
        A.pourEnd = A.pourEnd or (A.fill + A.quest)
        A.pourTime = 1.5
    end

    animating = true
    RenderText(true)
end

local function ResetAnimation()
    A.ready = false
    Refresh()
end

--------------------------------------------------------------------------------
-- Test mode, so the animation can be tuned without grinding
--------------------------------------------------------------------------------

local function SimGain(amount)
    sim.cur = sim.cur + amount
    sim.rested = max(0, sim.rested - amount)
    while sim.cur >= sim.max do
        sim.cur = sim.cur - sim.max
        sim.level = sim.level + 1
        sim.max = floor(sim.max * 1.08)
    end
    Refresh()
end

local function StartSim()
    if sim then return end
    local level, cur, mx, quest, rested = GetData()
    sim = { level = level, cur = cur, max = mx, quest = quest, rested = rested }
end

--------------------------------------------------------------------------------
-- Position / lock
--------------------------------------------------------------------------------

local function ApplyPosition()
    local p = db.point
    bar:ClearAllPoints()
    bar:SetPoint(p[1], _G[p[2]] or UIParent, p[3], p[4], p[5])
end

local function SavePosition()
    local point, _, relPoint, x, y = bar:GetPoint()
    db.point = { point, "UIParent", relPoint, x, y }
end

local function ApplyLock()
    unlockFrame:SetShown(not db.locked)
    if db.locked then GameTooltip:Hide() end
end

local function ApplyScale()
    bar:SetScale(db.scale)
end

-- Everything that depends on the bar size; also runs live while the grip is dragged.
local function OnBarResized(w, h)
    barWidth, barHeight = w, h
    liquid:SetSize(w, h)
    liquid:Snap(A.fill * w)
    ApplyTextSize()
    RenderBar()
end

local function ApplySize()
    db.width = min(MAX_WIDTH, max(MIN_WIDTH, db.width))
    db.height = min(MAX_HEIGHT, max(MIN_HEIGHT, db.height))
    bar:SetSize(db.width, db.height)
    OnBarResized(db.width, db.height)
end

bar:SetScript("OnSizeChanged", function(_, w, h)
    if w ~= barWidth or h ~= barHeight then OnBarResized(w, h) end
end)

grip:SetScript("OnMouseDown", function(_, button)
    if button ~= "LeftButton" then return end
    -- Pin the top-left corner so the bar grows toward the cursor instead of around its anchor.
    local left, top = bar:GetLeft(), bar:GetTop()
    bar:ClearAllPoints()
    bar:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", left, top)
    bar:StartSizing("BOTTOMRIGHT")
end)

grip:SetScript("OnMouseUp", function()
    bar:StopMovingOrSizing()
    db.width, db.height = floor(bar:GetWidth() + 0.5), floor(bar:GetHeight() + 0.5)
    ApplySize()
    SavePosition()
end)

-- The default XP bar differs between clients; hide whichever of these exist.
local BLIZZARD_BARS = { "MainMenuExpBar", "StatusTrackingBarManager", "MainStatusTrackingBarContainer" }
local hookedBars, hiddenBars = {}, {}

local function ApplyBlizzardBar()
    for _, name in ipairs(BLIZZARD_BARS) do
        local f = _G[name]
        if f then
            if not hookedBars[f] then
                hookedBars[f] = true
                hooksecurefunc(f, "Show", function(self)
                    if db.hideBlizzardBar then self:Hide() end
                end)
            end
            if db.hideBlizzardBar then
                if f:IsShown() then hiddenBars[f] = true end
                f:Hide()
            elseif hiddenBars[f] then
                hiddenBars[f] = nil
                f:Show()
            end
        end
    end
end

bar:SetScript("OnDragStart", function(self)
    if not db.locked then self:StartMoving() end
end)

bar:SetScript("OnDragStop", function(self)
    self:StopMovingOrSizing()
    SavePosition()
end)

--------------------------------------------------------------------------------
-- API for the settings page
--------------------------------------------------------------------------------

local Core = {}
ns.Core = Core

local openAfterCombat = false

-- The settings panel cannot be opened safely in combat, so wait for it to end.
function Core.OpenSettings()
    if InCombatLockdown() then
        if not openAfterCombat then
            openAfterCombat = true
            bar:RegisterEvent("PLAYER_REGEN_ENABLED")
            DEFAULT_CHAT_FRAME:AddMessage("|cffa070ffSmoothXP|r Settings will open after combat.")
        end
        return true
    end
    return ns.Options.Open()
end

bar:SetScript("OnMouseUp", function(_, button)
    if button == "RightButton" then Core.OpenSettings() end
end)

bar:SetScript("OnEnter", function(self)
    if db.locked then return end
    GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
    GameTooltip:AddLine("Smooth Experience Bar")
    GameTooltip:AddLine("Drag to move", 1, 1, 1)
    GameTooltip:AddLine("Drag the corner to resize", 1, 1, 1)
    GameTooltip:AddLine("Right-click for settings", 1, 1, 1)
    GameTooltip:Show()
end)

bar:SetScript("OnLeave", function() GameTooltip:Hide() end)

local SETTING_APPLY = {
    theme = function()
        ApplyTheme()
        RenderText(true)
    end,
    scale = ApplyScale,
    width = ApplySize,
    height = ApplySize,
    locked = ApplyLock,
    showMaxLevel = function() Refresh() end,
    hideBlizzardBar = ApplyBlizzardBar,
    showLevelTime = UpdateSessionTexts,
    showSessionTime = UpdateSessionTexts,
    showXPHour = UpdateSessionTexts,
    showQuestRested = UpdateSessionTexts,
    waves = function() liquid:ApplyOptions() end,
    bubbles = function() liquid:ApplyOptions() end,
    sparkles = function() liquid:ApplyOptions() end,
}

function Core.OnSettingChanged(key)
    local apply = SETTING_APPLY[key]
    if apply then apply() end
end

function Core.ResetPosition()
    db.point = { unpack(DEFAULTS.point) }
    db.width, db.height, db.scale = DEFAULTS.width, DEFAULTS.height, DEFAULTS.scale
    ApplyScale()
    ApplySize()
    ApplyPosition()
end

function Core.ResetSession()
    ResetSession()
    UpdateSessionTexts()
end

-- Preview animations on simulated XP: "gain", "turnin", "level", "multi", "quest", "rested" or "off".
function Core.Test(kind, amount)
    if kind == "off" then
        sim = nil
        ResetAnimation()
        return
    end
    StartSim()
    if kind == "level" then
        SimGain(sim.max - sim.cur + floor(sim.max * 0.25))
    elseif kind == "multi" then
        SimGain(floor(sim.max * 2.5))
    elseif kind == "quest" then
        sim.quest = sim.quest + floor(sim.max * 0.05)
        Refresh()
    elseif kind == "turnin" then
        -- Completes a quest first if there is nothing to hand in, then turns it in a moment later.
        if sim.quest <= 0 then
            sim.quest = floor(sim.max * 0.05)
            Refresh()
            C_Timer.After(0.6, function() if sim then Core.Test("turnin") end end)
            return
        end
        local q = sim.quest
        sim.quest = 0
        SimGain(q)
    elseif kind == "rested" then
        sim.rested = sim.rested + floor(sim.max * 0.1)
        Refresh()
    else
        SimGain(amount or floor(sim.max * 0.08))
    end
end

--------------------------------------------------------------------------------
-- Events
--------------------------------------------------------------------------------

local questScanQueued = false

local function QueueQuestScan()
    if questScanQueued or GetTime() < ignoreQuestUpdatesUntil then return end
    questScanQueued = true
    C_Timer.After(0.25, function()
        questScanQueued = false
        questXP = ScanQuestXP()
        Refresh()
    end)
end

bar:SetScript("OnEvent", function(self, event, arg1, arg2)
    if event == "ADDON_LOADED" then
        if arg1 ~= ADDON_NAME then return end
        SmoothExperienceBarDB = SmoothExperienceBarDB or {}
        SmoothExperienceBarCharDB = SmoothExperienceBarCharDB or {}
        db, cdb = SmoothExperienceBarDB, SmoothExperienceBarCharDB
        if db.layout ~= LAYOUT_VERSION then
            db.point = nil
            db.layout = LAYOUT_VERSION
        end
        for k, v in pairs(DEFAULTS) do
            if db[k] == nil then
                db[k] = type(v) == "table" and { unpack(v) } or v
            end
        end
        if not ns.Themes.list[db.theme] then db.theme = DEFAULTS.theme end
        liquid:SetOptions(db)
        ApplyTheme()
        ApplyScale()
        ApplySize()
        ApplyPosition()
        ApplyLock()
        ns.Options.Register(db, DEFAULTS)
        self:UnregisterEvent("ADDON_LOADED")

    elseif event == "PLAYER_REGEN_ENABLED" then
        self:UnregisterEvent("PLAYER_REGEN_ENABLED")
        if openAfterCombat then
            openAfterCombat = false
            ns.Options.Open()
        end

    elseif event == "PLAYER_ENTERING_WORLD" then
        local isLogin, isReload = arg1, arg2
        if isLogin or (isReload and db.resetOnReload) or not cdb.startTime
            or time() - cdb.startTime >= SESSION_MAX_AGE then
            ResetSession()
        end
        ApplyBlizzardBar()
        if isLogin or isReload then
            RequestPlayed()
        end
        QueueQuestScan()
        Refresh()
        UpdateSessionTexts()

    elseif event == "TIME_PLAYED_MSG" then
        played.total, played.level, played.at = arg1 or 0, arg2 or 0, time()
        if requestingPlayed then
            requestingPlayed = false
            C_Timer.After(0.5, RestoreChatFrames)
        end
        UpdateSessionTexts()

    elseif event == "QUEST_TURNED_IN" then
        -- arg2 is the XP reward; drop it now rather than waiting for the quest log rescan.
        if arg2 and arg2 > 0 and questXP > 0 then
            questXP = max(0, questXP - arg2)
            Refresh()
        end
        QueueQuestScan()

    elseif event == "QUEST_LOG_UPDATE" then
        QueueQuestScan()

    elseif event == "PLAYER_LEVEL_UP" then
        if played.at > 0 then played.total = played.total + time() - played.at end
        played.level, played.at = 0, time()
        -- UnitLevel/UnitXPMax can lag the event by a frame.
        C_Timer.After(0.1, Refresh)

    elseif event == "PLAYER_XP_UPDATE" then
        if not cdb.startTime then ResetSession() end
        local cur = UnitXP("player")
        local gained = cur - cdb.lastXP
        if gained < 0 then
            gained = cdb.maxXP - cdb.lastXP + cur
        end
        cdb.gainedXP = cdb.gainedXP + gained
        cdb.lastXP, cdb.maxXP = cur, UnitXPMax("player")
        Refresh()

    else
        Refresh()
    end
end)

bar:RegisterEvent("ADDON_LOADED")
bar:RegisterEvent("PLAYER_ENTERING_WORLD")
bar:RegisterEvent("PLAYER_XP_UPDATE")
bar:RegisterEvent("PLAYER_LEVEL_UP")
bar:RegisterEvent("UPDATE_EXHAUSTION")
bar:RegisterEvent("PLAYER_UPDATE_RESTING")
bar:RegisterEvent("QUEST_LOG_UPDATE")
bar:RegisterEvent("QUEST_TURNED_IN")
bar:RegisterEvent("TIME_PLAYED_MSG")
bar:SetScript("OnUpdate", OnUpdate)

C_Timer.NewTicker(1, function()
    if cdb and bar:IsShown() then UpdateSessionTexts() end
end)

--------------------------------------------------------------------------------
-- Slash commands
--------------------------------------------------------------------------------

local function Print(msg)
    DEFAULT_CHAT_FRAME:AddMessage("|cffa070ffSmoothXP|r " .. msg)
end

local HELP = {
    "/seb - open settings",
    "/seb unlock | lock - move and resize the bar",
    "/seb reset - default position and size",
    "/seb session - reset session time and XP/hour",
    "/seb test [xp] - simulate an XP gain (default 8% of a level)",
    "/seb test level - simulate a level-up",
    "/seb test multi - simulate gaining 2.5 levels",
    "/seb test quest - add completed quest XP, /seb test turnin to hand it in",
    "/seb test rested - add rested XP",
    "/seb test off - back to live data",
}

SLASH_SMOOTHEXPERIENCEBAR1 = "/seb"
SlashCmdList.SMOOTHEXPERIENCEBAR = function(input)
    local cmd, arg = strsplit(" ", strlower(strtrim(input or "")), 2)

    if cmd == "" or cmd == "config" or cmd == "options" then
        if not Core.OpenSettings() then
            for _, line in ipairs(HELP) do Print(line) end
        end
    elseif cmd == "unlock" or cmd == "lock" then
        db.locked = cmd == "lock"
        ApplyLock()
        Print(db.locked and "Locked." or "Unlocked: drag to move, drag the corner to resize.")
    elseif cmd == "reset" then
        Core.ResetPosition()
    elseif cmd == "session" then
        Core.ResetSession()
        Print("Session reset.")
    elseif cmd == "test" then
        local amount = tonumber(arg)
        Core.Test(amount and "gain" or arg or "gain", amount)
        if arg == "off" then Print("Test mode off.") end
    else
        for _, line in ipairs(HELP) do Print(line) end
    end
end
