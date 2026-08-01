local M = {}

function M.get_positions(gate_pos, dir)
    local tiles = {}
    local walls = {}

    local gx, gy = gate_pos.x, gate_pos.y

    if dir == "east" or dir == "west" then
        local s = (dir == "east") and 1 or -1
        local cgx = gx + 3 * s
        local fgx = gx + 24 * s
        local cx = gx + 25 * s

        table.insert(tiles, {gx + s, gy}); table.insert(tiles, {gx + 2*s, gy})
        table.insert(tiles, {gx + s, gy+1}); table.insert(tiles, {gx + s, gy-1})
        table.insert(tiles, {gx + 2*s, gy+1}); table.insert(tiles, {gx + 2*s, gy-1})
        table.insert(walls, {gx + s, gy+1}); table.insert(walls, {gx + s, gy-1})
        table.insert(walls, {gx + 2*s, gy+1}); table.insert(walls, {gx + 2*s, gy-1})

        for y = gy-2, gy+2 do
            table.insert(tiles, {cgx, y})
            if y ~= gy then table.insert(walls, {cgx, y}) end
        end

        local lo = math.min(cgx, fgx)
        local hi = math.max(cgx, fgx)
        for x = lo + 1, hi - 1 do
            for y = gy-1, gy+1 do table.insert(tiles, {x, y}) end
        end

        for x = lo, hi do
            table.insert(tiles, {x, gy+2}); table.insert(tiles, {x, gy-2})
            table.insert(walls, {x, gy+2}); table.insert(walls, {x, gy-2})
        end

        for y = gy-2, gy+2 do
            table.insert(tiles, {fgx, y})
            if y ~= gy then table.insert(walls, {fgx, y}) end
        end

        table.insert(tiles, {cx, gy})
        table.insert(tiles, {cx, gy+1})
        table.insert(tiles, {cx, gy-1})
        table.insert(walls, {cx, gy+1})
        table.insert(walls, {cx, gy-1})

    else
        local s = (dir == "north") and 1 or -1
        local cgy = gy + 3 * s
        local fgy = gy + 24 * s
        local cy = gy + 25 * s

        table.insert(tiles, {gx, gy + s}); table.insert(tiles, {gx, gy + 2*s})
        table.insert(tiles, {gx+1, gy + s}); table.insert(tiles, {gx-1, gy + s})
        table.insert(tiles, {gx+1, gy + 2*s}); table.insert(tiles, {gx-1, gy + 2*s})
        table.insert(walls, {gx+1, gy + s}); table.insert(walls, {gx-1, gy + s})
        table.insert(walls, {gx+1, gy + 2*s}); table.insert(walls, {gx-1, gy + 2*s})

        for x = gx-2, gx+2 do
            table.insert(tiles, {x, cgy})
            if x ~= gx then table.insert(walls, {x, cgy}) end
        end

        local lo = math.min(cgy, fgy)
        local hi = math.max(cgy, fgy)
        for y = lo + 1, hi - 1 do
            for x = gx-1, gx+1 do table.insert(tiles, {x, y}) end
        end

        for y = lo, hi do
            table.insert(tiles, {gx+2, y}); table.insert(tiles, {gx-2, y})
            table.insert(walls, {gx+2, y}); table.insert(walls, {gx-2, y})
        end

        for x = gx-2, gx+2 do
            table.insert(tiles, {x, fgy})
            if x ~= gx then table.insert(walls, {x, fgy}) end
        end

        table.insert(tiles, {gx, cy})
        table.insert(tiles, {gx+1, cy})
        table.insert(tiles, {gx-1, cy})
        table.insert(walls, {gx+1, cy})
        table.insert(walls, {gx-1, cy})
    end

    return tiles, walls
end

function M.get_bounding_box(gate_pos, dir)
    local gx, gy = gate_pos.x, gate_pos.y
    if dir == "east" then return {{gx + 2, gy - 2}, {gx + 25, gy + 2}}
    elseif dir == "west" then return {{gx - 25, gy - 2}, {gx - 2, gy + 2}}
    elseif dir == "north" then return {{gx - 2, gy + 2}, {gx + 2, gy + 25}}
    elseif dir == "south" then return {{gx - 2, gy - 25}, {gx + 2, gy - 2}}
    end
end

return M
