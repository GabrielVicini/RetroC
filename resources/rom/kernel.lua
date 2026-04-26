local text = require("libraries/text/text")

-- ==========================================
-- HYPER-PERFORMANCE 3D VOXEL CA + NETWORK
-- ==========================================
local RENDER_SCALE = 3
local GS           = 40
local GS2          = GS * GS
local MAX_RAY_STEPS = 45

local m_random, m_floor, m_abs = math.random, math.floor, math.abs
local m_max, m_min, m_sqrt = math.max, math.min, math.sqrt
local m_sin, m_cos = math.sin, math.cos
local t_setPixel, t_fillRect, t_getSize = term.setPixel, term.fillRect, term.getSize
local s_getFPS, s_getFrameTime = sys.getFPS, sys.getFrameTime

-- Network Globals
local mode = "MENU"
local socket = nil
local clients = {}
local other_players = {}
local server_ip = "0.0.0.0"
local server_port = 23828
local net_queue = {}
local debug_tx, debug_rx = 0, 0

-- Player Identifiers (Generated properly in main)
local local_id = ""
local my_color = {r=255, g=255, b=255}

-- Types
local T_EMPTY, T_SAND, T_WATER, T_ACID, T_WALL, T_CLOUD, T_GRASS = 0, 1, 2, 3, 4, 5, 6
local colors = {
    [T_EMPTY] = {0, 0, 0}, [T_SAND]  = {210, 190, 110}, [T_WATER] = {30, 100, 200},
    [T_ACID]  = {80, 255, 60}, [T_WALL]  = {50, 50, 50}, [T_CLOUD] = {245, 245, 255}, [T_GRASS] = {60, 160, 70}
}

local grid = {}
local physics_timer = 0
local PHYSICS_TICK_RATE = 0.05
local world_tick = 0

-- Player State
local pX, pY, pZ = GS/2, 5, GS/2
local pVelY = 0
local isGrounded = false
local camTheta, camPhi = 0, 0
local mouse_locked = false
local worldOffsetX, worldOffsetZ = 0, 0

local mats = {T_GRASS, T_SAND, T_WATER, T_ACID, T_CLOUD}
local mat_names = {"Grass", "Sand", "Water", "Acid", "Cloud"}
local hotbar_idx = 1
local tx, ty, tz, rx, ry, rz = -1, -1, -1, -1, -1, -1

-- ==========================================
-- DETERMINISTIC PHYSICS HASHING
-- ==========================================
-- Replaces math.random() so Host and Client simulate identically
local function hashFloat(x, y, z, tick)
    return ((x * 73856093 + y * 19349663 + z * 83492791 + tick * 11) % 100) / 100
end

local function hashInt(x, y, z, tick, max)
    return ((x * 73856093 + y * 19349663 + z * 83492791 + tick * 11) % max) + 1
end

-- ==========================================
-- CHUNKS & ENGINE
-- ==========================================
local function generateTerrain(startX, endX, startZ, endZ, offX, offZ)
    local water_level = m_floor(GS * 0.70)
    for z = startZ, endZ do
        for x = startX, endX do
            local absX, absZ = x + offX, z + offZ
            local nx, nz = absX / 8, absZ / 8
            local h_offset = m_sin(nx) * m_cos(nz) * 4 + m_sin(nx * 2.5 + nz * 1.5) * 2
            local ground_h = m_floor(GS * 0.65 - h_offset)

            for y = 1, GS - 2 do
                local idx = y * GS2 + z * GS + x
                if grid[idx] == T_EMPTY then
                    if y >= ground_h then
                        if y >= water_level - 2 and y <= water_level + 1 then grid[idx] = T_SAND
                        else grid[idx] = T_GRASS end
                    elseif y >= water_level then grid[idx] = T_WATER
                    elseif y > 2 and y < 8 then
                        local cx, cz = absX / 5, absZ / 5
                        if m_sin(cx * 1.5) * m_cos(cz * 1.5) > 0.6 then grid[idx] = T_CLOUD end
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

local function setBlockAbsolute(absX, absY, absZ, mat)
    local lx, ly, lz = absX - worldOffsetX, absY, absZ - worldOffsetZ
    if lx > 0 and lx < GS-1 and ly > 0 and ly < GS-1 and lz > 0 and lz < GS-1 then
        grid[ly * GS2 + lz * GS + lx] = mat
    end
end

local function swap(idx1, idx2)
    grid[idx1], grid[idx2] = grid[idx2], grid[idx1]
end

-- ==========================================
-- DETERMINISTIC CA UPDATE
-- ==========================================
local function updateCA(tick)
    local dir = (tick % 2 == 0) and 1 or -1
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
                        -- Deteministic Hash choice instead of m_random
                        local target = opts[hashInt(x+worldOffsetX, y, z+worldOffsetZ, tick, 4)]
                        local t_mat = grid[target]
                        if t_mat == T_EMPTY or t_mat == T_WATER or t_mat == T_ACID then swap(idx, target) end
                    end

                elseif c == T_WATER or c == T_ACID then
                    local down_idx = yd_idx + z_idx + x
                    local down = grid[down_idx]
                    if down == T_EMPTY then
                        swap(idx, down_idx)
                    else
                        if hashFloat(x+worldOffsetX, y, z+worldOffsetZ, tick) > 0.6 then
                            local diag_opts, h_opts = {}, {}
                            local dl, dr = yd_idx + z_idx + (x-1), yd_idx + z_idx + (x+1)
                            local df, db = yd_idx + (z-1)*GS + x, yd_idx + (z+1)*GS + x

                            if grid[dl] == T_EMPTY then diag_opts[#diag_opts+1] = dl end
                            if grid[dr] == T_EMPTY then diag_opts[#diag_opts+1] = dr end
                            if grid[df] == T_EMPTY then diag_opts[#diag_opts+1] = df end
                            if grid[db] == T_EMPTY then diag_opts[#diag_opts+1] = db end

                            if #diag_opts > 0 then
                                swap(idx, diag_opts[hashInt(x+worldOffsetX, y, z+worldOffsetZ, tick, #diag_opts)])
                            else
                                local hl, hr = y_idx + z_idx + (x-1), y_idx + z_idx + (x+1)
                                local hf, hb = y_idx + (z-1)*GS + x, y_idx + (z+1)*GS + x
                                if grid[hl] == T_EMPTY then h_opts[#h_opts+1] = hl end
                                if grid[hr] == T_EMPTY then h_opts[#h_opts+1] = hr end
                                if grid[hf] == T_EMPTY then h_opts[#h_opts+1] = hf end
                                if grid[hb] == T_EMPTY then h_opts[#h_opts+1] = hb end

                                if #h_opts > 0 then swap(idx, h_opts[hashInt(x+worldOffsetX, y, z+worldOffsetZ, tick, #h_opts)]) end
                            end
                        end
                    end
                elseif c == T_CLOUD then
                    if hashFloat(x+worldOffsetX, y, z+worldOffsetZ, tick) > 0.95 then
                        local target = y_idx + z_idx + x + 1
                        if x + 1 < GS - 1 and grid[target] == T_EMPTY then swap(idx, target)
                        elseif x + 1 >= GS - 1 then grid[idx] = T_EMPTY end
                    end
                end
            end
        end
    end
end

-- ==========================================
-- NETWORKING
-- ==========================================
local function sendNetworkData(data)
    if mode == "HOST" then
        for _, c in pairs(clients) do
            net.sendTo(socket, data, c.ip, c.port)
            debug_tx = debug_tx + 1
        end
    elseif mode == "JOIN" then
        net.sendTo(socket, data, server_ip, server_port)
        debug_tx = debug_tx + 1
    end
end

local function processNetwork()
    local now = sys.getUnixTime()

    for i = 1, #net_queue do sendNetworkData(net_queue[i]) end
    net_queue = {}

    local p_data = string.format("P|%s|%.2f|%.2f|%.2f|%d|%d|%d", local_id, pX + worldOffsetX, pY, pZ + worldOffsetZ, my_color.r, my_color.g, my_color.b)
    sendNetworkData(p_data)

    while true do
        local data, ip, port = net.recvFrom(socket, 1024)
        if not data then break end

        debug_rx = debug_rx + 1
        local p_type = data:sub(1,1)

        if mode == "HOST" then
            local cid = ip .. ":" .. port
            if not clients[cid] then
                clients[cid] = {ip = ip, port = port}
                local sync_msg = string.format("S|%d|%d", worldOffsetX, worldOffsetZ)
                net.sendTo(socket, sync_msg, ip, port)
                debug_tx = debug_tx + 1
            end
        end

        if p_type == "P" then
            local _, id, ex, ey, ez, r, g, b = data:match("([^|]+)|([^|]+)|([^|]+)|([^|]+)|([^|]+)|([^|]+)|([^|]+)|([^|]+)")
            if id and id ~= local_id then
                other_players[id] = {x = tonumber(ex), y = tonumber(ey), z = tonumber(ez), r = tonumber(r), g = tonumber(g), b = tonumber(b), last = now}
            end

            if mode == "HOST" then
                for target_id, c in pairs(clients) do
                    if target_id ~= (ip .. ":" .. port) then
                        net.sendTo(socket, data, c.ip, c.port)
                        debug_tx = debug_tx + 1
                    end
                end
            end

        elseif p_type == "B" then
            local _, bx, by, bz, mat = data:match("([^|]+)|([^|]+)|([^|]+)|([^|]+)|([^|]+)")
            if bx then setBlockAbsolute(tonumber(bx), tonumber(by), tonumber(bz), tonumber(mat)) end

            if mode == "HOST" then
                for target_id, c in pairs(clients) do
                    if target_id ~= (ip .. ":" .. port) then
                        net.sendTo(socket, data, c.ip, c.port)
                        debug_tx = debug_tx + 1
                    end
                end
            end

        elseif p_type == "S" and mode == "JOIN" then
            local _, ox, oz = data:match("([^|]+)|([^|]+)|([^|]+)")
            if ox then
                worldOffsetX = tonumber(ox)
                worldOffsetZ = tonumber(oz)
                initGrid()
            end
        end
    end

    for id, p in pairs(other_players) do
        -- Frame-based timeout fallback (3 seconds)
        if now - p.last > 3 and now - p.last < 1000 then other_players[id] = nil end
    end
end

-- ==========================================
-- RENDERING
-- ==========================================
local function renderView(sw, sh, cx, cy, cz, fX, fY, fZ, rX, rY, rZ, uX, uY, uZ, isUnderwater)
    local aspect = sw / sh
    local fov = 0.6
    local v_half_w = fov * aspect

    local tlX = fX - rX * v_half_w + uX * fov
    local tlY = fY - rY * v_half_w + uY * fov
    local tlZ = fZ - rZ * v_half_w + uZ * fov

    local stepRX, stepRY, stepRZ = (rX * v_half_w * 2)/sw, (rY * v_half_w * 2)/sw, (rZ * v_half_w * 2)/sw
    local stepUX, stepUY, stepUZ = (uX * fov * 2)/sh, (uY * fov * 2)/sh, (uZ * fov * 2)/sh
    local start_y = (world_tick % 2 == 0) and 0 or math.floor(RENDER_SCALE/2)

    for y = start_y, sh - 1, RENDER_SCALE do
        local rowX, rowY, rowZ = tlX - stepUX * y, tlY - stepUY * y, tlZ - stepUZ * y
        for x = 0, sw - 1, RENDER_SCALE do
            local dx, dy, dz = rowX + stepRX * x, rowY + stepRY * x, rowZ + stepRZ * x
            local d_inv = 1 / m_sqrt(dx*dx + dy*dy + dz*dz)
            local ndx, ndy, ndz = dx * d_inv, dy * d_inv, dz * d_inv

            local mapX, mapY, mapZ = m_floor(cx), m_floor(cy), m_floor(cz)
            local deltaX, deltaY, deltaZ = m_abs(1/dx), m_abs(1/dy), m_abs(1/dz)
            local stepX, stepY, stepZ = dx<0 and -1 or 1, dy<0 and -1 or 1, dz<0 and -1 or 1
            local sideX = (dx < 0 and (cx - mapX) or (mapX + 1.0 - cx)) * deltaX
            local sideY = (dy < 0 and (cy - mapY) or (mapY + 1.0 - cy)) * deltaY
            local sideZ = (dz < 0 and (cz - mapZ) or (mapZ + 1.0 - cz)) * deltaZ

            local hitMat, fluidMat, side, fSide, hitCursor, ray_steps = T_EMPTY, T_EMPTY, 0, 0, false, 0

            for i = 1, MAX_RAY_STEPS do
                ray_steps = i
                if mapX < 0 or mapX >= GS or mapY < 0 or mapY >= GS or mapZ < 0 or mapZ >= GS then break end
                if mapX == tx and mapY == ty and mapZ == tz then hitCursor = true end

                local cell = grid[mapY * GS2 + mapZ * GS + mapX]
                if cell == T_WATER or cell == T_ACID then
                    if fluidMat == T_EMPTY then fluidMat = cell; fSide = side end
                elseif cell ~= T_EMPTY and cell ~= T_WALL and cell ~= T_CLOUD then
                    hitMat = cell; break
                end

                if sideX < sideY then
                    if sideX < sideZ then sideX = sideX + deltaX; mapX = mapX + stepX; side = 1
                    else sideZ = sideZ + deltaZ; mapZ = mapZ + stepZ; side = 3 end
                else
                    if sideY < sideZ then sideY = sideY + deltaY; mapY = mapY + stepY; side = 2
                    else sideZ = sideZ + deltaZ; mapZ = mapZ + stepZ; side = 3 end
                end
            end

            -- Sky / Base
            local sky_t = m_max(0, m_min(1, (ndy + 1) * 0.5))
            local r, g, b_col = 50 + sky_t*100, 120 + sky_t*80, 255 - sky_t*60

            if hitMat ~= T_EMPTY then
                local col = colors[hitMat]
                r, g, b_col = col[1], col[2], col[3]
                if side == 1 then r, g, b_col = r*0.8, g*0.8, b_col*0.8
                elseif side == 2 then r, g, b_col = r*0.9, g*0.9, b_col*0.9 end
            end

            if fluidMat ~= T_EMPTY then
                local fCol = colors[fluidMat]
                local fr, fg, fb = fCol[1], fCol[2], fCol[3]
                if fSide == 1 then fr, fg, fb = fr*0.8, fg*0.8, fb*0.8
                elseif fSide == 2 then fr, fg, fb = fr*0.9, fg*0.9, fb*0.9 end
                r, g, b_col = r*0.4 + fr*0.6, g*0.4 + fg*0.6, b_col*0.4 + fb*0.6
            end

            local fog = m_min(1.0, ray_steps / MAX_RAY_STEPS) ^ 2
            r, g, b_col = r*(1-fog) + 150*fog, g*(1-fog) + 180*fog, b_col*(1-fog) + 220*fog

            if hitCursor then r, g, b_col = m_min(255, r+60), m_min(255, g+60), m_max(0, b_col-40) end
            if isUnderwater then r, g, b_col = r*0.3, m_min(255, g*0.6+50), m_min(255, b_col*0.9+100) end

            t_fillRect(x, y, RENDER_SCALE, RENDER_SCALE, m_floor(r), m_floor(g), m_floor(b_col))
        end
    end
end

-- Project 3D coordinate to 2D screen space
local function drawPlayers(sw, sh, camX, camY, camZ, fX, fY, fZ, rX, rY, rZ, uX, uY, uZ)
    local aspect = sw / sh
    local fov = 0.6

    for id, op in pairs(other_players) do
        local lx, ly, lz = op.x - worldOffsetX, op.y, op.z - worldOffsetZ
        local dx, dy, dz = lx - camX, ly - camY, lz - camZ

        -- Depth relative to camera forward vector
        local z = dx*fX + dy*fY + dz*fZ
        if z > 0.5 then
            -- Project onto right and up vectors
            local x = dx*rX + dy*rY + dz*rZ
            local y_proj = dx*uX + dy*uY + dz*uZ

            -- Screen coordinates
            local sx = (sw / 2) + (x / (z * fov * aspect)) * (sw / 2)
            local sy = (sh / 2) - (y_proj / (z * fov)) * (sh / 2)

            -- Size based on depth
            local w = m_max(4, m_floor(100 / z))
            local h = w * 2

            t_fillRect(m_floor(sx - w/2), m_floor(sy - h), w, h, op.r, op.g, op.b)
            local name = id:sub(1,4)
            local name_w = #name * 8
            text.drawText(m_floor(sx - name_w/2), m_floor(sy - h - 15), name, 255, 255, 255, 1)
        end
    end
end

-- ==========================================
-- MAIN LOOP
-- ==========================================
function main()
    text.loadFont((ENGINE_ROOT .. "/rom/libraries/text/font.bin"):gsub("//", "/"))

    -- FIX: True unique seeding to prevent the "Clone Issue"
    math.randomseed(os.time() + sys.getUnixTime() * 10000)
    local_id = tostring(math.random(10000, 99999))
    my_color = {r = math.random(50, 255), g = math.random(50, 255), b = math.random(50, 255)}

    while true do
        local sw, sh = t_getSize()
        if sw == 0 then sw, sh = 640, 360 end

        if mode == "MENU" then
            t_fillRect(0, 0, sw, sh, 20, 20, 25)
            text.drawTextCentered(sh/2 - 50, "VOXEL MULTIPLAYER", 255, 255, 255, 2)
            text.drawTextCentered(sh/2 + 10, "Press H to Host", 100, 255, 100, 1)
            text.drawTextCentered(sh/2 + 30, "Press J to Join", 100, 150, 255, 1)

            if input.keyPressed("H") then
                socket = net.udp()
                net.setNonBlocking(socket, true)
                net.bind(socket, "0.0.0.0", 23828)
                mode = "HOST"
                initGrid()
                if input.lockMouse then input.lockMouse() end
                mouse_locked = true
            elseif input.keyPressed("J") then
                socket = net.udp()
                net.setNonBlocking(socket, true)
                server_ip = "127.0.0.1"
                server_port = 23828
                mode = "JOIN"
                initGrid()
                if input.lockMouse then input.lockMouse() end
                mouse_locked = true
            end
        else
            local raw_dt = s_getFrameTime()
            local dt = m_min(raw_dt, 0.05)

            -- FIX: Deterministic fixed-step physics decoupled from Framerate
            physics_timer = physics_timer + dt
            while physics_timer >= PHYSICS_TICK_RATE do
                physics_timer = physics_timer - PHYSICS_TICK_RATE
                world_tick = world_tick + 1
                updateCA(world_tick)
            end

            processNetwork()

            if input.keyPressed("ESCAPE") then
                mouse_locked = not mouse_locked
                if mouse_locked and input.lockMouse then input.lockMouse()
                elseif not mouse_locked and input.unlockMouse then input.unlockMouse() end
            end

            local wheel = input.mouseWheel()
            if wheel > 0 then hotbar_idx = hotbar_idx + 1 end
            if wheel < 0 then hotbar_idx = hotbar_idx - 1 end
            if hotbar_idx > #mats then hotbar_idx = 1 end
            if hotbar_idx < 1 then hotbar_idx = #mats end
            local current_mat = mats[hotbar_idx]

            if mouse_locked then
                local mx, my = input.mouseDelta()
                camTheta = camTheta - mx * 0.005
                camPhi = m_max(m_min(camPhi + my * 0.005, 1.5), -1.5)
            end

            local fX = m_cos(camPhi) * m_sin(camTheta)
            local fY = m_sin(camPhi)
            local fZ = m_cos(camPhi) * m_cos(camTheta)
            local rX, rY, rZ = m_sin(camTheta - 1.57), 0, m_cos(camTheta - 1.57)

            local spd = 10.0 * dt
            local dx, dz = 0, 0
            if input.keyDown("W") then dx, dz = dx + m_sin(camTheta), dz + m_cos(camTheta) end
            if input.keyDown("S") then dx, dz = dx - m_sin(camTheta), dz - m_cos(camTheta) end
            if input.keyDown("A") then dx, dz = dx - rX, dz - rZ end
            if input.keyDown("D") then dx, dz = dx + rX, dz + rZ end

            if dx ~= 0 or dz ~= 0 then
                local len = m_sqrt(dx*dx + dz*dz)
                dx, dz = (dx/len)*spd, (dz/len)*spd
            end

            if not (isSolid(pX+dx, pY-0.1, pZ) or isSolid(pX+dx, pY-1.2, pZ)) then pX = pX + dx end
            if not (isSolid(pX, pY-0.1, pZ+dz) or isSolid(pX, pY-1.2, pZ+dz)) then pZ = pZ + dz end

            local body_in_fluid = inLiquid(pX, pY-0.1, pZ) or inLiquid(pX, pY-1.2, pZ)
            if body_in_fluid then
                pVelY = pVelY * 0.8 + (2.0 * dt)
                if input.keyDown("SPACE") then pVelY = pVelY - (6.0 * dt) end
            else
                pVelY = pVelY + (25.0 * dt)
            end
            if pVelY > 15.0 then pVelY = 15.0 end

            local stepY = pVelY * dt
            if stepY > 0 then
                if isSolid(pX, pY+stepY, pZ) then
                    pY = m_floor(pY+stepY) - 0.001; pVelY = 0; isGrounded = true
                else pY = pY + stepY; isGrounded = false end
            else
                if isSolid(pX, pY+stepY-1.6, pZ) then pVelY = 0
                else pY = pY + stepY end
                isGrounded = false
            end
            if isGrounded and not body_in_fluid and input.keyDown("SPACE") then pVelY = -9.0 end

            local shiftX, shiftZ = 0, 0
            if pX < 12 then shiftX = -12 elseif pX > GS - 12 then shiftX = 12 end
            if pZ < 12 then shiftZ = -12 elseif pZ > GS - 12 then shiftZ = 12 end

            if shiftX ~= 0 or shiftZ ~= 0 then
                local new_grid = {}
                for i = 0, GS*GS*GS - 1 do new_grid[i] = T_EMPTY end
                for y = 0, GS - 1 do
                    for z = 1, GS - 2 do
                        for x = 1, GS - 2 do
                            local ox, oz = x + shiftX, z + shiftZ
                            if ox >= 1 and ox < GS-1 and oz >= 1 and oz < GS-1 then
                                new_grid[y*GS2 + z*GS + x] = grid[y*GS2 + oz*GS + ox]
                            end
                        end
                    end
                end

                for y = 0, GS - 1 do
                    for z = 0, GS - 1 do
                        for x = 0, GS - 1 do
                            if x==0 or x==GS-1 or y==0 or y==GS-1 or z==0 or z==GS-1 then
                                new_grid[y*GS2 + z*GS + x] = T_WALL
                            end
                        end
                    end
                end

                grid = new_grid
                pX, pZ = pX - shiftX, pZ - shiftZ
                worldOffsetX, worldOffsetZ = worldOffsetX + shiftX, worldOffsetZ + shiftZ

                if shiftX > 0 then generateTerrain(GS-1-shiftX, GS-2, 1, GS-2, worldOffsetX, worldOffsetZ)
                elseif shiftX < 0 then generateTerrain(1, -shiftX, 1, GS-2, worldOffsetX, worldOffsetZ) end
                if shiftZ > 0 then generateTerrain(1, GS-2, GS-1-shiftZ, GS-2, worldOffsetX, worldOffsetZ)
                elseif shiftZ < 0 then generateTerrain(1, GS-2, 1, -shiftZ, worldOffsetX, worldOffsetZ) end
            end

            local camX, camY, camZ = pX, pY - 1.5, pZ
            local uX, uY, uZ = fY*rZ - fZ*rY, fZ*rX - fX*rZ, fX*rY - fY*rX

            local b_mapX, b_mapY, b_mapZ = m_floor(camX), m_floor(camY), m_floor(camZ)
            local bdDistX, bdDistY, bdDistZ = m_abs(1/fX), m_abs(1/fY), m_abs(1/fZ)
            local bStepX, bStepY, bStepZ = fX<0 and -1 or 1, fY<0 and -1 or 1, fZ<0 and -1 or 1
            local bSideX = (fX<0 and (camX-b_mapX) or (b_mapX+1.0-camX))*bdDistX
            local bSideY = (fY<0 and (camY-b_mapY) or (b_mapY+1.0-camY))*bdDistY
            local bSideZ = (fZ<0 and (camZ-b_mapZ) or (b_mapZ+1.0-camZ))*bdDistZ

            local hitFound, bHitSide = false, 0
            for i=1, 20 do
                if b_mapX<0 or b_mapX>=GS or b_mapY<0 or b_mapY>=GS or b_mapZ<0 or b_mapZ>=GS then break end
                if grid[b_mapY*GS2 + b_mapZ*GS + b_mapX] ~= T_EMPTY then hitFound = true; break end
                if bSideX < bSideY then
                    if bSideX < bSideZ then bSideX = bSideX+bdDistX; b_mapX = b_mapX+bStepX; bHitSide = 1
                    else bSideZ = bSideZ+bdDistZ; b_mapZ = b_mapZ+bStepZ; bHitSide = 3 end
                else
                    if bSideY < bSideZ then bSideY = bSideY+bdDistY; b_mapY = b_mapY+bStepY; bHitSide = 2
                    else bSideZ = bSideZ+bdDistZ; b_mapZ = b_mapZ+bStepZ; bHitSide = 3 end
                end
            end

            tx, ty, tz, rx, ry, rz = b_mapX, b_mapY, b_mapZ, b_mapX, b_mapY, b_mapZ
            if hitFound then
                if bHitSide == 1 then tx = tx - bStepX end
                if bHitSide == 2 then ty = ty - bStepY end
                if bHitSide == 3 then tz = tz - bStepZ end
            else tx, ty, tz = -1, -1, -1 end

            if input.mouseDown("LEFT") and hitFound and tx>0 and tx<GS-1 and ty>0 and ty<GS-1 and tz>0 and tz<GS-1 then
                if not (tx==m_floor(pX) and tz==m_floor(pZ) and ty>=m_floor(pY-1.5) and ty<=m_floor(pY)) then
                    local pIdx = ty * GS2 + tz * GS + tx
                    if grid[pIdx] ~= T_WALL and grid[pIdx] ~= current_mat then
                        grid[pIdx] = current_mat
                        table.insert(net_queue, string.format("B|%d|%d|%d|%d", tx + worldOffsetX, ty, tz + worldOffsetZ, current_mat))
                    end
                end
            end

            if input.mouseDown("RIGHT") and hitFound and rx>0 and rx<GS-1 and ry>0 and ry<GS-1 and rz>0 and rz<GS-1 then
                local rIdx = ry * GS2 + rz * GS + rx
                if grid[rIdx] ~= T_WALL and grid[rIdx] ~= T_EMPTY then
                    grid[rIdx] = T_EMPTY
                    table.insert(net_queue, string.format("B|%d|%d|%d|%d", rx + worldOffsetX, ry, rz + worldOffsetZ, T_EMPTY))
                end
            end

            renderView(sw, sh, camX, camY, camZ, fX, fY, fZ, rX, rY, rZ, uX, uY, uZ, inLiquid(pX, pY-1.5, pZ))
            drawPlayers(sw, sh, camX, camY, camZ, fX, fY, fZ, rX, rY, rZ, uX, uY, uZ)

            t_fillRect(0, 0, 200, 75, 0, 0, 0)
            text.drawText(5, 5, "FPS: " .. s_getFPS() .. " | " .. mode, 0, 255, 100, 1)

            local playerCount = 0
            for _ in pairs(other_players) do playerCount = playerCount + 1 end
            text.drawText(5, 31, "Connected Players: " .. (playerCount + 1), 255, 255, 0, 1)
            text.drawText(5, 44, "Server: " .. server_ip, 200, 200, 200, 1)
            text.drawText(5, 57, string.format("Net TX: %d | RX: %d", debug_tx, debug_rx), 100, 255, 255, 1)

            local bar_w = #mats * 35 - 5
            local st_x, st_y = m_floor((sw - bar_w) / 2), sh - 40
            for i, mat in ipairs(mats) do
                local px = st_x + (i - 1) * 35
                local col = colors[mat]
                if i == hotbar_idx then t_fillRect(px - 2, st_y - 2, 34, 34, 255, 255, 255)
                else t_fillRect(px - 2, st_y - 2, 34, 34, 100, 100, 100) end
                t_fillRect(px, st_y, 30, 30, col[1], col[2], col[3])
                text.drawText(px + 10, st_y + 10, tostring(i), 255, 255, 255, 1)
            end
            text.drawText(m_floor((sw - #mat_names[hotbar_idx]*8)/2), st_y - 15, mat_names[hotbar_idx], 200, 200, 200, 1)
        end
        coroutine.yield(0)
    end
end