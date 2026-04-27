local theme = require("libraries/ui/theme")
local tween = require("libraries/ui/tween")

local Slider = {}
Slider.__index = Slider

function Slider.new(w, h, min, max, val)
    local self = setmetatable({}, Slider)
    self.baseW, self.baseH = w, h
    self.w, self.h = w, h
    self.x, self.y = 0, 0
    self.min, self.max, self.val = min, max, val
    self.drag = false
    self.thumbX = 0
    self.z = 1
    self.vel = 0
    self.stretch = 0
    self.tilt = 0
    return self
end

function Slider:syncLayout()
    self.thumbX = self.x + (self.val - self.min) / (self.max - self.min) * self.w
end

function Slider:update(mx, my, mDown, dt, mPressed)
    local hover = (mx >= self.x and mx <= self.x + self.w and my >= self.y - 10 and my <= self.y + self.h + 10)
    local prevX = self.thumbX

    if hover and mDown and not self.drag then self.drag = true end
    if not mDown then self.drag = false end

    if self.drag then
        local pct = math.max(0, math.min(1, (mx - self.x) / self.w))
        self.val = self.min + pct * (self.max - self.min)
    end

    local targetX = self.x + (self.val - self.min) / (self.max - self.min) * self.w
    self.thumbX = self.thumbX + (targetX - self.thumbX) * (1 - math.exp(-25 * dt))

    self.vel = (self.thumbX - prevX) / dt

    local targetStretch = math.abs(self.vel) / 500
    if self.val <= self.min or self.val >= self.max then
        targetStretch = targetStretch + 0.5
    end

    self.stretch = self.stretch + (targetStretch - self.stretch) * (1 - math.exp(-15 * dt))
    self.tilt = self.tilt + ((self.vel / 1000) - self.tilt) * (1 - math.exp(-10 * dt))

    return hover or self.drag
end

function Slider:draw()
    local tr = math.max(0, theme.panel[1] - 20)
    local tg = math.max(0, theme.panel[2] - 20)
    local tb = math.max(0, theme.panel[3] - 20)

    term.fillRect(self.x, self.y + self.h / 2 - 2, self.w, 4, tr, tg, tb)
    term.fillRect(self.x, self.y + self.h / 2 - 2, math.max(0, self.thumbX - self.x), 4, theme.primary[1], theme.primary[2], theme.primary[3])

    local baseW, baseH = 8, 16
    local sW = baseW + (baseW * self.stretch * 0.5)
    local sH = baseH - (baseH * self.stretch * 0.2)

    local tX = self.thumbX - (sW / 2)
    local tY = (self.y + self.h / 2) - (sH / 2)

    local skew = math.floor(self.tilt * 5)

    term.fillRect(tX, tY + skew, sW, sH, theme.text[1], theme.text[2], theme.text[3])
end

return Slider