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

-- Shared helpers
local function add_tile(tiles, p)
    table.insert(tiles, {name = "otc-platform", position = p})
end

local function add_wall(walls, p)
    table.insert(walls, p)
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

-- Hub shape: 11x11 inner with wall border at ±6, 4 airlocks
local function build_hub(surface, cx, cy, conn_side)
    local tiles = {}
    local walls = {}

    for x = cx - 5, cx + 5 do
        for y = cy - 5, cy + 5 do
            add_tile(tiles, {x, y})
        end
    end

    local function wall_side(vertical, coord, has_gap)
        if vertical then
            for y = cy - 6, cy + 6 do
                add_tile(tiles, {coord, y})
                if not (has_gap and y == cy) then add_wall(walls, {coord, y}) end
            end
        else
            for x = cx - 6, cx + 6 do
                add_tile(tiles, {x, coord})
                if not (has_gap and x == cx) then add_wall(walls, {x, coord}) end
            end
        end
    end

    wall_side(true, cx - 6, true)
    wall_side(true, cx + 6, true)
    wall_side(false, cy - 6, true)
    wall_side(false, cy + 6, true)

    for _, side in ipairs{"east", "west", "north", "south"} do
        if side_is_vertical(side) then
            local ax = cx + (side == "east" and 7 or -7)
            add_tile(tiles, {ax, cy}); add_tile(tiles, {ax, cy + 1}); add_tile(tiles, {ax, cy - 1})
            add_wall(walls, {ax, cy + 1}); add_wall(walls, {ax, cy - 1})
        else
            local ay = cy + (side == "north" and 7 or -7)
            add_tile(tiles, {cx, ay}); add_tile(tiles, {cx + 1, ay}); add_tile(tiles, {cx - 1, ay})
            add_wall(walls, {cx + 1, ay}); add_wall(walls, {cx - 1, ay})
        end
    end

    surface.set_tiles(tiles, false)
    for _, pos in ipairs(walls) do
        place_wall(surface, pos)
    end

    for _, side in ipairs{"east", "west", "north", "south"} do
        local gx = cx + (side == "east" and 6 or side == "west" and -6 or 0)
        local gy = cy + (side == "north" and 6 or side == "south" and -6 or 0)
        local gate_entity = place_gate(surface, side, {gx, gy})
        local computer_entity
        if not conn_side or side ~= conn_side then
            computer_entity = place_computer(surface, gx, gy, side)
        end
        register_gate(gx, gy, side, gate_entity, computer_entity)
    end
end

-- Corridor shape: 20x3 inner, airlocks on both narrow ends, walls on long sides
local function build_corridor(surface, gate_pos, dir)
    local gx, gy = gate_pos.x, gate_pos.y
    local tiles = {}
    local walls = {}

    local conn_side, far_side
    if dir == "east" then conn_side, far_side = "west", "east"
    elseif dir == "west" then conn_side, far_side = "east", "west"
    elseif dir == "north" then conn_side, far_side = "south", "north"
    else conn_side, far_side = "north", "south"
    end

    if dir == "east" or dir == "west" then
        local s = (dir == "east") and 1 or -1
        local cgx = gx + 3 * s
        local fgx = gx + 24 * s
        local cx = gx + 25 * s

        add_tile(tiles, {gx + s, gy}); add_tile(tiles, {gx + 2*s, gy})
        add_tile(tiles, {gx + s, gy+1}); add_tile(tiles, {gx + s, gy-1})
        add_tile(tiles, {gx + 2*s, gy+1}); add_tile(tiles, {gx + 2*s, gy-1})
        add_wall(walls, {gx + s, gy+1}); add_wall(walls, {gx + s, gy-1})
        add_wall(walls, {gx + 2*s, gy+1}); add_wall(walls, {gx + 2*s, gy-1})

        for y = gy-2, gy+2 do
            add_tile(tiles, {cgx, y})
            if y ~= gy then add_wall(walls, {cgx, y}) end
        end

        local lo = math.min(cgx, fgx)
        local hi = math.max(cgx, fgx)
        for x = lo + 1, hi - 1 do
            for y = gy-1, gy+1 do add_tile(tiles, {x, y}) end
        end

        for x = lo, hi do
            add_tile(tiles, {x, gy+2}); add_tile(tiles, {x, gy-2})
            add_wall(walls, {x, gy+2}); add_wall(walls, {x, gy-2})
        end

        for y = gy-2, gy+2 do
            add_tile(tiles, {fgx, y})
            if y ~= gy then add_wall(walls, {fgx, y}) end
        end

        add_tile(tiles, {cx, gy}); add_tile(tiles, {cx, gy+1}); add_tile(tiles, {cx, gy-1})
        add_wall(walls, {cx, gy+1}); add_wall(walls, {cx, gy-1})

        surface.set_tiles(tiles, false)
        for _, pos in ipairs(walls) do
            place_wall(surface, pos)
        end

        local conn_gate = place_gate(surface, conn_side, {cgx, gy})
        register_gate(cgx, gy, conn_side, conn_gate)

        local far_gate = place_gate(surface, far_side, {fgx, gy})
        local far_computer = place_computer(surface, fgx, gy, far_side)
        register_gate(fgx, gy, far_side, far_gate, far_computer)

    else
        local s = (dir == "north") and 1 or -1
        local cgy = gy + 3 * s
        local fgy = gy + 24 * s
        local cy = gy + 25 * s

        add_tile(tiles, {gx, gy + s}); add_tile(tiles, {gx, gy + 2*s})
        add_tile(tiles, {gx+1, gy + s}); add_tile(tiles, {gx-1, gy + s})
        add_tile(tiles, {gx+1, gy + 2*s}); add_tile(tiles, {gx-1, gy + 2*s})
        add_wall(walls, {gx+1, gy + s}); add_wall(walls, {gx-1, gy + s})
        add_wall(walls, {gx+1, gy + 2*s}); add_wall(walls, {gx-1, gy + 2*s})

        for x = gx-2, gx+2 do
            add_tile(tiles, {x, cgy})
            if x ~= gx then add_wall(walls, {x, cgy}) end
        end

        local lo = math.min(cgy, fgy)
        local hi = math.max(cgy, fgy)
        for y = lo + 1, hi - 1 do
            for x = gx-1, gx+1 do add_tile(tiles, {x, y}) end
        end

        for y = lo, hi do
            add_tile(tiles, {gx+2, y}); add_tile(tiles, {gx-2, y})
            add_wall(walls, {gx+2, y}); add_wall(walls, {gx-2, y})
        end

        for x = gx-2, gx+2 do
            add_tile(tiles, {x, fgy})
            if x ~= gx then add_wall(walls, {x, fgy}) end
        end

        add_tile(tiles, {gx, cy}); add_tile(tiles, {gx+1, cy}); add_tile(tiles, {gx-1, cy})
        add_wall(walls, {gx+1, cy}); add_wall(walls, {gx-1, cy})

        surface.set_tiles(tiles, false)
        for _, pos in ipairs(walls) do
            place_wall(surface, pos)
        end

        local conn_gate = place_gate(surface, conn_side, {gx, cgy})
        register_gate(gx, cgy, conn_side, conn_gate)

        local far_gate = place_gate(surface, far_side, {gx, fgy})
        local far_computer = place_computer(surface, gx, fgy, far_side)
        register_gate(gx, fgy, far_side, far_gate, far_computer)
    end
end

function M.expand_from_gate(surface, gate_pos, shape)
    shape = shape or "hub"

    local key = gate_pos.x .. "," .. gate_pos.y
    local dir = platform_gates.get_gate_dir(key)
    if not dir then return false end

    local box
    if shape == "hub" then
        local CX, CY
        if dir == "east" then CX, CY = gate_pos.x + 9, gate_pos.y
        elseif dir == "west" then CX, CY = gate_pos.x - 9, gate_pos.y
        elseif dir == "north" then CX, CY = gate_pos.x, gate_pos.y + 9
        elseif dir == "south" then CX, CY = gate_pos.x, gate_pos.y - 9
        else return false end
        box = {{CX - 7, CY - 7}, {CX + 7, CY + 7}}
    elseif shape == "corridor" then
        if dir == "east" then box = {{gate_pos.x + 2, gate_pos.y - 2}, {gate_pos.x + 25, gate_pos.y + 2}}
        elseif dir == "west" then box = {{gate_pos.x - 25, gate_pos.y - 2}, {gate_pos.x - 2, gate_pos.y + 2}}
        elseif dir == "north" then box = {{gate_pos.x - 2, gate_pos.y + 2}, {gate_pos.x + 2, gate_pos.y + 25}}
        elseif dir == "south" then box = {{gate_pos.x - 2, gate_pos.y - 25}, {gate_pos.x + 2, gate_pos.y - 2}}
        else return false end
    else
        return false
    end

    local entities = surface.find_entities_filtered{area = box}
    for _, entity in ipairs(entities) do
        if entity.valid and entity.type ~= "item-on-ground" and entity.name ~= "tile-ghost" then
            return false, "Not enough space!"
        end
    end

    platform_gates.destroy_gate_control(key)

    if shape == "hub" then
        local CX, CY, conn_side
        if dir == "east" then CX, CY, conn_side = gate_pos.x + 9, gate_pos.y, "west"
        elseif dir == "west" then CX, CY, conn_side = gate_pos.x - 9, gate_pos.y, "east"
        elseif dir == "north" then CX, CY, conn_side = gate_pos.x, gate_pos.y + 9, "south"
        elseif dir == "south" then CX, CY, conn_side = gate_pos.x, gate_pos.y - 9, "north"
        end

        build_hub(surface, CX, CY, conn_side)

        local conn_gx = CX + (conn_side == "east" and 6 or conn_side == "west" and -6 or 0)
        local conn_gy = CY + (conn_side == "north" and 6 or conn_side == "south" and -6 or 0)

        if side_is_vertical(conn_side) then
            local s = math.min(gate_pos.x, conn_gx) + 1
            local e = math.max(gate_pos.x, conn_gx) - 1
            local tiles = {}
            local walls = {}
            for x = s, e do
                add_tile(tiles, {x, gate_pos.y})
                add_tile(tiles, {x, gate_pos.y + 1}); add_tile(tiles, {x, gate_pos.y - 1})
                add_wall(walls, {x, gate_pos.y + 1}); add_wall(walls, {x, gate_pos.y - 1})
            end
            surface.set_tiles(tiles, false)
            for _, pos in ipairs(walls) do
                place_wall(surface, pos)
            end
        else
            local s = math.min(gate_pos.y, conn_gy) + 1
            local e = math.max(gate_pos.y, conn_gy) - 1
            local tiles = {}
            local walls = {}
            for y = s, e do
                add_tile(tiles, {gate_pos.x, y})
                add_tile(tiles, {gate_pos.x + 1, y}); add_tile(tiles, {gate_pos.x - 1, y})
                add_wall(walls, {gate_pos.x + 1, y}); add_wall(walls, {gate_pos.x - 1, y})
            end
            surface.set_tiles(tiles, false)
            for _, pos in ipairs(walls) do
                place_wall(surface, pos)
            end
        end

    elseif shape == "corridor" then
        build_corridor(surface, gate_pos, dir)
    end

    return true
end

return M
