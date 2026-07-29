local M = {}

local TILE = "dirt-7"

function M.get_positions(gate_pos, dir)
    local tiles = {}
    local resources = {}

    local gx, gy = gate_pos.x, gate_pos.y
    local cx, cy

    if dir == "east" then cx, cy = gx + 7, gy
    elseif dir == "west" then cx, cy = gx - 7, gy
    elseif dir == "north" then cx, cy = gx, gy + 7
    elseif dir == "south" then cx, cy = gx, gy - 7
    else return tiles, resources end

    local rx, ry = 7, 7
    for x = cx - rx, cx + rx do
        for y = cy - ry, cy + ry do
            local dx = (x - cx) / rx
            local dy = (y - cy) / ry
            if dx * dx + dy * dy <= 1 then
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

    return tiles, resources
end

function M.get_bounding_box(gate_pos, dir)
    local gx, gy = gate_pos.x, gate_pos.y
    if dir == "east" then return {{gx, gy - 7}, {gx + 14, gy + 7}}
    elseif dir == "west" then return {{gx - 14, gy - 7}, {gx, gy + 7}}
    elseif dir == "north" then return {{gx - 7, gy}, {gx + 7, gy + 14}}
    elseif dir == "south" then return {{gx - 7, gy - 14}, {gx + 7, gy}}
    end
end

return M
