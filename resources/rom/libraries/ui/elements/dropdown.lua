local text = require("libraries/text/text")
local theme = require("libraries/ui/theme")
local tween = require("libraries/ui/tween")

local Dropdown = {}
Dropdown.__index = Dropdown

function Dropdown.new(w, h, opts)
    local self = setmetatable({}, Dropdown)
    self.baseW, self.baseH = w, h
    self.w, self.h = w, h
    self.x, self.y = 0, 0
    self.opts = opts
    self.idx = 1
    self.open = false
    self.z = 1
    self.animH = h
    return self
end

function Dropdown:syncLayout()
    self.animH = self.h
end

function Dropdown:update(mx, my, mDown, dt, mPressed)
    local targetH = self.h
    if self.open then
        targetH = self.h + (#self.opts * self.h)
    end

    self.animH = self.animH + (targetH - self.animH) * (1 - math.exp(-25 * dt))

    if math.abs(self.animH - targetH) < 0.5 then self.animH = targetH end

    local newZ = self.open and 100 or 1
    if newZ ~= self.z then
        self.z = newZ
        self.needsSort = true
    end

    local hoverMain = (mx >= self.x and mx <= self.x + self.w and my >= self.y and my <= self.y + self.h)

    if mPressed then
        if hoverMain then
            self.open = not self.open
        elseif self.open then
            local dropHover = (mx >= self.x and mx <= self.x + self.w and my > self.y + self.h and my <= self.y + self.h + #self.opts * self.h)
            if dropHover then
                local i = math.floor((my - (self.y + self.h)) / self.h) + 1
                if i >= 1 and i <= #self.opts then
                    self.idx = i
                end
            end
            self.open = false
        end
    end

    return (mx >= self.x and mx <= self.x + self.w and my >= self.y and my <= self.y + self.animH)
end

function Dropdown:draw()
    local tr = math.max(0, theme.panel[1] - 15)
    local tg = math.max(0, theme.panel[2] - 15)
    local tb = math.max(0, theme.panel[3] - 15)

    if self.animH > self.h then
        term.fillRect(self.x, self.y + self.h, self.w, math.floor(self.animH - self.h), tr, tg, tb)
    end

    term.fillRect(self.x, self.y, self.w, self.h, theme.primary[1], theme.primary[2], theme.primary[3])
    local ty = self.y + math.floor((self.h - 16) / 2)
    text.drawText(self.x + 10, ty, self.opts[self.idx], theme.text[1], theme.text[2], theme.text[3], 1)

    if self.animH > self.h then
        for i, opt in ipairs(self.opts) do
            local oy = self.y + (self.h * i)
            if oy < self.y + self.animH then
                local rowVisibleH = math.min(self.h, (self.y + self.animH) - oy)
                local mx, my = input.mousePos()

                if mx >= self.x and mx <= self.x + self.w and my >= oy and my <= oy + rowVisibleH then
                    term.fillRect(self.x, oy, self.w, math.floor(rowVisibleH), theme.primaryHover[1], theme.primaryHover[2], theme.primaryHover[3])
                end

                if rowVisibleH > 8 then
                    local item_ty = oy + math.floor((self.h - 16) / 2)
                    text.drawText(self.x + 10, item_ty, opt, theme.text[1], theme.text[2], theme.text[3], 1)
                end
            end
        end
    end
end

return Dropdown