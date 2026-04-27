local text = require("libraries/text/text")
local ui = require("libraries/ui/main")

function main()
    text.loadFont((ENGINE_ROOT .. "/rom/libraries/text/font.bin"):gsub("//", "/"))

    local mainPanel = ui.Panel.new(0.9, 0.9)
    ui.add(mainPanel, "center", 0, 0)

    local btn = ui.Button.new(120, 30, "Action")
    mainPanel:add(btn, "top-left", 20, 20)

    local sld = ui.Slider.new(200, 16, 0, 100, 50)
    mainPanel:add(sld, "top-left", 20, 70)

    local chk = ui.Checkbox.new(20, "Enable Feature")
    mainPanel:add(chk, "top-left", 20, 110)

    local prg = ui.ProgressBar.new(200, 12)
    mainPanel:add(prg, "top-left", 20, 150)

    prg.draw = function(self)
        local tr = math.max(0, 45 - 15)
        local tg = math.max(0, 45 - 15)
        local tb = math.max(0, 50 - 15)
        term.fillRect(self.x, self.y, self.w, self.h, tr, tg, tb)

        local fw = math.floor(self.w * self.animPct)
        if fw > 0 then
            local r, g, b
            if self.animPct < 0.5 then
                local ratio = self.animPct * 2
                r = 255
                g = math.floor(255 * ratio)
                b = 0
            else
                local ratio = (self.animPct - 0.5) * 2
                r = math.floor(255 * (1 - ratio))
                g = 255
                b = 0
            end
            term.fillRect(self.x, self.y, fw, self.h, r, g, b)
        end
    end

    local txt = ui.Textbox.new(200, 30, "Type here...")
    mainPanel:add(txt, "top-left", 20, 190)

    local drp = ui.Dropdown.new(150, 30, {"Low", "Medium", "High", "Ultra"})
    mainPanel:add(drp, "top-left", 250, 20)

    local gag = ui.Gauge.new(150, 150, 0, 100, 50, 80)
    mainPanel:add(gag, "top-left", 250, 70)

    local lastTime = sys.getPSTime()


    while true do
        local now = sys.getPSTime()
        local dt = now - lastTime
        lastTime = now

        if dt > 0.1 then dt = 0.1 end

        prg.pct = sld.val / 100
        gag.val = sld.val

        local evs = input.poll()
        ui.update(dt, evs)
        ui.draw()

        -- Draw the single white mouse pixel cursor
        local mx, my = input.mousePos()
        for ox = -1, 1 do
            for oy = -1, 1 do
                term.setPixel(mx + ox, my + oy, 255, 255, 255)
            end
        end

        term.flush()
        coroutine.yield(0)
    end
end