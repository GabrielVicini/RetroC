local text = require("libraries/text/text")
local theme = require("libraries/ui/theme")
local tween = require("libraries/ui/tween")
local Button = {}

Button.__index = Button

function Button.new(w, h, label)
    local self = setmetatable({}, Button)
    self.baseW, self.baseH = w, h
    self.w, self.h = w, h
    self.x, self.y = 0, 0
    self.label = label
    self.hovered, self.pressed = false, false
    self.color = {theme.primary[1], theme.primary[2], theme.primary[3]}
    self.z = 1
    self.clickAnim = 1
    return self
end

function Button:update(mx, my, mDown, dt, mPressed)
    self.hovered = (mx >= self.x and mx <= self.x + self.w and my >= self.y and my <= self.y + self.h)
    self.pressed = self.hovered and mDown

    local targetScale = 1
    if self.pressed then
        targetScale = 0.95
    elseif self.hovered then
        targetScale = 1.05
    end

    self.clickAnim = tween.expo(self.clickAnim, targetScale, dt)

    local target = self.pressed and theme.primaryPress or (self.hovered and theme.primaryHover or theme.primary)
    for i = 1, 3 do
        self.color[i] = tween.expo(self.color[i], target[i], dt)
    end

    return self.hovered
end

function Button:draw()
    local drawW = self.w * self.clickAnim
    local drawH = self.h * self.clickAnim
    local offX = (self.w - drawW) / 2
    local offY = (self.h - drawH) / 2

    term.fillRect(self.x + offX, self.y + offY, drawW, drawH, self.color[1], self.color[2], self.color[3])

    local tw = text.getTextWidth(self.label)
    local tx = self.x + math.floor((self.w - tw) / 2)
    local ty = self.y + math.floor((self.h - 16) / 2)

    text.drawText(tx, ty, self.label, theme.text[1], theme.text[2], theme.text[3], 1)
end

return Button