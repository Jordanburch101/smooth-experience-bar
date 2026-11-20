-- The reputation bar: the liquid drawn over the game's own reputation bar, which the game shows while
-- a faction is watched (Show as Experience Bar in the Reputation panel), wherever the game puts it.
-- It has its own theme (the game's standing colours to start with), texts and tooltip, and pours on
-- its own; the liquid effects, font and fill speed are the experience bar's settings.

local _, ns = ...
local B, Core, Themes = ns.Bar, ns.Core, ns.Themes
local min, max, floor, ceil = math.min, math.max, math.floor, math.ceil
local ANIM, Secret, FormatNumber, Round1 = B.anim, B.Secret, B.FormatNumber, B.Round1

local db = B.DB() -- the defaults until the saved settings load

-- Off to start with: the game's reputation bar stays as it is until the player turns this on.
local D = B.defaults
D.repBar = false
D.repTheme = Themes.standing
D.repLeft = "name"
D.repCentre = "value"
D.repRight = "standing"
D.repLeftSize = 100
D.repCentreSize = 100
D.repRightSize = 100
D.repTooltip = true
-- What the separate bar tracks: "xp", "rep", or "auto" (experience, then reputation at max level).
D.separateTracks = "xp"
local TRACKS = { xp = true, rep = true, auto = true }

--------------------------------------------------------------------------------
-- Data
--------------------------------------------------------------------------------

local STANDING_NAMES = { "Hated", "Hostile", "Unfriendly", "Neutral", "Friendly", "Honored", "Revered", "Exalted" }
-- How much reputation each standing spans, for previews.
local STANDING_SPANS = { 36000, 3000, 3000, 3000, 6000, 12000, 21000, 999 }
local MAX_REACTION = 8

-- The game's name for a standing, in the player's language (and gender, where the language has one).
local function StandingName(reaction)
    local token = "FACTION_STANDING_LABEL" .. tostring(reaction)
    local label = _G[token]
    if label and GetText and UnitSex then label = GetText(token, UnitSex("player")) or label end
    return label or STANDING_NAMES[reaction] or ""
end

local sim -- the previewed faction while /seb test rep runs

-- The watched faction: { id, name, reaction, value (into its standing), span (of the standing),
-- total (its overall reputation, for this session's gains), capped (nothing more to earn) }. nil
-- with none watched, false while the client keeps its values secret.
local function Watched()
    if sim then
        local copy = {}
        for k, v in pairs(sim) do copy[k] = v end
        return copy
    end
    local name, reaction, low, high, value, id
    if C_Reputation and C_Reputation.GetWatchedFactionData then
        local d = C_Reputation.GetWatchedFactionData()
        if not d then return end
        name, reaction, low, high, value, id = d.name, d.reaction, d.currentReactionThreshold,
            d.nextReactionThreshold, d.currentStanding, d.factionID
    elseif GetWatchedFactionInfo then
        name, reaction, low, high, value, id = GetWatchedFactionInfo()
    end
    if Secret(name, reaction, low, high, value, id) then return false end
    if not name or name == "" or not reaction then return end
    low, high, value = low or 0, high or 0, value or 0
    local total, paragon = value, false
    local IsParagon = C_Reputation and C_Reputation.IsFactionParagonForCurrentPlayer
    if id and id ~= 0 and IsParagon and IsParagon(id) and C_Reputation.GetFactionParagonInfo then
        local cur, threshold, _, pending = C_Reputation.GetFactionParagonInfo(id)
        if Secret(cur, threshold, pending) then return false end
        if cur and threshold and threshold > 0 then
            low, high, value, total, paragon = 0, threshold, cur % threshold + (pending and threshold or 0), cur, true
        end
    end
    local span, into = high - low, value - low
    -- At the top standing the game shows just the name; with nothing left to earn, a full bar.
    local capped = span <= 0 or (reaction >= MAX_REACTION and not paragon)
    if span <= 0 then span, into = 1, 1 end
    return { id = (id and id ~= 0) and id or name, name = name, reaction = reaction, value = into, span = span,
             total = total, capped = capped }
end

-- This session's reputation, kept with the experience bar's session (SmoothExperienceBarCharDB) so a
-- reload keeps it and a session reset starts it again: for each faction id, its total reputation
-- and the time when first seen watched this session.
local function RepSession()
    local cdb = B.CharDB()
    if not cdb then return { start = {} } end
    local s = cdb.repSession
    if type(s) ~= "table" or type(s.start) ~= "table" or s.at ~= cdb.startTime then
        s = { at = cdb.startTime, start = {} }
        cdb.repSession = s
    end
    return s
end

-- Reputation gained with a faction this session, and the seconds since it was first seen.
local function SessionGain(f)
    local start = not sim and RepSession().start[f.id]
    if not start then return 0, 0 end
    return f.total - start.total, time() - start.at
end

--------------------------------------------------------------------------------
-- View and animation
--------------------------------------------------------------------------------

local view -- the one over the game's reputation bar
local barView -- the separate bar, while it tracks reputation
-- The views drawn: either or both of those.
local drawn = {}
local watching = false -- a faction is watched

local function UpdateDrawn()
    for i = #drawn, 1, -1 do drawn[i] = nil end
    if view then drawn[#drawn + 1] = view end
    if barView then drawn[#drawn + 1] = barView end
end

-- Displayed state (R) chasing the faction as last read (T). fill and lead are fractions of the
-- displayed standing, which is R.reaction and R.span until a standing-up pour reaches the end.
local R = { ready = false, fill = 0, vel = 0, lead = 0, hold = 0, flash = 0, wrap = false, reaction = 4, span = 1 }
local T
local animating, idleAcc, pending = false, 0, false
local previewTheme, previewWatch -- the theme hovered in the theme picker, shown but never saved

local function Target()
    return T and min(1, T.value / T.span) or R.fill
end

local function RepTheme()
    local key = previewTheme or db.repTheme
    if key ~= Themes.standing and Themes.list[key] then return B.ResolveTheme(key) end
    return Themes.Standing(R.reaction)
end

local function ApplyViewTheme(v, t)
    v.theme = t
    v.bg:SetVertexColor(unpack(t.bg))
    v.leadTex:SetVertexColor(unpack(t.lead))
    v.flash:SetVertexColor(unpack(t.flash))
    v.liquid:SetTheme(t)
end

local function ApplyTheme()
    if #drawn == 0 then return end
    local t = RepTheme()
    for _, v in ipairs(drawn) do ApplyViewTheme(v, t) end
end

-- A new view drawn as the reputation bar: only the Left, Centre and Right lines, no completed quest
-- or rested XP (those are the experience bar's).
local SLOT_LINES -- below
local function NewRepView(frame, width, height)
    local v = B.NewView(frame, width, height, true, true)
    local used = {}
    for _, line in pairs(SLOT_LINES) do used[line] = true end
    for _, t in ipairs(v.texts) do
        if not used[t.spec.name] then t.fs:Hide() end
    end
    v.questTex:Hide()
    v.restedTex:Hide()
    v.liquid:SetOptions(db)
    v.liquid:SetRested(false)
    return v
end

-- What the bar can show on its left, in the middle and on its right. f is the faction as shown:
-- its standing and value are the displayed ones, mid-pour included.
local function Shown()
    if not T then return end
    local value = floor(R.fill * R.span + 0.5)
    return T, R.reaction, value, R.span, T.capped and R.reaction == T.reaction
end

local SLOTS = {
    { key = "none", name = "Nothing", text = function() return "" end },
    { key = "name", name = "Faction", text = function(f) return f.name end },
    { key = "standing", name = "Standing", text = function(_, reaction) return StandingName(reaction) end },
    { key = "nameStanding", name = "Faction & Standing", text = function(f, reaction)
        return f.name .. " (" .. StandingName(reaction) .. ")"
    end },
    { key = "value", name = "Reputation", poured = true, text = function(_, _, value, span, capped)
        if capped then return "" end
        return FormatNumber(value) .. " / " .. FormatNumber(span)
    end },
    { key = "percent", name = "Percentage", poured = true, text = function(_, _, value, span, capped)
        if capped then return "" end
        return Round1(value / span * 100) .. "%"
    end },
    { key = "remaining", name = "To Next Standing", poured = true, text = function(_, reaction, value, span, capped)
        if capped then return "" end
        local nextName = reaction < MAX_REACTION and StandingName(reaction + 1)
        return FormatNumber(span - value) .. (nextName and (" to " .. nextName) or " to go")
    end },
    { key = "session", name = "Gained This Session", text = function(f)
        local gained = SessionGain(f)
        if gained == 0 or sim then return "" end
        return (gained > 0 and "+" or "") .. FormatNumber(gained) .. " this session"
    end },
}
local SLOT_TEXT, SLOT_POURED = {}, {}
for _, slot in ipairs(SLOTS) do
    SLOT_TEXT[slot.key] = slot.text
    SLOT_POURED[slot.key] = slot.poured
end
-- The view's lines used for Left, Centre and Right; NewView makes the rest, which stay hidden.
SLOT_LINES = { repLeft = "levelText", repCentre = "xpText", repRight = "pctText" }

-- The game's own text on its reputation bar ("Stormwind 1,234 / 3,000"), faded while ours is in
-- the middle or shows the same numbers.
local function HidesGameText()
    return db.repCentre ~= "none" or db.repLeft == "value" or db.repRight == "value"
end

local renderedFill

-- force: every slot; otherwise only those that follow the liquid, and only when it has moved.
local function RenderTexts(force)
    if not force and renderedFill == R.fill then return end
    renderedFill = R.fill
    local f, reaction, value, span, capped = Shown()
    for setting, line in pairs(SLOT_LINES) do
        local key = SLOT_TEXT[db[setting]] and db[setting] or "none"
        if force or SLOT_POURED[key] then
            local text = f and SLOT_TEXT[key](f, reaction, value, span, capped) or ""
            for _, v in ipairs(drawn) do
                v[line]:SetText(text)
                v[line]:Show()
            end
        end
    end
end

-- The separate bar's lines around it while it tracks reputation, in the places and under the
-- settings of the experience ones: this session's gains above left, the session time above right,
-- the time to the next standing at this session's rate below left, and what is left to Exalted below
-- right. Its view's line name -> the setting that shows it.
local AROUND = { levelTime = "showLevelTime", sessionTime = "showSessionTime", levelInText = "showXPHour",
                 qrText = "showQuestRested" }

local function Hourly(n)
    return n > 10000 and (Round1(n / 1000) .. "K") or FormatNumber(n)
end

-- Reputation from here to the top of Exalted, using the classic standings' sizes beyond this one.
local function ToExalted(f)
    local left = f.span - f.value
    for r = f.reaction + 1, MAX_REACTION - 1 do left = left + STANDING_SPANS[r] end
    return left
end

-- This session's numbers for a faction, as shown around the separate bar and in the tooltip:
-- gained (signed text), session (time), hourly (reputation per hour), nextName (the next standing,
-- nil at the top), toNext (the time to it at this session's rate, "--" without gains).
local function Stats(f)
    local gained, elapsed = SessionGain(f)
    local cdb = B.CharDB()
    local hourly = (elapsed > 0 and gained > 0) and ceil(gained / (elapsed / 3600)) or 0
    return {
        gained = (gained > 0 and "+" or "") .. FormatNumber(gained),
        session = B.FormatTime(cdb and cdb.startTime and time() - cdb.startTime or 0),
        hourly = Hourly(hourly),
        nextName = f.reaction < MAX_REACTION and StandingName(f.reaction + 1) or nil,
        toNext = hourly > 0 and B.FormatTime(ceil((f.span - f.value) / hourly * 3600)) or "--",
    }
end

local function RenderStats()
    if not barView then return end
    local f = T
    for line, setting in pairs(AROUND) do
        local shown = db[setting] and f ~= nil
        if f and f.capped and (line == "levelInText" or line == "qrText") then shown = false end
        barView[line]:SetShown(shown)
    end
    if not f then return end
    local st = Stats(f)
    barView.levelTime:SetText("Gained this session: " .. st.gained)
    barView.sessionTime:SetText("Time this session: " .. st.session)
    if f.capped then return end
    barView.levelInText:SetText(string.format("%s in: %s (%s Rep/Hour)", st.nextName or "Next", st.toNext, st.hourly))
    barView.qrText:SetText(f.reaction < MAX_REACTION
        and ("To " .. StandingName(MAX_REACTION) .. ": " .. FormatNumber(ToExalted(f))) or "")
end

-- force: everything, the texts even while out of sight, so they are current when the game shows the
-- bar again (its container can be hidden while ours is attached).
local function Render(force)
    if #drawn == 0 then return end
    if force then
        RenderTexts(true)
        RenderStats()
    end
    for _, v in ipairs(drawn) do
        if v.frame:IsVisible() then
            local w = v.width
            B.Place(v.leadTex, R.fill * w, (R.lead - R.fill) * w, v.liquid:Back())
            v.flash:SetAlpha(R.flash * 0.35)
        end
    end
    if not force then RenderTexts() end
end

local function Snap()
    R.fill, R.vel, R.hold, R.flash, R.wrap = Target(), 0, 0, 0, false
    R.lead, R.reaction, R.span = R.fill, T.reaction, T.span
    R.ready, animating = true, false
    for _, v in ipairs(drawn) do v.liquid:Snap(R.fill * v.width) end
    ApplyTheme()
    Render(true)
end

-- The separate bar tracks reputation: set to, or set to at max level and there.
local function SeparateTracksRep()
    local mode = db.separateTracks
    return db.bars ~= "default" and (mode == "rep" or (mode == "auto" and B.Maxed()))
end

local function RepWanted()
    return db.repBar or SeparateTracksRep()
end

local function SetWatching(on)
    if on == watching then return end
    watching = on
    if barView then B.ShowViews() end
end

local function Refresh()
    if not RepWanted() then return end
    local f = Watched()
    pending = f == false
    if f == nil then
        SetWatching(false)
        T = nil
        animating, R.wrap = false, false
    end
    if not f then return end
    SetWatching(true)
    local session = RepSession()
    if not sim and session.start[f.id] == nil then session.start[f.id] = { total = f.total, at = time() } end
    local last = T
    T = f
    if #drawn == 0 then return end
    -- Another faction, a lower standing or a standing that changed size (paragon): straight there.
    if not R.ready or not last or last.id ~= f.id or f.reaction < last.reaction
        or (f.reaction == last.reaction and f.span ~= last.span) then
        Snap()
        return
    end

    local target, gained, span = Target(), 0, last.span
    if f.reaction > last.reaction then
        -- A new standing: pour to the end of this one, then flash and fill the next from empty.
        R.wrap, R.lead = true, 1
        gained = last.span - last.value + f.value
    else
        gained = f.value - last.value
        if target > R.lead + ANIM.epsilon then
            R.lead = target
            if R.vel == 0 then R.hold = ANIM.hold end
        elseif target < R.lead and not R.wrap then
            R.lead = max(target, R.fill)
        end
    end
    if gained > 0 then
        local intensity = min(1, (gained / span / ANIM.bigGain) ^ 0.5)
        for _, v in ipairs(drawn) do v.liquid:Splash(intensity, R.fill * v.width, R.lead * v.width) end
        if barView then B.WakeBar() end -- Fade When Idle: gains bring the separate bar back
    end
    animating = true
    Render(true)
end

local function Step(dt)
    local themeSpeed = drawn[1].theme.fillSpeed or 1
    if R.wrap then themeSpeed = max(1, themeSpeed) end
    local w = ANIM.rate * db.speed * themeSpeed * ANIM.spring
    local target = Target()
    if R.hold > 0 then
        R.hold = R.hold - dt
    else
        R.fill, R.vel = B.Spring(R.fill, R.vel, R.wrap and 1 + ANIM.overshoot or target, dt, w)
    end
    if R.wrap and R.fill >= 1 and T then
        R.wrap = false
        R.fill, R.vel, R.hold, R.lead = 0, 0, 0.08, target
        R.flash = db.flash and 1 or 0
        R.reaction, R.span = T.reaction, T.span
        ApplyTheme() -- the new standing's colours, before its burst
        for _, v in ipairs(drawn) do
            v.liquid:Snap(0)
            v.liquid:LevelUp()
        end
        RenderTexts(true)
    end
    if R.fill > 1 then R.fill = 1 end
    if R.lead < R.fill then R.lead = R.fill end
    if R.flash > 0 then R.flash = max(0, R.flash - dt / ANIM.flash) end
    if not R.wrap and R.hold <= 0 and R.fill == target and R.flash == 0 then
        R.lead = R.fill
        animating = false
    end
end

--------------------------------------------------------------------------------
-- Previews for the setup wizard: a made-up faction gaining reputation every few seconds, standing
-- after standing, so the standing colours change as it goes.
--------------------------------------------------------------------------------

local previews = {}
local PREVIEW = { name = "Stormwind", start = 0.35, every = 2.2, gain = 0.2, first = 3, reaction = 4 }

local function PreviewTheme(v)
    local key = v.themeKey
    if key ~= Themes.standing and Themes.list[key] then return B.ResolveTheme(key) end
    return Themes.Standing(v.demo.reaction)
end

local function PreviewTexts(v)
    local d = v.demo
    local span = STANDING_SPANS[d.reaction]
    v.levelText:SetText(PREVIEW.name)
    v.xpText:SetText(FormatNumber(floor(min(1, d.fill) * span + 0.5)) .. " / " .. FormatNumber(span))
    v.pctText:SetText(StandingName(d.reaction))
end

function Core.NewRepPreview(parent, width, height)
    local frame = CreateFrame("Frame", nil, parent)
    frame:SetSize(width, height)
    local v = NewRepView(frame, width, height)
    v.preview, v.themeKey = true, Themes.standing
    v.demo = { fill = PREVIEW.start, vel = 0, target = PREVIEW.start, wait = PREVIEW.every, flash = 0,
               reaction = PREVIEW.reaction }
    v.liquid:Snap(PREVIEW.start * width)
    ApplyViewTheme(v, PreviewTheme(v))
    B.ApplyRounding(v)
    B.ApplyTextSize(v)
    PreviewTexts(v)
    previews[#previews + 1] = v
    return v
end

-- themeKey: a theme, or Themes.standing for the standing colours. opts: the effect settings to show.
function Core.StyleRepPreview(v, themeKey, opts)
    v.themeKey = themeKey
    if opts ~= v.opts then
        v.opts = opts
        v.liquid:SetOptions(opts or db)
    end
    ApplyViewTheme(v, PreviewTheme(v))
    B.ApplyRounding(v)
end

local function StepPreview(v, dt)
    local d, w = v.demo, v.width
    d.wait = d.wait - dt
    if d.wait <= 0 then
        d.wait = PREVIEW.every
        d.target = d.target + PREVIEW.gain
        v.liquid:Splash(0.5, d.fill * w, min(1, d.target) * w)
    end
    local goal = d.target >= 1 and 1 + ANIM.overshoot or d.target
    d.fill, d.vel = B.Spring(d.fill, d.vel, goal, dt, ANIM.rate * ANIM.spring)
    if d.fill >= 1 then
        -- The next standing, after Exalted back round to the first shown.
        d.fill, d.vel, d.target = 0, 0, d.target - 1
        d.reaction = d.reaction < MAX_REACTION and d.reaction + 1 or PREVIEW.first
        d.flash = (v.opts or db).flash and 1 or 0
        ApplyViewTheme(v, PreviewTheme(v))
        v.liquid:Snap(0)
        v.liquid:LevelUp()
    end
    if d.flash > 0 then d.flash = max(0, d.flash - dt / ANIM.flash) end
    v.flash:SetAlpha(d.flash * 0.35)
    v.liquid:Update(dt, d.fill * w)
    PreviewTexts(v)
end

-- A view to draw: shown, and not the separate bar faded all the way out (Fade When Idle).
local function InSight(v)
    return v.frame:IsVisible() and v.frame:GetAlpha() > 0
end

-- Runs while a bar or a preview is in sight; the bars, once settled, at the idle rate.
local driver = CreateFrame("Frame")
driver:SetScript("OnUpdate", function(_, elapsed)
    for _, v in ipairs(previews) do
        if v.frame:IsVisible() and elapsed > 0 then StepPreview(v, min(elapsed, 0.1)) end
    end
    if not R.ready then return end
    local seen, quiet = false, true
    for _, v in ipairs(drawn) do
        if InSight(v) then
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
    local dt = min(elapsed, 0.1)
    if animating then Step(dt) end
    for _, v in ipairs(drawn) do
        if InSight(v) then v.liquid:Update(dt, R.fill * v.width) end
    end
    Render()
end)

--------------------------------------------------------------------------------
-- Tooltip
--------------------------------------------------------------------------------

local function Hex(c)
    return string.format("%02X%02X%02X", floor(c[1] * 255 + 0.5), floor(c[2] * 255 + 0.5), floor(c[3] * 255 + 0.5))
end

-- The tooltip of either reputation bar: the faction and standing, then this session, as the
-- experience bar's tooltip has them. Above the game's bar, below the separate one (it starts at the
-- top of the screen).
local function ShowTooltip(frame)
    local f = T
    if not (db.repTooltip and f) then return end
    local st = Stats(f)
    GameTooltip:SetOwner(frame, frame == B.main.frame and "ANCHOR_BOTTOM" or "ANCHOR_TOP")
    GameTooltip:AddLine(f.name, 1, 1, 1)
    B.TooltipRow("Standing", "|cFF" .. Hex(Themes.StandingColor(f.reaction)) .. StandingName(f.reaction) .. "|r")
    if not f.capped then
        B.TooltipRow("Reputation", string.format("%s / %s (%s%%)", FormatNumber(f.value), FormatNumber(f.span),
            Round1(f.value / f.span * 100)))
        B.TooltipRow(st.nextName and ("To " .. st.nextName) or "Remaining", FormatNumber(f.span - f.value))
        -- Below Revered, the way to Exalted is longer than to the next standing.
        if f.reaction < MAX_REACTION - 1 then
            B.TooltipRow("To " .. StandingName(MAX_REACTION), FormatNumber(ToExalted(f)))
        end
    end
    GameTooltip:AddLine(" ")
    B.TooltipRow("Gained this session", st.gained)
    B.TooltipRow("Time this session", st.session)
    if not f.capped then
        B.TooltipRow((st.nextName or "Next") .. " in", st.toNext)
        B.TooltipRow("Reputation per hour", st.hourly)
    end
    GameTooltip:AddLine(" ")
    GameTooltip:AddLine("Right-click for settings", 0.62, 0.62, 0.62)
    GameTooltip:Show()
end

--------------------------------------------------------------------------------
-- Drawing over the game's reputation bar
--------------------------------------------------------------------------------

local target, fill -- the game's reputation bar we are drawn over, and the fill in it
-- The Left, Centre and Right text sizes, on either bar.
local SIZE_KEYS = { levelText = "repLeftSize", xpText = "repCentreSize", pctText = "repRightSize" }
local gameTexts = { list = {}, muted = {} }
local ApplySkin

local function OnViewResized(w, h)
    view.width, view.height = w, h
    view.liquid:SetSize(w, h)
    view.liquid:Snap(R.fill * w)
    B.ApplyTextSize(view)
    B.ApplyRounding(view)
    Render(true)
end

-- Made the first time it is needed, so players who never turn it on pay nothing for it.
local function View()
    if view then return view end
    local frame = CreateFrame("Frame", "SmoothExperienceBarReputationFrame", UIParent)
    frame:SetSize(571, 13)
    frame:Hide()
    frame:EnableMouse(true)
    frame:SetScript("OnMouseUp", B.OpenSettingsOnRightClick)
    frame:SetScript("OnEnter", ShowTooltip)
    frame:SetScript("OnLeave", function() GameTooltip:Hide() end)
    view = NewRepView(frame, 571, 13)
    view.sizeKeys = SIZE_KEYS
    frame:SetScript("OnSizeChanged", function(_, w, h)
        if w ~= view.width or h ~= view.height then OnViewResized(w, h) end
    end)
    UpdateDrawn()
    ApplyTheme()
    B.ApplyRounding(view)
    B.ApplyTextSize(view)
    return view
end

local function Unskin()
    if not target then return end
    B.MuteGameTexts(gameTexts, false)
    gameTexts.list = {}
    target, fill = nil, nil
    B.DetachView(view)
end

local function OnGameBarShown()
    if db.repBar then ApplySkin() end
end

-- Runs on login, when the setting or the watched faction changes, when the game shows its bar and
-- every second while it is on, so the view follows the game moving or resizing its bar.
function ApplySkin()
    if not db.repBar then
        Unskin()
        return
    end
    local t, f = B.GameBar("Reputation", target, OnGameBarShown)
    if not t then
        Unskin()
        return
    end
    local w, h = f:GetWidth(), f:GetHeight()
    if w < 1 or h < 1 then return end -- not laid out yet; the ticker tries again
    local v = View()
    local moved = t ~= target or f ~= fill
    if moved then
        B.MuteGameTexts(gameTexts, false)
        gameTexts.list = B.FindGameTexts(t, v.frame)
        target, fill = t, f
        B.AttachView(v, t, f)
        v.frame:Show()
    end
    if w ~= v.width or h ~= v.height then v.frame:SetSize(w, h) end
    -- Above the action bars, the bar's ends are under the game's end caps.
    B.FitTextToCaps(v, f)
    B.MuteGameTexts(gameTexts, HidesGameText())
    if moved then
        R.ready = false
        Refresh()
    end
end

--------------------------------------------------------------------------------
-- The separate bar tracking reputation
--------------------------------------------------------------------------------

local separateOwner = {
    Shown = function() return watching end, -- hidden while no faction is watched
    Fill = function() return R.fill end,
    Tooltip = ShowTooltip, -- on hover while the bar is locked
}

-- Takes the separate bar over from the experience bar while it should track reputation, and gives
-- it back once it should not. Runs on login, when the settings change and every second (a level-up
-- to max level can switch it).
local function ApplySeparate()
    local want = SeparateTracksRep()
    if want and not barView then
        barView = B.main
        B.SetSeparateOwner(separateOwner)
        barView.sizeKeys = SIZE_KEYS
        for _, line in pairs(SLOT_LINES) do barView[line]:SetText("") end
        B.ApplyTextSize(barView)
        UpdateDrawn()
        -- Read afresh: until now reputation may not have been tracked at all.
        R.ready = false
        Refresh()
        B.ShowViews()
    elseif not want and barView then
        barView = nil
        UpdateDrawn()
        B.SetSeparateOwner(nil)
    end
end

--------------------------------------------------------------------------------
-- Settings, previews and events
--------------------------------------------------------------------------------

local function EndThemePreview()
    if previewWatch then
        previewWatch:Cancel()
        previewWatch = nil
    end
    if previewTheme then
        previewTheme = nil
        ApplyTheme()
    end
end

-- The themes on offer, Standing Colours first: { key, name } in menu order.
function Core.RepThemes()
    local list = { { key = Themes.standing, name = Themes.standingName } }
    for _, key in ipairs(Themes.order) do list[#list + 1] = { key = key, name = Themes.list[key].name } end
    return list
end

-- Hovering a theme in the open picker shows it on the bar until the menu closes.
function Core.PreviewRepTheme(key)
    if not (Menu and Menu.GetManager) then return end
    previewTheme = key ~= db.repTheme and key or nil
    ApplyTheme()
    if not previewWatch then
        previewWatch = C_Timer.NewTicker(0.1, function()
            if not Menu.GetManager():IsAnyMenuOpen() then EndThemePreview() end
        end)
    end
end

-- The choices for the bar's Left, Centre and Right: { key, name } in menu order.
function Core.RepSlots()
    local list = {}
    for _, slot in ipairs(SLOTS) do list[#list + 1] = { key = slot.key, name = slot.name } end
    return list
end

local function ApplyTexts()
    if #drawn == 0 then return end
    RenderTexts(true)
    if target then B.MuteGameTexts(gameTexts, HidesGameText()) end
end

local WATCH_HINT = "The reputation bar shows while you watch a faction: tick Show as Experience Bar for one "
    .. "in the Reputation panel."

local apply = B.settingApply
apply.repBar = function()
    B.ApplyBlizzardBar()
    ApplySkin()
    Refresh()
    if db.repBar and Watched() == nil then B.Print(WATCH_HINT) end
end
apply.separateTracks = function()
    ApplySeparate()
    if SeparateTracksRep() and Watched() == nil then B.Print(WATCH_HINT) end
end
-- Showing only the game's experience bar gives the separate bar back.
local applyBars = apply.bars
apply.bars = function()
    applyBars()
    ApplySeparate()
end
apply.repTheme = function()
    previewTheme = nil -- picked from the menu: the saved theme takes over
    ApplyTheme()
end
apply.repLeft, apply.repCentre, apply.repRight = ApplyTexts, ApplyTexts, ApplyTexts
local function ApplySize()
    for _, v in ipairs(drawn) do B.ApplyTextSize(v) end
end
apply.repLeftSize, apply.repCentreSize, apply.repRightSize = ApplySize, ApplySize, ApplySize
-- The separate bar's line settings, also for its reputation lines.
for _, setting in pairs(AROUND) do
    local applyXP = apply[setting]
    apply[setting] = function()
        if applyXP then applyXP() end
        RenderStats()
    end
end
apply.repTooltip = function()
    for _, v in ipairs(drawn) do
        if GameTooltip:IsOwned(v.frame) then GameTooltip:Hide() end
    end
end

-- Previews on the watched faction: "rep" gains a tenth of the standing, "standing" moves up one.
local function Test(kind)
    if not RepWanted() then
        B.Print("Turn on a reputation bar in the settings to preview it.")
        return
    end
    if not (sim or T) then
        B.Print("Watch a faction (Show as Experience Bar in the Reputation panel) to preview the reputation bar.")
        return
    end
    if not sim then
        sim = {}
        for k, v in pairs(T) do sim[k] = v end
        sim.capped = false
    end
    local gain = kind == "standing" and (sim.span - sim.value + floor(sim.span * 0.25)) or floor(sim.span * 0.1)
    sim.value, sim.total = sim.value + gain, sim.total + gain
    while sim.value >= sim.span and sim.reaction < MAX_REACTION do
        sim.value = sim.value - sim.span
        sim.reaction = sim.reaction + 1
        sim.span = STANDING_SPANS[sim.reaction]
    end
    sim.value = min(sim.value, sim.span)
    Refresh()
end

-- Reset Session restarts this session's reputation too: from the watched faction's reputation now, so the next
-- gain counts (the next reading would come only after it).
local XPResetSession = Core.ResetSession
function Core.ResetSession()
    XPResetSession()
    if T and not sim then RepSession().start[T.id] = { total = T.total, at = time() } end
    Render(true)
end

-- Whether a reputation bar shows now, for the settings page's previews: the game's, or the separate bar while
-- it tracks reputation (set to, or set to at max level and there).
function Core.RepShowing()
    return RepWanted()
end

-- /seb test rep and /seb test standing; /seb test off ends these previews too.
local XPTest = Core.Test
function Core.Test(kind, amount)
    if kind == "rep" or kind == "standing" then return Test(kind) end
    if kind == "off" and sim then
        sim = nil
        R.ready = false
        Refresh()
    end
    return XPTest(kind, amount)
end

for i, line in ipairs(B.help) do
    if line:find("^/seb test off") then
        table.insert(B.help, i, "/seb test rep - simulate a reputation gain, /seb test standing a new standing")
        break
    end
end

-- A profile's reputation settings that are not ones known here (hand-edited, or from a newer version), set back to
-- their defaults: at load and when copying another character's.
B.AddValidator(function(profile)
    local fixed = {}
    local function Check(key, ok)
        if profile[key] ~= nil and not ok then fixed[key] = D[key] end
    end
    Check("separateTracks", TRACKS[profile.separateTracks])
    Check("repTheme", profile.repTheme == Themes.standing or Themes.list[profile.repTheme])
    for setting in pairs(SLOT_LINES) do Check(setting, SLOT_TEXT[profile[setting]]) end
    return fixed
end)

B.OnLoaded(function(saved)
    db = saved
end)

-- After the main file's login handling: the session is started and max level known by then.
B.OnWorld(function()
    ApplyTheme() -- class and faction themes are known now
    ApplySkin()
    ApplySeparate()
    Refresh()
end)

local events = CreateFrame("Frame")
events:RegisterEvent("UPDATE_FACTION")
events:SetScript("OnEvent", function()
    ApplySkin()
    Refresh()
end)

-- For the tests: the view, the displayed state, the faction as last read and the bar drawn over.
ns.Reputation = {
    State = function() return { view = view, bar = barView, shown = R, faction = T, target = target } end,
}

C_Timer.NewTicker(1, function()
    ApplySeparate()
    if not RepWanted() then return end
    ApplySkin()
    if pending then Refresh() end
    -- Keep the tooltip and this session's gains current.
    for _, v in ipairs(drawn) do
        if GameTooltip:IsShown() and GameTooltip:IsOwned(v.frame) and (v ~= barView or db.locked) then
            ShowTooltip(v.frame)
        end
    end
    if R.ready then Render(true) end
end)
