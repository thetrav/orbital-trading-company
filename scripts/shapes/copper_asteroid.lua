local iron_asteroid = require("scripts.shapes.iron_asteroid")

local M = {}

local function patch_resources(tiles, resources, walls)
    local patched = {}
    for _, r in ipairs(resources) do
        table.insert(patched, {r[1], r[2], "copper-ore", r[4]})
    end
    return tiles, patched, walls
end

function M.get_positions(gate_pos, dir)
    local tiles, resources, walls = iron_asteroid.get_positions(gate_pos, dir)
    return patch_resources(tiles, resources, walls)
end

M.get_gate_pos = iron_asteroid.get_gate_pos
M.get_bounding_box = iron_asteroid.get_bounding_box

return M
