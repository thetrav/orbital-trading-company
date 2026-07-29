local M = {}

local platform_gates = require("scripts.platform_gates")
local hub_shape = require("scripts.shapes.hub")
local corridor_shape = require("scripts.shapes.corridor")
local factory_shape = require("scripts.shapes.factory")

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

local function register_gate(gx, gy, side, gate_entity, computer_entity)
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

local TILE_GHOST = {r = 0, g = 0.1, b = 0.3, a = 0.12}
local WALL_GHOST = {r = 0.9, g = 0.9, b = 1, a = 0.85}

local function render_preview(surface, player, tiles, walls)
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
    return renderings
end

function M.show_preview(surface, player, gate_pos, shape)
    local key = gate_pos.x .. "," .. gate_pos.y
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

    local key = gate_pos.x .. "," .. gate_pos.y
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
            register_gate(gx, gy, side, gate_entity, computer_entity)
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
            register_gate(cgx, gate_pos.y, conn_side, conn_gate)
            local far_gate = place_gate(surface, far_side, {fgx, gate_pos.y})
            local far_computer = place_computer(surface, fgx, gate_pos.y, far_side)
            register_gate(fgx, gate_pos.y, far_side, far_gate, far_computer)
        else
            local s = (dir == "north") and 1 or -1
            local cgy = gate_pos.y + 3 * s
            local fgy = gate_pos.y + 24 * s
            local conn_gate = place_gate(surface, conn_side, {gate_pos.x, cgy})
            register_gate(gate_pos.x, cgy, conn_side, conn_gate)
            local far_gate = place_gate(surface, far_side, {gate_pos.x, fgy})
            local far_computer = place_computer(surface, gate_pos.x, fgy, far_side)
            register_gate(gate_pos.x, fgy, far_side, far_gate, far_computer)
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
        register_gate(gx, gy, conn_side, gate_entity)

    else
        return false
    end

    return true
end

return M
