local M = {}

local platform_gates = require("scripts.platform_gates")
local hub_shape = require("scripts.shapes.hub")
local corridor_shape = require("scripts.shapes.corridor")
local factory_shape = require("scripts.shapes.factory")
local iron_asteroid_shape = require("scripts.shapes.iron_asteroid")
local copper_asteroid_shape = require("scripts.shapes.copper_asteroid")
local water_connection_shape = require("scripts.shapes.water_connection")
local buy_chest = require("scripts.buy_chest")
local sell_chest = require("scripts.sell_chest")

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
            end
            if is_in_wall_border(x, y) then
                table.insert(wall_positions, {x, y})
            end
        end
    end
    surface.set_tiles(tiles, false)
    surface.destroy_decoratives{area = {
        {area.left_top.x, area.left_top.y},
        {area.right_bottom.x - 1, area.right_bottom.y - 1}
    }}

    for _, pos in ipairs(wall_positions) do
        place_wall(surface, pos)
    end
end

local function side_is_vertical(s)
    return s == "east" or s == "west"
end

local function try_create(e)
    if e then e.minable = false; e.destructible = false end
    return e
end

local function place_gate(surface, side, pos)
    return try_create(surface.create_entity {
        name = "gate", position = pos, force = "player",
        direction = side_is_vertical(side) and defines.direction.north or defines.direction.east,
        create_build_effect_smoke = false
    })
end

local function place_computer(surface, gx, gy, side)
    local cdx, cdy = (side == "east" and 1 or side == "west" and -1 or 0),
                     (side == "north" and 1 or side == "south" and -1 or 0)
    local pos = {gx + cdx, gy + cdy}
    local function destroy_at(p)
        local box = {{p[1] - 1, p[2] - 1}, {p[1] + 1, p[2] + 1}}
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
        if destroy_at({pos[1] + d[1], pos[2] + d[2]}) then joined = true end
    end
    if not joined then
        return try_create(surface.create_entity {
            name = "otc-gate-computer", position = pos, force = "player",
        })
    end
end

local function register_gate(gx, gy, side, gate_entity, computer_entity, surface_name)
    local gkey = surface_name .. ":" .. gx .. "," .. gy
    if not storage.gates[gkey] then
        storage.gates[gkey] = {
            pos = {x = gx, y = gy},
            key = gkey,
            dir = side,
            surface_name = surface_name,
            expanded = false,
            gate_unit_number = gate_entity and gate_entity.unit_number,
            computer_unit_number = computer_entity and computer_entity.unit_number,
        }
        if computer_entity then
            storage.gates_by_id[computer_entity.unit_number] = storage.gates[gkey]
        end
    end
end

local function apply_tiles(surface, positions)
    local t = {}
    for _, p in ipairs(positions) do
        table.insert(t, {name = "otc-platform", position = p})
    end
    surface.set_tiles(t, false)
end

local function apply_walls(surface, positions)
    for _, p in ipairs(positions) do
        place_wall(surface, p)
    end
end

local function apply_custom_tiles(surface, positions, correct_tiles)
    local t = {}
    for _, entry in ipairs(positions) do
        table.insert(t, {name = entry[3], position = {entry[1], entry[2]}})
    end
    surface.set_tiles(t, correct_tiles or false)
end

local function place_resources(surface, resources)
    for _, r in ipairs(resources) do
        surface.create_entity{name = r[3], position = {r[1], r[2]}, amount = r[4]}
    end
end

local TILE_GHOST = {r = 0, g = 0.1, b = 0.3, a = 0.12}
local WALL_GHOST = {r = 0.9, g = 0.9, b = 1, a = 0.85}

local function render_preview(surface, player, tiles, walls, resources)
    local renderings = {}
    for _, p in ipairs(tiles) do
        table.insert(renderings, rendering.draw_rectangle{
            color = TILE_GHOST,
            left_top = {p[1], p[2] + 1},
            right_bottom = {p[1] + 1, p[2]},
            filled = true,
            surface = surface,
            players = {player},
        })
    end
    for _, p in ipairs(walls) do
        table.insert(renderings, rendering.draw_sprite{
            sprite = "entity/otc-platform-wall",
            tint = WALL_GHOST,
            target = {position = {p[1] + 0.5, p[2] + 0.5}},
            surface = surface,
            players = {player},
        })
    end
    for _, r in ipairs(resources or {}) do
        table.insert(renderings, rendering.draw_sprite{
            sprite = "item/iron-ore",
            tint = {r = 0.8, g = 0.5, b = 0.2, a = 1},
            target = {position = {r[1] + 0.5, r[2] + 0.5}},
            surface = surface,
            players = {player},
        })
    end
    return renderings
end

function M.show_preview(surface, player, gate_pos, shape)
    local key = surface.name .. ":" .. gate_pos.x .. "," .. gate_pos.y
    local dir = platform_gates.get_gate_dir(key)
    if not dir then return {} end

    local tiles, walls
    if shape == "hub" then
        local cx, cy
        if dir == "east" then cx, cy = gate_pos.x + 9, gate_pos.y
        elseif dir == "west" then cx, cy = gate_pos.x - 9, gate_pos.y
        elseif dir == "north" then cx, cy = gate_pos.x, gate_pos.y + 9
        elseif dir == "south" then cx, cy = gate_pos.x, gate_pos.y - 9
        else return {} end

        local conn_side
        if dir == "east" then conn_side = "west"
        elseif dir == "west" then conn_side = "east"
        elseif dir == "north" then conn_side = "south"
        else conn_side = "north"
        end

        tiles, walls = hub_shape.get_positions(cx, cy, conn_side, gate_pos)

    elseif shape == "corridor" then
        tiles, walls = corridor_shape.get_positions(gate_pos, dir)
    elseif shape == "factory" then
        local cx, cy
        if dir == "east" then cx, cy = gate_pos.x + 18, gate_pos.y
        elseif dir == "west" then cx, cy = gate_pos.x - 19, gate_pos.y
        elseif dir == "north" then cx, cy = gate_pos.x, gate_pos.y + 18
        elseif dir == "south" then cx, cy = gate_pos.x, gate_pos.y - 19
        else return {} end

        local conn_side
        if dir == "east" then conn_side = "west"
        elseif dir == "west" then conn_side = "east"
        elseif dir == "north" then conn_side = "south"
        else conn_side = "north"
        end

        tiles, walls = factory_shape.get_positions(cx, cy, conn_side, gate_pos)

    elseif shape == "water_connection" then
        local cx, cy
        if dir == "east" then cx, cy = gate_pos.x + 5, gate_pos.y
        elseif dir == "west" then cx, cy = gate_pos.x - 5, gate_pos.y
        elseif dir == "north" then cx, cy = gate_pos.x, gate_pos.y + 5
        elseif dir == "south" then cx, cy = gate_pos.x, gate_pos.y - 5
        else return {} end

        local conn_side
        if dir == "east" then conn_side = "west"
        elseif dir == "west" then conn_side = "east"
        elseif dir == "north" then conn_side = "south"
        else conn_side = "north"
        end

        tiles, walls = water_connection_shape.get_positions(cx, cy, conn_side, gate_pos)
        local renderings = render_preview(surface, player, tiles, walls)

        local dir_to_rotation = {east = -math.pi / 2, west = math.pi / 2, north = 0, south = math.pi}
        table.insert(renderings, rendering.draw_sprite{
            sprite = "entity/offshore-pump",
            tint = {r = 0.5, g = 0.7, b = 1, a = 0.4},
            target = {position = {cx + 0.5, cy + 0.5},
                      rotation = dir_to_rotation[dir] or 0},
            surface = surface,
            players = {player},
        })
        return renderings
    elseif shape == "orbital_station" then
        local dx, dy
        if dir == "east" then dx, dy = 1, 0
        elseif dir == "west" then dx, dy = -1, 0
        elseif dir == "north" then dx, dy = 0, 1
        elseif dir == "south" then dx, dy = 0, -1
        else return {} end

        local cx = gate_pos.x + dx * 9
        local cy = gate_pos.y + dy * 9
        tiles = {}
        walls = {}

        for x = cx - 7, cx + 7 do
            for y = cy - 7, cy + 7 do
                table.insert(tiles, {x, y})
            end
        end

        for y = cy - 7, cy + 7 do
            if not (dx > 0 and y == cy) then
                table.insert(walls, {cx - 7, y})
            end
            if not (dx < 0 and y == cy) then
                table.insert(walls, {cx + 7, y})
            end
        end
        for x = cx - 7, cx + 7 do
            if not (dy > 0 and x == cx) then
                table.insert(walls, {x, cy - 7})
            end
            if not (dy < 0 and x == cx) then
                table.insert(walls, {x, cy + 7})
            end
        end

        if dx ~= 0 then
            local room_edge_x = dx > 0 and (cx - 7) or (cx + 7)
            local s = math.min(gate_pos.x, room_edge_x) + 1
            local e = math.max(gate_pos.x, room_edge_x) - 1
            for x = s, e do
                table.insert(tiles, {x, gate_pos.y})
                table.insert(tiles, {x, gate_pos.y + 1})
                table.insert(tiles, {x, gate_pos.y - 1})
                table.insert(walls, {x, gate_pos.y + 1})
                table.insert(walls, {x, gate_pos.y - 1})
            end
        else
            local room_edge_y = dy > 0 and (cy - 7) or (cy + 7)
            local s = math.min(gate_pos.y, room_edge_y) + 1
            local e = math.max(gate_pos.y, room_edge_y) - 1
            for y = s, e do
                table.insert(tiles, {gate_pos.x, y})
                table.insert(tiles, {gate_pos.x + 1, y})
                table.insert(tiles, {gate_pos.x - 1, y})
                table.insert(walls, {gate_pos.x + 1, y})
                table.insert(walls, {gate_pos.x - 1, y})
            end
        end

        local renderings = render_preview(surface, player, tiles, walls)

        local gate_x, gate_y, conn_side
        if dx > 0 then gate_x, gate_y, conn_side = cx - 7, cy, "west"
        elseif dx < 0 then gate_x, gate_y, conn_side = cx + 7, cy, "east"
        elseif dy > 0 then gate_x, gate_y, conn_side = cx, cy - 7, "south"
        else gate_x, gate_y, conn_side = cx, cy + 7, "north"
        end
        table.insert(renderings, rendering.draw_sprite{
            sprite = "entity/gate",
            tint = WALL_GHOST,
            target = {position = {gate_x + 0.5, gate_y + 0.5},
                      rotation = side_is_vertical(conn_side) and 0 or math.pi / 2},
            surface = surface,
            players = {player},
        })

        for x = cx - 5, cx + 5 do
            for y = cy - 5, cy + 5 do
                table.insert(renderings, rendering.draw_rectangle{
                    color = {r = 0.5, g = 0.45, b = 0.4, a = 0.2},
                    left_top = {x, y + 1},
                    right_bottom = {x + 1, y},
                    filled = true,
                    surface = surface,
                    players = {player},
                })
            end
        end
        for x = cx - 4, cx + 4 do
            for y = cy - 4, cy + 4 do
                table.insert(renderings, rendering.draw_rectangle{
                    color = {r = 0.45, g = 0.35, b = 0.2, a = 0.2},
                    left_top = {x, y + 1},
                    right_bottom = {x + 1, y},
                    filled = true,
                    surface = surface,
                    players = {player},
                })
            end
        end
        table.insert(renderings, rendering.draw_rectangle{
            color = {r = 0.9, g = 0.2, b = 0.2, a = 0.25},
            left_top = {cx - 2.5, cy + 2.5},
            right_bottom = {cx + 2.5, cy - 2.5},
            filled = true,
            surface = surface,
            players = {player},
        })
        return renderings
    else
        return {}
    end

    return render_preview(surface, player, tiles, walls)
end

function M.clear_preview(objects)
    for _, obj in ipairs(objects) do
        if obj.valid then
            obj:destroy()
        end
    end
end

function M.expand_from_gate(surface, gate_pos, shape)
    shape = shape or "hub"

    local key = surface.name .. ":" .. gate_pos.x .. "," .. gate_pos.y
    local dir = platform_gates.get_gate_dir(key)
    if not dir then return false end

    if shape == "hub" then
        local CX, CY, conn_side
        if dir == "east" then CX, CY, conn_side = gate_pos.x + 9, gate_pos.y, "west"
        elseif dir == "west" then CX, CY, conn_side = gate_pos.x - 9, gate_pos.y, "east"
        elseif dir == "north" then CX, CY, conn_side = gate_pos.x, gate_pos.y + 9, "south"
        elseif dir == "south" then CX, CY, conn_side = gate_pos.x, gate_pos.y - 9, "north"
        else return false end

        local box = {{CX - 7, CY - 7}, {CX + 7, CY + 7}}
        local entities = surface.find_entities_filtered{area = box}
        for _, entity in ipairs(entities) do
            if entity.valid and entity.type ~= "item-on-ground" and entity.name ~= "tile-ghost" then
                return false, "Not enough space!"
            end
        end

        platform_gates.destroy_gate_control(key)

        local tiles, walls = hub_shape.get_positions(CX, CY, conn_side, gate_pos)
        apply_tiles(surface, tiles)
        apply_walls(surface, walls)

        for _, side in ipairs{"east", "west", "north", "south"} do
            local gx = CX + (side == "east" and 6 or side == "west" and -6 or 0)
            local gy = CY + (side == "north" and 6 or side == "south" and -6 or 0)
            local gate_entity = place_gate(surface, side, {gx, gy})
            local computer_entity
            if side ~= conn_side then
                computer_entity = place_computer(surface, gx, gy, side)
            end
            register_gate(gx, gy, side, gate_entity, computer_entity, surface.name)
        end

    elseif shape == "corridor" then
        local box = corridor_shape.get_bounding_box(gate_pos, dir)
        if not box then return false end

        local entities = surface.find_entities_filtered{area = box}
        for _, entity in ipairs(entities) do
            if entity.valid and entity.type ~= "item-on-ground" and entity.name ~= "tile-ghost" then
                return false, "Not enough space!"
            end
        end

        platform_gates.destroy_gate_control(key)

        local tiles, walls = corridor_shape.get_positions(gate_pos, dir)
        apply_tiles(surface, tiles)
        apply_walls(surface, walls)

        local conn_side, far_side
        if dir == "east" then conn_side, far_side = "west", "east"
        elseif dir == "west" then conn_side, far_side = "east", "west"
        elseif dir == "north" then conn_side, far_side = "south", "north"
        else conn_side, far_side = "north", "south"
        end

        if dir == "east" or dir == "west" then
            local s = (dir == "east") and 1 or -1
            local cgx = gate_pos.x + 3 * s
            local fgx = gate_pos.x + 24 * s
            local conn_gate = place_gate(surface, conn_side, {cgx, gate_pos.y})
            register_gate(cgx, gate_pos.y, conn_side, conn_gate, nil, surface.name)
            local far_gate = place_gate(surface, far_side, {fgx, gate_pos.y})
            local far_computer = place_computer(surface, fgx, gate_pos.y, far_side)
            register_gate(fgx, gate_pos.y, far_side, far_gate, far_computer, surface.name)
        else
            local s = (dir == "north") and 1 or -1
            local cgy = gate_pos.y + 3 * s
            local fgy = gate_pos.y + 24 * s
            local conn_gate = place_gate(surface, conn_side, {gate_pos.x, cgy})
            register_gate(gate_pos.x, cgy, conn_side, conn_gate, nil, surface.name)
            local far_gate = place_gate(surface, far_side, {gate_pos.x, fgy})
            local far_computer = place_computer(surface, gate_pos.x, fgy, far_side)
            register_gate(gate_pos.x, fgy, far_side, far_gate, far_computer, surface.name)
        end

    elseif shape == "factory" then
        local CX, CY, conn_side
        if dir == "east" then CX, CY, conn_side = gate_pos.x + 18, gate_pos.y, "west"
        elseif dir == "west" then CX, CY, conn_side = gate_pos.x - 19, gate_pos.y, "east"
        elseif dir == "north" then CX, CY, conn_side = gate_pos.x, gate_pos.y + 18, "south"
        elseif dir == "south" then CX, CY, conn_side = gate_pos.x, gate_pos.y - 19, "north"
        else return false end

        local box = factory_shape.get_bounding_box(CX, CY)
        local entities = surface.find_entities_filtered{area = box}
        for _, entity in ipairs(entities) do
            if entity.valid and entity.type ~= "item-on-ground" and entity.name ~= "tile-ghost" then
                return false, "Not enough space!"
            end
        end

        platform_gates.destroy_gate_control(key)

        local tiles, walls = factory_shape.get_positions(CX, CY, conn_side, gate_pos)
        apply_tiles(surface, tiles)
        apply_walls(surface, walls)

        local gx = CX + (conn_side == "east" and 16 or conn_side == "west" and -15 or 0)
        local gy = CY + (conn_side == "north" and 16 or conn_side == "south" and -15 or 0)
        local gate_entity = place_gate(surface, conn_side, {gx, gy})
        register_gate(gx, gy, conn_side, gate_entity, nil, surface.name)

    elseif shape == "iron_asteroid" then
        local box = iron_asteroid_shape.get_bounding_box(gate_pos, dir)
        if not box then return false end

        local entities = surface.find_entities_filtered{area = box}
        for _, entity in ipairs(entities) do
            if entity.valid and entity.type ~= "item-on-ground" and entity.name ~= "tile-ghost" then
                return false, "Not enough space!"
            end
        end

        platform_gates.destroy_gate_control(key)

        local tiles, resources, walls = iron_asteroid_shape.get_positions(gate_pos, dir)
        apply_custom_tiles(surface, tiles, true)
        place_resources(surface, resources)
        apply_walls(surface, walls)

        local gate_pos2 = iron_asteroid_shape.get_gate_pos(gate_pos, dir)
        if gate_pos2 then
            local asteroid_gate = place_gate(surface, dir, gate_pos2)
            register_gate(gate_pos2.x, gate_pos2.y, dir, asteroid_gate, nil, surface.name)
        end

    elseif shape == "copper_asteroid" then
        local box = copper_asteroid_shape.get_bounding_box(gate_pos, dir)
        if not box then return false end

        local entities = surface.find_entities_filtered{area = box}
        for _, entity in ipairs(entities) do
            if entity.valid and entity.type ~= "item-on-ground" and entity.name ~= "tile-ghost" then
                return false, "Not enough space!"
            end
        end

        platform_gates.destroy_gate_control(key)

        local tiles, resources, walls = copper_asteroid_shape.get_positions(gate_pos, dir)
        apply_custom_tiles(surface, tiles, true)
        place_resources(surface, resources)
        apply_walls(surface, walls)

        local gate_pos2 = copper_asteroid_shape.get_gate_pos(gate_pos, dir)
        if gate_pos2 then
            local asteroid_gate = place_gate(surface, dir, gate_pos2)
            register_gate(gate_pos2.x, gate_pos2.y, dir, asteroid_gate, nil, surface.name)
        end

    elseif shape == "water_connection" then
        local CX, CY, conn_side
        if dir == "east" then CX, CY, conn_side = gate_pos.x + 5, gate_pos.y, "west"
        elseif dir == "west" then CX, CY, conn_side = gate_pos.x - 5, gate_pos.y, "east"
        elseif dir == "north" then CX, CY, conn_side = gate_pos.x, gate_pos.y + 5, "south"
        elseif dir == "south" then CX, CY, conn_side = gate_pos.x, gate_pos.y - 5, "north"
        else return false end

        local min_x, max_x, min_y, max_y
        if dir == "east" then
            min_x, max_x = gate_pos.x + 1, CX + 4
            min_y, max_y = CY - 4, CY + 4
        elseif dir == "west" then
            min_x, max_x = CX - 4, gate_pos.x - 1
            min_y, max_y = CY - 4, CY + 4
        elseif dir == "north" then
            min_x, max_x = CX - 4, CX + 4
            min_y, max_y = gate_pos.y + 1, CY + 4
        else
            min_x, max_x = CX - 4, CX + 4
            min_y, max_y = CY - 4, gate_pos.y - 1
        end

        for _, entity in ipairs(surface.find_entities_filtered{area = {{min_x, min_y}, {max_x + 1, max_y + 1}}}) do
            if entity.valid and entity.type ~= "character" then entity.destroy() end
        end

        platform_gates.destroy_gate_control(key)

        local tiles, walls = water_connection_shape.get_positions(CX, CY, conn_side, gate_pos)
        apply_tiles(surface, tiles)
        apply_walls(surface, walls)

        local dir_to_defines = {
            east = defines.direction.east, west = defines.direction.west,
            north = defines.direction.south, south = defines.direction.north,
        }
        local pump = surface.create_entity{
            name = "otc-water-pump",
            position = {CX, CY},
            direction = dir_to_defines[dir],
            force = "player",
            create_build_effect_smoke = false,
        }
        if pump then
            pump.minable = false
            pump.destructible = false
        end

    elseif shape == "orbital_station" then
        local dx, dy
        if dir == "east" then dx, dy = 1, 0
        elseif dir == "west" then dx, dy = -1, 0
        elseif dir == "north" then dx, dy = 0, 1
        elseif dir == "south" then dx, dy = 0, -1
        else return false end

        local cx = gate_pos.x + dx * 9
        local cy = gate_pos.y + dy * 9

        local min_x = dx ~= 0 and (dx > 0 and gate_pos.x + 1 or cx - 7) or cx - 7
        local max_x = dx ~= 0 and (dx > 0 and cx + 7 or gate_pos.x - 1) or cx + 7
        local min_y = dy ~= 0 and (dy > 0 and gate_pos.y + 1 or cy - 7) or cy - 7
        local max_y = dy ~= 0 and (dy > 0 and cy + 7 or gate_pos.y - 1) or cy + 7

        for _, entity in ipairs(surface.find_entities_filtered{area = {{min_x, min_y}, {max_x + 1, max_y + 1}}}) do
            if entity.valid and entity.type ~= "character" then entity.destroy() end
        end

        platform_gates.destroy_gate_control(key)

        local tiles = {}

        for x = cx - 7, cx + 7 do
            for y = cy - 7, cy + 7 do
                table.insert(tiles, {name = "otc-platform", position = {x, y}})
            end
        end

        if dx ~= 0 then
            local room_edge_x = dx > 0 and (cx - 7) or (cx + 7)
            local s = math.min(gate_pos.x, room_edge_x) + 1
            local e = math.max(gate_pos.x, room_edge_x) - 1
            for x = s, e do
                for y = gate_pos.y - 1, gate_pos.y + 1 do
                    table.insert(tiles, {name = "otc-platform", position = {x, y}})
                end
            end
        else
            local room_edge_y = dy > 0 and (cy - 7) or (cy + 7)
            local s = math.min(gate_pos.y, room_edge_y) + 1
            local e = math.max(gate_pos.y, room_edge_y) - 1
            for y = s, e do
                for x = gate_pos.x - 1, gate_pos.x + 1 do
                    table.insert(tiles, {name = "otc-platform", position = {x, y}})
                end
            end
        end

        surface.set_tiles(tiles, true)

        local concrete_tiles = {}
        for x = cx - 5, cx + 5 do
            for y = cy - 5, cy + 5 do
                table.insert(concrete_tiles, {name = "concrete", position = {x, y}})
            end
        end
        surface.set_tiles(concrete_tiles, true)

        local hazard_tiles = {}
        for x = cx - 4, cx + 4 do
            for y = cy - 4, cy + 4 do
                table.insert(hazard_tiles, {name = "refined-hazard-concrete-left", position = {x, y}})
            end
        end
        surface.set_tiles(hazard_tiles, true)

        local wall_positions = {}

        for y = cy - 7, cy + 7 do
            if not (dx > 0 and y == cy) then
                table.insert(wall_positions, {cx - 7, y})
            end
            if not (dx < 0 and y == cy) then
                table.insert(wall_positions, {cx + 7, y})
            end
        end
        for x = cx - 7, cx + 7 do
            if not (dy > 0 and x == cx) then
                table.insert(wall_positions, {x, cy - 7})
            end
            if not (dy < 0 and x == cx) then
                table.insert(wall_positions, {x, cy + 7})
            end
        end

        if dx ~= 0 then
            local room_edge_x = dx > 0 and (cx - 7) or (cx + 7)
            local s = math.min(gate_pos.x, room_edge_x) + 1
            local e = math.max(gate_pos.x, room_edge_x) - 1
            for x = s, e do
                table.insert(wall_positions, {x, gate_pos.y + 1})
                table.insert(wall_positions, {x, gate_pos.y - 1})
            end
        else
            local room_edge_y = dy > 0 and (cy - 7) or (cy + 7)
            local s = math.min(gate_pos.y, room_edge_y) + 1
            local e = math.max(gate_pos.y, room_edge_y) - 1
            for y = s, e do
                table.insert(wall_positions, {gate_pos.x + 1, y})
                table.insert(wall_positions, {gate_pos.x - 1, y})
            end
        end

        local conn_side
        local gate_x, gate_y
        if dx > 0 then gate_x, gate_y, conn_side = cx - 7, cy, "west"
        elseif dx < 0 then gate_x, gate_y, conn_side = cx + 7, cy, "east"
        elseif dy > 0 then gate_x, gate_y, conn_side = cx, cy - 7, "south"
        else gate_x, gate_y, conn_side = cx, cy + 7, "north"
        end

        apply_walls(surface, wall_positions)

        local gate_entity = place_gate(surface, conn_side, {gate_x, gate_y})
        register_gate(gate_x, gate_y, conn_side, gate_entity, nil, surface.name)

        local silo = surface.create_entity{
            name = "rocket-silo",
            position = {cx, cy},
            force = "player",
        }
        if silo then
            silo.minable = false
            silo.destructible = false
        end

        if not storage.otc_station_index then storage.otc_station_index = 0 end
        storage.otc_station_index = storage.otc_station_index + 1
        local station_name = "otc-station-" .. storage.otc_station_index
        log("orbital_station: creating surface " .. station_name)

        local station_surface = game.create_surface(station_name, {
            peaceful_mode = true,
            width = 0,
            height = 0,
            starting_area = 0,
            terrain_segmentation = 0,
            water = 0,
            autoplace_controls = {},
            autoplace_settings = {
                tile = { settings = {["out-of-map"] = {}}, treat_missing_as_default = false },
                decorative = { settings = {}, treat_missing_as_default = false },
                entity = { settings = {}, treat_missing_as_default = false },
            },
        })
        log("orbital_station: surface created, requesting chunk generation")
        station_surface.request_to_generate_chunks({0, 0}, 4)
        station_surface.force_generate_chunk_requests()
        log("orbital_station: chunk generation done, building platform")
        local station_tiles = {}
        for x = -7, 7 do
            for y = -7, 7 do
                table.insert(station_tiles, {name = "otc-platform", position = {x, y}})
            end
        end
        station_surface.set_tiles(station_tiles, false)

        local station_ext_tiles = {}
        for x = -1, 1 do
            table.insert(station_ext_tiles, {name = "refined-concrete", position = {x, 8}})
        end
        station_surface.set_tiles(station_ext_tiles, false)

        local station_concrete = {}
        for x = -5, 5 do
            for y = -5, 5 do
                table.insert(station_concrete, {name = "concrete", position = {x, y}})
            end
        end
        station_surface.set_tiles(station_concrete, false)

        local station_hazard = {}
        for x = -4, 4 do
            for y = -4, 4 do
                table.insert(station_hazard, {name = "refined-hazard-concrete-left", position = {x, y}})
            end
        end
        station_surface.set_tiles(station_hazard, false)

        for y = -7, 7 do
            place_wall(station_surface, {-7, y})
            place_wall(station_surface, {7, y})
        end
        for x = -7, 7 do
            place_wall(station_surface, {x, -7})
            if x ~= 0 then
                place_wall(station_surface, {x, 7})
            end
        end

        for _, pos in ipairs{{-7, 0}, {7, 0}, {0, -7}} do
            local existing = station_surface.find_entity("otc-platform-wall", pos)
            if not existing then
                local w = station_surface.create_entity{name = "otc-platform-wall", position = pos, force = "player"}
                if w then w.minable = false; w.destructible = false end
            end
        end

        for _, pos in ipairs{{-1, 8}, {1, 8}} do
            local existing = station_surface.find_entity("otc-platform-wall", pos)
            if not existing then
                local w = station_surface.create_entity{name = "otc-platform-wall", position = pos, force = "player"}
                if w then w.minable = false; w.destructible = false end
            end
        end

        local station_gate = place_gate(station_surface, "south", {0, 7})
        local station_computer = try_create(station_surface.create_entity{
            name = "otc-gate-computer",
            position = {0, 8},
            force = "player",
        })
        register_gate(0, 7, "north", station_gate, station_computer, station_name)

        local station_silo = station_surface.create_entity{
            name = "rocket-silo",
            position = {0, 0},
            force = "player",
        }
        if station_silo then
            station_silo.minable = false
            station_silo.destructible = false
            storage.rocket_silos = storage.rocket_silos or {}
            storage.rocket_silos[station_silo.unit_number] = station_name
        end

        local buy = station_surface.create_entity{
            name = "otc-buy-chest",
            position = {-6, 6},
            force = "player",
        }
        if buy then
            buy.minable = false
            buy.destructible = false
            buy_chest.register(buy)
        end

        local combinator = station_surface.create_entity{
            name = "constant-combinator",
            position = {-6, 5},
            force = "player",
        }
        if combinator and buy then
            combinator.minable = false
            combinator.destructible = false
            local cw = combinator.get_wire_connector(defines.wire_connector_id.circuit_green, false)
            local bw = buy.get_wire_connector(defines.wire_connector_id.circuit_green, false)
            if cw and bw then
                ---@diagnostic disable-next-line: undefined-field
                cw.connect_to(bw)
            end
        end

        local sell = station_surface.create_entity{
            name = "otc-sell-chest",
            position = {6, 6},
            force = "player",
        }
        if sell then
            sell.minable = false
            sell.destructible = false
            sell_chest.register(sell)
        end

        if silo then
            storage.rocket_silos = storage.rocket_silos or {}
            storage.rocket_silos[silo.unit_number] = station_name
        end

        local teleporter_pos
        local teleporter_dir
        if dx > 0 then
            teleporter_pos = {cx - 5, cy}
            teleporter_dir = defines.direction.north
        elseif dx < 0 then
            teleporter_pos = {cx + 5, cy}
            teleporter_dir = defines.direction.south
        elseif dy > 0 then
            teleporter_pos = {cx, cy - 5}
            teleporter_dir = defines.direction.east
        else
            teleporter_pos = {cx, cy + 5}
            teleporter_dir = defines.direction.west
        end
        local teleporter = surface.create_entity{
            name = "otc-teleporter",
            position = teleporter_pos,
            direction = teleporter_dir,
            force = "player",
        }
        if teleporter then
            storage.otc_teleporters = storage.otc_teleporters or {}
            storage.otc_teleporters[teleporter.unit_number] = station_name
        end

        local return_teleporter = station_surface.create_entity{
            name = "otc-teleporter",
            position = {0, 5},
            direction = defines.direction.west,
            force = "player",
        }
        if return_teleporter then
            local return_pos
            if dx > 0 then
                return_pos = {teleporter_pos[1], teleporter_pos[2] + 1}
            elseif dx < 0 then
                return_pos = {teleporter_pos[1], teleporter_pos[2] - 1}
            elseif dy > 0 then
                return_pos = {teleporter_pos[1] - 1, teleporter_pos[2]}
            else
                return_pos = {teleporter_pos[1] + 1, teleporter_pos[2]}
            end
            storage.otc_return_teleporters = storage.otc_return_teleporters or {}
            storage.otc_return_teleporters[return_teleporter.unit_number] = {
                surface = "nauvis",
                position = return_pos,
            }
        end

    else
        return false
    end

    return true
end

return M
