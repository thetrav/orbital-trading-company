local M = {}

local TILE = "dirt-7"
local GAP = 2
local R = 7

local function get_center(gate_pos, dir)
    local gx, gy = gate_pos.x, gate_pos.y
    if dir == "east" then return gx + GAP + R, gy
    elseif dir == "west" then return gx - GAP - R, gy
    elseif dir == "north" then return gx, gy + GAP + R
    elseif dir == "south" then return gx, gy - GAP - R
    end
end

function M.get_positions(gate_pos, dir)
    local tiles = {}
    local resources = {}
    local walls = {}

    local cx, cy = get_center(gate_pos, dir)
    if not cx then return tiles, resources, walls end

    for x = cx - R, cx + R do
        for y = cy - R, cy + R do
            local dx = (x - cx) / R
            local dy = (y - cy) / R
            if dx * dx + dy * dy < 1 then
                table.insert(tiles, {x, y, TILE})
            end
        end
    end

    local rir, rir2 = 2, 2
    for x = cx - rir, cx + rir do
        for y = cy - rir2, cy + rir2 do
            local dx = (x - cx) / (rir + 0.5)
            local dy = (y - cy) / (rir2 + 0.5)
            if dx * dx + dy * dy <= 1 then
                table.insert(resources, {x, y, "iron-ore", 5000000})
            end
        end
    end

    local ex, wx, ey, wy
    if dir == "east" then
        ex, wx = cx - R + 1, cx - R
        ey, wy = cy, cy
    elseif dir == "west" then
        ex, wx = cx + R - 1, cx + R
        ey, wy = cy, cy
    elseif dir == "north" then
        ex, wx = cx, cx
        ey, wy = cy - R + 1, cy - R
    elseif dir == "south" then
        ex, wx = cx, cx
        ey, wy = cy + R - 1, cy + R
    end

    if dir == "east" or dir == "west" then
        table.insert(walls, {ex, ey + 1})
        table.insert(walls, {wx, wy + 1})
        table.insert(walls, {ex, ey - 1})
        table.insert(walls, {wx, wy - 1})
        table.insert(tiles, {ex, ey, "otc-platform"})
        table.insert(tiles, {wx, wy, "otc-platform"})
        table.insert(tiles, {ex, ey + 1, "otc-platform"})
        table.insert(tiles, {wx, wy + 1, "otc-platform"})
        table.insert(tiles, {ex, ey - 1, "otc-platform"})
        table.insert(tiles, {wx, wy - 1, "otc-platform"})
    else
        table.insert(walls, {ex + 1, ey})
        table.insert(walls, {ex + 1, wy})
        table.insert(walls, {ex - 1, ey})
        table.insert(walls, {ex - 1, wy})
        table.insert(tiles, {ex, ey, "otc-platform"})
        table.insert(tiles, {ex, wy, "otc-platform"})
        table.insert(tiles, {ex + 1, ey, "otc-platform"})
        table.insert(tiles, {ex + 1, wy, "otc-platform"})
        table.insert(tiles, {ex - 1, ey, "otc-platform"})
        table.insert(tiles, {ex - 1, wy, "otc-platform"})
    end

    return tiles, resources, walls
end

function M.get_gate_pos(gate_pos, dir)
    local cx, cy = get_center(gate_pos, dir)
    if not cx then return nil end
    if dir == "east" then return {x = cx - R + 1, y = cy}
    elseif dir == "west" then return {x = cx + R - 1, y = cy}
    elseif dir == "north" then return {x = cx, y = cy - R + 1}
    elseif dir == "south" then return {x = cx, y = cy + R - 1}
    end
end

function M.get_bounding_box(gate_pos, dir)
    local cx, cy = get_center(gate_pos, dir)
    if not cx then return nil end
    if dir == "east" then return {{cx - R, cy - R + 1}, {cx + R - 1, cy + R - 1}}
    elseif dir == "west" then return {{cx - R + 1, cy - R + 1}, {cx + R, cy + R - 1}}
    elseif dir == "north" then return {{cx - R + 1, cy - R}, {cx + R - 1, cy + R - 1}}
    elseif dir == "south" then return {{cx - R + 1, cy - R + 1}, {cx + R - 1, cy + R}}
    end
end

return M
