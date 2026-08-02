local platform_gates = require("scripts.platform_gates")

local M = {}

function M.is_nauvis(surface)
    return surface.name == "nauvis"
end

--- Everything otc places on Nauvis belongs to the Nauvis force, except the
--- teleporter, which has to belong to the company using it. `owned` is the
--- opt-out a company's own ground facilities take: the whole shape belongs to
--- the company, and it has to be the *whole* shape, because a gate only joins
--- up with walls on its own force.
function M.get_surface_force(surface, force_name, entity_type, owned)
    if owned then return force_name or "player" end
    if M.is_nauvis(surface) then
        if entity_type == "teleporter" then
            return force_name or "player"
        end
        return "Nauvis"
    end
    return force_name or "player"
end

function M.fix(entity)
    if entity then
        entity.minable = false
        entity.destructible = false
    end
    return entity
end

function M.side_is_vertical(side)
    return side == "east" or side == "west"
end

function M.place_wall(surface, pos, force_name, owned)
    force_name = M.get_surface_force(surface, force_name, "wall", owned)
    if platform_gates.is_entity_position(pos[1], pos[2]) then return end
    local existing = surface.find_entity("otc-platform-wall", pos)
    if existing then return existing end
    return M.fix(surface.create_entity {
        name = "otc-platform-wall",
        position = pos,
        force = force_name,
    })
end

function M.place_gate(surface, side, pos, force_name, owned)
    force_name = M.get_surface_force(surface, force_name, "gate", owned) or "nauvis"
    return M.fix(surface.create_entity {
        name = "gate",
        position = pos,
        force = force_name,
        direction = M.side_is_vertical(side) and defines.direction.north or defines.direction.east,
        create_build_effect_smoke = false,
    })
end

--- Gate computers merge with an adjacent one rather than stacking up, so a
--- newly built room does not leave a stale computer behind on the shared wall.
function M.place_computer(surface, gx, gy, side, force_name, owned)
    force_name = M.get_surface_force(surface, force_name, "computer", owned) or "nauvis"
    local cdx = (side == "east" and 1) or (side == "west" and -1) or 0
    local cdy = (side == "north" and 1) or (side == "south" and -1) or 0
    local pos = { gx + cdx, gy + cdy }

    local function destroy_at(p)
        local box = { { p[1] - 1, p[2] - 1 }, { p[1] + 1, p[2] + 1 } }
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
    for _, d in ipairs { { -1, 0 }, { 1, 0 }, { 0, -1 }, { 0, 1 } } do
        if destroy_at({ pos[1] + d[1], pos[2] + d[2] }) then joined = true end
    end
    if joined then return nil end

    return M.fix(surface.create_entity {
        name = "otc-gate-computer",
        position = pos,
        force = force_name,
    })
end

function M.register_gate(gx, gy, side, gate_entity, computer_entity, surface_name)
    local gkey = surface_name .. ":" .. gx .. "," .. gy
    if storage.gates[gkey] then return storage.gates[gkey] end
    storage.gates[gkey] = {
        pos = { x = gx, y = gy },
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
    return storage.gates[gkey]
end

--- Destroy everything (except players) inside a world box, used by shapes that
--- declare `clear_area`.
function M.clear_area(surface, box)
    local area = { { box[1][1], box[1][2] }, { box[2][1] + 1, box[2][2] + 1 } }
    for _, entity in ipairs(surface.find_entities_filtered { area = area }) do
        if entity.valid and entity.type ~= "character" then entity.destroy() end
    end
end

return M
