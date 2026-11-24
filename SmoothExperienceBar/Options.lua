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
local ROW_H, SECTION_H, SUBHEAD_H = 26, 45, 22
-- A row's controls start this far left of its centre, and its label ends just before them
-- (SettingsListElementMixin, SettingsSliderControlMixin).
local CONTROL_X = -80
-- The default bar's text rows: a narrower dropdown, and its size slider beside it.
local SLOT_DROPDOWN_W, SLOT_SLIDER_W, SLOT_GAP = 160, 180, 10
-- Text Size, in percent of the size the line has at the bar's height.
local SIZE_MIN, SIZE_MAX, SIZE_STEP = 50, 200, 5

local category, canvas, content, db, defaults
local rows = {} -- { frame, initializer, height, when, refresh }, in page order
local registered = {}
local watchers = {} -- setting key -> a function to call when it changes, for controls of our own
local LayoutRows

-- The section rows go in: a section for one of the bars shows only while that bar is used, so the
-- page follows the Experience Bar choice. when is a function saying whether its rows show.
local section
-- The settings that decide which rows show; changing one lays the page out again.
local LAYOUT_KEYS = { bars = true, repBar = true, separateTracks = true }

local function Register(key, name)
    local default = defaults[key]
    local setting = Settings.RegisterAddOnSetting(category, ADDON_NAME .. "_" .. key, key, db, type(default), name, default)
    setting:SetValueChangedCallback(function(_, value)
        ns.Core.OnSettingChanged(key, value)
        if LAYOUT_KEYS[key] then LayoutRows() end
        if watchers[key] then watchers[key](value) end
    end)
    registered[key] = setting
    return setting
end

-- A row: a frame of ours made from the initializer's template. The template's code finds its
-- initializer through GetElementData, as it does in the game's list. when, if given, narrows the
-- section's own condition for this row.
local function AddRow(row, when)
    local inSection = section
    row.height = row.height or ROW_H
    row.when = function() return (not inSection or inSection()) and (not when or when()) end
    rows[#rows + 1] = row
    return row
end

-- setup, if given, adjusts the frame before its first Init.
local function Row(initializer, height, when, setup)
    local frame = CreateFrame("Frame", nil, content, initializer:GetTemplate())
    frame.GetElementData = function() return initializer end
    if setup then setup(frame) end
    initializer:InitFrame(frame)
    return AddRow({ frame = frame, initializer = initializer, height = height }, when)
end

local function Header(text, when)
    section = when
    Row(CreateSettingsListSectionHeaderInitializer(text), SECTION_H)
end

-- A group inside a section: white text, smaller than a section's, with a faint line after it.
local function SubHeader(text)
    local frame = CreateFrame("Frame", nil, content)
    local label = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    label:SetPoint("BOTTOMLEFT", 17, 4)
    label:SetText(text)
    local line = frame:CreateTexture(nil, "ARTWORK")
    line:SetColorTexture(1, 1, 1, 0.15)
    line:SetPoint("LEFT", label, "RIGHT", 8, 0)
    line:SetPoint("RIGHT", frame, "RIGHT", -20, 0)
    line:SetHeight(1)
    AddRow({ frame = frame, height = SUBHEAD_H })
end

local function Checkbox(key, name, tooltip, when)
    Row(Settings.CreateCheckboxInitializer(Register(key, name), nil, tooltip), nil, when)
end

local function SliderOptions(minValue, maxValue, step, format)
    local sliderOptions = Settings.CreateSliderOptions(minValue, maxValue, step)
    sliderOptions:SetLabelFormatter(MinimalSliderWithSteppersMixin.Label.Right, function(value)
        return format:format(value)
    end)
    return sliderOptions
end

local function Slider(key, name, tooltip, minValue, maxValue, step, format)
    Row(Settings.CreateSliderInitializer(Register(key, name), SliderOptions(minValue, maxValue, step, format), tooltip))
end

local SIZE_TOOLTIP = "Size of this text. 100% is its usual size, which follows the bar's height."
local sizeOptions -- shared by every Text Size slider; made on first use, once the Settings API is checked

local function SizeOptions()
    sizeOptions = sizeOptions or SliderOptions(SIZE_MIN, SIZE_MAX, SIZE_STEP, "%d%%")
    return sizeOptions
end

-- One of the separate bar's text lines: whether it shows, and its size beside it, greyed out while
-- the line is off (the game's own checkbox-and-slider row).
local function TextRow(showKey, name, tooltip, sizeKey)
    local show, size = Register(showKey, name), Register(sizeKey, name .. " Size")
    if CreateSettingsCheckboxSliderInitializer then
        Row(CreateSettingsCheckboxSliderInitializer(show, name, tooltip, size, SizeOptions(), name .. " Size", SIZE_TOOLTIP))
    else
        Row(Settings.CreateCheckboxInitializer(show, nil, tooltip))
        Row(Settings.CreateSliderInitializer(size, SizeOptions(), SIZE_TOOLTIP))
    end
end

local swatches = {} -- a function for each swatch, to show the colour in use

local function RefreshSwatches()
    for _, refresh in ipairs(swatches) do refresh() end
end

local function HexColour(r, g, b)
    return ("%02X%02X%02X"):format(math.floor(r * 255 + 0.5), math.floor(g * 255 + 0.5), math.floor(b * 255 + 0.5))
end

-- A colour: whether it is the player's own, and a swatch beside it that opens the game's colour picker, off
-- while the usual one is used (the game's own checkbox-and-swatch row). The swatch shows the colour in use
-- either way. what is what it colours, for Core.CurrentColour.
local function ColourRow(customKey, key, name, what, tooltip)
    if not (CreateSettingsCheckboxWithColorSwatchInitializer and ColorPickerFrame
        and ColorPickerFrame.SetupColorPickerAndShow) then
        return
    end
    local custom, colour = Register(customKey, "Custom " .. name), Register(key, name)
    local function Current() return CreateColor(ns.Core.CurrentColour(what)) end
    -- Opening the picker reports the colour it opened on, which leaves the setting as it was.
    local function OpenPicker()
        local before = colour:GetValue()
        local r, g, b = ns.Core.CurrentColour(what)
        local start = HexColour(r, g, b)
        ColorPickerFrame:SetupColorPickerAndShow({
            r = r, g = g, b = b, hasOpacity = false,
            swatchFunc = function()
                local hex = HexColour(ColorPickerFrame:GetColorRGB())
                colour:SetValue(hex == start and before or hex)
            end,
            cancelFunc = function() colour:SetValue(before) end,
        })
    end
    local row = Row(CreateSettingsCheckboxWithColorSwatchInitializer(custom, tooltip, OpenPicker, true, false, Current,
        name, "Click to pick the colour."))
    local swatch = row.frame.ColorSwatch
    row.refresh = function()
        swatch:SetColor(Current())
        swatch:SetAlpha(custom:GetValue() and 1 or 0.4)
    end
    row.refresh()
    swatches[#swatches + 1] = row.refresh
    watchers[customKey], watchers[key], watchers.theme = RefreshSwatches, RefreshSwatches, RefreshSwatches
end

local function Dropdown(setting, tooltip, getOptions, when)
    Row(Settings.CreateDropdownInitializer(setting, getOptions, tooltip), nil, when)
end

-- One of the default bar's texts: what shows there, and its size beside it, greyed out while it
-- shows Nothing. The game has no dropdown-and-slider row, so the slider (the game's own) goes on
-- the dropdown row, with the dropdown narrowed and its arrows left off to make room. A client whose
-- dropdown row is built differently gets the size on a row of its own under it instead.
local function SlotRow(key, name, tooltip, getOptions, sizeKey)
    local sizeSetting = Register(sizeKey, name .. " Size")
    local options = SizeOptions()
    local row = Row(Settings.CreateDropdownInitializer(Register(key, name), getOptions, tooltip), nil, nil,
        function(frame) frame.forceSteppersHidden = true end)
    local frame = row.frame
    local control = frame.Control
    if not (control and control.Dropdown and MinimalSliderWithSteppersMixin.Event) then
        Row(Settings.CreateSliderInitializer(sizeSetting, options, SIZE_TOOLTIP))
        return
    end
    control:ClearAllPoints()
    control:SetPoint("LEFT", frame, "CENTER", CONTROL_X, 3)
    control:SetWidth(SLOT_DROPDOWN_W)
    control.Dropdown:SetWidth(SLOT_DROPDOWN_W)

    local slider = CreateFrame("Frame", nil, frame, "MinimalSliderWithSteppersTemplate")
    slider:SetWidth(SLOT_SLIDER_W)
    slider:SetPoint("LEFT", control, "RIGHT", SLOT_GAP, 0)
    slider:RegisterCallback(MinimalSliderWithSteppersMixin.Event.OnValueChanged, function(_, value)
        sizeSetting:SetValue(value)
    end, frame)
    if Mixin and DefaultTooltipMixin and GenerateClosure and Settings.InitTooltip then
        Mixin(slider.Slider, DefaultTooltipMixin)
        slider.Slider:InitDefaultTooltipScriptHandlers()
        slider.Slider:SetCustomTooltipAnchoring(slider.Slider, "ANCHOR_RIGHT", 20, 0)
        slider.Slider:SetTooltipFunc(GenerateClosure(Settings.InitTooltip, name .. " Size", SIZE_TOOLTIP))
    end
    frame.SizeSlider = slider

    local function Enable() slider:SetEnabled(db[key] ~= "none") end
    -- As the game's rows do on each page open: release, then set up from the setting again.
    row.refresh = function()
        slider:Release()
        slider:Init(sizeSetting:GetValue(), options.minValue, options.maxValue, options.steps, options.formatters)
        Enable()
    end
    row.refresh()
    watchers[key] = Enable
    watchers[sizeKey] = function(value) slider:SetValue(value) end
end

-- The fifth argument is whether the row adds search tags; the game asserts it is given, and a
-- canvas has nothing for the search to find.
local function Button(name, text, onClick, tooltip, when)
    Row(CreateSettingsButtonInitializer(name, text, onClick, tooltip, false), nil, when)
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
local function SeparateTracksRep() return SeparateUsed() and db.separateTracks ~= "xp" end
-- The reputation theme and text are for either reputation bar.
local function RepUsed() return db.repBar or SeparateTracksRep() end
-- A reputation bar shows now (the separate bar set to reputation at max level only counts there).
local function RepShowing() return ns.Core.RepShowing() end

-- What the separate bar tracks.
local TRACKS = {
    { "xp", "Experience" },
    { "rep", "Reputation" },
    { "auto", "Experience, Reputation at Max Level" },
}

local function TrackOptions()
    local container = Settings.CreateControlTextContainer()
    for _, track in ipairs(TRACKS) do container:Add(track[1], track[2]) end
    return container:GetData()
end

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

local function PreviewRepOption(option)
    ns.Core.PreviewRepTheme(option.value)
end

local function RepThemeOptions()
    local container = Settings.CreateControlTextContainer()
    for _, theme in ipairs(ns.Core.RepThemes()) do
        local option = container:Add(theme.key, theme.name)
        if option then option.onEnter = PreviewRepOption end
    end
    return container:GetData()
end

local function RepSlotOptions()
    local container = Settings.CreateControlTextContainer()
    for _, slot in ipairs(ns.Core.RepSlots()) do
        container:Add(slot.key, slot.name)
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

local function SlotOptions()
    local container = Settings.CreateControlTextContainer()
    for _, slot in ipairs(ns.Core.SkinSlots()) do
        container:Add(slot.key, slot.name)
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
            if row.initializer then
                row.initializer:Resetter(row.frame)
                row.initializer:InitFrame(row.frame)
            end
            if row.refresh then row.refresh() end
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

    -- Which bars show and what each tracks, then how they look, then each bar's own settings.
    Header("Bars")
    Dropdown(Register("bars", "Bars"), "Which bars show your experience: a separate bar you move and resize, the "
        .. "game's own experience bar filled with the liquid, or both. Each has its section below.", BarOptions)
    Dropdown(Register("separateTracks", "Separate Bar Tracks"), "What the separate bar shows: your experience, "
        .. "the faction you watch (tick Show as Experience Bar for one in the Reputation panel), or experience "
        .. "until max level and reputation from then on.", TrackOptions, SeparateUsed)
    Checkbox("repBar", "Default Reputation Bar", "Fill the game's own reputation bar with the liquid. The game "
        .. "shows it while you watch a faction: tick Show as Experience Bar for one in the Reputation panel.")

    Header("Look")
    Dropdown(Register("theme", "Experience Theme"), "Colours and effects of the experience bars.", ThemeOptions)
    ColourRow("customQuestColor", "questColor", "Quest Colour", "quest", "Pick the colour of completed quest XP, in "
        .. "the bar and its numbers. Untick for the theme's.")
    ColourRow("customRestedColor", "restedColor", "Rested Colour", "rested", "Pick the colour of rested XP, in the "
        .. "bar and its numbers (inside the default bar the number is in the text's colour). Untick for the theme's.")
    Dropdown(Register("repTheme", "Reputation Theme"), "Colours and effects of reputation, on the game's "
        .. "reputation bar and on the separate bar while it tracks reputation. Standing Colours takes the game's "
        .. "colour for your standing, from red at Hated to green from Friendly up.", RepThemeOptions, RepUsed)
    Dropdown(Register("font", "Font"), "Font of the bars' text, from the game's own fonts.", FontOptions)
    Checkbox("fontOutline", "Font Outline", "A dark outline around the text. Untick for a plain drop shadow.")
    ColourRow("customTextColor", "textColor", "Text Colour", "text", "Pick the colour of the text on every bar, "
        .. "reputation included. The completed quest and rested numbers around the separate bar keep their own. "
        .. "Untick for white.")

    Header("Experience")
    Checkbox("showMaxLevel", "Show at Max Level", "Keep the experience bars visible at max level, showing time "
        .. "played.")
    Checkbox("trackedQuestsOnly", "Tracked Quests Only", "Count completed quest XP only for quests on your "
        .. "quest tracker. On Era and Anniversary the game untracks quests it tracked for you 5 minutes after "
        .. "their last update, and quests with no objectives can't be tracked.")
    Checkbox("resetOnReload", "Reset Session on Reload", "Restart the session (its time, XP/hour, and reputation "
        .. "gained and per hour) on /reload as well as on login.")

    local repText = " While the bar tracks reputation, its text comes from the Reputation section."
    Header("Separate Bar", SeparateUsed)
    SubHeader("Size & Position")
    Checkbox("locked", "Lock Bar", "Untick to move the bar by dragging it and resize it from the corner grip.")
    Slider("scale", "Scale", "Size of the whole bar, text included.", 0.4, 1.5, 0.05, "%.2f")
    Slider("width", "Width", "Bar width. Also set by dragging the corner grip while unlocked.", 200, 1600, 10, "%d")
    Slider("height", "Height", "Bar height; text scales with it.", 16, 60, 1, "%d")
    Button("Reset Position & Size", "Reset", Core.ResetPosition, "Move the bar back to the top of the screen at its default size.")
    SubHeader("Text in the Bar")
    TextRow("showLevelText", "Level", "Your level on the left of the bar." .. repText, "levelSize")
    TextRow("showXPText", "XP", "Current and max XP, and the XP still to go, in the middle of the bar." .. repText,
        "xpSize")
    TextRow("showPctText", "Percentage", "How far through the level you are, on the right of the bar." .. repText,
        "pctSize")
    SubHeader("Lines Around the Bar")
    TextRow("showLevelTime", "Time This Level", "Played time at this level above the bar (total played at max "
        .. "level). While the bar tracks reputation: reputation gained this session.", "levelTimeSize")
    TextRow("showSessionTime", "Session Time", "Time since you logged in, above the bar.", "sessionTimeSize")
    TextRow("showXPHour", "Leveling Time & XP/Hour", "Estimated time to level from this session's XP rate, under "
        .. "the bar. While the bar tracks reputation: the time to the next standing and reputation per hour.",
        "xpHourSize")
    TextRow("showQuestRested", "Completed & Rested", "Completed quest XP and rested XP as a percentage of the "
        .. "level, under the bar. While the bar tracks reputation: what is left to Exalted.", "questRestedSize")
    SubHeader("Bar")
    Checkbox("questBar", "Completed Quest Bar", "The XP of quests ready to turn in, shown after your XP in the bar.")
    Checkbox("restedBar", "Rested Bar", "Your rested XP, shown after your XP (and completed quests) in the bar.")
    Checkbox("rounding", "Rounded Liquid", "Shade the top and bottom of the bar so the liquid looks round.")
    Checkbox("segments", "Segmented Bar", "Divide the bar into 20 segments, like the game's experience bar.")
    Checkbox("hideBlizzardBar", "Hide Default Experience Bar", "Hide the game's own experience bar. Not while "
        .. "Default Reputation Bar is on: the game keeps its reputation bar with it.",
        function() return SeparateOnly() and not db.repBar end)
    SubHeader("Fade")
    Checkbox("fadeIdle", "Fade When Idle", "Fade the bar after a while. Hover over it to reveal it; it also "
        .. "comes back when you gain XP (or reputation, while it tracks reputation), in or out of combat.")
    Slider("fadeDelay", "Fade After", "Seconds since the last gain or hover before the bar fades.",
        2, 30, 1, "%ds")
    Slider("fadeOpacity", "Faded Opacity", "How visible the bar stays once faded. 0% hides it until you hover over it.",
        0, 90, 5, "%d%%")

    Header("Default Experience Bar", DefaultUsed)
    local slotHelp = " Time This Level, Time to Level and XP/Hour come from your played time and this session's XP."
    SlotRow("defaultLeft", "Left Text", "What shows on the left of the bar." .. slotHelp, SlotOptions, "defaultLeftSize")
    SlotRow("defaultCentre", "Centre Text", "What shows in the middle of the bar. While anything shows "
        .. "there, the game's own XP text is hidden so the two do not overlap." .. slotHelp, SlotOptions,
        "defaultCentreSize")
    SlotRow("defaultRight", "Right Text", "What shows on the right of the bar." .. slotHelp, SlotOptions, "defaultRightSize")
    Checkbox("defaultLabels", "Text Labels", "Name each number, as in \"Time this level: 2h 13m\". "
        .. "Untick for just the numbers (XP/hour keeps a short /h).")
    Checkbox("defaultQuestBar", "Completed Quest Bar", "The XP of quests ready to turn in, shown after your XP in the bar.")
    Checkbox("defaultRestedBar", "Rested Bar", "Your rested XP, shown after your XP (and completed quests) in the bar.")
    Checkbox("defaultTooltip", "Tooltip",
        "Hover the bar for the rest of the numbers: completed and rested XP, session time, XP/hour and the time to level.")

    -- The text in either reputation bar: the game's, and the separate bar while it tracks reputation.
    Header("Reputation", RepUsed)
    local repSlotHelp = " On the game's reputation bar, and in the separate bar while it tracks reputation."
        .. " Reputation, Percentage and To Next Standing are left out at the top standing."
    SlotRow("repLeft", "Left Text", "What shows on the left of the bar." .. repSlotHelp, RepSlotOptions, "repLeftSize")
    SlotRow("repCentre", "Centre Text", "What shows in the middle of the bar. While anything shows there, "
        .. "the game's own reputation text is hidden so the two do not overlap." .. repSlotHelp, RepSlotOptions,
        "repCentreSize")
    SlotRow("repRight", "Right Text", "What shows on the right of the bar." .. repSlotHelp, RepSlotOptions, "repRightSize")
    Checkbox("repTooltip", "Tooltip", "Hover a reputation bar for your standing, reputation, what is left to "
        .. "the next standing and to Exalted, and this session's gains, time and reputation per hour.")

    Header("Animation")
    Slider("speed", "Fill Speed", "How quickly the liquid flows to its new level.", 0.5, 2, 0.1, "%.1fx")
    Checkbox("waves", "Liquid Waves", "Wobbling liquid front that sloshes and ripples on gains.")
    Checkbox("swirl", "Magic Swirl", "Glowing veins, clouds and light drifting inside the liquid.")
    Checkbox("bubbles", "Bubbles", "Bubbles rising through the liquid.")
    Checkbox("sparkles", "Sparkles", "Motes thrown off by gains, quest turn-ins, level-ups and new standings.")
    Checkbox("ambient", "Ambient Particles", "Embers, snow, spores, stars and the like from themes that have them.")
    Checkbox("lightning", "Lightning", "Faint flashes in the liquid at rest that build into a storm with big or rapid gains.")
    Checkbox("restedGlow", "Rested Glow", "A soft glow in the liquid while you have rested XP.")
    Checkbox("flash", "Level-Up Flash", "Flash the bar when you level up or reach a new standing.")
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
    Button("Preview Reputation Gain", "Gain", function() Core.Test("rep") end,
        "Simulate a reputation gain with the watched faction. Does not touch your real reputation.", RepShowing)
    Button("Preview New Standing", "Standing Up", function() Core.Test("standing") end,
        "Simulate reaching the next standing with the watched faction.", RepShowing)
    Button("Stop Preview", "Stop", function() Core.Test("off") end, "Return the bars to your real XP and reputation.")
    Button("Reset Session", "Reset", Core.ResetSession, "Restart the session: its time, XP/hour, and reputation "
        .. "gained and per hour.")
    Button("Setup Wizard", "Open", function() ns.Wizard.Open() end,
        "Pick where the bars go, their themes, effects and text again, with live previews.")
    Button("What's New", "Open", function() ns.WhatsNew.Open() end,
        "What changed in this version and the ones before (also /seb changes).")

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
