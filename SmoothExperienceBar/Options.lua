-- Settings page in the game's AddOns options, built on the native Settings API.
-- Values live directly in the character's profile; changes are forwarded to ns.Core.OnSettingChanged.
--
-- The page is a canvas: one frame of ours, with every row drawn by the game's own row template on a
-- frame of ours, so it looks like the game's pages. It is not a vertical layout list. The game
-- reuses that list's row frames for every category, and on Forever rows set up by our code carried
-- our taint into the Social page, which then had its protected IsUserOAuthed blocked in our name.
-- So nothing is added to the game's lists, and every row is built once at login while the page is
-- hidden, never while the settings panel is open.

local ADDON_NAME, ns = ...

local Options = {}
ns.Options = Options

-- The settings list's own measurements (Blizzard_SettingsList.xml), so the page lines up with the
-- game's: the header strip, where the list sits under it, the row padding, and the row heights.
local HEADER_H, TITLE_X, TITLE_Y = 50, 7, -22
local LIST_X, LIST_Y, LIST_RIGHT, LIST_BOTTOM = -15, -2, -20, -2
local PAD, PAD_LEFT, SPACING = 10, 25, 9
local ROW_H, SECTION_H = 26, 45

local category, canvas, content, db, defaults
local rows = {} -- { frame, initializer, height, when }, in page order
local registered = {}
local LayoutRows

-- The section rows go in: a section for one of the bars shows only while that bar is used, so the
-- page follows the Experience Bar choice. when is a function saying whether its rows show.
local section

local function Register(key, name)
    local default = defaults[key]
    local setting = Settings.RegisterAddOnSetting(category, ADDON_NAME .. "_" .. key, key, db, type(default), name, default)
    setting:SetValueChangedCallback(function(_, value)
        ns.Core.OnSettingChanged(key, value)
        if key == "bars" then LayoutRows() end
    end)
    registered[key] = setting
    return setting
end

-- A row: a frame of ours made from the initializer's template. The template's code finds its
-- initializer through GetElementData, as it does in the game's list. when, if given, narrows the
-- section's own condition for this row.
local function Row(initializer, height, when)
    local frame = CreateFrame("Frame", nil, content, initializer:GetTemplate())
    frame.GetElementData = function() return initializer end
    initializer:InitFrame(frame)
    local inSection = section
    rows[#rows + 1] = {
        frame = frame, initializer = initializer, height = height or ROW_H,
        when = function() return (not inSection or inSection()) and (not when or when()) end,
    }
end

local function Header(text, when)
    section = when
    Row(CreateSettingsListSectionHeaderInitializer(text), SECTION_H)
end

local function Checkbox(key, name, tooltip, when)
    Row(Settings.CreateCheckboxInitializer(Register(key, name), nil, tooltip), nil, when)
end

local function Slider(key, name, tooltip, minValue, maxValue, step, format)
    local sliderOptions = Settings.CreateSliderOptions(minValue, maxValue, step)
    sliderOptions:SetLabelFormatter(MinimalSliderWithSteppersMixin.Label.Right, function(value)
        return format:format(value)
    end)
    Row(Settings.CreateSliderInitializer(Register(key, name), sliderOptions, tooltip))
end

local function Dropdown(setting, tooltip, getOptions)
    Row(Settings.CreateDropdownInitializer(setting, getOptions, tooltip))
end

-- The fifth argument is whether the row adds search tags; the game asserts it is given, and a
-- canvas has nothing for the search to find.
local function Button(name, text, onClick, tooltip)
    Row(CreateSettingsButtonInitializer(name, text, onClick, tooltip, false))
end

-- Which bars are used, as the setup wizard asks it.
local BARS = {
    { "separate", "Separate Bar" },
    { "default", "Default Experience Bar" },
    { "both", "Both" },
}

local function BarOptions()
    local container = Settings.CreateControlTextContainer()
    for _, bar in ipairs(BARS) do container:Add(bar[1], bar[2]) end
    return container:GetData()
end

local function SeparateUsed() return db.bars ~= "default" end
local function DefaultUsed() return db.bars ~= "separate" end
local function SeparateOnly() return db.bars == "separate" end

-- Hovering a theme in the open menu shows it on the bar; the menu calls onEnter with the option.
local function PreviewOption(option)
    ns.Core.PreviewTheme(option.value)
end

local function ThemeOptions()
    local container = Settings.CreateControlTextContainer()
    for _, key in ipairs(ns.Themes.order) do
        local option = container:Add(key, ns.Themes.list[key].name)
        if option then option.onEnter = PreviewOption end
    end
    return container:GetData()
end

local function FontOptions()
    local container = Settings.CreateControlTextContainer()
    for _, font in ipairs(ns.Core.Fonts()) do
        container:Add(font.key, font.name)
    end
    return container:GetData()
end

-- The page frame: the title and divider the game's list draws above its rows, and a scroll frame
-- for the rows where the list would be. The game parents and shows it when the category opens.
local function BuildPage(title)
    canvas = CreateFrame("Frame")
    canvas:Hide()

    local text = canvas:CreateFontString(nil, "ARTWORK", "GameFontHighlightHuge")
    text:SetPoint("TOPLEFT", TITLE_X, TITLE_Y)
    text:SetText(title)

    local divider = canvas:CreateTexture(nil, "ARTWORK")
    divider:SetColorTexture(1, 1, 1, 0.15)
    divider:SetPoint("TOPLEFT", 0, -HEADER_H)
    divider:SetPoint("TOPRIGHT", LIST_RIGHT, -HEADER_H)
    divider:SetHeight(1)

    local scroll = CreateFrame("ScrollFrame", nil, canvas)
    scroll:SetPoint("TOPLEFT", LIST_X, -HEADER_H + LIST_Y)
    scroll:SetPoint("BOTTOMRIGHT", LIST_RIGHT, LIST_BOTTOM)
    content = CreateFrame("Frame", nil, scroll)
    content:SetSize(1, 1)
    scroll:SetScrollChild(content)
    scroll:SetScript("OnSizeChanged", function(_, width)
        if width and width > 0 then content:SetWidth(width) end
    end)

    if ScrollUtil and ScrollUtil.InitScrollFrameWithScrollBar then
        local bar = CreateFrame("EventFrame", nil, canvas, "MinimalScrollBar")
        ScrollUtil.InitScrollFrameWithScrollBar(scroll, bar)
        bar:SetPoint("TOPLEFT", scroll, "TOPRIGHT", 0, -4)
        bar:SetPoint("BOTTOMLEFT", scroll, "BOTTOMRIGHT", -1, 7)
    else
        scroll:EnableMouseWheel(true)
        scroll:SetScript("OnMouseWheel", function(self, delta)
            local offset = self:GetVerticalScroll() - delta * 30
            self:SetVerticalScroll(math.max(0, math.min(self:GetVerticalScrollRange(), offset)))
        end)
    end

    -- Each time the page opens every row reads its setting again, as the game's list does, so
    -- changes made elsewhere (/seb lock, dragging the grip, a copied profile) show.
    canvas:SetScript("OnShow", function()
        for _, row in ipairs(rows) do
            row.initializer:Resetter(row.frame)
            row.initializer:InitFrame(row.frame)
        end
        LayoutRows()
    end)
end

-- Places the rows that show, one under the other, and hides the rest (the sections of a bar not in
-- use). Only moves and hides frames of ours, so it is safe while the settings panel is open.
function LayoutRows()
    local y = PAD
    for _, row in ipairs(rows) do
        local shown = row.when()
        row.frame:SetShown(shown)
        if shown then
            row.frame:ClearAllPoints()
            row.frame:SetPoint("TOPLEFT", content, "TOPLEFT", PAD_LEFT, -y)
            row.frame:SetPoint("TOPRIGHT", content, "TOPRIGHT", 0, -y)
            row.frame:SetHeight(row.height)
            y = y + row.height + SPACING
        end
    end
    content:SetHeight(y - SPACING + PAD)
end

function Options.Register(savedDB, defaultValues)
    if not (Settings and Settings.RegisterCanvasLayoutCategory and Settings.CreateCheckboxInitializer
        and CreateSettingsButtonInitializer and CreateSettingsListSectionHeaderInitializer) then
        return
    end
    db, defaults = savedDB, defaultValues
    local Core = ns.Core
    local title = "Smooth Experience Bar"

    BuildPage(title)
    category = Settings.RegisterCanvasLayoutCategory(canvas, title)

    Header("General")
    Dropdown(Register("bars", "Experience Bar"), "Where your experience shows: a separate bar you move and "
        .. "resize, the game's own experience bar filled with the liquid, or both. Each has its settings below.",
        BarOptions)
    Dropdown(Register("theme", "Theme"), "Colours and effects of the bar.", ThemeOptions)
    Dropdown(Register("font", "Font"), "Font of the bar's text, from the game's own fonts.", FontOptions)
    Checkbox("fontOutline", "Font Outline", "A dark outline around the text. Untick for a plain drop shadow.")
    Checkbox("showMaxLevel", "Show at Max Level", "Keep the bar visible at max level, showing time played.")
    Checkbox("resetOnReload", "Reset Session on Reload", "Restart session time and XP/hour on /reload as well as on login.")

    Header("Separate Bar", SeparateUsed)
    Checkbox("locked", "Lock Bar", "Untick to move the bar by dragging it and resize it from the corner grip.")
    Slider("scale", "Scale", "Size of the whole bar, text included.", 0.4, 1.5, 0.05, "%.2f")
    Slider("width", "Width", "Bar width. Also set by dragging the corner grip while unlocked.", 200, 1600, 10, "%d")
    Slider("height", "Height", "Bar height; text scales with it.", 16, 60, 1, "%d")
    Checkbox("showLevelTime", "Time This Level", "Played time at this level above the bar (total played at max level).")
    Checkbox("showSessionTime", "Session Time", "Time since you logged in, above the bar.")
    Checkbox("showXPHour", "Leveling Time & XP/Hour", "Estimated time to level from this session's XP rate, under the bar.")
    Checkbox("showQuestRested", "Completed & Rested", "Completed quest XP and rested XP as a percentage of the level, under the bar.")
    Checkbox("questBar", "Completed Quest Bar", "The XP of quests ready to turn in, shown after your XP in the bar.")
    Checkbox("restedBar", "Rested Bar", "Your rested XP, shown after your XP (and completed quests) in the bar.")
    Checkbox("rounding", "Rounded Liquid", "Shade the top and bottom of the bar so the liquid looks round.")
    Checkbox("hideBlizzardBar", "Hide Default Experience Bar", "Hide the game's own experience bar.", SeparateOnly)
    Button("Reset Position & Size", "Reset", Core.ResetPosition, "Move the bar back to the top of the screen at its default size.")

    Header("Default Experience Bar", DefaultUsed)
    Checkbox("defaultLevelTime", "Time This Level",
        "Played time at this level on the left of the bar (total played at max level). Untick for no text there.")
    Checkbox("defaultXPText", "XP", "Current and max XP, and the XP still to go, in the middle of the bar. "
        .. "While it shows, the game's own XP text there is hidden so it does not show twice.")
    Checkbox("defaultQuestBar", "Completed Quest Bar", "The XP of quests ready to turn in, shown after your XP in the bar.")
    Checkbox("defaultRestedBar", "Rested Bar", "Your rested XP, shown after your XP (and completed quests) in the bar.")
    Checkbox("defaultTooltip", "Tooltip",
        "Hover the bar for the rest of the numbers: completed and rested XP, session time, XP/hour and the time to level.")

    Header("Animation")
    Slider("speed", "Fill Speed", "How quickly the liquid flows to its new level.", 0.5, 2, 0.1, "%.1fx")
    Checkbox("waves", "Liquid Waves", "Wobbling liquid front that sloshes and ripples on XP gains.")
    Checkbox("swirl", "Magic Swirl", "Glowing veins, clouds and light drifting inside the liquid.")
    Checkbox("bubbles", "Bubbles", "Bubbles rising through the liquid.")
    Checkbox("sparkles", "Sparkles", "Motes thrown off by XP gains, quest turn-ins and level-ups.")
    Checkbox("ambient", "Ambient Particles", "Embers, snow, spores, stars and the like from themes that have them.")
    Checkbox("lightning", "Lightning", "Faint flashes in the liquid at rest that build into a storm with big or rapid XP gains.")
    Checkbox("restedGlow", "Rested Glow", "A soft glow in the liquid while you have rested XP.")
    Checkbox("flash", "Level-Up Flash", "Flash the bar when you level up.")
    Checkbox("glass", "Glass", "Reflections along the bar, as if it were a glass tube.")

    -- Settings are saved per character. Pick another character, then copy their settings onto this one.
    -- The first character starts out chosen: with no value in the list the game shows "Custom".
    Header("Profile")
    local copy = { copyFrom = Core.OtherProfiles()[1] or "" }
    local copySetting = Settings.RegisterAddOnSetting(category, ADDON_NAME .. "_copyFrom", "copyFrom", copy, "string",
        "Copy Settings From", "")
    Dropdown(copySetting, "Settings are saved per character (this is " .. Core.ProfileKey() .. "). Pick another character here, then press Copy.",
        function()
            local container = Settings.CreateControlTextContainer()
            local others = Core.OtherProfiles()
            if #others == 0 then
                container:Add("", "No other characters yet")
            end
            for _, key in ipairs(others) do
                container:Add(key, key)
            end
            return container:GetData()
        end)
    Button("Copy Settings", "Copy", function()
        if copy.copyFrom ~= "" then Core.CopyProfile(copy.copyFrom) end
    end, "Replace this character's settings with the chosen character's.")

    Header("Preview & Reset")
    Button("Preview XP Gain", "Gain", function() Core.Test("gain") end, "Simulate an XP gain. Does not touch your real XP.")
    Button("Preview Quest Turn-In", "Turn In", function() Core.Test("turnin") end, "Simulate completing and turning in a quest.")
    Button("Preview Level-Up", "Level Up", function() Core.Test("level") end, "Simulate a level-up.")
    Button("Stop Preview", "Stop", function() Core.Test("off") end, "Return the bar to your real XP.")
    Button("Reset Session", "Reset", Core.ResetSession, "Restart session time and XP/hour.")
    Button("Setup Wizard", "Open", function() ns.Wizard.Open() end,
        "Pick where the bar goes, its theme, effects and text again, with live previews.")

    LayoutRows()
    Settings.RegisterAddOnCategory(category)
end

-- Set every control from another profile's values, defaults where it has none. Going through the
-- control fires the same callbacks as the player changing it, so the bar and the page both follow.
function Options.SetAll(values)
    for key, setting in pairs(registered) do
        local v = values[key]
        if v == nil then v = defaults[key] end
        setting:SetValue(v)
    end
end

-- Change one setting through its control, as the player would. False when there is no control.
function Options.Set(key, value)
    local setting = registered[key]
    if not setting then return false end
    setting:SetValue(value)
    return true
end

function Options.Open()
    if category and Settings.OpenToCategory then
        Settings.OpenToCategory(category:GetID())
        return true
    end
end
