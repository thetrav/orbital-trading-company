local M = {}

local platform_gates = require("scripts.platform_gates")

local R = 5

local function place_wall(surface, pos)
    if platform_gates.is_gate_position(pos[1], pos[2]) then return end
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

function M.is_in_platform(x, y)
    return x >= -R and x <= R
       and y >= -R and y <= R
end

local function is_in_wall_border(x, y)
    if M.is_in_platform(x, y) then return false end
    return x >= -R - 1 and x <= R + 1
       and y >= -R - 1 and y <= R + 1
end

function M.build_platform(surface, area)
    local tiles = {}
    local wall_positions = {}

    for x = area.left_top.x, area.right_bottom.x - 1 do
        for y = area.left_top.y, area.right_bottom.y - 1 do
            if M.is_in_platform(x, y) then
                table.insert(tiles, {name = "otc-platform", position = {x, y}})
            elseif is_in_wall_border(x, y) then
                table.insert(tiles, {name = "otc-platform", position = {x, y}})
                table.insert(wall_positions, {x, y})
            else
                table.insert(tiles, {name = "out-of-map", position = {x, y}})
            end
        end
    end
    surface.set_tiles(tiles, true)

    for _, pos in ipairs(wall_positions) do
        place_wall(surface, pos)
    end
end

function M.expand_from_gate(surface, gate_pos)
    local key = gate_pos.x .. "," .. gate_pos.y
    local dir = platform_gates.get_gate_dir(key)
    if not dir then return false end

    local tiles = {}

    if dir == "east" then
        for x = 7, 17 do
            for y = -5, 5 do
                table.insert(tiles, {name = "otc-platform", position = {x, y}})
            end
        end
        for x = 7, 18 do
            table.insert(tiles, {name = "otc-platform", position = {x, 6}})
            table.insert(tiles, {name = "otc-platform", position = {x, -6}})
        end
        for y = -5, 6 do
            table.insert(tiles, {name = "otc-platform", position = {18, y}})
            table.insert(tiles, {name = "otc-platform", position = {18, -y}})
        end

        surface.set_tiles(tiles, false)

        for y = -6, 6 do
            place_wall(surface, {18, y})
        end
        for x = 7, 18 do
            place_wall(surface, {x, 6})
            place_wall(surface, {x, -6})
        end

    elseif dir == "west" then
        for x = -17, -7 do
            for y = -5, 5 do
                table.insert(tiles, {name = "otc-platform", position = {x, y}})
            end
        end
        for x = -18, -7 do
            table.insert(tiles, {name = "otc-platform", position = {x, 6}})
            table.insert(tiles, {name = "otc-platform", position = {x, -6}})
        end
        for y = -5, 6 do
            table.insert(tiles, {name = "otc-platform", position = {-18, y}})
            table.insert(tiles, {name = "otc-platform", position = {-18, -y}})
        end

        surface.set_tiles(tiles, false)

        for y = -6, 6 do
            place_wall(surface, {-18, y})
        end
        for x = -18, -7 do
            place_wall(surface, {x, 6})
            place_wall(surface, {x, -6})
        end

    elseif dir == "north" then
        for y = 7, 17 do
            for x = -5, 5 do
                table.insert(tiles, {name = "otc-platform", position = {x, y}})
            end
        end
        for y = 7, 18 do
            table.insert(tiles, {name = "otc-platform", position = {6, y}})
            table.insert(tiles, {name = "otc-platform", position = {-6, y}})
        end
        for x = -5, 6 do
            table.insert(tiles, {name = "otc-platform", position = {x, 18}})
            table.insert(tiles, {name = "otc-platform", position = {-x, 18}})
        end

        surface.set_tiles(tiles, false)

        for x = -6, 6 do
            place_wall(surface, {x, 18})
        end
        for y = 7, 18 do
            place_wall(surface, {6, y})
            place_wall(surface, {-6, y})
        end

    elseif dir == "south" then
        for y = -17, -7 do
            for x = -5, 5 do
                table.insert(tiles, {name = "otc-platform", position = {x, y}})
            end
        end
        for y = -18, -7 do
            table.insert(tiles, {name = "otc-platform", position = {6, y}})
            table.insert(tiles, {name = "otc-platform", position = {-6, y}})
        end
        for x = -5, 6 do
            table.insert(tiles, {name = "otc-platform", position = {x, -18}})
            table.insert(tiles, {name = "otc-platform", position = {-x, -18}})
        end

        surface.set_tiles(tiles, false)

        for x = -6, 6 do
            place_wall(surface, {x, -18})
        end
        for y = -18, -7 do
            place_wall(surface, {6, y})
            place_wall(surface, {-6, y})
        end
    end

    platform_gates.destroy_gate_control(surface, gate_pos)

    local gate = surface.create_entity {
        name = "gate",
        position = gate_pos,
        force = "player",
    }
    if gate then
        gate.minable = false
        gate.destructible = false
    end

    return true
end

return M
