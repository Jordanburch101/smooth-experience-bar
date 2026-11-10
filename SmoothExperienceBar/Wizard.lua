-- First-time setup: where the bar goes, its theme, how lively it is and what text it shows, each
-- with live previews. Opens on the first login of someone new to the addon, or with /seb setup.
--
-- Built from the game's own window (as Road to Sixty's), button, radio button and font templates so
-- it looks like the game's UI on every client; colours are SetColorTexture and never game files by path (see the
-- project rules about Forever).

local _, ns = ...

local Wizard = {}
ns.Wizard = Wizard

local W, H = 880, 500
local GOLD = { 1, 0.82, 0 }
local EDGE = { 0.32, 0.30, 0.36 }

-- Effect presets; Balanced is the defaults, filled in on first use.
local EFFECT_KEYS = { "waves", "swirl", "bubbles", "sparkles", "ambient", "lightning", "restedGlow", "glass",
                      "rounding", "flash" }
local PRESETS = {
    full = { waves = true, swirl = true, bubbles = true, sparkles = true, ambient = true, lightning = true,
             restedGlow = true, glass = true, rounding = true, flash = true },
    calm = { waves = false, swirl = false, bubbles = false, sparkles = false, ambient = false, lightning = false,
             restedGlow = false, glass = false, rounding = false, flash = false },
}
local TEXT_KEYS = { "showLevelTime", "showSessionTime", "showXPHour", "showQuestRested" }

local PLACES = {
    { key = "separate", label = "Separate bar",
      desc = "A bar you move and resize anywhere, with session time, XP/hour, completed and rested XP around it." },
    { key = "default", label = "In the game's bar",
      desc = "The liquid fills the game's own experience bar, with the time this level and your XP on it." },
    { key = "both", label = "Both",
      desc = "The separate bar with all its numbers, and the liquid in the game's bar too." },
}
local THEMES = { "luxthos", "class", "arcane", "fel", "fire", "frost", "cosmic", "void" }
local EFFECTS = {
    { key = "full", label = "Everything", desc = "Every effect, plus glass reflections, a rested glow and rounded liquid." },
    { key = "balanced", label = "Balanced", desc = "The default: waves, swirl, bubbles, sparkles and lightning." },
    { key = "calm", label = "Calm", desc = "A smooth fill with no particles, lightning or flashes." },
}
local TEXTS = {
    { key = "all", label = "All the numbers", desc = "Times, leveling estimate, XP/hour, completed and rested XP" },
    { key = "none", label = "Just the bar", desc = "Level, XP and percentage inside the bar only" },
}

-- XP gains the previews play while the wizard is open, as /seb test does.
local DEMO = { "gain", "gain", "turnin", "gain", "gain", "level" }

local frame, ui, choice, page, pages, previews, demo, demoStep, closing

local function Label(list, key)
    for _, item in ipairs(list) do
        if item.key == key then return item.label end
    end
end

local function Preset(key)
    if not PRESETS.balanced then
        local defaults, balanced = ns.Core.Defaults(), {}
        for _, k in ipairs(EFFECT_KEYS) do balanced[k] = defaults[k] end
        PRESETS.balanced = balanced
    end
    return PRESETS[key]
end

-- The choices as they stand in the settings, so running the wizard again starts from them.
local function CurrentChoices()
    local get = ns.Core.Get
    local place = get("bars")
    local effects = "balanced"
    for _, key in ipairs({ "full", "calm", "balanced" }) do
        local match = true
        for _, k in ipairs(EFFECT_KEYS) do
            if Preset(key)[k] ~= get(k) then match = false end
        end
        if match then effects = key end
    end
    local text = "none"
    for _, k in ipairs(TEXT_KEYS) do
        if get(k) then text = "all" end
    end
    return { place = place, theme = get("theme"), effects = effects, text = text }
end

--------------------------------------------------------------------------------
-- Building blocks: the game's templates and font objects
--------------------------------------------------------------------------------

local function Font(parent, template, text, justify)
    local fs = parent:CreateFontString(nil, "OVERLAY", template)
    fs:SetText(text or "")
    if justify then fs:SetJustifyH(justify) end
    return fs
end

local function Button(parent, text, width, onClick)
    local b = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    b:SetSize(width, 26)
    b:SetText(text)
    b:SetScript("OnClick", onClick)
    return b
end

-- A 1 px outline of solid colour around a frame.
local function Outline(f, color)
    local edges = {}
    for _, side in ipairs({ { "TOPLEFT", "TOPRIGHT" }, { "BOTTOMLEFT", "BOTTOMRIGHT" },
                            { "TOPLEFT", "BOTTOMLEFT" }, { "TOPRIGHT", "BOTTOMRIGHT" } }) do
        local t = f:CreateTexture(nil, "BORDER")
        t:SetColorTexture(color[1], color[2], color[3], 1)
        t:SetPoint(side[1])
        t:SetPoint(side[2])
        if side[1]:sub(1, 3) == side[2]:sub(1, 3) then t:SetHeight(1) else t:SetWidth(1) end
        edges[#edges + 1] = t
    end
    return edges
end

local function Panel(parent, w, h, alpha)
    local f = CreateFrame("Frame", nil, parent)
    f:SetSize(w, h)
    local bg = f:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetColorTexture(0, 0, 0, alpha or 0.45)
    Outline(f, EDGE)
    return f
end

-- An option: a radio button and title, an optional description, a gold outline when picked.
local function Card(parent, w, h, title, desc, onPick)
    local c = CreateFrame("Button", nil, parent)
    c:SetSize(w, h)
    local bg = c:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetColorTexture(0, 0, 0, 0.45)
    local hl = c:CreateTexture(nil, "HIGHLIGHT")
    hl:SetAllPoints()
    hl:SetColorTexture(1, 1, 1, 0.06)
    local edges = Outline(c, EDGE)
    c.radio = CreateFrame("CheckButton", nil, c, "UIRadioButtonTemplate")
    c.radio:SetPoint("TOPLEFT", 8, -8)
    c.radio:SetScript("OnClick", onPick)
    c.title = Font(c, "GameFontNormal", title, "LEFT")
    c.title:SetPoint("LEFT", c.radio, "RIGHT", 4, 0)
    if desc then
        c.desc = Font(c, "GameFontHighlightSmall", desc, "LEFT")
        c.desc:SetPoint("TOPLEFT", 12, -32)
        c.desc:SetWidth(w - 24)
        c.desc:SetJustifyV("TOP")
        c.desc:SetWordWrap(true)
    end
    c:SetScript("OnClick", onPick)
    function c.SetSelected(_, on)
        c.radio:SetChecked(on)
        local color = on and GOLD or EDGE
        for _, t in ipairs(edges) do t:SetColorTexture(color[1], color[2], color[3], 1) end
        bg:SetColorTexture(on and 0.12 or 0, on and 0.09 or 0, on and 0.02 or 0, on and 0.55 or 0.45)
    end
    return c
end

-- A live preview bar at scale k, its top-left at (x, y) in parent.
local function Preview(parent, look, k, point, x, y, rel)
    local v = ns.Core.NewPreview(parent, look)
    v.frame:SetScale(k)
    v.frame:SetPoint(point, rel or parent, point, x / k, y / k)
    previews[#previews + 1] = v
    return v
end

local function Heading(parent, title, sub)
    local h = Font(parent, "GameFontNormalLarge", title, "LEFT")
    h:SetPoint("TOPLEFT", 0, 0)
    local s = Font(parent, "GameFontHighlightSmall", sub, "LEFT")
    s:SetPoint("TOPLEFT", h, "BOTTOMLEFT", 0, -6)
end

--------------------------------------------------------------------------------
-- Pages
--------------------------------------------------------------------------------

local Refresh, ShowPage

local function Pick(field, key)
    return function()
        choice[field] = key
        Refresh()
    end
end

local function Cards(parent, list, field, w, h, x, y, gap)
    local cards = {}
    for i, item in ipairs(list) do
        local c = Card(parent, w, h, item.label, item.desc, Pick(field, item.key))
        c:SetPoint("TOPLEFT", x + (i - 1) * (w + gap), y)
        cards[item.key] = c
    end
    return cards
end

local BUILD = {}

function BUILD.welcome(p)
    local title = Font(p, "GameFontNormalHuge", "Welcome", "CENTER")
    title:SetPoint("TOP", 0, -8)
    local text = Font(p, "GameFontHighlight", "Pick where your experience bar goes, how it looks and what it "
        .. "shows. It takes about a minute, and every preview is the real bar.", "CENTER")
    text:SetPoint("TOP", title, "BOTTOM", 0, -10)
    text:SetWidth(600)
    text:SetWordWrap(true)
    p.preview = Preview(p, "bar", 1.15, "TOP", 0, -124)
    ui.start = Button(p, "Set it up", 220, function() ShowPage("place") end)
    ui.start:SetPoint("TOP", 0, -236)
    ui.welcomeLater = Button(p, "Ask me later", 160, function() Wizard.Close("later") end)
    ui.welcomeLater:SetPoint("TOPRIGHT", p, "TOP", -6, -272)
    -- Skipping changes nothing: for someone new that is the defaults, for anyone else their settings.
    ui.welcomeSkip = Button(p, "", 200, function() Wizard.Close("skip") end)
    ui.welcomeSkip:SetPoint("TOPLEFT", p, "TOP", 6, -272)
end

-- The game's action bars (Media\ActionBars, made by tools/make_media.py from a screenshot of
-- Forever's): the composite's size in the screenshot's pixels, the part of the texture it fills, and
-- where its experience bar is, emptied for the wizard to fill.
local ACTION_BARS = { w = 1187, h = 144, texBottom = 124 / 128, bar = { x = 170, y = 67, w = 823, h = 13 } }

-- The placement scene, shared with the last page: the separate bar above, and below it the game's
-- action bars, their experience bar filled by the default bar's liquid when chosen and by the game's
-- own fill when not.
local function BuildScene()
    local scene = Panel(frame, 760, 200, 0.55)
    scene.bar = Preview(scene, "bar", 0.85, "TOP", 0, -38)

    local A = ACTION_BARS
    local k = 744 / A.w
    local art = CreateFrame("Frame", nil, scene)
    art:SetSize(A.w, A.h)
    art:SetScale(k)
    art:SetPoint("BOTTOM", scene, "BOTTOM", 0, 2 / k)
    local tex = art:CreateTexture(nil, "ARTWORK")
    tex:SetAllPoints()
    tex:SetTexture("Interface\\AddOns\\SmoothExperienceBar\\Media\\ActionBars")
    tex:SetTexCoord(0, 1, 0, A.texBottom)

    -- The experience bar: the game's own fill where nothing draws over it, the default bar's liquid
    -- when chosen, and the game's segment lines over either.
    local b = A.bar
    local xp = CreateFrame("Frame", nil, art)
    xp:SetSize(b.w, b.h)
    xp:SetPoint("TOPLEFT", b.x, -b.y)
    local fill = xp:CreateTexture(nil, "ARTWORK")
    fill:SetPoint("TOPLEFT")
    fill:SetPoint("BOTTOMLEFT")
    fill:SetWidth(b.w * 0.66)
    fill:SetColorTexture(0.35, 0.16, 0.55, 1)
    scene.gameFill = { fill }
    scene.skin = ns.Core.NewPreview(xp, "skin", b.w, b.h)
    scene.skin.frame:SetPoint("TOPLEFT")
    previews[#previews + 1] = scene.skin
    local lines = CreateFrame("Frame", nil, xp)
    lines:SetAllPoints()
    lines:SetFrameLevel(scene.skin.frame:GetFrameLevel() + 2)
    scene.skin.textFrame:SetFrameLevel(lines:GetFrameLevel() + 1)
    for i = 1, 19 do
        local line = lines:CreateTexture(nil, "OVERLAY")
        line:SetColorTexture(0.53, 0.49, 0.41, 1)
        line:SetPoint("TOPLEFT", math.floor(b.w * i / 20 + 0.5), 0)
        line:SetPoint("BOTTOMLEFT", math.floor(b.w * i / 20 + 0.5), 0)
        line:SetWidth(1)
    end
    return scene
end

function BUILD.place(p)
    Heading(p, "Where should the bar go?", "You can show it on its own, inside the game's experience bar, or both.")
    ui.scene = ui.scene or BuildScene()
    ui.cards.place = Cards(p, PLACES, "place", 245, 84, 0, -258, 12)
end

function BUILD.theme(p)
    Heading(p, "Pick a theme", "A few favourites. All 25 are in the settings, and hovering one there shows it on your bar.")
    ui.cards.theme = {}
    p.tiles = {}
    for i, key in ipairs(THEMES) do
        local col, row = (i - 1) % 2, math.floor((i - 1) / 2)
        local c = Card(p, 374, 70, ns.Themes.list[key].name, nil, Pick("theme", key))
        c:SetPoint("TOPLEFT", col * 386, -46 - row * 80)
        local v = Preview(c, "bar", 0.58, "TOPLEFT", 13, -36)
        p.tiles[key] = v
        ui.cards.theme[key] = c
    end
end

function BUILD.effects(p)
    Heading(p, "How lively should it be?", "Each effect can be turned on or off in the settings later.")
    local scene = Panel(p, 760, 150, 0.55)
    scene:SetPoint("TOP", 0, -46)
    p.preview = Preview(scene, "bar", 1.15, "TOP", 0, -68)
    ui.cards.effects = Cards(p, EFFECTS, "effects", 245, 84, 0, -208, 12)
end

function BUILD.text(p)
    Heading(p, "What should the separate bar show?", "Each line can be turned on or off on its own in the settings.")
    ui.cards.text = Cards(p, TEXTS, "text", 760, 136, 0, -46, 0)
    for i, item in ipairs(TEXTS) do
        local c = ui.cards.text[item.key]
        c:ClearAllPoints()
        c:SetPoint("TOPLEFT", 0, -46 - (i - 1) * 146)
        c.desc:ClearAllPoints()
        c.desc:SetPoint("LEFT", c.title, "RIGHT", 10, 0)
        c.desc:SetWidth(0)
        c.preview = Preview(c, "bar", 0.95, "TOP", 0, -62)
    end
end

function BUILD.done(p)
    local title = Font(p, "GameFontNormalHuge", "All set", "CENTER")
    title:SetPoint("TOP", 0, -4)
    p.summary = Font(p, "GameFontHighlight", "", "CENTER")
    p.summary:SetPoint("TOP", 0, -258)
    local hint = Font(p, "GameFontHighlightSmall", "Change any of this with /seb, or right-click the bar.", "CENTER")
    hint:SetPoint("TOP", 0, -284)
end

--------------------------------------------------------------------------------
-- The window
--------------------------------------------------------------------------------

-- The text page is about the separate bar, so it drops out when only the game's bar is used.
local function Flow()
    local flow = { "welcome", "place", "theme", "effects" }
    if choice.place ~= "default" then flow[#flow + 1] = "text" end
    flow[#flow + 1] = "done"
    return flow
end

local function IndexOf(list, value)
    for i, v in ipairs(list) do
        if v == value then return i end
    end
end

local function StopDemo()
    if demo then
        demo:Cancel()
        demo = nil
        ns.Core.Test("off")
    end
end

local function StartDemo()
    if demo then return end
    demoStep = 0
    demo = C_Timer.NewTicker(2.2, function()
        demoStep = demoStep % #DEMO + 1
        ns.Core.Test(DEMO[demoStep])
    end)
    ns.Core.Test("gain")
end

-- Every preview takes the chosen theme and effects, except the theme tiles (each its own theme) and
-- the text page (each card its own lines).
function Refresh()
    local opts = Preset(choice.effects)
    for _, v in ipairs(previews) do ns.Core.StylePreview(v, choice.theme, opts, "none") end
    if pages.welcome then ns.Core.StylePreview(pages.welcome.preview, choice.theme, opts, "all") end
    if ui.scene then
        local scene = ui.scene
        scene.bar.frame:SetShown(choice.place ~= "default")
        scene.skin.frame:SetShown(choice.place ~= "separate")
        for _, t in ipairs(scene.gameFill) do t:SetShown(choice.place == "separate") end
        ns.Core.StylePreview(scene.bar, choice.theme, opts, "all")
    end
    if pages.theme then
        for key, v in pairs(pages.theme.tiles) do ns.Core.StylePreview(v, key, opts, "none") end
    end
    if pages.text then
        for _, item in ipairs(TEXTS) do
            ns.Core.StylePreview(ui.cards.text[item.key].preview, choice.theme, opts, item.key)
        end
    end
    for field, cards in pairs(ui.cards) do
        for key, c in pairs(cards) do c:SetSelected(choice[field] == key) end
    end
    if pages.done then
        local lines = { "Bar: " .. Label(PLACES, choice.place), "Theme: " .. ns.Themes.list[choice.theme].name,
                        "Effects: " .. Label(EFFECTS, choice.effects) }
        if choice.place ~= "default" then lines[#lines + 1] = "Text: " .. Label(TEXTS, choice.text) end
        pages.done.summary:SetText(table.concat(lines, "    "))
    end

    local flow = Flow()
    ui.footer:SetShown(page ~= "welcome")
    ui.next:SetText(page == "done" and "Finish" or "Next")
    ui.step:SetText(page == "done" and "Done"
        or string.format("Step %d of %d", (IndexOf(flow, page) or 2) - 1, #flow - 2))
end

function ShowPage(name)
    page = name
    if not pages[name] then
        local p = CreateFrame("Frame", nil, ui.body)
        p:SetAllPoints()
        pages[name] = p
        BUILD[name](p)
    end
    for key, p in pairs(pages) do p:SetShown(key == name) end
    -- The placement scene sits on the placement page and again on the last one.
    if ui.scene and (name == "place" or name == "done") then
        ui.scene:SetParent(pages[name])
        ui.scene:ClearAllPoints()
        ui.scene:SetPoint("TOP", 0, name == "place" and -46 or -40)
        ui.scene:Show()
    end
    Refresh()
end

local function Step(delta)
    local flow = Flow()
    local index = IndexOf(flow, page) or 1
    ShowPage(flow[math.max(1, math.min(#flow, index + delta))])
end

-- Apply the choices through the settings controls, so the settings page shows them.
local function Apply()
    local set = ns.Core.SetSetting
    set("bars", choice.place)
    set("theme", choice.theme)
    for key, value in pairs(Preset(choice.effects)) do set(key, value) end
    if choice.place ~= "default" then
        for _, key in ipairs(TEXT_KEYS) do set(key, choice.text == "all") end
    end
end

-- The game's own window: metal border, dark background, gold title, without the portrait, the
-- button bar or the inset, the background started below the title bar so the bar stays dark. Era's
-- and Anniversary's window has the classic border, whose inside starts at the template's own offset.
local function Window()
    local ok, f = pcall(CreateFrame, "Frame", "SmoothExperienceBarSetup", UIParent, "ButtonFrameTemplate")
    if not ok then return end
    if ButtonFrameTemplate_HidePortrait then ButtonFrameTemplate_HidePortrait(f) end
    if ButtonFrameTemplate_HideButtonBar then ButtonFrameTemplate_HideButtonBar(f) end
    if f.Inset then f.Inset:Hide() end
    if f.Bg then
        local interface = select(4, GetBuildInfo())
        local classic = interface < 16000 or interface >= 17000
        local left = classic and select(4, f.Bg:GetPoint(1)) or 6
        f.Bg:SetPoint("TOPLEFT", left, -21)
        if f.TopTileStreaks then f.TopTileStreaks:SetPoint("TOPLEFT", left, -21) end
    end
    return f
end

local function Build()
    -- A plain dark panel should a client not have the window template.
    frame = Window()
    if not frame then
        frame = CreateFrame("Frame", "SmoothExperienceBarSetup", UIParent)
        local bg = frame:CreateTexture(nil, "BACKGROUND")
        bg:SetAllPoints()
        bg:SetColorTexture(0.06, 0.06, 0.08, 0.96)
        Outline(frame, EDGE)
        local close = Button(frame, "Close", 80, function() frame:Hide() end)
        close:SetPoint("TOPRIGHT", -8, -8)
    end
    frame:SetSize(W, H)
    frame:SetPoint("CENTER")
    frame:SetFrameStrata("DIALOG")
    frame:SetToplevel(true)
    frame:SetClampedToScreen(true)
    frame:EnableMouse(true)
    frame:SetMovable(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", frame.StartMoving)
    frame:SetScript("OnDragStop", frame.StopMovingOrSizing)
    frame:Hide()
    -- Escape closes it like the game's windows; closing without finishing means ask me later.
    table.insert(UISpecialFrames, "SmoothExperienceBarSetup")
    frame:SetScript("OnHide", function()
        StopDemo()
        if not closing then ns.Core.EndSetup("later") end
        closing = nil
    end)
    if frame.SetTitle then
        frame:SetTitle("Smooth Experience Bar Setup")
    elseif frame.TitleText then
        frame.TitleText:SetText("Smooth Experience Bar Setup")
    else
        Font(frame, "GameFontNormal", "Smooth Experience Bar Setup", "CENTER"):SetPoint("TOP", 0, -6)
    end

    ui = { cards = {} }
    ui.body = CreateFrame("Frame", nil, frame)
    ui.body:SetPoint("TOPLEFT", 60, -40)
    ui.body:SetPoint("BOTTOMRIGHT", -60, 56)

    ui.footer = CreateFrame("Frame", nil, frame)
    ui.footer:SetPoint("BOTTOMLEFT", 16, 14)
    ui.footer:SetPoint("BOTTOMRIGHT", -16, 14)
    ui.footer:SetHeight(30)
    ui.later = Button(ui.footer, "Ask me later", 130, function() Wizard.Close("later") end)
    ui.later:SetPoint("LEFT", 0, 0)
    ui.skip = Button(ui.footer, "Skip setup", 110, function() Wizard.Close("skip") end)
    ui.skip:SetPoint("LEFT", ui.later, "RIGHT", 8, 0)
    ui.next = Button(ui.footer, "Next", 120, function()
        if page == "done" then
            Apply()
            Wizard.Close("done")
        else
            Step(1)
        end
    end)
    ui.next:SetPoint("RIGHT", 0, 0)
    ui.back = Button(ui.footer, "Back", 100, function() Step(-1) end)
    ui.back:SetPoint("RIGHT", ui.next, "LEFT", -8, 0)
    ui.step = Font(ui.footer, "GameFontHighlightSmall", "", "CENTER")
    ui.step:SetPoint("CENTER")
end

function Wizard.Open()
    if not frame then Build() end
    previews, pages = previews or {}, pages or {}
    choice = CurrentChoices()
    -- Shrink to fit small screens.
    frame:SetScale(math.min(1, (UIParent:GetHeight() - 40) / H))
    frame:Show()
    ShowPage("welcome")
    ui.welcomeSkip:SetText(ns.Core.Get("setupNew") and "Skip, use the defaults" or "Skip, keep my settings")
    StartDemo()
end

-- At login: once out of combat, so it never covers the screen mid-fight.
function Wizard.OpenWhenReady()
    if not ns.Core.SetupWanted() or (frame and frame:IsShown()) then return end
    if InCombatLockdown() then
        C_Timer.After(5, Wizard.OpenWhenReady)
        return
    end
    Wizard.Open()
end

-- how: "later" (open again at the next login), "skip" or "done".
function Wizard.Close(how)
    ns.Core.EndSetup(how)
    closing = true
    frame:Hide()
end

-- For the tests: the window's controls, the page shown and the choices.
function Wizard.State()
    return { frame = frame, ui = ui, page = page, choice = choice, pages = pages }
end
