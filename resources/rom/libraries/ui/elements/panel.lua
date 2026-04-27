local theme = require("libraries/ui/theme")

local Panel = {}
Panel.__index = Panel

function Panel.new(w, h)
    local self = setmetatable({}, Panel)
    self.baseW = w
    self.baseH = h
    self.w = w
    self.h = h
    self.x = 0
    self.y = 0
    self.padX = 0
    self.padY = 0
    self.anchor = "top-left"
    self.z = 0
    self.children = {}
    return self
end

function Panel:add(el, anchor, padX, padY)
    el.parent = self
    el.anchor = anchor or "top-left"
    el.padX = padX or 0
    el.padY = padY or 0
    table.insert(self.children, el)
    self:syncLayout()
end

function Panel:syncLayout()
    for _, el in ipairs(self.children) do
        el.w = (el.baseW > 0 and el.baseW <= 1) and (el.baseW * self.w) or el.baseW
        el.h = (el.baseH > 0 and el.baseH <= 1) and (el.baseH * self.h) or el.baseH
        if el.anchor == "center" then
            el.x = self.x + (self.w - el.w) / 2 + el.padX
            el.y = self.y + (self.h - el.h) / 2 + el.padY
        elseif el.anchor == "right" then
            el.x = self.x + self.w - el.w - el.padX
            el.y = self.y + el.padY
        elseif el.anchor == "bottom" then
            el.x = self.x + el.padX
            el.y = self.y + self.h - el.h - el.padY
        else
            el.x = self.x + el.padX
            el.y = self.y + el.padY
        end
        if el.syncLayout then el:syncLayout() end
    end
end

function Panel:update(mx, my, mDown, dt, mPressed)
    local hit = false
    for i = #self.children, 1, -1 do
        local el = self.children[i]
        if el:update(mx, my, mDown, dt, mPressed and not hit) then
            hit = true
        end
    end
    if mx >= self.x and mx <= self.x + self.w and my >= self.y and my <= self.y + self.h then
        hit = true
    end
    return hit
end

function Panel:draw()
    term.fillRect(self.x, self.y, self.w, self.h, theme.panel[1], theme.panel[2], theme.panel[3])
    for _, el in ipairs(self.children) do
        el:draw()
    end
end

return Panel