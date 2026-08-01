local M = {}

local function side_is_vertical(s)
    return s == "east" or s == "west"
end

function M.get_positions(cx, cy, conn_side, gate_pos)
    local tiles = {}
    local walls = {}

    for x = cx - 2, cx + 2 do
        for y = cy - 2, cy + 2 do
            table.insert(tiles, {x, y})
        end
    end

    for y = cy - 3, cy + 3 do
        table.insert(tiles, {cx - 3, y})
        if not (conn_side == "west" and y == cy) then
            table.insert(walls, {cx - 3, y})
        end
        table.insert(tiles, {cx + 3, y})
        if not (conn_side == "east" and y == cy) then
            table.insert(walls, {cx + 3, y})
        end
    end

    for x = cx - 3, cx + 3 do
        table.insert(tiles, {x, cy - 3})
        if not (conn_side == "south" and x == cx) then
            table.insert(walls, {x, cy - 3})
        end
        table.insert(tiles, {x, cy + 3})
        if not (conn_side == "north" and x == cx) then
            table.insert(walls, {x, cy + 3})
        end
    end

    local conn_gx = cx + (conn_side == "east" and 3 or conn_side == "west" and -3 or 0)
    local conn_gy = cy + (conn_side == "north" and 3 or conn_side == "south" and -3 or 0)

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

function M.get_bounding_box(cx, cy)
    return {{cx - 4, cy - 4}, {cx + 4, cy + 4}}
end

return M
