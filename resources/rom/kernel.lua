local text = require("libraries.text")

local function clamp(v, lo, hi)
    if v < lo then return lo end
    if v > hi then return hi end
    return v
end

local function utf8_pop(s)
    local i = #s
    while i > 0 do
        local c = s:byte(i)
        if c < 0x80 or c >= 0xC0 then
            return s:sub(1, i - 1)
        end
        i = i - 1
    end
    return ""
end

local function sanitize_ascii(s, maxlen)
    local out = {}
    for i = 1, #s do
        local b = s:byte(i)
        if b >= 32 and b <= 126 then
            out[#out + 1] = string.char(b)
        end
    end
    local str = table.concat(out)
    if #str > maxlen then
        str = str:sub(#str - maxlen + 1)
    end
    return str
end

local function rotate(x, y, z, ax, ay, az)
    local cx, sx = math.cos(ax), math.sin(ax)
    local cy, sy = math.cos(ay), math.sin(ay)
    local cz, sz = math.cos(az), math.sin(az)

    local y1 = y * cx - z * sx
    local z1 = y * sx + z * cx
    y, z = y1, z1

    local x2 = x * cy + z * sy
    local z2 = -x * sy + z * cy
    x, z = x2, z2

    local x3 = x * cz - y * sz
    local y3 = x * sz + y * cz
    return x3, y3, z
end

local function project(x, y, z, cx, cy, scale, zoff)
    local zz = z + zoff
    if zz <= 0.1 then
        return nil
    end
    local px = x / zz * scale + cx
    local py = y / zz * scale + cy
    return px, py, zz
end

local cube = {
    {-1, -1, -1}, { 1, -1, -1}, { 1,  1, -1}, {-1,  1, -1},
    {-1, -1,  1}, { 1, -1,  1}, { 1,  1,  1}, {-1,  1,  1},
}

local edges = {
    {1, 2}, {2, 3}, {3, 4}, {4, 1},
    {5, 6}, {6, 7}, {7, 8}, {8, 5},
    {1, 5}, {2, 6}, {3, 7}, {4, 8},
}

local rx, ry, rz = 0, 0, 0
local spin = true
local zoom = 3.2
local typed = ""
local backspace_next = 0
local backspace_delay = 0.35
local backspace_repeat = 0.06
local last_event = ""
local last_time = sys.getPSTime()

local stars = {}
local star_count = 120
local last_w, last_h = 0, 0

local function init_stars(w, h)
    stars = {}
    if w < 1 or h < 1 then
        return
    end
    for i = 1, star_count do
        stars[i] = {
            x = math.random(0, w - 1),
            y = math.random(0, h - 1),
            s = math.random() * 0.8 + 0.2,
        }
    end
end

local function draw_stars(w, h, t)
    for i = 1, #stars do
        local s = stars[i]
        local yy = (s.y + t * (8 + 10 * s.s)) % h
        local y = math.floor(yy)
        term.setPixel(s.x, y, 30, 30, 60)
    end
end

local function draw_cube(w, h)
    local cx = w * 0.5
    local cy = h * 0.5
    local scale = math.min(w, h) * 0.35

    local pts = {}
    for i = 1, #cube do
        local v = cube[i]
        local x, y, z = rotate(v[1], v[2], v[3], rx, ry, rz)
        local px, py, zz = project(x, y, z, cx, cy, scale, zoom)
        pts[i] = {px, py, zz}
    end

    for i = 1, #edges do
        local a = edges[i][1]
        local b = edges[i][2]
        local p1 = pts[a]
        local p2 = pts[b]
        if p1[1] and p2[1] then
            local depth = (p1[3] + p2[3]) * 0.5
            local shade = clamp(255 - depth * 40, 80, 255)
            term.drawLine(
                math.floor(p1[1]), math.floor(p1[2]),
                math.floor(p2[1]), math.floor(p2[2]),
                shade, shade, 255
            )
        end
    end
end

local function draw_ui(w, h, dt)
    local mx, my = input.mousePos()
    local fps = dt > 0 and math.floor(1 / dt + 0.5) or 0

    text.drawText(4, 4, "LuaC Input Demo", 200, 220, 255, 1)
    text.drawText(4, 14, "Drag mouse: rotate  Wheel: zoom", 180, 180, 180, 1)
    text.drawText(4, 24, "Arrows: rotate  Space: spin  R: reset", 180, 180, 180, 1)

    text.drawText(4, 34, "FPS: " .. fps, 160, 200, 160, 1)
    text.drawText(4, 44, "Mouse: " .. math.floor(mx) .. "," .. math.floor(my), 160, 200, 160, 1)

    local event_line = sanitize_ascii(last_event, 36)
    if event_line ~= "" then
        text.drawText(4, 54, "Event: " .. event_line, 160, 180, 200, 1)
    end

    local display = sanitize_ascii(typed, 36)
    if h > 20 then
        text.drawText(4, h - 12, "Type: " .. display, 200, 220, 255, 1)
    end

    local cx = math.floor(mx)
    local cy = math.floor(my)
    term.drawLine(cx - 5, cy, cx + 5, cy, 255, 80, 80)
    term.drawLine(cx, cy - 5, cx, cy + 5, 255, 80, 80)

    local base_x = w - 64
    local base_y = 4
    local function key_box(x, y, label, down)
        if down then
            term.fillRect(x, y, 14, 10, 60, 200, 90)
        else
            term.fillRect(x, y, 14, 10, 30, 30, 40)
        end
        text.drawText(x + 2, y + 1, label, 230, 230, 230, 1)
    end

    key_box(base_x + 16, base_y, "W", input.keyDown("W"))
    key_box(base_x, base_y + 12, "A", input.keyDown("A"))
    key_box(base_x + 16, base_y + 12, "S", input.keyDown("S"))
    key_box(base_x + 32, base_y + 12, "D", input.keyDown("D"))
end

math.randomseed(math.floor(sys.getUnixTime()))

function main()
    while true do
        local now = sys.getPSTime()
        local dt = now - last_time
        last_time = now

        local w, h = term.getSize()
        if w ~= last_w or h ~= last_h then
            last_w, last_h = w, h
            init_stars(w, h)
        end

        if w <= 0 or h <= 0 then
            sys.wait(0.1)
        else
            if input.keyPressed("SPACE") then
                spin = not spin
            end
            if input.keyPressed("R") then
                rx, ry, rz = 0, 0, 0
            end
            if input.keyPressed("C") then
                typed = ""
            end

            local wheel = input.mouseWheel()
            if wheel ~= 0 then
                zoom = clamp(zoom - wheel * 0.3, 2.0, 8.0)
            end

            local mdx, mdy = input.mouseDelta()
            if input.mouseDown("LEFT") then
                ry = ry + mdx * 0.01
                rx = rx + mdy * 0.01
            end

            if input.keyDown("LEFT") then ry = ry - dt * 1.8 end
            if input.keyDown("RIGHT") then ry = ry + dt * 1.8 end
            if input.keyDown("UP") then rx = rx - dt * 1.8 end
            if input.keyDown("DOWN") then rx = rx + dt * 1.8 end

            if spin then
                ry = ry + dt * 0.7
                rx = rx + dt * 0.4
                rz = rz + dt * 0.2
            end

            local new_text = input.readText()
            if #new_text > 0 then
                typed = typed .. new_text
                if #typed > 256 then
                    typed = typed:sub(#typed - 255)
                end
            end
            if input.keyPressed("BACKSPACE") then
                typed = utf8_pop(typed)
                backspace_next = now + backspace_delay
            elseif input.keyDown("BACKSPACE") then
                if now >= backspace_next then
                    typed = utf8_pop(typed)
                    backspace_next = now + backspace_repeat
                end
            else
                backspace_next = 0
            end

            local events = input.poll()
            if #events > 0 then
                local e = events[#events]
                if e.type == "key_down" then
                    last_event = "key down " .. e.key
                elseif e.type == "key_up" then
                    last_event = "key up " .. e.key
                elseif e.type == "text" then
                    last_event = "text " .. sanitize_ascii(e.text, 8)
                elseif e.type == "mouse_button" then
                    local state = e.pressed and "down" or "up"
                    last_event = "mouse " .. e.button .. " " .. state
                elseif e.type == "mouse_wheel" then
                    last_event = "wheel " .. string.format("%.2f", e.wheel)
                elseif e.type == "mouse_move" then
                    last_event = "mouse move"
                end
            end

            term.fillRect(0, 0, w, h, 10, 10, 18)
            draw_stars(w, h, now)
            draw_cube(w, h)
            draw_ui(w, h, dt)

            sys.wait(1 / 60)
        end
    end
end
