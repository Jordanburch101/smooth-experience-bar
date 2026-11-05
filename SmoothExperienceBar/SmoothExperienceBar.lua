local ADDON_NAME, ns = ...

local UnitXP, UnitXPMax, UnitLevel, GetXPExhaustion = UnitXP, UnitXPMax, UnitLevel, GetXPExhaustion
local exp, min, max, abs, floor, ceil = math.exp, math.min, math.max, math.abs, math.floor, math.ceil

--------------------------------------------------------------------------------
-- Config (layout matches the Luxthos Experience Bar WeakAura; colours live in Themes.lua)
--------------------------------------------------------------------------------

local barWidth, barHeight = 600, 30 -- starting size of a view; each keeps its own (main follows db.width / db.height)
local BASE_HEIGHT = 30 -- text sizes and offsets below are for this height and scale with it
local MIN_WIDTH, MAX_WIDTH, MIN_HEIGHT, MAX_HEIGHT = 200, 1600, 16, 60
-- Game files by path are unreliable on Forever, so solid fills use SetColorTexture, textures are the
-- addon's own TGAs, and the font is taken from a game font object.
local MEDIA = "Interface\\AddOns\\SmoothExperienceBar\\Media\\"
local FONT = (GameFontNormal and GameFontNormal:GetFont()) or "Fonts\\FRIZQT__.TTF"
local LAYOUT_VERSION = 2 -- bump to reset saved positions when the layout changes

local ANIM = {
    rate      = 6,      -- exponential approach rate, higher = snappier
    spring    = 1.7,    -- the fill and rested pour on a spring this many times the rate
    hold      = 0.20,   -- seconds the gain highlight shows before the fill chases it
    overshoot = 0.04,   -- aim past 100% on level-up so the ease-out does not crawl into the wrap
    epsilon   = 0.0005, -- snap threshold, in bar fractions
    flash     = 0.6,    -- level-up flash duration
    idleFPS   = 30,     -- update rate once the bar and liquid have settled (idle wobble only)
    bigGain   = 0.08,   -- gain (fraction of a level) that gets the full splash
}

local SESSION_MAX_AGE = 86400 * 3

-- Saved per character, as that character's profile in SmoothExperienceBarDB.profiles (keyed
-- "Name - Realm"), so any character can copy another's. Everything except point/layout is on the
-- settings page.
local DEFAULTS = {
    point = { "TOP", "UIParent", "TOP", 0, -40 },
    theme = "luxthos",
    scale = 0.65,
    width = 600,
    height = 30,
    locked = true,
    showMaxLevel = false,
    hideBlizzardBar = false,
    showBar = true,         -- the separate bar
    skinDefaultBar = false, -- the bar drawn over the game's own XP bar

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
    ambient = true,
    lightning = true,
    restedGlow = false,
    glass = false,
    rounding = false,
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

local function Print(msg)
    DEFAULT_CHAT_FRAME:AddMessage("|cffa070ffSmoothXP|r " .. msg)
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

-- A view is one drawing of the bar: the separate bar (main), and the one drawn over the game's own XP
-- bar (skin, Use Default Experience Bar). Either or both can be shown. They share the XP and the
-- animation state below; each has its own size, liquid and text.
local views = {}
local main, skin
-- The game's XP bar the skin view is drawn over, and the fill in it whose rect it covers.
local skinTarget, skinFill

-- The text lines. size and y offset are for BASE_HEIGHT; ApplyTextSize rescales them for the view's
-- height. around marks the lines outside the bar, which the skin view leaves out: the default bar has
-- the action bars right under it and its end caps over its ends.
local TEXTS = {
    { name = "levelText",   size = 16, point = "LEFT",     relPoint = "LEFT",        x = 5,  y = 0 },
    { name = "xpText",      size = 14, point = "CENTER",   relPoint = "CENTER",      x = 0,  y = 0 },
    { name = "pctText",     size = 16, point = "RIGHT",    relPoint = "RIGHT",       x = -5, y = 0 },
    { name = "levelInText", size = 14, point = "LEFT",     relPoint = "BOTTOMLEFT",  x = 0,  y = -18, around = true },
    { name = "qrText",      size = 14, point = "RIGHT",    relPoint = "BOTTOMRIGHT", x = 0,  y = -18, around = true },
    { name = "levelTime",   size = 14, point = "TOPLEFT",  relPoint = "TOPLEFT",     x = 0,  y = 24,  around = true },
    { name = "sessionTime", size = 14, point = "TOPRIGHT", relPoint = "TOPRIGHT",    x = 0,  y = 24,  around = true },
}

-- A view may also carry its own look, for the setup wizard's previews: themeKey (a theme of its own),
-- opts (its own effect settings, rounding included) and textMode ("all" or "none": the lines around
-- the bar regardless of the settings). Without them it follows the settings.
local function NewView(frame, width, height, skinned)
    local v = { frame = frame, width = width, height = height, skinned = skinned, rounded = false, texts = {},
                theme = theme }

    v.bg = frame:CreateTexture(nil, "BACKGROUND")
    v.bg:SetAllPoints()
    v.bg:SetColorTexture(1, 1, 1, 1)

    local function Segment(sublevel)
        local t = frame:CreateTexture(nil, "ARTWORK", nil, sublevel)
        t:SetColorTexture(1, 1, 1, 1)
        t:SetPoint("TOPLEFT")
        t:SetPoint("BOTTOMLEFT")
        return t
    end

    v.restedTex = Segment(0)
    v.questTex  = Segment(1)
    v.leadTex   = Segment(2)
    v.liquid    = ns.Liquid.New(frame, width, height, theme, db)

    -- Rounded Liquid: shading that rounds off everything inside the bar, and masks that cut both ends
    -- into half circles so the bar is a capsule and nothing inside spills past the ends. Mask textures
    -- are a newer API; without them only the shading is used. The optional glass is drawn by the
    -- liquid, since it reflects what the liquid is doing.
    v.shade = frame:CreateTexture(nil, "OVERLAY", nil, 0)
    v.shade:SetAllPoints()
    v.shade:SetTexture(MEDIA .. "Shade")
    v.shade:SetVertexColor(0, 0, 0)
    v.shade:Hide()

    if frame.CreateMaskTexture then
        v.roundL = frame:CreateMaskTexture()
        v.roundL:SetTexture(MEDIA .. "RoundEndL", "CLAMP", "CLAMP")
        v.roundL:SetPoint("TOPLEFT")
        v.roundL:SetPoint("BOTTOMLEFT")
        v.roundR = frame:CreateMaskTexture()
        v.roundR:SetTexture(MEDIA .. "RoundEndR", "CLAMP", "CLAMP")
        v.roundR:SetPoint("TOPRIGHT")
        v.roundR:SetPoint("BOTTOMRIGHT")
    end

    v.flash = frame:CreateTexture(nil, "OVERLAY", nil, 2)
    v.flash:SetAllPoints()
    v.flash:SetColorTexture(1, 1, 1, 1)
    v.flash:SetBlendMode("ADD")
    v.flash:SetAlpha(0)

    -- Over the default bar the text has a frame of its own, raised above the game's art there.
    local textParent = frame
    if skinned then
        v.textFrame = CreateFrame("Frame", nil, frame)
        v.textFrame:SetAllPoints()
        textParent = v.textFrame
    end
    for _, spec in ipairs(TEXTS) do
        local fs = textParent:CreateFontString(nil, "OVERLAY")
        fs:SetDrawLayer("OVERLAY", 7)
        fs:SetShadowColor(0, 0, 0, 1)
        fs:SetShadowOffset(1, -1)
        fs:SetTextColor(1, 1, 1, 1)
        v.texts[#v.texts + 1] = { fs = fs, spec = spec }
        v[spec.name] = fs
    end
    -- Over the default bar the time this level takes the level's place and there is no percentage.
    if skinned then v.pctText:Hide() end

    views[#views + 1] = v
    return v
end

local function ApplyTextSize(v)
    local k = min(1.6, max(0.6, v.height / BASE_HEIGHT))
    for _, t in ipairs(v.texts) do
        local s = t.spec
        t.fs:SetFont(FONT, floor(s.size * k + 0.5), "OUTLINE")
        t.fs:SetPoint(s.point, v.frame, s.relPoint, s.x, s.y * k)
    end
end

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

main = NewView(bar, barWidth, barHeight, false)
ApplyTextSize(main)

-- Hidden at max level (unless kept there); each view also has its own setting.
local barsWanted = true

local function ShowViews()
    bar:SetShown(barsWanted and db.showBar)
    if skin then skin.frame:SetShown(barsWanted and skinTarget ~= nil) end
end

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
gripTex:SetTexture(MEDIA .. "Grip")
gripTex:SetVertexColor(0.8, 0.8, 0.8)
grip:SetScript("OnEnter", function() gripTex:SetVertexColor(1, 0.9, 0.4) end)
grip:SetScript("OnLeave", function() gripTex:SetVertexColor(0.8, 0.8, 0.8) end)

-- back, if given, stretches the segment left to there; it stays under the liquid until the front dips.
local function Place(tex, x, w, back)
    if w < 0.5 then
        tex:Hide()
        return
    end
    if back and back < x then
        x, w = back, w + x - back
    end
    tex:SetPoint("TOPLEFT", x, 0)
    tex:SetPoint("BOTTOMLEFT", x, 0)
    tex:SetWidth(w)
    tex:Show()
end

-- v.rounded is whether the masks are on the view's textures. The skin view is always rounded; the
-- setting is the separate bar's.
local function ApplyRounding(v)
    local on
    if v.skinned then
        on = true
    elseif v.opts then
        on = v.opts.rounding and true or false
    else
        on = db.rounding and true or false
    end
    v.shade:SetShown(on)
    if not v.roundL then return end
    -- The masks are 0.625 bar heights wide with the half circle in their outer part (RoundEnd.tga).
    v.roundL:SetWidth(v.height * 0.625)
    v.roundR:SetWidth(v.height * 0.625)
    if on == v.rounded then return end
    v.rounded = on
    v.liquid:SetRoundEnds(on)
    for _, r in ipairs({ v.frame:GetRegions() }) do
        if r:GetObjectType() == "Texture" then
            if on then
                r:AddMaskTexture(v.roundL)
                r:AddMaskTexture(v.roundR)
            else
                r:RemoveMaskTexture(v.roundL)
                r:RemoveMaskTexture(v.roundR)
            end
        end
    end
end

local function ApplyRoundingAll()
    for _, v in ipairs(views) do ApplyRounding(v) end
end

local function ApplyLiquidOptions()
    for _, v in ipairs(views) do v.liquid:ApplyOptions() end
end

local previewTheme -- theme hovered in the settings theme picker; shown on the bar but never saved

local function ResolveTheme(key)
    local t = ns.Themes.Get(key)
    if t.Resolve then
        t = t:Resolve() -- e.g. class or faction colours, known once the player has loaded
    end
    return t
end

local function ApplyTheme()
    theme = ResolveTheme(previewTheme or db.theme)
    for _, v in ipairs(views) do
        local t = v.themeKey and ResolveTheme(v.themeKey) or theme
        v.theme = t
        v.bg:SetVertexColor(unpack(t.bg))
        v.restedTex:SetVertexColor(unpack(t.rested))
        v.questTex:SetVertexColor(unpack(t.quest))
        v.leadTex:SetVertexColor(unpack(t.lead))
        v.flash:SetVertexColor(unpack(t.flash))
        v.liquid:SetTheme(t)
    end
end

--------------------------------------------------------------------------------
-- Data
--------------------------------------------------------------------------------

local questXP = 0
local sim -- table while /seb test is active, nil for live data
local maxed = false -- at max level with "Show at Max Level" on

-- Forever runs the Midnight API, where the client can hand addons secret values (in combat, for
-- example): they can be shown but not compared or used in arithmetic. Era and Anniversary have no
-- issecretvalue, so nothing is ever secret there.
local function Secret(...)
    if not issecretvalue then return false end
    for i = 1, select("#", ...) do
        if issecretvalue((select(i, ...))) then return true end
    end
    return false
end

-- Returns nothing while the client keeps the XP values secret; callers try again later. Secret
-- rested XP alone only hides the rested segment.
local function GetData()
    if sim then
        return sim.level, sim.cur, sim.max, sim.quest, sim.rested
    end
    local level, cur, mx, rested = UnitLevel("player"), UnitXP("player"), UnitXPMax("player"), GetXPExhaustion()
    if Secret(level, cur, mx) then return end
    if Secret(rested) then rested = nil end
    return level, cur, max(mx or 1, 1), questXP, rested or 0
end

local function MaxLevel()
    return (GetMaxPlayerLevel and GetMaxPlayerLevel()) or MAX_PLAYER_LEVEL or 70
end

-- Forever may not report its own level cap (GetMaxPlayerLevel missing, or the retail cap), so a
-- level with no XP left to earn counts as max level too.
local function AtMaxLevel(level)
    if IsPlayerAtEffectiveMaxLevel and IsPlayerAtEffectiveMaxLevel() then return true end
    local mx = UnitXPMax("player")
    return level >= MaxLevel() or (not Secret(mx) and mx == 0)
end

local IsQuestComplete = (C_QuestLog and C_QuestLog.IsComplete) or IsQuestComplete

-- Selecting entries fires QUEST_LOG_UPDATE, so scans we trigger ourselves are ignored briefly.
local ignoreQuestUpdatesUntil = 0

-- Forever runs the modern quest log API; the classic functions below are missing there.
local function ScanQuestXPModern()
    local total = 0
    for i = 1, C_QuestLog.GetNumQuestLogEntries() do
        local info = C_QuestLog.GetInfo(i)
        local questID = info and not info.isHeader and not info.isHidden and info.questID
        if questID and questID > 0 and (C_QuestLog.IsComplete(questID)
            or (C_QuestLog.ReadyForTurnIn and C_QuestLog.ReadyForTurnIn(questID))) then
            total = total + (GetQuestLogRewardXP(questID) or 0)
        end
    end
    return total
end

local function ScanQuestXP()
    if not GetQuestLogRewardXP then return 0 end
    if not GetQuestLogTitle then
        if C_QuestLog and C_QuestLog.GetInfo then return ScanQuestXPModern() end
        return 0
    end
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
local xpPending = false -- an XP change arrived while the values were secret

local function ResetSession()
    cdb.startTime = time()
    cdb.gainedXP = 0
    local level, cur, mx = UnitLevel("player"), UnitXP("player"), UnitXPMax("player")
    if Secret(level, cur, mx) then
        -- The first readable XP becomes the baseline; the ticker takes it as soon as it can.
        cdb.lastLevel, cdb.lastXP, cdb.maxXP = nil, nil, nil
        xpPending = true
    else
        cdb.lastLevel, cdb.lastXP, cdb.maxXP = level, cur, mx
    end
end

-- Adds the XP gained since the last reading to the session total, for XP/hour. Several levels can
-- pass between readings while the values are secret.
local function CountGainedXP()
    local level, cur, mx = UnitLevel("player"), UnitXP("player"), UnitXPMax("player")
    xpPending = Secret(level, cur, mx)
    if xpPending then return end
    if not cdb.startTime then ResetSession() end
    if cdb.lastXP and cdb.maxXP then
        local last = cdb.lastLevel or level
        -- XP can wrap a frame before UnitLevel catches up: that is a level too.
        local levels = max(level - last, cur < cdb.lastXP and 1 or 0)
        local gained = cur - cdb.lastXP
        if levels > 0 then
            -- Levels in between are estimated at the current level's size.
            gained = cdb.maxXP - cdb.lastXP + cur + (levels - 1) * mx
        end
        cdb.gainedXP = cdb.gainedXP + gained
        level = max(level, last + levels) -- a wrap counted early is not counted again
    end
    cdb.lastLevel, cdb.lastXP, cdb.maxXP = level, cur, mx
end

local function RestoreChatFrames()
    for cf in pairs(mutedChatFrames) do
        cf:RegisterEvent("TIME_PLAYED_MSG")
    end
    wipe(mutedChatFrames)
end

-- Ask for /played without printing it to chat.
local function RequestPlayed()
    if requestingPlayed or not RequestTimePlayed then return end
    requestingPlayed = true
    for i = 1, NUM_CHAT_WINDOWS or 10 do
        local cf = _G["ChatFrame" .. i]
        if cf and cf:IsEventRegistered("TIME_PLAYED_MSG") then
            cf:UnregisterEvent("TIME_PLAYED_MSG")
            mutedChatFrames[cf] = true
        end
    end
    -- C_Timer rejects the bare C function, so wrap it.
    C_Timer.After(0.5, function() RequestTimePlayed() end)
    -- Never leave /played muted, even if no answer arrives.
    C_Timer.After(5, function()
        requestingPlayed = false
        RestoreChatFrames()
    end)
end

-- Sets one text line on every view.
local function SetText(name, text)
    for _, v in ipairs(views) do v[name]:SetText(text) end
end

-- "Time this level" (time played at max level): a line above the separate bar, and the skin view's
-- left text in place of the level.
local levelTimeText

-- Time this level, time played, session time, XP/hour and the time to level, for the lines around the
-- separate bar and the default bar's tooltip.
local function SessionStats(cur, mx)
    local now = time()
    local since = played.at > 0 and now - played.at or 0
    local elapsed = now - cdb.startTime
    local hourly, toLevel = 0, 0
    if elapsed > 0 and cdb.gainedXP > 0 then
        hourly = ceil(cdb.gainedXP / (elapsed / 3600))
        toLevel = ceil((mx - cur) / hourly * 3600)
    end
    return {
        levelTime = FormatTime(played.at > 0 and since + played.level or 0),
        played = FormatTime(played.at > 0 and since + played.total or 0),
        session = FormatTime(elapsed),
        hourly = hourly > 10000 and (Round1(hourly / 1000) .. "K") or FormatNumber(hourly),
        toLevel = toLevel > 0 and FormatTime(toLevel) or "--",
    }
end

local function UpdateSessionTexts()
    if not (cdb and cdb.startTime) then return end
    local level, cur, mx = GetData()
    if not level then return end
    local stats = SessionStats(cur, mx)

    for _, v in ipairs(views) do
        -- A preview's textMode shows all the lines or none, whatever the settings say.
        local all, around = v.textMode == "all", not v.skinned
        if v.textMode then around = all end
        v.levelTime:SetShown(around and (all or db.showLevelTime))
        v.sessionTime:SetShown(around and (all or db.showSessionTime))
        v.levelInText:SetShown(around and (all or db.showXPHour) and not maxed)
        v.qrText:SetShown(around and (all or db.showQuestRested) and not maxed)
    end

    levelTimeText = maxed and ("Time played: " .. stats.played) or ("Time this level: " .. stats.levelTime)
    SetText("levelTime", levelTimeText)
    for _, v in ipairs(views) do
        if v.skinned and (db.showLevelTime or v.preview) then v.levelText:SetText(levelTimeText) end
    end
    SetText("sessionTime", "Time this session: " .. stats.session)
    SetText("levelInText", string.format("Leveling in: %s (%s XP/Hour)", stats.toLevel, stats.hourly))
end

--------------------------------------------------------------------------------
-- Animation
--------------------------------------------------------------------------------

-- Displayed state (A) chases target state (T). All bar values are fractions of the displayed level.
local A = { ready = false, fill = 0, lead = 0, quest = 0, rested = 0, wraps = 0, hold = 0, flash = 0, level = 0, maxXP = 1,
            fillVel = 0, restedVel = 0 }
local animating, idleAcc = false, 0
local T = { level = 0, cur = 0, max = 1, quest = 0, rested = 0 }

local function Approach(cur, target, dt, rate)
    local d = target - cur
    if abs(d) < ANIM.epsilon then return target end
    return cur + d * (1 - exp(-rate * dt))
end

-- Critically damped spring, exact for any dt: from rest it speeds up, then eases in without
-- overshooting. Returns the new value and velocity.
local function Spring(cur, vel, target, dt, w)
    local e = cur - target
    if abs(e) < ANIM.epsilon and abs(vel) < ANIM.epsilon * w then return target, 0 end
    local k = exp(-w * dt)
    local push = (vel + w * e) * dt
    local e2 = (e + push) * k
    if e2 * e < 0 then return target, 0 end -- a retarget can carry it past; stop there instead
    return target + e2, (vel - w * push) * k
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

    for _, v in ipairs(views) do
        local timed = v.skinned and (db.showLevelTime or v.preview) and levelTimeText
        v.levelText:SetText(timed or ("Level " .. A.level))
    end
    if maxed then
        SetText("xpText", "Max Level")
        SetText("pctText", "")
        return
    end

    local xp = floor(fill * A.maxXP + 0.5)
    SetText("xpText", string.format("%s / %s (%s)", FormatNumber(xp), FormatNumber(A.maxXP), FormatNumber(A.maxXP - xp)))

    if quest > 0 then
        SetText("pctText", string.format("%s%% (%s%%)", Round1(fill * 100), Round1((fill + quest) * 100)))
    else
        SetText("pctText", string.format("%s%%", Round1(fill * 100)))
    end

    for _, v in ipairs(views) do
        v.qrText:SetText(string.format("Completed: |cFF%s%s%%|r - Rested: |cFF%s%s%%|r",
            v.theme.questText, Round1(T.quest / T.max * 100), v.theme.restedText, Round1(T.rested / T.max * 100)))
    end
end

local function RenderView(v)
    local w = v.width
    local fillW = A.fill * w
    -- When the front sloshes back, the segment after the fill shows there instead of the empty bar.
    local back = v.liquid:Back()
    Place(v.leadTex, fillW, (A.lead - A.fill) * w, back)

    -- Overlays sit after the fill and clip at the bar end.
    local questW = min(A.quest, 1 - A.fill) * w
    local restedW = min(A.rested, max(0, 1 - A.fill - A.quest)) * w
    Place(v.questTex, fillW, questW, back)
    Place(v.restedTex, fillW + questW, restedW, questW < 0.5 and back or nil)

    if questW >= 0.5 then
        v.liquid:SetContact(v.theme.quest, fillW + questW)
    elseif restedW >= 0.5 then
        v.liquid:SetContact(v.theme.rested, fillW + restedW)
    else
        v.liquid:SetContact(nil)
    end

    v.flash:SetAlpha(A.flash * 0.35)
end

-- Views out of sight are skipped; they catch up on the next frame they are seen.
local function RenderBar()
    for _, v in ipairs(views) do
        if v.frame:IsVisible() then RenderView(v) end
    end
    RenderText()
end

-- Advance the fill toward its target; the liquid reacts to however the fill moves.
local function StepFill(dt)
    local wrapping = A.wraps > 0
    local target = FillTarget()

    -- Several pending level-ups speed the sweep up so it never feels stuck.
    -- Slow themes still sweep through a level-up at normal speed so it never crawls.
    local themeSpeed = theme.fillSpeed or 1
    if wrapping then themeSpeed = max(1, themeSpeed) end
    local rate = ANIM.rate * db.speed * themeSpeed * (1 + max(0, A.wraps - 1) * 0.5)
    local w = rate * ANIM.spring
    local held = A.hold > 0
    if held then
        A.hold = A.hold - dt
    else
        A.fill, A.fillVel = Spring(A.fill, A.fillVel, wrapping and 1 + ANIM.overshoot or target, dt, w)
    end

    if wrapping and A.fill >= 1 then
        A.wraps = A.wraps - 1
        A.level = A.level + 1
        A.fill, A.flash, A.pourEnd = 0, db.flash and 1 or 0, nil
        A.fillVel, A.restedVel = 0, 0
        if A.wraps == 0 then
            A.level, A.maxXP = T.level, T.max
        end
        A.lead = FillTarget()
        A.hold = 0.08
        wrapping = A.wraps > 0
        target = FillTarget()
        for _, v in ipairs(views) do
            v.liquid:Snap(0)
            v.liquid:LevelUp()
        end
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
    -- Rested waits and pours on the same spring as the fill, so its far end never backs up.
    if not held then
        A.rested, A.restedVel = Spring(A.rested, A.restedVel, wrapping and 0 or T.rested / T.max, dt, w)
    end
    if A.flash > 0 then A.flash = max(0, A.flash - dt / ANIM.flash) end

    if not wrapping and A.hold <= 0 and A.fill == target and A.flash == 0
        and A.quest == T.quest / T.max and A.rested == T.rested / T.max then
        A.lead = A.fill
        animating = false
    end
end

-- Runs while a view is in sight. Once everything has settled only the idle wobble remains, so it
-- drops to ANIM.idleFPS.
local function OnUpdate(self, elapsed)
    local seen, quiet = false, true
    for _, v in ipairs(views) do
        if v.frame:IsVisible() then
            seen = true
            quiet = quiet and v.liquid:IsQuiet()
        end
    end
    if not seen then return end
    if not animating and quiet then
        idleAcc = idleAcc + elapsed
        if idleAcc < 1 / ANIM.idleFPS then return end
        elapsed, idleAcc = idleAcc, 0
    end
    if elapsed <= 0 then return end
    local dt = min(elapsed, 0.1) -- loading-screen hitches should not teleport the bar

    if animating then StepFill(dt) end
    for _, v in ipairs(views) do
        if v.frame:IsVisible() then v.liquid:Update(dt, A.fill * v.width) end
    end
    RenderBar()
end

local refreshPending = false -- XP values were secret; the 1-second ticker tries again

local function Refresh()
    local level, cur, mx, quest, rested = GetData()
    refreshPending = not level
    if refreshPending then return end

    local wasMaxed = maxed
    maxed = not sim and AtMaxLevel(level)
    barsWanted = not maxed or db.showMaxLevel
    ShowViews()
    if not barsWanted then return end
    if maxed then
        cur, mx, quest, rested = 1, 1, 0, 0 -- a full bottle
    end
    for _, v in ipairs(views) do v.liquid:SetRested(rested > 0) end
    if maxed ~= wasMaxed then UpdateSessionTexts() end

    if not A.ready or level < T.level or maxed ~= wasMaxed then
        T.level, T.cur, T.max, T.quest, T.rested = level, cur, mx, quest, rested
        A.level, A.maxXP, A.wraps, A.hold, A.flash = level, mx, 0, 0, 0
        A.fill, A.quest, A.rested = cur / mx, quest / mx, rested / mx
        A.fillVel, A.restedVel = 0, 0
        A.lead = A.fill
        A.ready, animating, A.pourEnd = true, false, nil
        for _, v in ipairs(views) do v.liquid:Snap(A.fill * v.width) end
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
    local questBefore = A.quest

    T.level, T.cur, T.max, T.quest, T.rested = level, cur, mx, quest, rested
    if A.wraps == 0 then
        A.level, A.maxXP = level, mx
    end

    local target = FillTarget()
    if target > A.lead + ANIM.epsilon then
        A.lead = target
        -- Already pouring: carry on toward the new target rather than stopping dead to show it.
        if A.fillVel == 0 then A.hold = ANIM.hold end
    elseif target < A.lead then
        A.lead = max(target, A.fill)
    end

    if gained > 0 then
        -- sqrt so a single mob kill still ripples, while a big turn-in gets the full splash.
        local intensity = min(1, (gained / mx / ANIM.bigGain) ^ 0.5)
        for _, v in ipairs(views) do
            v.liquid:Splash(intensity, A.fill * v.width, A.lead * v.width)
        end
    end

    -- Turn-in XP and the quest log change arrive as separate events in either order, so hold the
    -- orange where it is until the liquid reaches it (or give up, e.g. for an abandoned quest).
    if questDrop > 0 and A.wraps == 0 then
        local intensity = min(1, questDrop / mx / ANIM.bigGain)
        for _, v in ipairs(views) do
            local edge = A.fill * v.width
            v.liquid:Absorb(edge, edge + questBefore * v.width, intensity)
        end
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
    if not level then -- secret right now: start from what the bar last showed
        level, cur, mx, quest, rested = max(T.level, 1), T.cur, T.max, T.quest, T.rested
    end
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

-- Everything that depends on a view's size; also runs live while the grip is dragged.
local function OnViewResized(v, w, h)
    v.width, v.height = w, h
    v.liquid:SetSize(w, h)
    v.liquid:Snap(A.fill * w)
    ApplyTextSize(v)
    ApplyRounding(v)
    RenderBar()
end

local function ApplySize()
    db.width = min(MAX_WIDTH, max(MIN_WIDTH, db.width))
    db.height = min(MAX_HEIGHT, max(MIN_HEIGHT, db.height))
    bar:SetSize(db.width, db.height)
    OnViewResized(main, db.width, db.height)
end

bar:SetScript("OnSizeChanged", function(_, w, h)
    if w ~= main.width or h ~= main.height then OnViewResized(main, w, h) end
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

-- The default XP bar differs between clients; hide whichever of these exist. Forever has only
-- StatusTrackingBarManager, and its bar containers are listed on it rather than named.
local BLIZZARD_BARS = { "MainMenuExpBar", "StatusTrackingBarManager", "MainStatusTrackingBarContainer" }
local hookedBars, hiddenBars = {}, {}

local function BlizzardBars()
    local list, seen = {}, {}
    local function add(f)
        if type(f) == "table" and f.Hide and not seen[f] then
            seen[f] = true
            list[#list + 1] = f
        end
    end
    for _, name in ipairs(BLIZZARD_BARS) do add(_G[name]) end
    local manager = StatusTrackingBarManager
    if manager and type(manager.barContainers) == "table" then
        for _, container in ipairs(manager.barContainers) do add(container) end
    end
    return list
end

-- Drawn over the default bar, the bar lives inside it, so hiding it would hide ours too.
local function HideWanted()
    return db.hideBlizzardBar and not db.skinDefaultBar
end

local function ApplyBlizzardBar()
    for _, f in ipairs(BlizzardBars()) do
        if not hookedBars[f] then
            hookedBars[f] = true
            -- Remember what the game wanted shown, so turning the option off brings it back.
            hooksecurefunc(f, "Show", function(self)
                if HideWanted() then
                    hiddenBars[self] = true
                    self:Hide()
                end
            end)
            -- The modern UI and Edit Mode show these with SetShown(true) rather than Show.
            if f.SetShown then
                hooksecurefunc(f, "SetShown", function(self, shown)
                    if not HideWanted() then return end
                    hiddenBars[self] = shown or nil
                    if shown then self:Hide() end
                end)
            end
        end
        if HideWanted() then
            if f:IsShown() then hiddenBars[f] = true end
            f:Hide()
        elseif hiddenBars[f] then
            hiddenBars[f] = nil
            f:Show()
        end
    end
end

-- Use Default Experience Bar: the skin view, drawn over the game's own XP bar. The game's frames are
-- only read, never changed: the view's frame becomes a child of the XP bar, so it shows, hides, moves
-- and scales with it (Edit Mode included), and covers its fill from a higher frame level.

-- The default XP bar: the frame whose visibility we follow and the fill whose rect we cover. Forever
-- keeps its bars in StatusTrackingBarManager.barContainers[i].bars, each with a StatusBar; the
-- experience one is told apart by its index or its rested-XP parts. Era and Anniversary have
-- MainMenuExpBar, which is both.
local function DefaultXPBar()
    local manager = StatusTrackingBarManager
    if manager and type(manager.barContainers) == "table" then
        local enum = StatusTrackingBarInfo and StatusTrackingBarInfo.BarsEnum
        local expIndex = enum and enum.Experience
        for _, container in ipairs(manager.barContainers) do
            if type(container.bars) == "table" then
                for index, b in pairs(container.bars) do
                    local fill = type(b) == "table" and b.StatusBar
                    if fill and ((expIndex and (index == expIndex or b.barIndex == expIndex))
                        or b.ExhaustionTick or b.ExhaustionLevelFillBar) then
                        return b, fill
                    end
                end
            end
        end
        return
    end
    if MainMenuExpBar then return MainMenuExpBar, MainMenuExpBar end
end

-- What the game has, for when the XP bar is not found: each container's bars and their parts.
local function DescribeBars()
    local manager = StatusTrackingBarManager
    if not (manager and type(manager.barContainers) == "table") then
        return "no StatusTrackingBarManager.barContainers, no MainMenuExpBar"
    end
    local out = {}
    for i, container in ipairs(manager.barContainers) do
        local bars = {}
        for index, b in pairs(type(container.bars) == "table" and container.bars or {}) do
            local parts = {}
            if type(b) == "table" then
                for k, v in pairs(b) do
                    if type(k) == "string" and type(v) == "table" and k:match("^%u") then parts[#parts + 1] = k end
                end
                if b.barIndex then parts[#parts + 1] = "barIndex=" .. tostring(b.barIndex) end
            end
            table.sort(parts)
            bars[#bars + 1] = tostring(index) .. "(" .. table.concat(parts, " ") .. ")"
        end
        out[#out + 1] = "container " .. i .. ": " .. (#bars > 0 and table.concat(bars, ", ") or "no bars")
    end
    return table.concat(out, "; ")
end

local STRATA_ORDER = { BACKGROUND = 1, LOW = 2, MEDIUM = 3, HIGH = 4, DIALOG = 5, FULLSCREEN = 6,
                       FULLSCREEN_DIALOG = 7, TOOLTIP = 8 }

-- The highest strata and frame level in the game's frames around its XP bar (from the topmost parent
-- below UIParent), skipping ours, so the text can go above the segment lines and end caps there.
local function TopOfBarArt(target, ours)
    local root = target
    while root:GetParent() and root:GetParent() ~= UIParent do root = root:GetParent() end
    local strata, level = root:GetFrameStrata(), root:GetFrameLevel()
    local function visit(f, depth)
        if f == ours or depth > 6 then return end
        local s, l = f:GetFrameStrata(), f:GetFrameLevel()
        if (STRATA_ORDER[s] or 0) > (STRATA_ORDER[strata] or 0) then
            strata, level = s, l
        elseif s == strata and l > level then
            level = l
        end
        for _, child in ipairs({ f:GetChildren() }) do visit(child, depth + 1) end
    end
    visit(root, 0)
    return strata, level, root
end

local function OpenSettingsOnRightClick(_, button)
    if button == "RightButton" then ns.Core.OpenSettings() end
end

-- The default bar's tooltip: everything the separate bar shows around itself, which the default bar
-- has no room for. Quest and rested XP take the theme's text colours, as on the separate bar.
local function TooltipRow(label, value)
    GameTooltip:AddDoubleLine(label, value, 1, 0.82, 0, 1, 1, 1)
end

local function ShowSkinTooltip(frame)
    GameTooltip:SetOwner(frame, "ANCHOR_TOP")
    GameTooltip:AddLine("Level " .. T.level, 1, 1, 1)
    if maxed then
        GameTooltip:AddLine("Max Level", 1, 0.82, 0)
    else
        local pct = function(xp) return Round1(xp / T.max * 100) .. "%" end
        TooltipRow("Experience", FormatNumber(T.cur) .. " / " .. FormatNumber(T.max) .. " (" .. pct(T.cur) .. ")")
        TooltipRow("Remaining", FormatNumber(T.max - T.cur))
        if T.quest > 0 then
            TooltipRow("Completed quests", string.format("|cFF%s%s|r (%s XP)", theme.questText, pct(T.quest),
                FormatNumber(T.quest)))
        end
        TooltipRow("Rested", T.rested > 0
            and string.format("|cFF%s%s|r (%s XP)", theme.restedText, pct(T.rested), FormatNumber(T.rested))
            or "None")
    end
    if cdb and cdb.startTime then
        local stats = SessionStats(T.cur, T.max)
        GameTooltip:AddLine(" ")
        if maxed then
            TooltipRow("Time played", stats.played)
        else
            TooltipRow("Time this level", stats.levelTime)
        end
        TooltipRow("Time this session", stats.session)
        if not maxed then
            TooltipRow("Leveling in", stats.toLevel)
            TooltipRow("XP per hour", stats.hourly)
        end
    end
    GameTooltip:AddLine(" ")
    GameTooltip:AddLine("Right-click for settings", 0.62, 0.62, 0.62)
    GameTooltip:Show()
end

-- The skin view is made the first time it is needed, so players who never use it pay nothing for it.
local function SkinView()
    if skin then return skin end
    local frame = CreateFrame("Frame", "SmoothExperienceBarDefaultFrame", UIParent)
    frame:SetSize(barWidth, barHeight)
    frame:Hide()
    frame:EnableMouse(true)
    frame:SetScript("OnMouseUp", OpenSettingsOnRightClick)
    frame:SetScript("OnEnter", ShowSkinTooltip)
    frame:SetScript("OnLeave", function() GameTooltip:Hide() end)
    skin = NewView(frame, barWidth, barHeight, true)
    frame:SetScript("OnSizeChanged", function(_, w, h)
        if w ~= skin.width or h ~= skin.height then OnViewResized(skin, w, h) end
    end)
    skin.liquid:SetOptions(db)
    ApplyTheme()
    ApplyRounding(skin)
    ApplyTextSize(skin)
    skin.liquid:SetRested(T.rested > 0)
    return skin
end

local function Unskin()
    if not skinTarget then return end
    skinTarget, skinFill = nil, nil
    skin.frame:Hide()
    skin.frame:ClearAllPoints()
    skin.frame:SetParent(UIParent)
end

-- Runs on login, when either bar option changes and every second while it is on, so the skin view
-- follows the game swapping or resizing its XP bar. verbose reports the outcome in chat.
local function ApplySkin(verbose)
    ApplyBlizzardBar()
    if not db.skinDefaultBar then
        Unskin()
        ShowViews()
        return
    end
    local target, fill = DefaultXPBar()
    if not target then
        Unskin()
        ShowViews()
        if verbose then Print("Could not find the default experience bar: " .. DescribeBars()) end
        return
    end
    local w, h = fill:GetWidth(), fill:GetHeight()
    if w < 1 or h < 1 then
        if verbose then Print("The default experience bar is not laid out yet; trying again every second.") end
        return
    end
    local v = SkinView()
    local frame = v.frame
    local textStrata, textLevel, root
    if target ~= skinTarget or fill ~= skinFill then
        skinTarget, skinFill = target, fill
        frame:SetParent(target)
        frame:SetFrameStrata(fill:GetFrameStrata())
        frame:SetFrameLevel(fill:GetFrameLevel() + 10)
        frame:SetScale(1)
        frame:ClearAllPoints()
        frame:SetPoint("TOPLEFT", fill, "TOPLEFT", 0, 0)
        textStrata, textLevel, root = TopOfBarArt(target, frame)
        v.textFrame:SetFrameStrata(textStrata)
        v.textFrame:SetFrameLevel(min(10000, max(textLevel, frame:GetFrameLevel()) + 1))
        ShowViews()
    end
    if w ~= v.width or h ~= v.height then frame:SetSize(w, h) end
    if root then
        RenderBar()
        UpdateSessionTexts()
        RenderText(true)
    end
    if verbose then
        local name = target.GetDebugName and target:GetDebugName() or "the default experience bar"
        local rootName = root and root.GetDebugName and root:GetDebugName() or "?"
        Print(string.format("Drawing over %s (%dx%d); text at %s %d above %s.", name,
            floor(w + 0.5), floor(h + 0.5), textStrata or "?", textLevel or 0, rootName))
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

-- Theme picker hover: the menu reports which option the mouse enters but not when it closes, so
-- watch for the close and go back to the saved theme if nothing was picked.
local previewWatch

local function EndThemePreview()
    if previewWatch then
        previewWatch:Cancel()
        previewWatch = nil
    end
    if previewTheme then
        previewTheme = nil
        ApplyTheme()
        RenderText(true)
    end
end

function Core.PreviewTheme(key)
    if not (Menu and Menu.GetManager) or not ns.Themes.list[key] then return end
    previewTheme = key ~= db.theme and key or nil
    ApplyTheme()
    RenderText(true)
    if not previewWatch then
        previewWatch = C_Timer.NewTicker(0.1, function()
            if not Menu.GetManager():IsAnyMenuOpen() then EndThemePreview() end
        end)
    end
end

local SETTING_APPLY = {
    theme = function()
        previewTheme = nil -- picked from the menu: the saved theme takes over
        ApplyTheme()
        RenderText(true)
    end,
    scale = ApplyScale,
    width = ApplySize,
    height = ApplySize,
    locked = ApplyLock,
    showMaxLevel = function() Refresh() end,
    hideBlizzardBar = ApplyBlizzardBar,
    showBar = function() ShowViews(); RenderBar(); UpdateSessionTexts() end,
    skinDefaultBar = function() ApplySkin(db.skinDefaultBar) end,
    showLevelTime = function() UpdateSessionTexts(); RenderText(true) end,
    showSessionTime = UpdateSessionTexts,
    showXPHour = UpdateSessionTexts,
    showQuestRested = UpdateSessionTexts,
    waves = ApplyLiquidOptions,
    bubbles = ApplyLiquidOptions,
    sparkles = ApplyLiquidOptions,
    ambient = ApplyLiquidOptions,
    lightning = ApplyLiquidOptions,
    glass = ApplyLiquidOptions,
    rounding = ApplyRoundingAll,
}

function Core.OnSettingChanged(key)
    local apply = SETTING_APPLY[key]
    if apply then apply() end
end

local function CopyValue(v)
    return type(v) == "table" and { unpack(v) } or v
end

function Core.ResetPosition()
    db.point = CopyValue(DEFAULTS.point)
    db.width, db.height, db.scale = DEFAULTS.width, DEFAULTS.height, DEFAULTS.scale
    ApplyScale()
    ApplySize()
    ApplyPosition()
end

-- Profiles: every character's settings, keyed "Name - Realm".
local profiles, profileKey

function Core.ProfileKey()
    return profileKey
end

-- Other characters' profiles, sorted, for the settings page.
function Core.OtherProfiles()
    local keys = {}
    for key in pairs(profiles or {}) do
        if key ~= profileKey then keys[#keys + 1] = key end
    end
    table.sort(keys)
    return keys
end

-- Copy another character's settings onto this character. Everything but the position goes through
-- its settings control, so the page and the bar follow as if the player had set each one.
function Core.CopyProfile(key)
    local src = profiles[key]
    if not src then return end
    db.point = CopyValue(src.point or DEFAULTS.point)
    ApplyPosition()
    ns.Options.SetAll(src)
    DEFAULT_CHAT_FRAME:AddMessage("|cffa070ffSmoothXP|r Copied settings from " .. key .. ".")
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
-- API for the setup wizard
--------------------------------------------------------------------------------

function Core.Defaults()
    return DEFAULTS
end

function Core.Get(key)
    return db[key]
end

-- Through the settings control where there is one, so the settings page follows.
function Core.SetSetting(key, value)
    if not (ns.Options.Set and ns.Options.Set(key, value)) then
        db[key] = value
        Core.OnSettingChanged(key)
    end
end

-- A live bar for a preview, on parent: look "bar" is the separate bar, "skin" the bar over the game's
-- own. It shows the same XP as the real bars (the wizard plays /seb test gains on them).
function Core.NewPreview(parent, look)
    local skinned = look == "skin"
    local w, h = skinned and 571 or 600, skinned and 13 or 30
    local frame = CreateFrame("Frame", nil, parent)
    frame:SetSize(w, h)
    local v = NewView(frame, w, h, skinned)
    v.preview = true
    if not skinned then v.textMode = "none" end
    v.liquid:SetOptions(db)
    v.liquid:SetRested(T.rested > 0)
    v.liquid:Snap(A.fill * w)
    ApplyTheme()
    ApplyRounding(v)
    ApplyTextSize(v)
    UpdateSessionTexts()
    RenderText(true)
    return v
end

-- A preview's own theme, effect settings (rounding included) and, for the separate bar, its lines
-- ("all" or "none").
function Core.StylePreview(v, themeKey, opts, textMode)
    v.themeKey = themeKey
    if opts ~= v.opts then
        v.opts = opts
        v.liquid:SetOptions(opts or db)
    end
    if not v.skinned then v.textMode = textMode or "none" end
    ApplyTheme()
    ApplyRounding(v)
    UpdateSessionTexts()
    RenderText(true)
end

-- Setup state: db.setupPending while the wizard is still to be done, db.setupSnoozed after Ask Me
-- Later until the next login. how: "later", "skip" or "done".
function Core.SetupWanted()
    return db.setupPending and not db.setupSnoozed
end

function Core.EndSetup(how)
    db.setupPending = how == "later" or nil
    db.setupSnoozed = how == "later" or nil
    if how ~= "later" then db.setupNew = nil end
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
        local root = SmoothExperienceBarDB
        -- Settings used to be shared by the whole account. Keep them as the starting point for each
        -- character's own profile, so nobody loses their setup on updating.
        if not root.profiles then
            root = { profiles = {}, legacy = next(root) and root or nil }
            SmoothExperienceBarDB = root
        end
        profiles = root.profiles
        profileKey = (UnitName("player") or "Unknown") .. " - " .. (GetRealmName() or "Unknown")
        local newToAddon = not next(profiles) and not root.legacy
        if not profiles[profileKey] then
            local profile = {}
            for k, v in pairs(root.legacy or {}) do profile[k] = CopyValue(v) end
            profiles[profileKey] = profile
        end
        db, cdb = profiles[profileKey], SmoothExperienceBarCharDB
        -- The setup wizard opens once per account, on the first character logged in: for someone new
        -- to the addon, and for those who had it before the wizard, starting from their settings.
        -- Other characters can copy a setup from the settings, or open the wizard themselves.
        if not root.setupOffered then
            root.setupOffered = true
            db.setupPending = true
            db.setupNew = newToAddon or nil
        end
        if db.layout ~= LAYOUT_VERSION then
            db.point = nil
            db.layout = LAYOUT_VERSION
        end
        for k, v in pairs(DEFAULTS) do
            if db[k] == nil then db[k] = CopyValue(v) end
        end
        if not ns.Themes.list[db.theme] then db.theme = DEFAULTS.theme end
        main.liquid:SetOptions(db)
        ApplyTheme()
        ApplyRounding(main)
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
        if ns.Themes.Get(db.theme).Resolve then ApplyTheme() end
        ApplySkin()
        if isLogin or isReload then
            RequestPlayed()
        end
        if isLogin then db.setupSnoozed = nil end
        if Core.SetupWanted() and ns.Wizard then
            C_Timer.After(2, function() ns.Wizard.OpenWhenReady() end)
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
        if arg2 and not Secret(arg2) and arg2 > 0 and questXP > 0 then
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
        CountGainedXP()
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
-- On a frame of its own, so the animation runs whichever views are shown.
local driver = CreateFrame("Frame")
driver:SetScript("OnUpdate", OnUpdate)

C_Timer.NewTicker(1, function()
    if not cdb then return end
    -- Catch up on XP that changed while its values were secret.
    if xpPending then CountGainedXP() end
    if refreshPending then Refresh() end
    if db.skinDefaultBar then ApplySkin() end
    -- Keep an open tooltip's times and XP current.
    if skin and GameTooltip:IsShown() and GameTooltip:IsOwned(skin.frame) then ShowSkinTooltip(skin.frame) end
    if bar:IsShown() or (skin and skin.frame:IsShown()) then UpdateSessionTexts() end
end)

--------------------------------------------------------------------------------
-- Slash commands
--------------------------------------------------------------------------------

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
    "/seb skin - use the game's own experience bar, or a separate bar again",
    "/seb setup - open the setup wizard",
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
    elseif cmd == "setup" then
        if ns.Wizard then ns.Wizard.Open() end
    elseif cmd == "skin" then
        db.skinDefaultBar = not db.skinDefaultBar
        ApplySkin(db.skinDefaultBar)
        if not db.skinDefaultBar then Print("Back to a separate bar.") end
    else
        for _, line in ipairs(HELP) do Print(line) end
    end
end
