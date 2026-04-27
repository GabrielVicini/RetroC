local theme = require("libraries/ui/theme")
local tween = require("libraries/ui/tween")

local ProgressBar = {}
ProgressBar.__index = ProgressBar

function ProgressBar.new(w, h)
    local self = setmetatable({}, ProgressBar)
    self.baseW = w
    self.baseH = h
    self.w = w
    self.h = h
    self.x = 0
    self.y = 0
    self.padX = 0
    self.padY = 0
    self.anchor = "top-left"
    self.pct = 0
    self.animPct = 0
    self.z = 1
    return self
end

function ProgressBar:syncLayout()
end

function ProgressBar:update(mx, my, mDown, dt, mPressed)
    self.animPct = tween.expo(self.animPct, self.pct, dt)
    return false
end

function ProgressBar:draw()
    local tr = math.max(0, theme.panel[1] - 15)
    local tg = math.max(0, theme.panel[2] - 15)
    local tb = math.max(0, theme.panel[3] - 15)

    term.fillRect(self.x, self.y, self.w, self.h, tr, tg, tb)

    local fw = self.w * self.animPct
    if fw > 1 then
        term.fillRect(self.x, self.y, fw, self.h, theme.primary[1], theme.primary[2], theme.primary[3])
    end
end

return ProgressBar