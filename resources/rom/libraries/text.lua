local ffi = require("ffi")
local bit = require("bit")

local text = {}

local font_memory = ffi.new("uint8_t[?]", 65536 * 32)

function text.loadFont(filepath)
    local f = io.open(filepath, "rb")
    if not f then
        -- Show the ACTUAL path that failed in the error
        error("FFI Load Error: Cannot open file at path: " .. tostring(filepath))
    end
    local data = f:read("*all")
    f:close()
    ffi.copy(font_memory, data, #data)
end

local function utf8_to_codepoints(str)
    local points = {}
    local i = 1
    while i <= #str do
        local b = str:byte(i)
        local val, bytes
        if b < 0x80 then val, bytes = b, 1
        elseif b < 0xE0 then val, bytes = bit.band(b, 0x1F), 2
        elseif b < 0xF0 then val, bytes = bit.band(b, 0x0F), 3
        else val, bytes = bit.band(b, 0x07), 4 end

        for j = 1, bytes - 1 do
            val = bit.bor(bit.lshift(val, 6), bit.band(str:byte(i + j), 0x3F))
        end
        table.insert(points, val)
        i = i + bytes
    end
    return points
end

function text.drawChar(x, y, codepoint, r, g, b, scale)
    scale = scale or 1

    if codepoint < 0 or codepoint > 65535 then codepoint = 63 end

    local offset = codepoint * 32

    for row = 0, 15 do
        local byte1 = font_memory[offset + (row * 2)]
        local byte2 = font_memory[offset + (row * 2) + 1]

        local rowBits = bit.bor(bit.lshift(byte1, 8), byte2)

        for col = 0, 15 do
            local px_bit = bit.band(bit.rshift(rowBits, 15 - col), 1)

            if px_bit == 1 then
                if scale == 1 then
                    term.setPixel(x + col, y + row, r, g, b)
                else
                    local px = x + (col * scale)
                    local py = y + (row * scale)
                    for sx = 0, scale - 1 do
                        for sy = 0, scale - 1 do
                            term.setPixel(px + sx, py + sy, r, g, b)
                        end
                    end
                end
            end
        end
    end
end

function text.drawText(x, y, str, r, g, b, scale)
    scale = scale or 1
    local codepoints = utf8_to_codepoints(str)

    for i = 1, #codepoints do
        local codepoint = codepoints[i]
        text.drawChar(x, y, codepoint, r, g, b, scale)

        local step = (codepoint > 255) and 16 or 8
        x = x + (step * scale)
    end
end

return text