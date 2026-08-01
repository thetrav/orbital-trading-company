local M = {}

--- The 3-wide walled tunnel joining a gate to the connection anchor of a shape.
--- `gap` is the number of tiles between the gate and the shape's anchor; the
--- tunnel fills the tiles strictly between them, so gap <= 1 produces nothing.
--- Returns tile positions and wall positions, both in world tile coordinates.
function M.get_positions(gate_pos, dir, gap)
    local tiles = {}
    local walls = {}
    if not gap or gap < 2 then return tiles, walls end

    local gx, gy = gate_pos.x, gate_pos.y

    if dir == "east" or dir == "west" then
        local step = (dir == "east") and 1 or -1
        for i = 1, gap - 1 do
            local x = gx + i * step
            tiles[#tiles + 1] = { x, gy }
            tiles[#tiles + 1] = { x, gy + 1 }
            tiles[#tiles + 1] = { x, gy - 1 }
            walls[#walls + 1] = { x, gy + 1 }
            walls[#walls + 1] = { x, gy - 1 }
        end
    else
        local step = (dir == "north") and 1 or -1
        for i = 1, gap - 1 do
            local y = gy + i * step
            tiles[#tiles + 1] = { gx, y }
            tiles[#tiles + 1] = { gx + 1, y }
            tiles[#tiles + 1] = { gx - 1, y }
            walls[#walls + 1] = { gx + 1, y }
            walls[#walls + 1] = { gx - 1, y }
        end
    end

    return tiles, walls
end

--- Same geometry, packaged as the extra_tile_layers / extra_entities that
--- shape_def.apply and shape_def.preview accept.
function M.get_extras(gate_pos, dir, gap, tile_name)
    local tiles, walls = M.get_positions(gate_pos, dir, gap)
    local entities = {}
    for _, w in ipairs(walls) do
        entities[#entities + 1] = {
            name = "otc-platform-wall",
            position = { w[1] + 0.5, w[2] + 0.5 },
        }
    end
    return {
        tile_layers = { { name = tile_name or "otc-platform", correct = false, tiles = tiles } },
        entities = entities,
    }
end

return M
