-- Liquid rendering for the experience fill: a wobbling front, swirling magic inside,
-- bubbles and glowing motes. Positions are in bar units (pixels before the bar's scale).

local _, ns = ...

local exp, min, max, abs, sin, floor, random = math.exp, math.min, math.max, math.abs, math.sin, math.floor, math.random

local MEDIA = "Interface\\AddOns\\SmoothExperienceBar\\Media\\"
local TEX = "Interface\\Buttons\\WHITE8x8"
local SWIRL_W, SWIRL_H = 256, 64

local CFG = {
    rows        = 15,      -- horizontal slices that make up the liquid front
    amplitude   = 10,      -- how far the front can bulge or dip, px
    stiffness   = 90,      -- spring pulling each slice back to rest
    damping     = 3.5,
    coupling    = 900,     -- how strongly neighbouring slices pull on each other (wave speed)
    slosh       = 0.18,    -- front displacement per px/s change in fill speed
    ambient     = 1.0,     -- idle wobble, px
    step        = 1 / 120, -- fixed physics step
    energyDecay = 0.8,     -- per second
    fizz        = 0.5,     -- idle bubbles per second
    bubbles     = 16,      -- pool sizes
    motes       = 40,
}

local function Rand(a, b)
    return a + (b - a) * random()
end

local function Lerp(a, b, t)
    return a + (b - a) * t
end

local Liquid = {}
Liquid.__index = Liquid
ns.Liquid = Liquid

-- opts holds the user toggles (waves, swirl, bubbles, sparkles) and is read live.
function Liquid.New(parent, width, height, theme, opts)
    local self = setmetatable({}, Liquid)
    self.parent, self.width, self.height, self.opts = parent, width, height, opts
    self.rowH = height / CFG.rows

    local function Tex(layer, sublevel, file, blend, wrap)
        local t = parent:CreateTexture(nil, layer, nil, sublevel)
        if wrap then
            t:SetTexture(file, wrap, wrap)
        else
            t:SetTexture(file)
        end
        if blend then t:SetBlendMode(blend) end
        if t.SetSnapToPixelGrid then
            t:SetSnapToPixelGrid(false)
            t:SetTexelSnappingBias(0)
        end
        t:Hide()
        return t
    end

    self.body = Tex("ARTWORK", 3, TEX)
    self.body:SetPoint("TOPLEFT")
    self.body:SetPoint("BOTTOMLEFT")

    self.rows, self.tips, self.pos, self.vel = {}, {}, {}, {}
    for i = 1, CFG.rows do
        local row = Tex("ARTWORK", 3, TEX)
        row:SetHeight(self.rowH)
        self.rows[i] = row

        local tip = Tex("ARTWORK", 6, TEX, "ADD")
        tip:SetSize(3, self.rowH)
        self.tips[i] = tip

        self.pos[i], self.vel[i] = 0, 0
    end

    self.swirlA = Tex("ARTWORK", 5, MEDIA .. "Swirl", "ADD", "REPEAT")
    self.swirlA:SetPoint("TOPLEFT")
    self.swirlA:SetPoint("BOTTOMLEFT")

    self.swirlB = Tex("ARTWORK", 5, MEDIA .. "Swirl", "ADD", "REPEAT")
    self.swirlB:SetPoint("TOPLEFT")
    self.swirlB:SetPoint("BOTTOMLEFT")

    self.glow = Tex("ARTWORK", 7, MEDIA .. "Glow", "ADD")
    self.glow:SetSize(36, height * 1.7)

    self.bubbles = {}
    for i = 1, CFG.bubbles do
        self.bubbles[i] = { tex = Tex("OVERLAY", 3, MEDIA .. "Bubble"), active = false }
    end

    self.motes, self.moteNext = {}, 1
    for i = 1, CFG.motes do
        self.motes[i] = { tex = Tex("OVERLAY", 4, MEDIA .. "Mote", "ADD"), active = false }
    end

    self.gradA, self.gradB, self.gradC = CreateColor(1, 1, 1, 1), CreateColor(1, 1, 1, 1), CreateColor(1, 1, 1, 1)
    self.t, self.acc, self.energy, self.fizzAcc = 0, 0, 0, 0
    self.edge, self.speed = 0, 0
    self.uA, self.uB, self.vB = 0, 0.37, 0
    self:SetTheme(theme)
    return self
end

function Liquid:SetTheme(theme)
    self.theme = theme
    for _, tip in ipairs(self.tips) do
        tip:SetVertexColor(unpack(theme.tip))
    end
    self.swirlA:SetVertexColor(unpack(theme.swirlA))
    self.swirlB:SetVertexColor(unpack(theme.swirlB))
    self.glow:SetVertexColor(unpack(theme.glow))
    for _, b in ipairs(self.bubbles) do
        b.tex:SetVertexColor(unpack(theme.bubble))
    end
end

function Liquid:SetSize(width, height)
    self.width, self.height = width, height
    self.rowH = height / CFG.rows
    for i = 1, CFG.rows do
        self.rows[i]:SetHeight(self.rowH)
        self.tips[i]:SetSize(3, self.rowH)
    end
    self.glow:SetSize(36, height * 1.7)
end

function Liquid:SetOptions(opts)
    self.opts = opts
    self:ApplyOptions()
end

-- Clear anything a toggle just switched off.
function Liquid:ApplyOptions()
    local opts = self.opts
    if not opts.waves then
        for i = 1, CFG.rows do self.pos[i], self.vel[i] = 0, 0 end
    end
    if not opts.bubbles then
        for _, b in ipairs(self.bubbles) do
            b.active = false
            b.tex:Hide()
        end
    end
    if not opts.sparkles then
        for _, m in ipairs(self.motes) do
            m.active = false
            m.tex:Hide()
        end
    end
end

--------------------------------------------------------------------------------
-- Events from the bar
--------------------------------------------------------------------------------

-- Jump the front without sloshing, e.g. on load or when a level wraps back to 0.
function Liquid:Snap(edge)
    self.edge, self.speed = edge, 0
end

-- XP gained. intensity 0..1, fromX..toX is where the new XP will land.
function Liquid:Splash(intensity, fromX, toX)
    self.energy = min(1.5, self.energy + 0.08 + intensity * 0.9)

    -- Ripple out from a random point on the front.
    if self.opts.waves then
        local n = CFG.rows
        local centre = random(1, n)
        local kick = 40 + 160 * intensity
        for i = 1, n do
            local d = (i - centre) / n
            self.vel[i] = self.vel[i] + kick * exp(-d * d * 8)
        end
    end

    local h, theme = self.height, self.theme
    for _ = 1, floor(1 + intensity * 18) do
        local s = 0.5 + intensity
        self:EmitMote(Rand(fromX - 6, max(fromX, toX)), Rand(2, h - 2),
            Rand(-20, 60) * s, Rand(10, 70) * s,
            Rand(0.5, 1.1) + intensity * 0.4, Rand(8, 14) * (0.7 + 0.5 * intensity),
            theme.splashFrom, theme.splashTo)
    end
    for _ = 1, floor(intensity * 8) do
        self:EmitBubble(Rand(max(4, fromX - 40), max(4, fromX - 2)))
    end
end

-- Completed-quest XP turned in: orange motes stream from the quest segment into the liquid.
function Liquid:Absorb(fromX, toX, intensity)
    local h, theme = self.height, self.theme
    for _ = 1, floor(4 + intensity * 16) do
        self:EmitMote(Rand(fromX, max(fromX, toX)), Rand(2, h - 2),
            -Rand(40, 140), Rand(-10, 25),
            Rand(0.6, 1.1), Rand(8, 13),
            theme.quest, theme.absorbTo)
    end
end

function Liquid:LevelUp()
    self.energy = 1.5
    if self.opts.waves then
        for i = 1, CFG.rows do
            self.vel[i] = self.vel[i] + Rand(120, 220)
        end
    end
    local w, h, theme = self.width, self.height, self.theme
    for _ = 1, 30 do
        self:EmitMote(Rand(0, w), Rand(0, h),
            Rand(-30, 30), Rand(40, 120),
            Rand(0.8, 1.6), Rand(10, 18),
            theme.levelFrom, theme.levelTo)
    end
end

-- Nothing visible is moving beyond the idle wobble, so the caller can lower the update rate.
function Liquid:IsQuiet()
    if self.energy > 0.02 then return false end
    for i = 1, CFG.rows do
        if abs(self.vel[i]) > 1 or abs(self.pos[i]) > 0.3 then return false end
    end
    for _, m in ipairs(self.motes) do
        if m.active then return false end
    end
    return true
end

--------------------------------------------------------------------------------
-- Particles
--------------------------------------------------------------------------------

-- from/to are the colours the mote fades between over its life.
function Liquid:EmitMote(x, y, vx, vy, life, size, from, to)
    if not self.opts.sparkles then return end
    local m = self.motes[self.moteNext]
    self.moteNext = self.moteNext % #self.motes + 1
    m.x, m.y, m.vx, m.vy, m.age, m.life, m.size = x, y, vx, vy, 0, life, size
    m.r1, m.g1, m.b1, m.r2, m.g2, m.b2 = from[1], from[2], from[3], to[1], to[2], to[3]
    m.active = true
    m.tex:Show()
end

function Liquid:EmitBubble(x)
    if not self.opts.bubbles then return end
    for _, b in ipairs(self.bubbles) do
        if not b.active then
            b.x, b.y = x, Rand(2, 6)
            b.vx, b.vy = Rand(4, 14), Rand(12, 26)
            b.size = Rand(3, 6)
            b.phase, b.freq = Rand(0, 6.28), Rand(4, 8)
            b.pop = nil
            b.active = true
            b.tex:Show()
            return
        end
    end
end

function Liquid:UpdateParticles(dt)
    local parent, h, edge = self.parent, self.height, self.edge

    for _, b in ipairs(self.bubbles) do
        if b.active then
            if b.pop then
                b.pop = b.pop + dt
                local p = b.pop / 0.15
                if p >= 1 then
                    b.active = false
                    b.tex:Hide()
                else
                    b.tex:SetSize(b.size * (1 + p), b.size * (1 + p))
                    b.tex:SetAlpha(0.6 * (1 - p))
                end
            else
                b.x = b.x + (b.vx + self.speed * 0.3) * dt
                b.y = b.y + b.vy * dt
                if b.y >= h - b.size * 0.5 or b.x > edge - 2 then
                    b.pop = 0
                end
                b.tex:SetSize(b.size, b.size)
                b.tex:SetAlpha(0.6)
            end
            b.tex:SetPoint("CENTER", parent, "BOTTOMLEFT", b.x + sin(b.phase + self.t * b.freq) * 1.5, b.y)
        end
    end

    local drag = exp(-1.8 * dt)
    for _, m in ipairs(self.motes) do
        if m.active then
            m.age = m.age + dt
            local p = m.age / m.life
            if p >= 1 then
                m.active = false
                m.tex:Hide()
            else
                m.vx = m.vx * drag
                m.vy = m.vy * drag + 20 * dt -- motes float up
                m.x = m.x + m.vx * dt
                m.y = m.y + m.vy * dt
                local size = m.size * (1 - 0.5 * p)
                local fadeIn = p < 0.1 and p / 0.1 or 1
                m.tex:SetSize(size, size)
                m.tex:SetVertexColor(Lerp(m.r1, m.r2, p), Lerp(m.g1, m.g2, p), Lerp(m.b1, m.b2, p))
                m.tex:SetAlpha(fadeIn * (1 - p) ^ 1.5)
                m.tex:SetPoint("CENTER", parent, "BOTTOMLEFT", m.x, m.y)
            end
        end
    end
end

--------------------------------------------------------------------------------
-- Simulation and drawing
--------------------------------------------------------------------------------

function Liquid:Simulate(dt)
    local pos, vel, n = self.pos, self.vel, CFG.rows
    local k, d, c, limit = CFG.stiffness, CFG.damping, CFG.coupling, CFG.amplitude * 1.2
    local s = CFG.step

    self.acc = min(self.acc + dt, s * 8)
    while self.acc >= s do
        self.acc = self.acc - s
        for i = 1, n do
            local p = pos[i]
            local lap = (pos[i - 1] or p) + (pos[i + 1] or p) - 2 * p
            vel[i] = vel[i] + (-k * p - d * vel[i] + c * lap) * s
        end
        for i = 1, n do
            local p = pos[i] + vel[i] * s
            if p > limit then
                p, vel[i] = limit, 0
            elseif p < -limit then
                p, vel[i] = -limit, 0
            end
            pos[i] = p
        end
    end
end

function Liquid:Update(dt, edge)
    self.t = self.t + dt

    -- The liquid's inertia: speeding up drags the front back, slowing down sloshes it forward.
    local speed = (edge - self.edge) / dt
    local dv = speed - self.speed
    self.edge, self.speed = edge, speed
    if dv ~= 0 and self.opts.waves then
        local kick = -dv * CFG.slosh
        local n = CFG.rows
        for i = 1, n do
            self.vel[i] = self.vel[i] + kick * sin(math.pi * (i - 0.5) / n)
        end
    end

    self:Simulate(dt)
    self.energy = self.energy * exp(-CFG.energyDecay * dt)

    self.fizzAcc = self.fizzAcc + dt * (CFG.fizz + self.energy * 14)
    while self.fizzAcc >= 1 do
        self.fizzAcc = self.fizzAcc - 1
        if edge > 16 then self:EmitBubble(Rand(4, edge - 8)) end
    end

    self:Draw(dt)
    self:UpdateParticles(dt)
end

function Liquid:Draw(dt)
    local parent, w, h, amp = self.parent, self.width, self.height, CFG.amplitude
    local edge, energy, t = self.edge, self.energy, self.t
    local base = max(0, edge - amp)
    local opts = self.opts
    local fa, fb = self.theme.fillA, self.theme.fillB

    -- Gradient stretched over the whole fill, like the WeakAura; the body stops where the front begins.
    local tb = edge > 0 and base / edge or 0
    self.gradA:SetRGBA(fa[1], fa[2], fa[3], 1)
    self.gradB:SetRGBA(Lerp(fa[1], fb[1], tb), Lerp(fa[2], fb[2], tb), Lerp(fa[3], fb[3], tb), 1)
    self.gradC:SetRGBA(fb[1], fb[2], fb[3], 1)

    if base >= 0.5 then
        self.body:SetGradient("HORIZONTAL", self.gradA, self.gradB)
        self.body:SetWidth(base)
        self.body:Show()
    else
        self.body:Hide()
    end

    local wobble = opts.waves and CFG.ambient * (0.6 + energy) or 0
    local tipAlpha = 0.25 + 0.5 * min(1, energy)
    local rowH = self.rowH
    for i = 1, CFG.rows do
        local row, tip = self.rows[i], self.tips[i]
        local off = self.pos[i] + wobble * (sin(t * 2.3 + i * 0.6) + 0.5 * sin(t * 3.7 - i * 1.1))
        local right = min(w, edge + off)
        local rw = right - base
        if edge < 0.5 or rw < 0.5 then
            row:Hide()
            tip:Hide()
        else
            local y = -(i - 1) * rowH
            row:SetGradient("HORIZONTAL", self.gradB, self.gradC)
            row:SetPoint("TOPLEFT", parent, "TOPLEFT", base, y)
            row:SetWidth(rw)
            row:Show()
            if right < w - 1 then
                tip:SetPoint("TOPLEFT", parent, "TOPLEFT", right - 2, y)
                tip:SetAlpha(min(1, tipAlpha + abs(self.vel[i]) * 0.01))
                tip:Show()
            else
                tip:Hide()
            end
        end
    end

    -- Magic veins drift toward the front; faster and brighter with energy and fill speed.
    local swirlW = max(0, edge - amp * 0.5)
    if swirlW >= 1 and opts.swirl then
        local flow = 0.015 + 0.12 * energy + max(0, self.speed) / 2000
        self.uA = (self.uA - flow * dt) % 1
        self.uB = (self.uB - flow * 0.6 * dt) % 1
        self.vB = (self.vB + 0.03 * dt) % 1
        local spanU, spanV = swirlW / SWIRL_W, h / SWIRL_H
        self.swirlA:SetTexCoord(self.uA, self.uA + spanU, 0, spanV)
        self.swirlB:SetTexCoord(self.uB, self.uB + spanU * 0.7, self.vB, self.vB + spanV * 0.7)
        self.swirlA:SetWidth(swirlW)
        self.swirlB:SetWidth(swirlW)
        self.swirlA:SetAlpha(min(1, 0.12 + 0.3 * energy))
        self.swirlB:SetAlpha(min(1, 0.08 + 0.22 * energy + 0.05 * sin(t * 1.3)))
        self.swirlA:Show()
        self.swirlB:Show()
    else
        self.swirlA:Hide()
        self.swirlB:Hide()
    end

    if edge > 1 and edge < w - 1 then
        self.glow:SetPoint("CENTER", parent, "LEFT", edge, 0)
        self.glow:SetAlpha(min(1, 0.12 + 0.55 * energy))
        self.glow:Show()
    else
        self.glow:Hide()
    end
end
