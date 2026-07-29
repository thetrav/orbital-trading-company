local M = {}

local function side_is_vertical(s)
    return s == "east" or s == "west"
end

function M.get_positions(cx, cy, conn_side, gate_pos)
    local tiles = {}
    local walls = {}

    for x = cx - 5, cx + 5 do
        for y = cy - 5, cy + 5 do
            table.insert(tiles, {x, y})
        end
    end

    local function add_border(vertical, coord)
        if vertical then
            for y = cy - 6, cy + 6 do
                table.insert(tiles, {coord, y})
                if y ~= cy then table.insert(walls, {coord, y}) end
            end
        else
            for x = cx - 6, cx + 6 do
                table.insert(tiles, {x, coord})
                if x ~= cx then table.insert(walls, {x, coord}) end
            end
        end
    end
    add_border(true, cx - 6)
    add_border(true, cx + 6)
    add_border(false, cy - 6)
    add_border(false, cy + 6)

    for _, side in ipairs{"east", "west", "north", "south"} do
        if side_is_vertical(side) then
            local ax = cx + (side == "east" and 7 or -7)
            table.insert(tiles, {ax, cy})
            table.insert(tiles, {ax, cy + 1})
            table.insert(tiles, {ax, cy - 1})
            table.insert(walls, {ax, cy + 1})
            table.insert(walls, {ax, cy - 1})
        else
            local ay = cy + (side == "north" and 7 or -7)
            table.insert(tiles, {cx, ay})
            table.insert(tiles, {cx + 1, ay})
            table.insert(tiles, {cx - 1, ay})
            table.insert(walls, {cx + 1, ay})
            table.insert(walls, {cx - 1, ay})
        end
    end

    local conn_gx = cx + (conn_side == "east" and 6 or conn_side == "west" and -6 or 0)
    local conn_gy = cy + (conn_side == "north" and 6 or conn_side == "south" and -6 or 0)

    if side_is_vertical(conn_side) then
        local s = math.min(gate_pos.x, conn_gx) + 1
        local e = math.max(gate_pos.x, conn_gx) - 1
        for x = s, e do
            table.insert(tiles, {x, gate_pos.y})
            table.insert(tiles, {x, gate_pos.y + 1})
            table.insert(tiles, {x, gate_pos.y - 1})
            table.insert(walls, {x, gate_pos.y + 1})
            table.insert(walls, {x, gate_pos.y - 1})
        end
    else
        local s = math.min(gate_pos.y, conn_gy) + 1
        local e = math.max(gate_pos.y, conn_gy) - 1
        for y = s, e do
            table.insert(tiles, {gate_pos.x, y})
            table.insert(tiles, {gate_pos.x + 1, y})
            table.insert(tiles, {gate_pos.x - 1, y})
            table.insert(walls, {gate_pos.x + 1, y})
            table.insert(walls, {gate_pos.x - 1, y})
        end
    end

    return tiles, walls
end

return M
