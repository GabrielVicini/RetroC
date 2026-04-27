local text = require("libraries/text/text")
local theme = require("libraries/ui/theme")
local tween = require("libraries/ui/tween")

local Checkbox = {}
Checkbox.__index = Checkbox

function Checkbox.new(s, label)
    local self = setmetatable({}, Checkbox)
    self.baseW = s
    self.baseH = s
    self.w = s
    self.h = s
    self.x = 0
    self.y = 0
    self.padX = 0
    self.padY = 0
    self.anchor = "top-left"
    self.label = label
    self.checked = false
    self.fill = 0
    self.z = 1
    return self
end

function Checkbox:syncLayout()
end

function Checkbox:update(mx, my, mDown, dt, mPressed)
    local hover = (mx >= self.x and mx <= self.x + self.w + 10 + text.getTextWidth(self.label) and my >= self.y and my <= self.y + self.h)
    if hover and mPressed then
        self.checked = not self.checked
    end
    self.fill = tween.expo(self.fill, self.checked and 1 or 0, dt)
    return hover
end

function Checkbox:draw()
    local tr = math.max(0, theme.panel[1] - 15)
    local tg = math.max(0, theme.panel[2] - 15)
    local tb = math.max(0, theme.panel[3] - 15)

    term.fillRect(self.x, self.y, self.w, self.h, tr, tg, tb)

    if self.fill > 0.05 then
        local fs = math.floor(self.w * 0.7 * self.fill)
        local o = math.floor((self.w - fs) / 2)
        term.fillRect(self.x + o, self.y + o, fs, fs, theme.success[1], theme.success[2], theme.success[3])
    end

    local ty = self.y + math.floor((self.h - 16) / 2)
    text.drawText(self.x + self.w + 10, ty, self.label, theme.text[1], theme.text[2], theme.text[3], 1)
end

return Checkbox