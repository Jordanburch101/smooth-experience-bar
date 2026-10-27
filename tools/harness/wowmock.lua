-- Minimal WoW API mock: enough to load SmoothExperienceBar, drive it with events and read back
-- every region's layout so Python can draw it.

__regions, __frames, __timers, __now, __chat = {}, {}, {}, 0, {}
__player = { level = 57, xp = 204931, max = 311490, rested = 20000 }
__quests = {}

local function anchorPos(name, w, h)
    local x = name:find("LEFT") and 0 or (name:find("RIGHT") and w or w / 2)
    local y = name:find("TOP") and 0 or (name:find("BOTTOM") and h or h / 2)
    return x, y
end

local Region = {}
Region.__index = Region

local function NewRegion(kind, parent, layer, sub)
    local r = setmetatable({
        kind = kind, parent = parent, layer = layer or "ARTWORK", sub = sub or 0,
        points = {}, w = 0, h = 0, shown = true, alpha = 1, vc = { 1, 1, 1, 1 },
        tc = { 0, 1, 0, 1 }, blend = "BLEND", order = #__regions + 1, scripts = {}, events = {},
    }, Region)
    __regions[#__regions + 1] = r
    return r
end

function Region:SetPoint(point, a, b, c, d)
    local rel, relPoint, x, y
    if a == nil then
        rel, relPoint, x, y = self.parent, point, 0, 0
    elseif type(a) == "number" then
        rel, relPoint, x, y = self.parent, point, a, b or 0
    elseif type(b) == "string" then
        rel, relPoint, x, y = a, b, c or 0, d or 0
    else
        rel, relPoint, x, y = a, point, b or 0, c or 0
    end
    self.points[point] = { rel = rel, relPoint = relPoint, x = x, y = y }
end
function Region:ClearAllPoints() self.points = {} end
function Region:SetAllPoints()
    self.points = {}
    self:SetPoint("TOPLEFT")
    self:SetPoint("BOTTOMRIGHT")
end
function Region:GetPoint()
    for p, v in pairs(self.points) do return p, v.rel, v.relPoint, v.x, v.y end
end
function Region:SetWidth(w) self.w = w end
function Region:SetHeight(h) self.h = h end
function Region:SetSize(w, h) self.w, self.h = w, h end
function Region:GetWidth() return self.w end
function Region:Show() self.shown = true end
function Region:Hide() self.shown = false end
function Region:IsShown() return self.shown end
function Region:SetAlpha(a) self.alpha = a end
function Region:SetScale(s) self.scale = s end
function Region:SetFrameStrata() end
function Region:SetClampedToScreen() end
function Region:SetMovable() end
function Region:RegisterForDrag() end
function Region:EnableMouse() end
function Region:StartMoving() end
function Region:StopMovingOrSizing() end
function Region:SetScript(name, fn) self.scripts[name] = fn end
function Region:RegisterEvent(e) self.events[e] = true end
function Region:UnregisterEvent(e) self.events[e] = nil end
function Region:IsEventRegistered(e) return self.events[e] end
function Region:SetTexture(file, wh) self.file, self.wrap, self.color = file, wh, nil end
function Region:SetColorTexture(r, g, b, a) self.file, self.color = "SOLID", { r, g, b, a or 1 } end
function Region:SetVertexColor(r, g, b, a) self.vc, self.grad = { r, g, b, a or 1 }, nil end
function Region:SetGradient(_, c1, c2)
    self.grad = { { c1:GetRGBA() }, { c2:GetRGBA() } }
end
function Region:SetBlendMode(m) self.blend = m end
function Region:SetTexCoord(l, r, t, b) self.tc = { l, r, t, b } end
function Region:SetDrawLayer(layer, sub) self.layer, self.sub = layer, sub or 0 end
function Region:SetSnapToPixelGrid() end
function Region:SetTexelSnappingBias() end
function Region:SetFont(_, size) self.fontSize = size end
function Region:SetShadowColor() end
function Region:SetShadowOffset() end
function Region:SetTextColor() end
function Region:SetJustifyH() end
function Region:SetText(t) self.text = t end
function Region:SetFormattedText(fmt, ...) self.text = string.format(fmt, ...) end
function Region:GetStringWidth()
    local plain = (self.text or ""):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
    return #plain * (self.fontSize or 12) * 0.55
end
function Region:CreateTexture(_, layer, _, sub) return NewRegion("Texture", self, layer, sub) end
function Region:CreateFontString(_, layer) return NewRegion("FontString", self, layer, 0) end

-- Rect relative to the region's parent, top-left origin, y down.
function Region:Rect()
    local pw, ph = 600, 30
    if self.parent and self.parent.w then pw, ph = self.parent.w, self.parent.h end
    local w, h = self.w, self.h
    if self.kind == "FontString" then
        w, h = self:GetStringWidth(), (self.fontSize or 12)
    end
    local left, right, cx, top, bottom, cy
    for p, a in pairs(self.points) do
        local ax, ay = anchorPos(a.relPoint, pw, ph)
        local x, y = ax + a.x, ay - a.y
        if p:find("LEFT") then left = x elseif p:find("RIGHT") then right = x else cx = x end
        if p:find("TOP") then top = y elseif p:find("BOTTOM") then bottom = y else cy = y end
    end
    if left and right then w = right - left
    elseif right then left = right - w
    elseif not left then left = (cx or 0) - w / 2 end
    if top and bottom then h = bottom - top
    elseif bottom then top = bottom - h
    elseif not top then top = (cy or 0) - h / 2 end
    return left, top, w, h
end

UIParent = NewRegion("Frame", nil, "BACKGROUND", 0)
UIParent.w, UIParent.h = 1920, 1080

function CreateFrame(_, name, parent)
    local f = NewRegion("Frame", parent, "BACKGROUND", 0)
    __frames[#__frames + 1] = f
    if name then _G[name] = f end
    return f
end

local Color = {}
Color.__index = Color
function Color:SetRGBA(r, g, b, a) self.r, self.g, self.b, self.a = r, g, b, a end
function Color:GetRGBA() return self.r, self.g, self.b, self.a end
function CreateColor(r, g, b, a) return setmetatable({ r = r, g = g, b = b, a = a or 1 }, Color) end

function UnitXP() return __player.xp end
function UnitXPMax() return __player.max end
function UnitLevel() return __player.level end
function GetXPExhaustion() return __player.rested > 0 and __player.rested or nil end
function GetMaxPlayerLevel() return 70 end
function GetNumQuestLogEntries() return #__quests end
function GetQuestLogTitle(i)
    local q = __quests[i]
    return "Quest", 57, 0, false, false, q.complete and 1 or nil, 0, q.id
end
function GetQuestLogRewardXP(id)
    for _, q in ipairs(__quests) do if q.id == id then return q.xp end end
    return 0
end
function GetQuestLogSelection() return 0 end
function SelectQuestLogEntry() end
function IsQuestComplete() return false end
function RequestTimePlayed() __fire("TIME_PLAYED_MSG", 360000, 240) end
function GetTime() return __now end
function time() return 1800000000 + floor(__now) end
floor = math.floor

C_QuestLog = {}
C_Timer = {}
function C_Timer.After(d, fn) __timers[#__timers + 1] = { at = __now + d, fn = fn } end
function C_Timer.NewTicker(d, fn)
    local t = { cancelled = false }
    function t:Cancel() self.cancelled = true end
    local function tick()
        if t.cancelled then return end
        fn()
        C_Timer.After(d, tick)
    end
    C_Timer.After(d, tick)
    return t
end

NUM_CHAT_WINDOWS = 1
ChatFrame1 = NewRegion("Frame", nil)
ChatFrame1.events.TIME_PLAYED_MSG = true
DEFAULT_CHAT_FRAME = { AddMessage = function(_, m) __chat[#__chat + 1] = m end }
SlashCmdList = {}
function wipe(t) for k in pairs(t) do t[k] = nil end return t end
function strlower(s) return s:lower() end
function strtrim(s) return (s:gsub("^%s+", ""):gsub("%s+$", "")) end
function strsplit(sep, s, n)
    local out, start = {}, 1
    while true do
        if n and #out == n - 1 then out[#out + 1] = s:sub(start); break end
        local i = s:find(sep, start, true)
        if not i then out[#out + 1] = s:sub(start); break end
        out[#out + 1] = s:sub(start, i - 1)
        start = i + 1
    end
    return unpack(out)
end
function FormatLargeNumber(n)
    local s = tostring(n)
    local k
    repeat s, k = s:gsub("^(-?%d+)(%d%d%d)", "%1,%2") until k == 0
    return s
end

function __fire(event, ...)
    for _, f in ipairs(__frames) do
        if f.events[event] and f.scripts.OnEvent then f.scripts.OnEvent(f, event, ...) end
    end
end

function __step(dt)
    __now = __now + dt
    local due = {}
    for i = #__timers, 1, -1 do
        if __timers[i].at <= __now then
            due[#due + 1] = __timers[i]
            table.remove(__timers, i)
        end
    end
    for i = #due, 1, -1 do due[i].fn() end
    for _, f in ipairs(__frames) do
        if f.shown and f.scripts.OnUpdate then f.scripts.OnUpdate(f, dt) end
    end
end

function __load(path, name, ns)
    local chunk = assert(loadfile(path))
    chunk(name, ns)
end
