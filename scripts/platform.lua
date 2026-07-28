local M = {}

local PLATFORM_SIZE = 10
local PLATFORM_HALF = PLATFORM_SIZE / 2

local function is_in_platform(x, y)
    return x >= -PLATFORM_HALF and x < PLATFORM_HALF
       and y >= -PLATFORM_HALF and y < PLATFORM_HALF
end

local function is_in_wall_border(x, y)
    if is_in_platform(x, y) then return false end
    return x >= -PLATFORM_HALF - 1 and x < PLATFORM_HALF + 1
       and y >= -PLATFORM_HALF - 1 and y < PLATFORM_HALF + 1
end

function M.build_platform(surface, area)
    local tiles = {}
    local wall_positions = {}

    for x = area.left_top.x, area.right_bottom.x - 1 do
        for y = area.left_top.y, area.right_bottom.y - 1 do
            if is_in_platform(x, y) then
                table.insert(tiles, {name = "otc-platform", position = {x, y}})
            elseif is_in_wall_border(x, y) then
                table.insert(tiles, {name = "out-of-map", position = {x, y}})
                table.insert(wall_positions, {x, y})
            else
                table.insert(tiles, {name = "out-of-map", position = {x, y}})
            end
        end
    end
    surface.set_tiles(tiles, true)

    for _, pos in pairs(wall_positions) do
        local existing = surface.find_entity("otc-platform-wall", pos)
        if not existing then
            local wall = surface.create_entity {
                name = "otc-platform-wall",
                position = pos,
                force = "player",
            }
            if wall then
                wall.minable = false
                wall.destructible = false
            end
        end
    end
end

return M
