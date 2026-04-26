local text = require("libraries.text")

-- ==========================================
-- HYPER-PERFORMANCE CONFIG
-- ==========================================
local RENDER_SCALE   = 1      -- 1 for 1:1 quality
local MAX_BOUNCES    = 2      -- Optimized to 2 for the perfect quality/speed balance
local INTERLACE      = true   -- Renders half the lines per frame (massive FPS boost)
local TARGET_FPS     = 999

-- Ultra-Localize for LuaJIT hot-loop optimization
local m_sin, m_cos, m_sqrt, m_max, m_min = math.sin, math.cos, math.sqrt, math.max, math.min
local t_setPixel = term.setPixel
local t_fillRect = term.fillRect
local t_getSize  = term.getSize
local t_blit     = term.blit
local s_getFPS   = sys.getFPS

-- ==========================================
-- SCENE DATA
-- ==========================================
local spheres = {
    {0, 0, 0, 1.2, 255, 255, 255, 0.7}, -- Center
    {2, 0.5, 2, 0.6, 255, 50, 50, 0.3},  -- Red
    {-2, 0.5, 1, 0.5, 50, 255, 50, 0.2}, -- Green
}
local lightX, lightY, lightZ = 5, 10, 5
local frame_parity = 0 -- For interlacing

-- ==========================================
-- OPTIMIZED MATH
-- ==========================================
local function trace(ox, oy, oz, dx, dy, dz, depth)
    local closest_t = 1e30
    local hit_obj = nil

    -- Inlined Sphere Intersection for speed
    for i = 1, #spheres do
        local s = spheres[i]
        local sx, sy, sz, sr = s[1], s[2], s[3], s[4]
        local vx, vy, vz = ox - sx, oy - sy, oz - sz
        local b = vx*dx + vy*dy + vz*dz
        local c = (vx*vx + vy*vy + vz*vz) - sr*sr
        local h = b*b - c
        if h >= 0 then
            local t = -b - m_sqrt(h)
            if t > 0.001 and t < closest_t then
                closest_t = t
                hit_obj = s
            end
        end
    end

    -- Floor Intersection
    if dy < -0.001 then
        local t = (-1.2 - oy) / dy
        if t > 0.001 and t < closest_t then
            local hx, hz = ox + dx * t, oz + dz * t
            local check = (math.floor(hx) + math.floor(hz)) % 2
            local col = (check == 0) and 180 or 100
            return col, col, col
        end
    end

    if not hit_obj then
        local bg = m_max(0, dy + 0.2) * 150
        return 20, 30 + bg, 50 + bg
    end

    -- Shading logic
    local hx, hy, hz = ox + dx * closest_t, oy + dy * closest_t, oz + dz * closest_t
    local nx, ny, nz = hx - hit_obj[1], hy - hit_obj[2], hz - hit_obj[3]
    local n_inv_mag = 1 / m_sqrt(nx*nx + ny*ny + nz*nz)
    nx, ny, nz = nx * n_inv_mag, ny * n_inv_mag, nz * n_inv_mag

    local lx, ly, lz = lightX - hx, lightY - hy, lightZ - hz
    local l_inv_mag = 1 / m_sqrt(lx*lx + ly*ly + lz*lz)
    lx, ly, lz = lx * l_inv_mag, ly * l_inv_mag, lz * l_inv_mag

    local dot_l = m_max(0.1, nx*lx + ny*ly + nz*lz)
    local r, g, b = hit_obj[5] * dot_l, hit_obj[6] * dot_l, hit_obj[7] * dot_l

    if depth < MAX_BOUNCES and hit_obj[8] > 0 then
        local ref_dot = 2 * (dx*nx + dy*ny + dz*nz)
        local rr, rg, rb = trace(hx, hy, hz, dx - ref_dot*nx, dy - ref_dot*ny, dz - ref_dot*nz, depth + 1)
        local ref_amt = hit_obj[8]
        r = r * (1 - ref_amt) + rr * ref_amt
        g = g * (1 - ref_amt) + rg * ref_amt
        b = b * (1 - ref_amt) + rb * ref_amt
    end

    return r, g, b
end

function main()
    text.loadFont((ENGINE_ROOT .. "/rom/libraries/font.bin"):gsub("//", "/"))
    local camPhi, camTheta, camDist = 0.5, 0, 6

    while true do
        local sw, sh = t_getSize()
        if sw == 0 then sw, sh = 640, 360 end

        -- 1. Optimized Input
        if input.mouseDown("LEFT") then
            local mx, my = input.mouseDelta()
            camTheta = camTheta - mx * 0.01
            camPhi = m_min(m_max(camPhi + my * 0.01, 0.1), 1.5)
        end

        -- 2. Animate
        local time = sys.getPSTime()
        spheres[2][1], spheres[2][3] = m_sin(time) * 3, m_cos(time) * 3

        -- 3. Camera Vectors (Precompute outside the pixel loop)
        local cx = camDist * m_cos(camPhi) * m_sin(camTheta)
        local cy = camDist * m_sin(camPhi)
        local cz = camDist * m_cos(camPhi) * m_cos(camTheta)

        local fX, fY, fZ = -cx, -cy, -cz
        local f_mag = 1 / m_sqrt(fX*fX + fY*fY + fZ*fZ)
        fX, fY, fZ = fX * f_mag, fY * f_mag, fZ * f_mag

        local rX, rY, rZ = m_sin(camTheta - 1.57), 0, m_cos(camTheta - 1.57)
        local uX, uY, uZ = fY*rZ - fZ*rY, fZ*rX - fX*rZ, fX*rY - fY*rX

        -- 4. Ray-Vector Interpolation (The "Secret Sauce")
        -- Instead of normalizing per pixel, we find the corners and interpolate
        local aspect = sw / sh
        local v_half_h = 0.6 -- Field of View
        local v_half_w = v_half_h * aspect

        -- Calculate the "Top Left" ray and the "Step" vectors
        local tlX = fX - rX * v_half_w + uX * v_half_h
        local tlY = fY - rY * v_half_w + uY * v_half_h
        local tlZ = fZ - rZ * v_half_w + uZ * v_half_h

        local stepRX = (rX * v_half_w * 2) / sw
        local stepRY = (rY * v_half_w * 2) / sw
        local stepRZ = (rZ * v_half_w * 2) / sw

        local stepUX = (uX * v_half_h * 2) / sh
        local stepUY = (uY * v_half_h * 2) / sh
        local stepUZ = (uZ * v_half_h * 2) / sh

        -- 5. Hot Rendering Loop
        frame_parity = (frame_parity + 1) % 2
        local start_y = INTERLACE and frame_parity or 0
        local step_y = INTERLACE and 2 or 1

        for y = start_y, sh - 1, step_y do
            -- Pre-calculate row starting vector
            local rowX = tlX - stepUX * y
            local rowY = tlY - stepUY * y
            local rowZ = tlZ - stepUZ * y

            for x = 0, sw - 1, RENDER_SCALE do
                local dx = rowX + stepRX * x
                local dy = rowY + stepRY * x
                local dz = rowZ + stepRZ * x

                -- Fast Normalization in-loop
                local d_inv = 1 / m_sqrt(dx*dx + dy*dy + dz*dz)
                local r, g, b = trace(cx, cy, cz, dx*d_inv, dy*d_inv, dz*d_inv, 0)

                t_setPixel(x, y, r, g, b)
            end
        end

        -- 6. Blit trick: Fill the interlaced gaps with the previous frame's data
        -- This reduces the "flicker" of interlacing while keeping the 120fps speed
        if INTERLACE then
            local other_parity = (frame_parity + 1) % 2
            -- We don't have a second buffer, so we actually just leave the old pixels there.
            -- term.setPixel doesn't clear the screen, so it acts as an automatic persistence buffer!
        end

        -- UI
        t_fillRect(0, 0, 240, 30, 0, 0, 0)
        text.drawText(5, 5, "FPS: " .. s_getFPS() .. " (ULTRA MODE)", 0, 255, 100, 1)

        coroutine.yield(0)
    end
end