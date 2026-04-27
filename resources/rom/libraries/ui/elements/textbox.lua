local text = require("libraries/text/text")
local theme = require("libraries/ui/theme")

local Textbox = {}
Textbox.__index = Textbox

function Textbox.new(w, h, placeholder)
    local self = setmetatable({}, Textbox)
    self.baseW, self.baseH = w, h
    self.w, self.h = w, h
    self.x, self.y = 0, 0
    self.padX, self.padY = 0, 0
    self.anchor = "top-left"
    self.z = 1
    self.text = ""
    self.placeholder = placeholder or ""
    self.focused = false
    self.cursorTimer = 0
    self.animScale = 1
    self.cursorPos = 0
    self.selectedAll = false
    self.viewStart = 1

    self.backspaceTimer = 0
    self.leftTimer = 0
    self.rightTimer = 0

    return self
end

function Textbox:syncLayout()
end

function Textbox:update(mx, my, mDown, dt, mPressed)
    local hover = (mx >= self.x and mx <= self.x + self.w and my >= self.y and my <= self.y + self.h)

    if mPressed then
        self.focused = hover
        if self.focused then
            self.cursorTimer = 0
            self.selectedAll = false
            self.cursorPos = #self.text
        end
    end

    if self.focused then
        self.cursorTimer = (self.cursorTimer + dt) % 1.0

        local ctrlDown = input.keyDown("lctrl") or input.keyDown("rctrl")
        if ctrlDown and input.keyPressed("a") then
            self.selectedAll = true
            self.cursorPos = #self.text
            self.cursorTimer = 0
        end

        local doLeft = false
        if input.keyPressed("left") then
            doLeft = true; self.leftTimer = 0.4
        elseif input.keyDown("left") then
            self.leftTimer = self.leftTimer - dt
            if self.leftTimer <= 0 then doLeft = true; self.leftTimer = 0.04 end
        else self.leftTimer = 0 end

        local doRight = false
        if input.keyPressed("right") then
            doRight = true; self.rightTimer = 0.4
        elseif input.keyDown("right") then
            self.rightTimer = self.rightTimer - dt
            if self.rightTimer <= 0 then doRight = true; self.rightTimer = 0.04 end
        else self.rightTimer = 0 end

        -- Apply Arrow Movement
        if doLeft then
            self.cursorPos = math.max(0, self.cursorPos - 1)
            self.selectedAll = false
            self.cursorTimer = 0
        elseif doRight then
            self.cursorPos = math.min(#self.text, self.cursorPos + 1)
            self.selectedAll = false
            self.cursorTimer = 0
        end

        local newText = input.readText()
        if #newText > 0 then
            if self.selectedAll then
                self.text = newText
                self.cursorPos = #newText
                self.selectedAll = false
            else
                self.text = self.text:sub(1, self.cursorPos) .. newText .. self.text:sub(self.cursorPos + 1)
                self.cursorPos = self.cursorPos + #newText
            end
            self.animScale = 1.05
            self.cursorTimer = 0
        end

        -- Backspace Logic
        local doBackspace = false
        if input.keyPressed("backspace") then
            doBackspace = true; self.backspaceTimer = 0.4
        elseif input.keyDown("backspace") then
            self.backspaceTimer = self.backspaceTimer - dt
            if self.backspaceTimer <= 0 then doBackspace = true; self.backspaceTimer = 0.04 end
        else self.backspaceTimer = 0 end

        if doBackspace then
            if self.selectedAll then
                self.text = ""
                self.cursorPos = 0
                self.selectedAll = false
            elseif self.cursorPos > 0 then
                self.text = self.text:sub(1, self.cursorPos - 1) .. self.text:sub(self.cursorPos + 1)
                self.cursorPos = self.cursorPos - 1
            end
            self.animScale = 0.95
            self.cursorTimer = 0
        end
    end

    self.animScale = self.animScale + (1 - self.animScale) * (1 - math.exp(-20 * dt))

    return hover or self.focused
end

function Textbox:draw()
    local tr = math.max(0, theme.panel[1] - 15)
    local tg = math.max(0, theme.panel[2] - 15)
    local tb = math.max(0, theme.panel[3] - 15)

    if self.focused then
        tr, tg, tb = theme.panel[1] + 10, theme.panel[2] + 10, theme.panel[3] + 10
    end

    local drawW = self.w * self.animScale
    local drawH = self.h * self.animScale
    local offX = (self.w - drawW) / 2
    local offY = (self.h - drawH) / 2

    term.fillRect(self.x + offX, self.y + offY, drawW, drawH, tr, tg, tb)

    local tx = self.x + 10
    local ty = self.y + math.floor((self.h - 16) / 2)

    if #self.text == 0 and not self.focused then
        local cR = math.floor(theme.text[1] * 0.5)
        local cG = math.floor(theme.text[2] * 0.5)
        local cB = math.floor(theme.text[3] * 0.5)
        text.drawText(tx + offX, ty + offY, self.placeholder, cR, cG, cB, 1)
        return
    end

    local maxW = self.w - 20

    if self.cursorPos < self.viewStart - 1 then
        self.viewStart = math.max(1, self.cursorPos)
    end
    if self.viewStart < 1 then self.viewStart = 1 end

    while text.getTextWidth(self.text:sub(self.viewStart, self.cursorPos)) > maxW do
        self.viewStart = self.viewStart + 1
    end

    local viewEnd = self.viewStart
    while viewEnd <= #self.text and text.getTextWidth(self.text:sub(self.viewStart, viewEnd)) <= maxW do
        viewEnd = viewEnd + 1
    end
    viewEnd = viewEnd - 1

    local displayStr = self.text:sub(self.viewStart, viewEnd)

    if self.selectedAll then
        local selW = text.getTextWidth(displayStr)
        term.fillRect(tx + offX, ty + offY, selW, 16, theme.primaryPress[1], theme.primaryPress[2], theme.primaryPress[3])
    end

    text.drawText(tx + offX, ty + offY, displayStr, theme.text[1], theme.text[2], theme.text[3], 1)

    if self.focused and self.cursorTimer < 0.5 and not self.selectedAll then
        local cursorOffset = text.getTextWidth(self.text:sub(self.viewStart, self.cursorPos))
        term.fillRect(tx + offX + cursorOffset, ty + offY, 2, 16, 255, 255, 255)
    end
end

return Textbox