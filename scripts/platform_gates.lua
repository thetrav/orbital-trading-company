local M = {}

local GATE_DIRS = {
    ["6,0"] = "east",
    ["-6,0"] = "west",
    ["0,6"] = "north",
    ["0,-6"] = "south",
}

function M.is_gate_position(x, y)
    return GATE_DIRS[x .. "," .. y] ~= nil
end

function M.get_gate_dir(key)
    return GATE_DIRS[key]
end

function M.get_gate_positions()
    local positions = {}
    for key, _ in pairs(GATE_DIRS) do
        local x, y = key:match("^(-?[%d]+),(-?[%d]+)$")
        positions[#positions + 1] = {x = tonumber(x), y = tonumber(y)}
    end
    return positions
end

function M.init_gates()
    storage.gates = {}
    storage.gates_by_id = {}
    for _, pos in ipairs(M.get_gate_positions()) do
        local key = pos.x .. "," .. pos.y
        storage.gates[key] = {
            pos = pos,
            key = key,
            expanded = false,
        }
    end
end

function M.place_gate_controls(surface)
    for _, gate in pairs(storage.gates) do
        local ctrl = surface.create_entity {
            name = "otc-gate-control",
            position = gate.pos,
            force = "player",
        }
        if ctrl then
            ctrl.minable = false
            ctrl.destructible = false
            storage.gates_by_id[ctrl.unit_number] = gate
        end
    end
end

function M.get_gate_by_unit(unit_number)
    return storage.gates_by_id and storage.gates_by_id[unit_number]
end

function M.destroy_gate_control(surface, pos)
    local ctrl = surface.find_entity("otc-gate-control", pos)
    if ctrl then ctrl.destroy() end
end

return M
