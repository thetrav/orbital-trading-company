local M = {}

local AIRLOCKS = {
    east = {
        gate = {x = 6, y = 0},
        computer = {x = 7, y = 0},
        walls = {{x = 7, y = 1}, {x = 7, y = -1}},
        gate_dir = defines.direction.north,
    },
    west = {
        gate = {x = -6, y = 0},
        computer = {x = -7, y = 0},
        walls = {{x = -7, y = 1}, {x = -7, y = -1}},
        gate_dir = defines.direction.north,
    },
    north = {
        gate = {x = 0, y = 6},
        computer = {x = 0, y = 7},
        walls = {{x = 1, y = 7}, {x = -1, y = 7}},
        gate_dir = defines.direction.east,
    },
    south = {
        gate = {x = 0, y = -6},
        computer = {x = 0, y = -7},
        walls = {{x = 1, y = -7}, {x = -1, y = -7}},
        gate_dir = defines.direction.east,
    },
}

function M.get_airlock(dir)
    return AIRLOCKS[dir]
end

function M.is_airlock_position(x, y)
    for _, a in pairs(AIRLOCKS) do
        if a.gate.x == x and a.gate.y == y then return true end
        if a.computer.x == x and a.computer.y == y then return true end
        for _, w in ipairs(a.walls) do
            if w.x == x and w.y == y then return true end
        end
    end
    return false
end

function M.is_entity_position(x, y)
    for _, a in pairs(AIRLOCKS) do
        if a.gate.x == x and a.gate.y == y then return true end
        if a.computer.x == x and a.computer.y == y then return true end
    end
    return false
end

function M.get_gate_dir(key)
    if storage.gates and storage.gates[key] then
        return storage.gates[key].dir
    end
    for dir, a in pairs(AIRLOCKS) do
        if a.gate.x .. "," .. a.gate.y == key then return dir end
    end
    return nil
end

function M.init_gates()
    if not storage.gates then storage.gates = {} end
    if not storage.gates_by_id then storage.gates_by_id = {} end
    for dir, a in pairs(AIRLOCKS) do
        local key = a.gate.x .. "," .. a.gate.y
        if not storage.gates[key] then
            storage.gates[key] = {
                pos = {x = a.gate.x, y = a.gate.y},
                key = key,
                dir = dir,
                expanded = false,
                gate_unit_number = nil,
                computer_unit_number = nil,
            }
        end
    end
end

function M.place_gate_controls(surface)
    for _, gate in pairs(storage.gates) do
        local a = AIRLOCKS[gate.dir]
        if not a then return end

        local gate_entity = surface.create_entity {
            name = "gate",
            position = a.gate,
            force = "player",
            direction = a.gate_dir,
            create_build_effect_smoke = false,
        }
        if gate_entity then
            gate_entity.minable = false
            gate_entity.destructible = false
            gate.gate_unit_number = gate_entity.unit_number
        end

        local computer = surface.create_entity {
            name = "otc-gate-computer",
            position = a.computer,
            force = "player",
        }
        if computer then
            computer.minable = false
            computer.destructible = false
            gate.computer_unit_number = computer.unit_number
            storage.gates_by_id[computer.unit_number] = gate
        end
    end
end

function M.get_gate_by_unit(unit_number)
    return storage.gates_by_id and storage.gates_by_id[unit_number]
end

function M.destroy_gate_control(key)
    local gate = storage.gates and storage.gates[key]
    if gate and gate.computer_unit_number then
        local computer = game.get_entity_by_unit_number(gate.computer_unit_number)
        if computer and computer.valid then
            computer.destroy()
        end
    end
end

function M.register_events(register, expand_gui_ref)
    register(defines.events.on_gui_opened, function(event)
        local entity = event.entity
        if not entity or entity.name ~= "otc-gate-computer" then return end
        local player = game.get_player(event.player_index)
        if not player then return end

        player.opened = nil

        local dx = player.position.x - entity.position.x
        local dy = player.position.y - entity.position.y
        if dx * dx + dy * dy > 25 then
            player.print("Too far from the gate!")
            return
        end
        local gate = M.get_gate_by_unit(entity.unit_number)
        if gate and not gate.expanded then
            expand_gui_ref.show_for_gate(player, gate)
        end
    end)
end

return M