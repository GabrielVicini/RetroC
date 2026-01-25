local w, h = term.getSize()
local text = require("libraries.text")

function main()
    while true do
        for x = 1, w do
            for y = 1, h do
                term.setPixel(x, y, math.random(1, 255), math.random(1, 255), math.random(1, 255))
            end
        end
    sys.wait(0)
    end
end
