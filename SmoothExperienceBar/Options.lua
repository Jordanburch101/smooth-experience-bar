-- Settings page in the game's AddOns options, built on the native Settings API.
-- Values live directly in SmoothExperienceBarDB; changes are forwarded to ns.Core.OnSettingChanged.

local ADDON_NAME, ns = ...

local Options = {}
ns.Options = Options

local category, layout, db, defaults

local function Header(text)
    if CreateSettingsListSectionHeaderInitializer then
        layout:AddInitializer(CreateSettingsListSectionHeaderInitializer(text))
    end
end

local registered = {}

local function Register(key, name)
    local default = defaults[key]
    local setting = Settings.RegisterAddOnSetting(category, ADDON_NAME .. "_" .. key, key, db, type(default), name, default)
    setting:SetValueChangedCallback(function(_, value)
        ns.Core.OnSettingChanged(key, value)
    end)
    registered[key] = setting
    return setting
end

local function Checkbox(key, name, tooltip)
    Settings.CreateCheckbox(category, Register(key, name), tooltip)
end

local function Slider(key, name, tooltip, minValue, maxValue, step, format)
    local sliderOptions = Settings.CreateSliderOptions(minValue, maxValue, step)
    sliderOptions:SetLabelFormatter(MinimalSliderWithSteppersMixin.Label.Right, function(value)
        return format:format(value)
    end)
    Settings.CreateSlider(category, Register(key, name), sliderOptions, tooltip)
end

local function Dropdown(key, name, tooltip, getOptions)
    Settings.CreateDropdown(category, Register(key, name), getOptions, tooltip)
end

local function Button(name, text, onClick, tooltip)
    layout:AddInitializer(CreateSettingsButtonInitializer(name, text, onClick, tooltip, true))
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

function Options.Register(savedDB, defaultValues)
    if not (Settings and Settings.RegisterVerticalLayoutCategory) then return end
    db, defaults = savedDB, defaultValues
    local Core = ns.Core

    category, layout = Settings.RegisterVerticalLayoutCategory("Smooth Experience Bar")

    Header("General")
    Dropdown("theme", "Theme", "Colours and effects of the bar.", ThemeOptions)
    Checkbox("locked", "Lock Bar", "Untick to move the bar by dragging it and resize it from the corner grip.")
    Slider("scale", "Scale", "Size of the whole bar, text included.", 0.4, 1.5, 0.05, "%.2f")
    Slider("width", "Width", "Bar width. Also set by dragging the corner grip while unlocked.", 200, 1600, 10, "%d")
    Slider("height", "Height", "Bar height; text scales with it.", 16, 60, 1, "%d")
    Checkbox("showMaxLevel", "Show at Max Level", "Keep the bar visible at max level, showing time played.")
    Checkbox("hideBlizzardBar", "Hide Default Experience Bar", "Hide the game's own experience bar.")

    Header("Text")
    Checkbox("showLevelTime", "Time This Level", "Played time at this level (total played at max level).")
    Checkbox("showSessionTime", "Session Time", "Time since you logged in.")
    Checkbox("showXPHour", "Leveling Time & XP/Hour", "Estimated time to level from this session's XP rate.")
    Checkbox("showQuestRested", "Completed & Rested", "Completed quest XP and rested XP as a percentage of the level.")
    Checkbox("resetOnReload", "Reset Session on Reload", "Restart session time and XP/hour on /reload as well as on login.")

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
    Checkbox("rounding", "Rounded Liquid", "Shade the top and bottom of the bar so the liquid looks round.")

    -- Settings are saved per character. Pick another character, then copy their settings onto this one.
    Header("Profile")
    local copy = { copyFrom = "" }
    local copySetting = Settings.RegisterAddOnSetting(category, ADDON_NAME .. "_copyFrom", "copyFrom", copy, "string",
        "Copy Settings From", "")
    Settings.CreateDropdown(category, copySetting, function()
        local container = Settings.CreateControlTextContainer()
        local others = Core.OtherProfiles()
        if #others == 0 then
            container:Add("", "No other characters yet")
        end
        for _, key in ipairs(others) do
            container:Add(key, key)
        end
        return container:GetData()
    end, "Settings are saved per character (this is " .. Core.ProfileKey() .. "). Pick another character here, then press Copy.")
    Button("Copy Settings", "Copy", function()
        if copy.copyFrom ~= "" then Core.CopyProfile(copy.copyFrom) end
    end, "Replace this character's settings with the chosen character's.")

    Header("Preview & Reset")
    Button("Preview XP Gain", "Gain", function() Core.Test("gain") end, "Simulate an XP gain. Does not touch your real XP.")
    Button("Preview Quest Turn-In", "Turn In", function() Core.Test("turnin") end, "Simulate completing and turning in a quest.")
    Button("Preview Level-Up", "Level Up", function() Core.Test("level") end, "Simulate a level-up.")
    Button("Stop Preview", "Stop", function() Core.Test("off") end, "Return the bar to your real XP.")
    Button("Reset Position & Size", "Reset", Core.ResetPosition, "Move the bar back to the top of the screen at its default size.")
    Button("Reset Session", "Reset", Core.ResetSession, "Restart session time and XP/hour.")

    Settings.RegisterAddOnCategory(category)
end

-- After the values changed underneath the page (a copied profile), push them to its controls.
function Options.Refresh()
    for key, setting in pairs(registered) do
        setting:SetValue(db[key])
    end
end

function Options.Open()
    if category and Settings.OpenToCategory then
        Settings.OpenToCategory(category:GetID())
        return true
    end
end
