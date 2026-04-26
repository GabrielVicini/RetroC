local text = require("libraries.text")

-- ==========================================
-- HYPER-PERFORMANCE 3D VOXEL CA CONFIG
-- ==========================================
local RENDER_SCALE = 3
local GS           = 40
local GS2          = GS * GS
local MAX_RAY_STEPS = 45 -- LOD distance cap

local m_random, m_floor, m_abs = math.random, math.floor, math.abs
local m_max, m_min, m_sqrt = math.max, math.min, math.sqrt
local m_sin, m_cos = math.sin, math.cos
local t_setPixel = term.setPixel
local t_fillRect = term.fillRect
local t_getSize  = term.getSize
local s_getFPS   = sys.getFPS
local s_getFrameTime = sys.getFrameTime

-- Types
local T_EMPTY  = 0
local T_SAND   = 1
local T_WATER  = 2
local T_ACID   = 3
local T_WALL   = 4
local T_CLOUD  = 5
local T_GRASS  = 6
local T_MIRROR = 7

-- Colors {R, G, B}
local colors = {
    [T_EMPTY]  = {0, 0, 0},
    [T_SAND]   = {210, 190, 110},
    [T_WATER]  = {30, 100, 200},
    [T_ACID]   = {80, 255, 60},
    [T_WALL]   = {50, 50, 50},
    [T_CLOUD]  = {245, 245, 255},
    [T_GRASS]  = {60, 160, 70},
    [T_MIRROR] = {200, 200, 220}
}

local grid = {}
local frame_parity = 0
local liquid_timer = 0
local LIQUID_TICK_RATE = 0.08
local global_time = 0

-- Player & Camera State
local pX, pY, pZ = GS/2, 5, GS/2
local pVelY = 0
local isGrounded = false
local camTheta, camPhi = 0, 0
local mouse_locked = false

-- World State (Infinite Treadmill)
local worldOffsetX, worldOffsetZ = 0, 0

local mats = {T_GRASS, T_SAND, T_WATER, T_ACID, T_CLOUD, T_MIRROR}
local mat_names = {"Grass", "Sand", "Water", "Acid", "Cloud", "Mirror"}
local hotbar_idx = 1
local tx, ty, tz = -1, -1, -1
local rx, ry, rz = -1, -1, -1

-- ==========================================
-- INFINITE CHUNK GENERATOR
-- ==========================================
local function generateTerrain(startX, endX, startZ, endZ, offX, offZ)
    local water_level = m_floor(GS * 0.70)
    for z = startZ, endZ do
        for x = startX, endX do
            local absX = x + offX
            local absZ = z + offZ

            local nx, nz = absX / 8, absZ / 8
            local h_offset = m_sin(nx) * m_cos(nz) * 4 + m_sin(nx * 2.5 + nz * 1.5) * 2
            local ground_h = m_floor(GS * 0.65 - h_offset)

            for y = 1, GS - 2 do
                local idx = y * GS2 + z * GS + x
                if grid[idx] == T_EMPTY then
                    if y >= ground_h then
                        if y >= water_level - 2 and y <= water_level + 1 then
                            grid[idx] = T_SAND
                        else
                            grid[idx] = T_GRASS
                        end
                    elseif y >= water_level then
                        grid[idx] = T_WATER
                    end
                end
            end
        end
    end
end

local function initGrid()
    for i = 0, GS * GS * GS - 1 do grid[i] = T_EMPTY end
    for y = 0, GS - 1 do
        for z = 0, GS - 1 do
            for x = 0, GS - 1 do
                if x == 0 or x == GS - 1 or y == 0 or y == GS - 1 or z == 0 or z == GS - 1 then
                    grid[y * GS2 + z * GS + x] = T_WALL
                end
            end
        end
    end
    generateTerrain(1, GS - 2, 1, GS - 2, worldOffsetX, worldOffsetZ)
end

-- ==========================================
-- PHYSICS & CA ENGINE
-- ==========================================
local function isSolid(x, y, z)
    local gx, gy, gz = m_floor(x), m_floor(y), m_floor(z)
    if gx < 0 or gx >= GS or gy < 0 or gy >= GS or gz < 0 or gz >= GS then return true end
    local b = grid[gy * GS2 + gz * GS + gx]
    return b ~= T_EMPTY and b ~= T_WATER and b ~= T_ACID and b ~= T_CLOUD
end

local function inLiquid(x, y, z)
    local gx, gy, gz = m_floor(x), m_floor(y), m_floor(z)
    if gx < 0 or gx >= GS or gy < 0 or gy >= GS or gz < 0 or gz >= GS then return false end
    local b = grid[gy * GS2 + gz * GS + gx]
    return b == T_WATER or b == T_ACID
end

local function swap(idx1, idx2)
    grid[idx1], grid[idx2] = grid[idx2], grid[idx1]
end

local function updateCA(do_liquids)
    frame_parity = 1 - frame_parity
    local dir = (frame_parity == 0) and 1 or -1
    local start_i = (dir == 1) and 1 or (GS - 2)
    local end_i   = (dir == 1) and (GS - 2) or 1

    for y = GS - 2, 1, -1 do
        local y_idx = y * GS2
        local yd_idx = (y + 1) * GS2

        for z = start_i, end_i, dir do
            local z_idx = z * GS
            for x = start_i, end_i, dir do
                local idx = y_idx + z_idx + x
                local c = grid[idx]

                if c == T_SAND or c == T_GRASS then
                    local down_idx = yd_idx + z_idx + x
                    local down = grid[down_idx]

                    if down == T_EMPTY or down == T_WATER or down == T_ACID then
                        swap(idx, down_idx)
                    else
                        local opts = { down_idx - 1, down_idx + 1, down_idx - GS, down_idx + GS }
                        local target = opts[m_random(1, 4)]
                        local t_mat = grid[target]
                        if t_mat == T_EMPTY or t_mat == T_WATER or t_mat == T_ACID then
                            swap(idx, target)
                        end
                    end

                elseif c == T_WATER or c == T_ACID then
                    if do_liquids then
                        local down_idx = yd_idx + z_idx + x
                        local down = grid[down_idx]

                        if down == T_EMPTY then
                            swap(idx, down_idx)
                        else
                            if m_random() > 0.6 then
                                local diag_opts = {}
                                local d_left, d_right = yd_idx + z_idx + (x-1), yd_idx + z_idx + (x+1)
                                local d_fwd, d_back = yd_idx + (z-1)*GS + x, yd_idx + (z+1)*GS + x

                                if grid[d_left] == T_EMPTY then diag_opts[#diag_opts+1] = d_left end
                                if grid[d_right] == T_EMPTY then diag_opts[#diag_opts+1] = d_right end
                                if grid[d_fwd] == T_EMPTY then diag_opts[#diag_opts+1] = d_fwd end
                                if grid[d_back] == T_EMPTY then diag_opts[#diag_opts+1] = d_back end

                                if #diag_opts > 0 then
                                    swap(idx, diag_opts[m_random(1, #diag_opts)])
                                else
                                    local h_opts = {}
                                    local h_left, h_right = y_idx + z_idx + (x-1), y_idx + z_idx + (x+1)
                                    local h_fwd, h_back = y_idx + (z-1)*GS + x, y_idx + (z+1)*GS + x

                                    if grid[h_left] == T_EMPTY then h_opts[#h_opts+1] = h_left end
                                    if grid[h_right] == T_EMPTY then h_opts[#h_opts+1] = h_right end
                                    if grid[h_fwd] == T_EMPTY then h_opts[#h_opts+1] = h_fwd end
                                    if grid[h_back] == T_EMPTY then h_opts[#h_opts+1] = h_back end

                                    if #h_opts > 0 then swap(idx, h_opts[m_random(1, #h_opts)]) end
                                end
                            end

                            if c == T_ACID and m_random() > 0.6 then
                                local a_opts = { y_idx + z_idx + x - 1, y_idx + z_idx + x + 1, y_idx + (z-1)*GS + x, y_idx + (z+1)*GS + x }
                                for i=1, 4 do
                                    local n = a_opts[i]
                                    if grid[n] == T_SAND or grid[n] == T_WATER or grid[n] == T_GRASS then
                                        grid[n] = T_EMPTY
                                        if m_random() > 0.8 then grid[idx] = T_EMPTY end
                                    end
                                end
                            end
                        end
                    end
                elseif c == T_CLOUD then
                    if m_random() > 0.95 then
                        local next_x = x + 1
                        if next_x < GS - 1 then
                            local target = y_idx + z_idx + next_x
                            if grid[target] == T_EMPTY then swap(idx, target) end
                        else
                            grid[idx] = T_EMPTY
                        end
                    end
                end
            end
        end
    end
end

-- ==========================================
-- RAY-TRACED VOLUMETRIC DDA
-- ==========================================
local function renderView(sw, sh, cx, cy, cz, fX, fY, fZ, rX, rY, rZ, uX, uY, uZ, isUnderwater)
    local aspect = sw / sh
    local fov = 0.6
    local v_half_w = fov * aspect

    local tlX = fX - rX * v_half_w + uX * fov
    local tlY = fY - rY * v_half_w + uY * fov
    local tlZ = fZ - rZ * v_half_w + uZ * fov

    local stepRX = (rX * v_half_w * 2) / sw
    local stepRY = (rY * v_half_w * 2) / sw
    local stepRZ = (rZ * v_half_w * 2) / sw

    local stepUX = (uX * fov * 2) / sh
    local stepUY = (uY * fov * 2) / sh
    local stepUZ = (uZ * fov * 2) / sh

    local start_y = (frame_parity == 0) and 0 or math.floor(RENDER_SCALE/2)

    for y = start_y, sh - 1, RENDER_SCALE do
        local rowX = tlX - stepUX * y
        local rowY = tlY - stepUY * y
        local rowZ = tlZ - stepUZ * y

        for x = 0, sw - 1, RENDER_SCALE do
            local dx = rowX + stepRX * x
            local dy = rowY + stepRY * x
            local dz = rowZ + stepRZ * x

            local d_inv = 1 / m_sqrt(dx*dx + dy*dy + dz*dz)
            local ndx, ndy, ndz = dx * d_inv, dy * d_inv, dz * d_inv

            local curX, curY, curZ = cx, cy, cz
            local cDX, cDY, cDZ = ndx, ndy, ndz

            local hitMat = T_EMPTY
            local fluidMat = T_EMPTY
            local side = 0
            local fSide = 0
            local hitCursor = false

            local total_steps = 0
            local attenuation = 1.0
            local bounce = 0
            local f_r, f_g, f_b = 0, 0, 0

            -- RAY BOUNCE LOOP
            while bounce < 2 do
                local mapX, mapY, mapZ = m_floor(curX), m_floor(curY), m_floor(curZ)
                local deltaX = cDX == 0 and 1e30 or m_abs(1 / cDX)
                local deltaY = cDY == 0 and 1e30 or m_abs(1 / cDY)
                local deltaZ = cDZ == 0 and 1e30 or m_abs(1 / cDZ)

                local stepX = cDX < 0 and -1 or 1
                local stepY = cDY < 0 and -1 or 1
                local stepZ = cDZ < 0 and -1 or 1

                local sideX = (cDX < 0 and (curX - mapX) or (mapX + 1.0 - curX)) * deltaX
                local sideY = (cDY < 0 and (curY - mapY) or (mapY + 1.0 - curY)) * deltaY
                local sideZ = (cDZ < 0 and (curZ - mapZ) or (mapZ + 1.0 - curZ)) * deltaZ

                hitMat = T_EMPTY

                for i = 1, MAX_RAY_STEPS do
                    total_steps = total_steps + 1
                    if mapX < 0 or mapX >= GS or mapY < 0 or mapY >= GS or mapZ < 0 or mapZ >= GS then
                        break
                    end

                    if bounce == 0 and mapX == tx and mapY == ty and mapZ == tz then hitCursor = true end

                    local cell = grid[mapY * GS2 + mapZ * GS + mapX]

                    if cell == T_WATER or cell == T_ACID then
                        if fluidMat == T_EMPTY then
                            fluidMat = cell
                            fSide = side
                        end
                    elseif cell ~= T_EMPTY and cell ~= T_WALL and cell ~= T_CLOUD then
                        hitMat = cell
                        break
                    end

                    if sideX < sideY then
                        if sideX < sideZ then sideX = sideX + deltaX; mapX = mapX + stepX; side = 1
                        else sideZ = sideZ + deltaZ; mapZ = mapZ + stepZ; side = 3 end
                    else
                        if sideY < sideZ then sideY = sideY + deltaY; mapY = mapY + stepY; side = 2
                        else sideZ = sideZ + deltaZ; mapZ = mapZ + stepZ; side = 3 end
                    end
                end

                if hitMat == T_MIRROR then
                    -- PERFECT REFLECTION MATH
                    local dist
                    local nX, nY, nZ = 0, 0, 0
                    if side == 1 then dist = (mapX - curX + (1 - stepX) * 0.5) / cDX; nX = -stepX
                    elseif side == 2 then dist = (mapY - curY + (1 - stepY) * 0.5) / cDY; nY = -stepY
                    else dist = (mapZ - curZ + (1 - stepZ) * 0.5) / cDZ; nZ = -stepZ end

                    local hX = curX + cDX * dist
                    local hY = curY + cDY * dist
                    local hZ = curZ + cDZ * dist

                    local dot = cDX*nX + cDY*nY + cDZ*nZ
                    cDX = cDX - 2 * dot * nX
                    cDY = cDY - 2 * dot * nY
                    cDZ = cDZ - 2 * dot * nZ

                    curX = hX + nX * 0.001
                    curY = hY + nY * 0.001
                    curZ = hZ + nZ * 0.001

                    bounce = bounce + 1
                    attenuation = attenuation * 0.75 -- Mirror tinting / light loss
                else
                    -- Draw hit material or sky
                    local r, g, b_col

                    if hitMat == T_EMPTY then
                        local sky_t = m_max(0, m_min(1, (cDY + 1) * 0.5))
                        r = 50 + sky_t * 100
                        g = 120 + sky_t * 80
                        b_col = 255 - sky_t * 60

                        -- PROCEDURAL SKY CLOUDS
                        if cDY > 0.05 then
                            local clX = cDX / cDY * 4.0 + global_time * 0.15
                            local clZ = cDZ / cDY * 4.0
                            local noise = m_sin(clX) * m_cos(clZ) + m_sin(clX * 1.5 + clZ * 2.1)
                            if noise > 0.4 then
                                local c_alpha = m_min(1, (noise - 0.4) * 2.5) * m_min(1, cDY * 5)
                                r = r * (1 - c_alpha) + 255 * c_alpha
                                g = g * (1 - c_alpha) + 255 * c_alpha
                                b_col = b_col * (1 - c_alpha) + 255 * c_alpha
                            end
                        end

                        local sunDX, sunDY, sunDZ = 0.5, -0.6, 0.4
                        local sLen = 1 / m_sqrt(sunDX^2 + sunDY^2 + sunDZ^2)
                        if cDX*(sunDX*sLen) + cDY*(sunDY*sLen) + cDZ*(sunDZ*sLen) > 0.98 then
                            r, g, b_col = 255, 255, 220
                        end
                    else
                        local col = colors[hitMat]
                        r, g, b_col = col[1], col[2], col[3]

                        local absX, absZ = mapX + worldOffsetX, mapZ + worldOffsetZ
                        if hitMat == T_SAND then
                            local noise = (absX * 31 + mapY * 17 + absZ * 23) % 5
                            if noise == 0 then r, g, b_col = m_max(0, r-20), m_max(0, g-20), m_max(0, b_col-15)
                            elseif noise == 1 then r, g, b_col = m_min(255, r+15), m_min(255, g+15), m_min(255, b_col+10) end
                        elseif hitMat == T_GRASS then
                            local noise = (absX * 11 + mapY * 19 + absZ * 29) % 4
                            if noise == 0 then r, g, b_col = m_max(0, r-15), m_max(0, g-15), m_max(0, b_col-10) end
                        end

                        if side == 1 then r, g, b_col = r*0.8, g*0.8, b_col*0.8
                        elseif side == 2 then r, g, b_col = r*0.9, g*0.9, b_col*0.9 end
                    end

                    f_r, f_g, f_b = r * attenuation, g * attenuation, b_col * attenuation
                    break
                end
            end

            -- BLEND TRANSLUCENT FLUIDS
            if fluidMat ~= T_EMPTY then
                local fCol = colors[fluidMat]
                local fr, fg, fb = fCol[1], fCol[2], fCol[3]
                if fSide == 1 then fr, fg, fb = fr*0.8, fg*0.8, fb*0.8
                elseif fSide == 2 then fr, fg, fb = fr*0.9, fg*0.9, fb*0.9 end
                f_r = f_r * 0.4 + fr * 0.6
                f_g = f_g * 0.4 + fg * 0.6
                f_b = f_b * 0.4 + fb * 0.6
            end

            -- APPLY LOD FOG
            local sky_t = m_max(0, m_min(1, (ndy + 1) * 0.5))
            local sky_r = 50 + sky_t * 100
            local sky_g = 120 + sky_t * 80
            local sky_b = 255 - sky_t * 60

            local fog_factor = m_min(1.0, total_steps / (MAX_RAY_STEPS * 1.5))
            fog_factor = fog_factor * fog_factor
            f_r = f_r * (1 - fog_factor) + sky_r * fog_factor
            f_g = f_g * (1 - fog_factor) + sky_g * fog_factor
            f_b = f_b * (1 - fog_factor) + sky_b * fog_factor

            if hitCursor then f_r, f_g, f_b = m_min(255, f_r+60), m_min(255, f_g+60), m_max(0, f_b-40) end

            if isUnderwater then
                f_r = f_r * 0.3
                f_g = m_min(255, f_g * 0.6 + 50)
                f_b = m_min(255, f_b * 0.9 + 100)
            end

            t_fillRect(x, y, RENDER_SCALE, RENDER_SCALE, m_floor(f_r), m_floor(f_g), m_floor(f_b))
        end
    end
end

-- ==========================================
-- MAIN LOOP
-- ==========================================
function main()
    text.loadFont((ENGINE_ROOT .. "/rom/libraries/font.bin"):gsub("//", "/"))

    initGrid()
    if input.lockMouse then input.lockMouse() end
    mouse_locked = true

    while true do
        local sw, sh = t_getSize()
        if sw == 0 then sw, sh = 640, 360 end

        -- 1. Fixed Timesteps & Global Time
        local raw_dt = s_getFrameTime()
        local dt = m_min(raw_dt, 0.05)
        global_time = global_time + dt

        liquid_timer = liquid_timer + dt
        local do_liquids = false
        if liquid_timer >= LIQUID_TICK_RATE then
            do_liquids = true
            liquid_timer = liquid_timer - LIQUID_TICK_RATE
        end

        -- 2. Input
        if input.keyPressed("1") then hotbar_idx = 1 end
        if input.keyPressed("2") then hotbar_idx = 2 end
        if input.keyPressed("3") then hotbar_idx = 3 end
        if input.keyPressed("4") then hotbar_idx = 4 end
        if input.keyPressed("5") then hotbar_idx = 5 end
        if input.keyPressed("6") then hotbar_idx = 6 end

        if input.keyPressed("ESCAPE") then
            mouse_locked = not mouse_locked
            if mouse_locked then
                if input.lockMouse then input.lockMouse() end
            else
                if input.unlockMouse then input.unlockMouse() end
            end
        end

        local wheel = input.mouseWheel()
        if wheel > 0 then hotbar_idx = hotbar_idx + 1 end
        if wheel < 0 then hotbar_idx = hotbar_idx - 1 end
        if hotbar_idx > #mats then hotbar_idx = 1 end
        if hotbar_idx < 1 then hotbar_idx = #mats end
        local current_mat = mats[hotbar_idx]

        -- 3. Camera
        if mouse_locked then
            local mx, my = input.mouseDelta()
            camTheta = camTheta - mx * 0.005
            camPhi = m_max(m_min(camPhi + my * 0.005, 1.5), -1.5)
        end

        local fX = m_cos(camPhi) * m_sin(camTheta)
        local fY = m_sin(camPhi)
        local fZ = m_cos(camPhi) * m_cos(camTheta)
        local rX, rY, rZ = m_sin(camTheta - 1.57), 0, m_cos(camTheta - 1.57)

        -- 4. Player Physics
        local spd = 10.0 * dt
        local dx, dz = 0, 0
        local move_fX = m_sin(camTheta)
        local move_fZ = m_cos(camTheta)

        if input.keyDown("W") then dx = dx + move_fX; dz = dz + move_fZ end
        if input.keyDown("S") then dx = dx - move_fX; dz = dz - move_fZ end
        if input.keyDown("A") then dx = dx - rX; dz = dz - rZ end
        if input.keyDown("D") then dx = dx + rX; dz = dz + rZ end

        if dx ~= 0 or dz ~= 0 then
            local len = m_sqrt(dx*dx + dz*dz)
            dx = (dx / len) * spd
            dz = (dz / len) * spd
        end

        if not (isSolid(pX + dx, pY - 0.1, pZ) or isSolid(pX + dx, pY - 1.2, pZ)) then pX = pX + dx end
        if not (isSolid(pX, pY - 0.1, pZ + dz) or isSolid(pX, pY - 1.2, pZ + dz)) then pZ = pZ + dz end

        local body_in_fluid = inLiquid(pX, pY - 0.1, pZ) or inLiquid(pX, pY - 1.2, pZ)
        local head_in_fluid = inLiquid(pX, pY - 1.5, pZ)

        if body_in_fluid then
            pVelY = pVelY * 0.8
            pVelY = pVelY + (2.0 * dt)
            if input.keyDown("SPACE") then pVelY = pVelY - (6.0 * dt) end
        else
            pVelY = pVelY + (25.0 * dt)
        end

        if pVelY > 15.0 then pVelY = 15.0 end

        local stepY = pVelY * dt
        if stepY > 0 then
            if isSolid(pX, pY + stepY, pZ) then
                pY = m_floor(pY + stepY) - 0.001
                pVelY = 0
                isGrounded = true
            else
                pY = pY + stepY
                isGrounded = false
            end
        else
            if isSolid(pX, pY + stepY - 1.6, pZ) then
                pVelY = 0
            else
                pY = pY + stepY
            end
            isGrounded = false
        end

        if isGrounded and not body_in_fluid and input.keyDown("SPACE") then pVelY = -9.0 end

        -- 5. INFINITE WORLD SHIFTING (The Treadmill)
        local shiftX, shiftZ = 0, 0
        local SHIFT_THRESH = 12

        if pX < SHIFT_THRESH then shiftX = -SHIFT_THRESH
        elseif pX > GS - SHIFT_THRESH then shiftX = SHIFT_THRESH end

        if pZ < SHIFT_THRESH then shiftZ = -SHIFT_THRESH
        elseif pZ > GS - SHIFT_THRESH then shiftZ = SHIFT_THRESH end

        if shiftX ~= 0 or shiftZ ~= 0 then
            local new_grid = {}
            for i = 0, GS*GS*GS - 1 do new_grid[i] = T_EMPTY end

            for y = 0, GS - 1 do
                for z = 1, GS - 2 do
                    for x = 1, GS - 2 do
                        local old_x = x + shiftX
                        local old_z = z + shiftZ
                        if old_x >= 1 and old_x < GS-1 and old_z >= 1 and old_z < GS-1 then
                            new_grid[y*GS2 + z*GS + x] = grid[y*GS2 + old_z*GS + old_x]
                        end
                    end
                end
            end

            for y = 0, GS - 1 do
                for z = 0, GS - 1 do
                    for x = 0, GS - 1 do
                        if x == 0 or x == GS - 1 or y == 0 or y == GS - 1 or z == 0 or z == GS - 1 then
                            new_grid[y*GS2 + z*GS + x] = T_WALL
                        end
                    end
                end
            end

            grid = new_grid
            pX = pX - shiftX
            pZ = pZ - shiftZ
            worldOffsetX = worldOffsetX + shiftX
            worldOffsetZ = worldOffsetZ + shiftZ

            if shiftX > 0 then generateTerrain(GS - 1 - shiftX, GS - 2, 1, GS - 2, worldOffsetX, worldOffsetZ)
            elseif shiftX < 0 then generateTerrain(1, -shiftX, 1, GS - 2, worldOffsetX, worldOffsetZ) end

            if shiftZ > 0 then generateTerrain(1, GS - 2, GS - 1 - shiftZ, GS - 2, worldOffsetX, worldOffsetZ)
            elseif shiftZ < 0 then generateTerrain(1, GS - 2, 1, -shiftZ, worldOffsetX, worldOffsetZ) end
        end

        local camX, camY, camZ = pX, pY - 1.5, pZ
        local uX, uY, uZ = fY*rZ - fZ*rY, fZ*rX - fX*rZ, fX*rY - fY*rX

        -- 6. Raycast Placement
        local b_mapX, b_mapY, b_mapZ = m_floor(camX), m_floor(camY), m_floor(camZ)
        local bdDistX = fX == 0 and 1e30 or m_abs(1 / fX)
        local bdDistY = fY == 0 and 1e30 or m_abs(1 / fY)
        local bdDistZ = fZ == 0 and 1e30 or m_abs(1 / fZ)
        local bStepX = fX < 0 and -1 or 1
        local bStepY = fY < 0 and -1 or 1
        local bStepZ = fZ < 0 and -1 or 1
        local bSideX = (fX < 0 and (camX - b_mapX) or (b_mapX + 1.0 - camX)) * bdDistX
        local bSideY = (fY < 0 and (camY - b_mapY) or (b_mapY + 1.0 - camY)) * bdDistY
        local bSideZ = (fZ < 0 and (camZ - b_mapZ) or (b_mapZ + 1.0 - camZ)) * bdDistZ

        local hitFound = false
        local bHitSide = 0

        for i=1, 20 do
            if b_mapX < 0 or b_mapX >= GS or b_mapY < 0 or b_mapY >= GS or b_mapZ < 0 or b_mapZ >= GS then break end
            local b = grid[b_mapY * GS2 + b_mapZ * GS + b_mapX]
            if b ~= T_EMPTY then
                hitFound = true; break
            end

            if bSideX < bSideY then
                if bSideX < bSideZ then bSideX = bSideX + bdDistX; b_mapX = b_mapX + bStepX; bHitSide = 1
                else bSideZ = bSideZ + bdDistZ; b_mapZ = b_mapZ + bStepZ; bHitSide = 3 end
            else
                if bSideY < bSideZ then bSideY = bSideY + bdDistY; b_mapY = b_mapY + bStepY; bHitSide = 2
                else bSideZ = bSideZ + bdDistZ; b_mapZ = b_mapZ + bStepZ; bHitSide = 3 end
            end
        end

        rx, ry, rz = b_mapX, b_mapY, b_mapZ
        tx, ty, tz = b_mapX, b_mapY, b_mapZ

        if hitFound then
            if bHitSide == 1 then tx = tx - bStepX end
            if bHitSide == 2 then ty = ty - bStepY end
            if bHitSide == 3 then tz = tz - bStepZ end
        else
            tx, ty, tz = -1, -1, -1
        end

        local function overlapsPlayer(x, y, z)
            local px, pz = m_floor(pX), m_floor(pZ)
            local headY, footY = m_floor(pY - 1.5), m_floor(pY)
            return (x == px and z == pz and y >= headY and y <= footY)
        end

        if input.mouseDown("LEFT") and hitFound then
            if tx > 0 and tx < GS-1 and ty > 0 and ty < GS-1 and tz > 0 and tz < GS-1 then
                if not overlapsPlayer(tx, ty, tz) then
                    local pIdx = ty * GS2 + tz * GS + tx
                    if grid[pIdx] ~= T_WALL then grid[pIdx] = current_mat end
                end
            end
        end
        if input.mouseDown("RIGHT") and hitFound then
            if rx > 0 and rx < GS-1 and ry > 0 and ry < GS-1 and rz > 0 and rz < GS-1 then
                local rIdx = ry * GS2 + rz * GS + rx
                if grid[rIdx] ~= T_WALL then grid[rIdx] = T_EMPTY end
            end
        end

        -- 7. Graphics & Execution
        updateCA(do_liquids)
        renderView(sw, sh, camX, camY, camZ, fX, fY, fZ, rX, rY, rZ, uX, uY, uZ, head_in_fluid)

        t_fillRect(0, 0, 200, 35, 0, 0, 0)
        text.drawText(5, 5, "FPS: " .. s_getFPS() .. " | INFINITE", 0, 255, 100, 1)
        text.drawText(5, 18, "Mouse Locked: " .. tostring(mouse_locked), 200, 200, 200, 1)

        local slot_size = 30
        local padding = 5
        local bar_w = #mats * (slot_size + padding) - padding
        local start_x = m_floor((sw - bar_w) / 2)
        local start_y = sh - slot_size - 10

        for i, mat in ipairs(mats) do
            local px = start_x + (i - 1) * (slot_size + padding)
            local col = colors[mat]
            if i == hotbar_idx then t_fillRect(px - 2, start_y - 2, slot_size + 4, slot_size + 4, 255, 255, 255)
            else t_fillRect(px - 2, start_y - 2, slot_size + 4, slot_size + 4, 100, 100, 100) end
            t_fillRect(px, start_y, slot_size, slot_size, col[1], col[2], col[3])
            text.drawText(px + 10, start_y + 10, tostring(i), 255, 255, 255, 1)
        end
        local name_w = #mat_names[hotbar_idx] * 8
        text.drawText(m_floor((sw - name_w) / 2), start_y - 15, mat_names[hotbar_idx], 200, 200, 200, 1)

        coroutine.yield(0)
    end
end