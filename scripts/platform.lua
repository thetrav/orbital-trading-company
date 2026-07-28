local M = {}

local PLATFORM_SIZE = 10
local PLATFORM_HALF = PLATFORM_SIZE / 2

function M.is_in_platform(x, y)
    return x >= -PLATFORM_HALF and x < PLATFORM_HALF
       and y >= -PLATFORM_HALF and y < PLATFORM_HALF
end

function M.build_platform(surface, area)
    local tiles = {}
    for x = area.left_top.x, area.right_bottom.x - 1 do
        for y = area.left_top.y, area.right_bottom.y - 1 do
            local tile_name = M.is_in_platform(x, y) and "concrete" or "out-of-map"
            table.insert(tiles, {name = tile_name, position = {x, y}})
        end
    end
    surface.set_tiles(tiles, true)
end

return M
