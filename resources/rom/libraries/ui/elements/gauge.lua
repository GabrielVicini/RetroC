local text = require("libraries/text/text")
local theme = require("libraries/ui/theme")

local Gauge = {}
Gauge.__index = Gauge

function Gauge.new(w, h, min, max, val, redline)
    local self = setmetatable({}, Gauge)
    self.baseW, self.baseH = w, h
    self.w, self.h = w, h
    self.x, self.y = 0, 0
    self.padX, self.padY = 0, 0
    self.anchor = "top-left"
    self.min = min
    self.max = max
    self.val = val
    self.animVal = val
    self.redline = redline or max
    self.z = 1
    return self
end

function Gauge:syncLayout()
end

function Gauge:update(mx, my, mDown, dt, mPressed)
    self.animVal = self.animVal + (self.val - self.animVal) * (1 - math.exp(-15 * dt))
    return false
end

function Gauge:draw()
    local tr = math.max(0, theme.panel[1] - 15)
    local tg = math.max(0, theme.panel[2] - 15)
    local tb = math.max(0, theme.panel[3] - 15)

    local cx = math.floor(self.x + self.w / 2)
    local cy = math.floor(self.y + self.h / 2)

    local maxR = math.floor(math.min(self.w, self.h) / 2)

    for y = 0, self.h do
        local dy = (self.y + y) - cy
        local dx = 0

        if maxR^2 - dy^2 > 0 then
            dx = math.sqrt(maxR^2 - dy^2)
        end

        if dx > 0 then
            local drawW = math.floor(dx * 2)
            local drawX = cx - math.floor(dx)
            term.fillRect(drawX, self.y + y, drawW, 1, tr, tg, tb)
        end
    end

    local r = maxR - 18

    local startAngle = math.pi * 0.75
    local endAngle = math.pi * 2.25
    local sweep = endAngle - startAngle

    local ticks = 10
    for i = 0, ticks do
        local pct = i / ticks
        local a = startAngle + (sweep * pct)
        local tickVal = self.min + pct * (self.max - self.min)

        local cR, cG, cB = theme.text[1], theme.text[2], theme.text[3]
        if tickVal >= self.redline then
            cR, cG, cB = 255, 60, 60
        end

        local ox = cx + math.cos(a) * r
        local oy = cy + math.sin(a) * r
        local ix = cx + math.cos(a) * (r - 6)
        local iy = cy + math.sin(a) * (r - 6)

        term.drawLine(math.floor(ix), math.floor(iy), math.floor(ox), math.floor(oy), cR, cG, cB)

        if i % 2 == 0 then
            local tx = cx + math.cos(a) * (r - 18)
            local ty = cy + math.sin(a) * (r - 18)
            local str = tostring(math.floor(tickVal))
            local tw = text.getTextWidth(str)
            text.drawText(math.floor(tx - tw / 2), math.floor(ty - 8), str, cR, cG, cB, 1)
        end
    end

    local animPct = (self.animVal - self.min) / (self.max - self.min)
    animPct = math.max(0, math.min(1, animPct))
    local na = startAngle + (sweep * animPct)

    local nx = cx + math.cos(na) * (r - 4)
    local ny = cy + math.sin(na) * (r - 4)

    term.drawLine(cx, cy, math.floor(nx), math.floor(ny), theme.primary[1], theme.primary[2], theme.primary[3])

    term.fillRect(cx - 3, cy - 3, 6, 6, theme.text[1], theme.text[2], theme.text[3])

    local valStr = tostring(math.floor(self.animVal))
    local vw = text.getTextWidth(valStr)
    text.drawText(math.floor(cx - vw / 2), math.floor(cy + maxR - 22), valStr, theme.text[1], theme.text[2], theme.text[3], 1)
end

return Gauge