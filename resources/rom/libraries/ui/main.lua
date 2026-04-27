local theme = require("libraries/ui/theme")
local Button = require("libraries/ui/elements/button")
local Slider = require("libraries/ui/elements/slider")
local Dropdown = require("libraries/ui/elements/dropdown")
local Checkbox = require("libraries/ui/elements/checkbox")
local ProgressBar = require("libraries/ui/elements/progressbar")
local Panel = require("libraries/ui/elements/panel")
local Textbox = require("libraries/ui/elements/textbox")
local Gauge = require("libraries/ui/elements/gauge")

local ui = {}
ui.elements = {}
ui.lastW, ui.lastH = 0, 0

ui.Button = Button
ui.Slider = Slider
ui.Dropdown = Dropdown
ui.Checkbox = Checkbox
ui.ProgressBar = ProgressBar
ui.Panel = Panel
ui.Textbox = Textbox
ui.Gauge = Gauge

function ui.add(el, anchor, padX, padY)
    el.anchor = anchor or "top-left"
    el.padX = padX or 0
    el.padY = padY or 0
    table.insert(ui.elements, el)
    ui.layout()
    ui.sort()
end

function ui.sort()
    table.sort(ui.elements, function(a, b) return (a.z or 0) < (b.z or 0) end)
end

function ui.layout()
    local sw, sh = term.getSize()
    if sw == 0 or sh == 0 then return end

    for _, el in ipairs(ui.elements) do
        el.w = (el.baseW > 0 and el.baseW <= 1) and (el.baseW * sw) or el.baseW
        el.h = (el.baseH > 0 and el.baseH <= 1) and (el.baseH * sh) or el.baseH

        if el.anchor == "center" then
            el.x = (sw - el.w) / 2 + el.padX
            el.y = (sh - el.h) / 2 + el.padY
        elseif el.anchor == "right" then
            el.x = sw - el.w - el.padX
            el.y = el.padY
        elseif el.anchor == "bottom" then
            el.x = el.padX
            el.y = sh - el.h - el.padY
        else
            el.x = el.padX
            el.y = el.padY
        end

        if el.syncLayout then el:syncLayout() end
    end
end

function ui.update(dt, evs)
    local sw, sh = term.getSize()
    if sw ~= ui.lastW or sh ~= ui.lastH then
        ui.lastW, ui.lastH = sw, sh
        ui.layout()
    end

    local mx, my = input.mousePos()
    local mDown = input.mouseDown("left")
    local mPressed = false

    for _, e in ipairs(evs) do
        if e.type == "mouse_button" and e.pressed and e.button == 0 then
            mPressed = true
            break
        end
    end

    local hit = false
    local doSort = false

    for i = #ui.elements, 1, -1 do
        local el = ui.elements[i]
        if el.needsSort then
            doSort = true
            el.needsSort = false
        end

        local captured = el:update(mx, my, mDown, dt, mPressed and not hit)
        if captured then hit = true end
    end

    if doSort then ui.sort() end
end

function ui.draw()
    local w, h = term.getSize()
    term.fillRect(0, 0, w, h, theme.bg[1], theme.bg[2], theme.bg[3])
    for _, el in ipairs(ui.elements) do
        el:draw()
    end
    term.flush()
end

return ui