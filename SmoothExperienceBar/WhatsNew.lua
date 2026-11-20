-- The in-game changelog, as Smooth Animated Bars' and Road to Sixty's: once per account for each release, a window
-- with the notes of every version the account has not seen, newest first, a few seconds after login and never in
-- combat. /seb changes and the settings page open it again. The notes are CHANGELOG.md's, in WhatsNewData.lua, which
-- the build writes (tools/whatsnew_data.py, run by scripts/package.ps1); a dev install has none until that script is
-- run by hand.
--
--   SmoothExperienceBarDB.whatsNewSeen = the newest version the window has shown, or the version a new account
--                                        started on
--
-- Only a full release (X.Y.Z) shows it at login, never a dev build. A new account shows nothing (the setup wizard
-- greets it) and notes its first version quietly; so does an account whose setup is still to be done, as the wizard
-- walks through everything. An account that already had the addon but no whatsNewSeen (updating into the first
-- version with the window) sees that version's notes. The window is built like the setup wizard's, from the game's
-- own window template, with the addon's own icon (game files by path are unreliable on Forever).

local addonName, ns = ...

local WhatsNew = {}
ns.WhatsNew = WhatsNew

local DELAY = 6             -- seconds after login before it shows
local MOST = 8              -- versions shown at most; the rest are in the release notes
local W, H = 520, 470
local ICON = "Interface\\AddOns\\SmoothExperienceBar\\Media\\Icon"
local GOLD = { 1, 0.82, 0 }
local SECTION_COLORS = { New = GOLD, Fixed = { 0.45, 0.85, 0.6 } }
local RULE = { 0.32, 0.30, 0.36 }

-- A version's three numbers, or nil for anything but X.Y.Z.
local function Parts(version)
    local a, b, c = tostring(version or ""):match("^(%d+)%.(%d+)%.(%d+)$")
    if a then return tonumber(a), tonumber(b), tonumber(c) end
end

-- Whether version a is newer than b; false when either is not X.Y.Z.
function WhatsNew.Newer(a, b)
    local a1, a2, a3 = Parts(a)
    local b1, b2, b3 = Parts(b)
    if not a1 or not b1 then return false end
    if a1 ~= b1 then return a1 > b1 end
    if a2 ~= b2 then return a2 > b2 end
    return a3 > b3
end

-- The versions of data (newest first) after seen, up to current, at most MOST; list.cut when there were more.
function WhatsNew.Unseen(data, current, seen)
    local list = {}
    for _, v in ipairs(data) do
        if not WhatsNew.Newer(v.version, current) and WhatsNew.Newer(v.version, seen) then
            if #list >= MOST then
                list.cut = true
                break
            end
            list[#list + 1] = v
        end
    end
    return list
end

-- What a login shows, and the seen version to keep once it has: the list may be nil or empty when nothing shows.
-- known: the account had the addon before.
function WhatsNew.AtLogin(data, current, seen, known)
    if not Parts(current) then return nil, seen end
    if not seen then
        if not known then return nil, current end
        for _, v in ipairs(data) do
            if v.version == current then return { v }, current end
        end
        return nil, current
    end
    if not WhatsNew.Newer(current, seen) then return nil, seen end
    return WhatsNew.Unseen(data, current, seen), current
end

local function Version()
    local get = (C_AddOns and C_AddOns.GetAddOnMetadata) or rawget(_G, "GetAddOnMetadata")
    return get and get(addonName, "Version")
end

--------------------------------------------------------------------------------
-- The window
--------------------------------------------------------------------------------

local frame

-- The game's own window, as the setup wizard's: metal border, dark background, gold title.
local function Window()
    local ok, f = pcall(CreateFrame, "Frame", "SmoothExperienceBarWhatsNew", UIParent, "ButtonFrameTemplate")
    if not ok then
        f = CreateFrame("Frame", "SmoothExperienceBarWhatsNew", UIParent)
        local bg = f:CreateTexture(nil, "BACKGROUND")
        bg:SetAllPoints()
        bg:SetColorTexture(0.06, 0.06, 0.08, 0.96)
        return f
    end
    if ButtonFrameTemplate_HidePortrait then ButtonFrameTemplate_HidePortrait(f) end
    if ButtonFrameTemplate_HideButtonBar then ButtonFrameTemplate_HideButtonBar(f) end
    if f.Inset then f.Inset:Hide() end
    if f.Bg then
        -- Era's and Anniversary's window has the classic border, whose inside starts at the template's own offset.
        local interface = select(4, GetBuildInfo())
        local classic = interface < 16000 or interface >= 17000
        local left = classic and select(4, f.Bg:GetPoint(1)) or 6
        f.Bg:SetPoint("TOPLEFT", left, -21)
        if f.TopTileStreaks then f.TopTileStreaks:SetPoint("TOPLEFT", left, -21) end
    end
    return f
end

local function Button(parent, text, width, onClick)
    local b = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    b:SetSize(width, 26)
    b:SetText(text)
    b:SetScript("OnClick", onClick)
    return b
end

-- Font strings and rules from the window's pools, reused each fill.
local function Text(font, used)
    local pool = frame.pools[font] or {}
    frame.pools[font] = pool
    used[font] = (used[font] or 0) + 1
    local fs = pool[used[font]]
    if not fs then
        fs = frame.child:CreateFontString(nil, "OVERLAY", font)
        fs:SetJustifyH("LEFT")
        fs:SetWordWrap(true)
        pool[used[font]] = fs
    end
    fs:ClearAllPoints()
    fs:SetTextColor(1, 1, 1)
    fs:Show()
    return fs
end

local function Rule(used)
    used.rules = (used.rules or 0) + 1
    local line = frame.rules[used.rules]
    if not line then
        line = frame.child:CreateTexture(nil, "ARTWORK")
        line:SetHeight(1)
        line:SetColorTexture(RULE[1], RULE[2], RULE[3], 1)
        frame.rules[used.rules] = line
    end
    line:ClearAllPoints()
    line:Show()
    return line
end

local function Create()
    frame = Window()
    frame:SetSize(W, H)
    frame:SetPoint("CENTER", 0, 40)
    frame:SetFrameStrata("DIALOG")
    frame:SetToplevel(true)
    frame:SetClampedToScreen(true)
    frame:EnableMouse(true)
    frame:SetMovable(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", frame.StartMoving)
    frame:SetScript("OnDragStop", frame.StopMovingOrSizing)
    frame:Hide()
    table.insert(UISpecialFrames, "SmoothExperienceBarWhatsNew")
    if frame.SetTitle then
        frame:SetTitle("Smooth Experience Bar")
    elseif frame.TitleText then
        frame.TitleText:SetText("Smooth Experience Bar")
    end

    -- The addon's icon and the heading.
    local icon = frame:CreateTexture(nil, "ARTWORK")
    icon:SetTexture(ICON)
    icon:SetSize(40, 40)
    icon:SetPoint("TOPLEFT", 22, -34)
    local heading = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    heading:SetPoint("TOPLEFT", icon, "TOPRIGHT", 12, -4)
    heading:SetText("What's New")
    frame.subtitle = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    frame.subtitle:SetPoint("TOPLEFT", heading, "BOTTOMLEFT", 0, -6)

    local scroll = CreateFrame("ScrollFrame", nil, frame)
    scroll:SetPoint("TOPLEFT", 26, -86)
    scroll:SetPoint("BOTTOMRIGHT", -34, 52)
    frame.child = CreateFrame("Frame", nil, scroll)
    frame.child:SetSize(W - 26 - 34, 1)
    scroll:SetScrollChild(frame.child)
    if ScrollUtil and ScrollUtil.InitScrollFrameWithScrollBar then
        local bar = CreateFrame("EventFrame", nil, frame, "MinimalScrollBar")
        ScrollUtil.InitScrollFrameWithScrollBar(scroll, bar)
        bar:SetPoint("TOPLEFT", scroll, "TOPRIGHT", 8, -2)
        bar:SetPoint("BOTTOMLEFT", scroll, "BOTTOMRIGHT", 8, 2)
    else
        scroll:EnableMouseWheel(true)
        scroll:SetScript("OnMouseWheel", function(self, delta)
            local offset = self:GetVerticalScroll() - delta * 40
            self:SetVerticalScroll(math.max(0, math.min(self:GetVerticalScrollRange(), offset)))
        end)
    end
    frame.scroll = scroll
    frame.pools, frame.rules = {}, {}

    local close = Button(frame, "Close", 100, function() frame:Hide() end)
    close:SetPoint("BOTTOMRIGHT", -16, 14)
    local settings = Button(frame, "Open Settings", 130, function()
        frame:Hide()
        ns.Core.OpenSettings()
    end)
    settings:SetPoint("RIGHT", close, "LEFT", -8, 0)
end

-- Fills the window with list's versions: each version's number over a rule, its sections in their colours, each
-- note a gold bullet with its lines hanging after it. A note with a title ({ title, text }, from a bold start in
-- CHANGELOG.md) has the title on its own line, in gold, over its text.
local function Fill(list)
    for _, pool in pairs(frame.pools) do
        for _, fs in ipairs(pool) do fs:Hide() end
    end
    for _, line in ipairs(frame.rules) do line:Hide() end
    local used, y, width = {}, 0, frame.child:GetWidth()
    local function Place(fs, x, gap)
        y = y + gap
        fs:SetPoint("TOPLEFT", x, -y)
        fs:SetWidth(width - x)
        y = y + fs:GetStringHeight()
    end
    for i, v in ipairs(list) do
        local head = Text("GameFontHighlightLarge", used)
        head:SetText(v.version)
        Place(head, 0, i == 1 and 2 or 20)
        local rule = Rule(used)
        rule:SetPoint("TOPLEFT", 0, -(y + 4))
        rule:SetPoint("TOPRIGHT", -4, -(y + 4))
        y = y + 6
        for _, section in ipairs(v.sections) do
            local title = Text("GameFontNormal", used)
            title:SetText(section[1]:upper())
            local c = SECTION_COLORS[section[1]] or GOLD
            title:SetTextColor(c[1], c[2], c[3])
            Place(title, 0, 8)
            for n, note in ipairs(section[2]) do
                local gap = n == 1 and 6 or 10
                local dot = Text("GameFontNormal", used)
                dot:SetText("\226\128\162") -- a bullet
                dot:SetTextColor(GOLD[1], GOLD[2], GOLD[3])
                dot:SetWidth(10)
                dot:SetPoint("TOPLEFT", 4, -(y + gap))
                local text = note
                if type(note) == "table" then
                    local noteTitle = Text("GameFontNormal", used)
                    noteTitle:SetText(note[1])
                    noteTitle:SetTextColor(GOLD[1], GOLD[2], GOLD[3])
                    Place(noteTitle, 16, gap)
                    text, gap = note[2], 2
                end
                local line = Text("GameFontHighlight", used)
                line:SetText(text)
                line:SetTextColor(0.86, 0.86, 0.84)
                Place(line, 16, gap)
            end
        end
    end
    if list.cut then
        local rest = Text("GameFontDisableSmall", used)
        rest:SetText("Older versions' notes are in the release notes on CurseForge.")
        Place(rest, 0, 18)
    end
    frame.child:SetHeight(math.max(y + 4, 1))
    frame.scroll:SetVerticalScroll(0)
end

-- Shows list's versions (newest first), with a line for older ones when list.cut. The subtitle names the newest.
function WhatsNew.Show(list)
    if not frame then Create() end
    frame.subtitle:SetText(("Version %s"):format(list[1].version))
    Fill(list)
    frame:Show()
end

-- The newest MOST versions, for /seb changes and the settings page. False when this build has no notes.
function WhatsNew.Open()
    local data = ns.WhatsNewData or {}
    if not data[1] then
        DEFAULT_CHAT_FRAME:AddMessage("|cffa070ffSmoothXP|r This build has no changelog. Run tools/whatsnew_data.py "
            .. "to make one.")
        return false
    end
    local list = { cut = #data > MOST }
    for i = 1, math.min(MOST, #data) do list[i] = data[i] end
    WhatsNew.Show(list)
    return true
end

--------------------------------------------------------------------------------
-- At login
--------------------------------------------------------------------------------

local waiting -- { list, seen } until combat ends

local function ShowNow(list, seen)
    if InCombatLockdown() then
        waiting = { list, seen }
        return
    end
    waiting = nil
    ns.Core.Account().whatsNewSeen = seen
    WhatsNew.Show(list)
end

local events = CreateFrame("Frame")
events:RegisterEvent("PLAYER_LOGIN")
events:RegisterEvent("PLAYER_REGEN_ENABLED")
events:SetScript("OnEvent", function(_, event)
    local db = ns.Core.Account() -- the changelog is noted per account
    if not db then return end
    if event == "PLAYER_LOGIN" then
        -- With the setup wizard still to come, it walks through what is new; the notes are noted as seen.
        -- Pending, not SetupWanted: a snooze (Ask Me Later) only ends at PLAYER_ENTERING_WORLD, after this.
        local setup = ns.Core.Get("setupPending")
        local known = ns.Core.AccountKnown() and not setup
        local list, seen = WhatsNew.AtLogin(ns.WhatsNewData or {}, Version(), db.whatsNewSeen, known)
        if not list or not list[1] or (db.whatsNewSeen and setup) then
            db.whatsNewSeen = seen
            return
        end
        -- Noted as seen once it shows, so a /reload before then still shows it.
        C_Timer.After(DELAY, function() ShowNow(list, seen) end)
    elseif waiting then
        ShowNow(waiting[1], waiting[2])
    end
end)

-- For the tests: the window.
function WhatsNew.Frame()
    return frame
end
