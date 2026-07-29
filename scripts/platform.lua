local M = {}

local platform_gates = require("scripts.platform_gates")

local R = 5

local function place_wall(surface, pos)
    if platform_gates.is_entity_position(pos[1], pos[2]) then return end
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
    if x >= -R - 1 and x <= R + 1 and y >= -R - 1 and y <= R + 1 then return true end
    if platform_gates.is_airlock_position(x, y) then return true end
    return false
end

function M.build_platform(surface, area)
    local tiles = {}
    local wall_positions = {}

    for x = area.left_top.x, area.right_bottom.x - 1 do
        for y = area.left_top.y, area.right_bottom.y - 1 do
            if M.is_in_platform(x, y) or is_in_wall_border(x, y) then
                table.insert(tiles, {name = "otc-platform", position = {x, y}})
            else
                table.insert(tiles, {name = "out-of-map", position = {x, y}})
            end
            if is_in_wall_border(x, y) then
                table.insert(wall_positions, {x, y})
            end
        end
    end
    surface.set_tiles(tiles, false)

    for _, pos in ipairs(wall_positions) do
        place_wall(surface, pos)
    end
end

function M.expand_from_gate(surface, gate_pos)
    local key = gate_pos.x .. "," .. gate_pos.y
    local dir = platform_gates.get_gate_dir(key)
    if not dir then return false end

    local CX, CY, conn_side
    if dir == "east" then CX, CY, conn_side = gate_pos.x + 9, gate_pos.y, "west"
    elseif dir == "west" then CX, CY, conn_side = gate_pos.x - 9, gate_pos.y, "east"
    elseif dir == "north" then CX, CY, conn_side = gate_pos.x, gate_pos.y + 9, "south"
    elseif dir == "south" then CX, CY, conn_side = gate_pos.x, gate_pos.y - 9, "north"
    else return false end

    local entities = surface.find_entities_filtered{area = {{CX - 7, CY - 7}, {CX + 7, CY + 7}}}
    for _, entity in ipairs(entities) do
        if entity.valid and entity.type ~= "item-on-ground" and entity.name ~= "tile-ghost" then
            return false, "Not enough space!"
        end
    end

    platform_gates.destroy_gate_control(key)

    local function add_tile(tiles, p)
        table.insert(tiles, {name = "otc-platform", position = p})
    end

    local function add_wall(walls, p)
        table.insert(walls, p)
    end

    local function side_is_vertical(s)
        return s == "east" or s == "west"
    end

    local tiles = {}
    local walls = {}

    for x = CX - 5, CX + 5 do
        for y = CY - 5, CY + 5 do
            add_tile(tiles, {x, y})
        end
    end

    local function wall_side(vertical, coord, has_gap)
        if vertical then
            for y = CY - 6, CY + 6 do
                add_tile(tiles, {coord, y})
                if not (has_gap and y == CY) then add_wall(walls, {coord, y}) end
            end
        else
            for x = CX - 6, CX + 6 do
                add_tile(tiles, {x, coord})
                if not (has_gap and x == CX) then add_wall(walls, {x, coord}) end
            end
        end
    end

    wall_side(true, CX - 6, true)
    wall_side(true, CX + 6, true)
    wall_side(false, CY - 6, true)
    wall_side(false, CY + 6, true)

    for _, side in ipairs{"east", "west", "north", "south"} do
        if side_is_vertical(side) then
            local ax = CX + (side == "east" and 7 or -7)
            add_tile(tiles, {ax, CY}); add_tile(tiles, {ax, CY + 1}); add_tile(tiles, {ax, CY - 1})
            add_wall(walls, {ax, CY + 1}); add_wall(walls, {ax, CY - 1})
        else
            local ay = CY + (side == "north" and 7 or -7)
            add_tile(tiles, {CX, ay}); add_tile(tiles, {CX + 1, ay}); add_tile(tiles, {CX - 1, ay})
            add_wall(walls, {CX + 1, ay}); add_wall(walls, {CX - 1, ay})
        end
    end

    local conn_gate_pos = {
        CX + (conn_side == "east" and 6 or conn_side == "west" and -6 or 0),
        CY + (conn_side == "north" and 6 or conn_side == "south" and -6 or 0),
    }

    if side_is_vertical(conn_side) then
        local s = math.min(gate_pos.x, conn_gate_pos[1]) + 1
        local e = math.max(gate_pos.x, conn_gate_pos[1]) - 1
        for x = s, e do
            add_tile(tiles, {x, gate_pos.y})
            add_tile(tiles, {x, gate_pos.y + 1}); add_tile(tiles, {x, gate_pos.y - 1})
            add_wall(walls, {x, gate_pos.y + 1}); add_wall(walls, {x, gate_pos.y - 1})
        end
    else
        local s = math.min(gate_pos.y, conn_gate_pos[2]) + 1
        local e = math.max(gate_pos.y, conn_gate_pos[2]) - 1
        for y = s, e do
            add_tile(tiles, {gate_pos.x, y})
            add_tile(tiles, {gate_pos.x + 1, y}); add_tile(tiles, {gate_pos.x - 1, y})
            add_wall(walls, {gate_pos.x + 1, y}); add_wall(walls, {gate_pos.x - 1, y})
        end
    end

    surface.set_tiles(tiles, false)

    for _, pos in ipairs(walls) do
        place_wall(surface, pos)
    end

    local function try_create(e)
        if e then e.minable = false; e.destructible = false end
        return e
    end

    local function place_gate(side, pos)
        return try_create(surface.create_entity {
            name = "gate", position = pos, force = "player",
            direction = side_is_vertical(side) and defines.direction.north
                or defines.direction.east,
            create_build_effect_smoke = false
        })
    end

    for _, side in ipairs{"east", "west", "north", "south"} do
        local gx = CX + (side == "east" and 6 or side == "west" and -6 or 0)
        local gy = CY + (side == "north" and 6 or side == "south" and -6 or 0)
        local gate_entity = place_gate(side, {gx, gy})
        local computer_entity
        if side ~= conn_side then
            local cdx, cdy = (side == "east" and 1 or side == "west" and -1 or 0),
                             (side == "north" and 1 or side == "south" and -1 or 0)
            local computer_pos = {gx + cdx, gy + cdy}
            local function destroy_computer_at(pos)
                local box = {{pos[1] - 1, pos[2] - 1}, {pos[1] + 1, pos[2] + 1}}
                for _, entity in ipairs(surface.find_entities(box)) do
                    if entity.valid and entity.name == "otc-gate-computer" then
                        local gate_entry = platform_gates.get_gate_by_unit(entity.unit_number)
                        if gate_entry then
                            storage.gates_by_id[entity.unit_number] = nil
                            gate_entry.computer_unit_number = nil
                        end
                        entity.destroy()
                        return true
                    end
                end
                return false
            end
            local joined = false
            for _, d in ipairs{{-1,0},{1,0},{0,-1},{0,1}} do
                if destroy_computer_at({computer_pos[1] + d[1], computer_pos[2] + d[2]}) then
                    joined = true
                end
            end
            if not joined then
                computer_entity = try_create(surface.create_entity {
                    name = "otc-gate-computer", position = computer_pos, force = "player",
                })
            end
        end
        local gkey = gx .. "," .. gy
        if not storage.gates[gkey] then
            storage.gates[gkey] = {
                pos = {x = gx, y = gy},
                key = gkey,
                dir = side,
                expanded = false,
                gate_unit_number = gate_entity and gate_entity.unit_number,
                computer_unit_number = computer_entity and computer_entity.unit_number,
            }
            if computer_entity then
                storage.gates_by_id[computer_entity.unit_number] = storage.gates[gkey]
            end
        end
    end

    return true
end

return M