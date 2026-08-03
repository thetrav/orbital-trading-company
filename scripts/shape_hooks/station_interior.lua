local room_builder = require("scripts.room_builder")
local room_gates = require("scripts.shape_hooks.room_gates")
local trading_silo = require("scripts.trading_silo")

local M = {}

local function first(ctx, role)
    local bucket = ctx.roles[role]
    return bucket and bucket[1]
end

--- The orbital station's own surface: the trading silo and the return trip.
--- ctx.station_name and ctx.return_target are supplied by the caller.
function M.run(ctx)
    local surface = ctx.surface

    for _, entry in ipairs(ctx.roles.gate or {}) do
        local gx, gy = room_gates.tile_of(entry.def.position)
        local gate = room_builder.place_gate(surface, entry.def.side, { gx, gy }, ctx.force_name)
        local computer
        local computer_def = first(ctx, "computer")
        if computer_def then
            computer = room_builder.fix(surface.create_entity {
                name = "otc-gate-computer",
                position = computer_def.def.position,
                force = ctx.force_name,
            })
        end
        -- Registered facing north: the gate sits on the station's south wall and
        -- any future expansion from it heads away from the room.
        room_builder.register_gate(gx, gy, "north", gate, computer, surface.name)
        entry.entity = gate
    end

    local silo = first(ctx, "silo")
    if silo and silo.entity then
        trading_silo.register(silo.entity)
    end

    local teleporter = first(ctx, "return_teleporter")
    if teleporter and ctx.return_target then
        local entity = surface.create_entity {
            name = teleporter.def.name,
            position = teleporter.def.position,
            direction = teleporter.def.direction,
            force = ctx.force_name,
        }
        if entity then
            storage.otc_return_teleporters = storage.otc_return_teleporters or {}
            storage.otc_return_teleporters[entity.unit_number] = ctx.return_target
            teleporter.entity = entity
        end
    end
end

return M
