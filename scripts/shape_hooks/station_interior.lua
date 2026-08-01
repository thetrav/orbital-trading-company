local room_builder = require("scripts.room_builder")
local room_gates = require("scripts.shape_hooks.room_gates")
local buy_chest = require("scripts.buy_chest")
local sell_chest = require("scripts.sell_chest")

local M = {}

local function first(ctx, role)
    local bucket = ctx.roles[role]
    return bucket and bucket[1]
end

--- The orbital station's own surface: trading chests, silo and the return trip.
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
        storage.rocket_silos = storage.rocket_silos or {}
        storage.rocket_silos[silo.entity.unit_number] = ctx.station_name
    end

    local buy = first(ctx, "buy_chest")
    if buy and buy.entity then buy_chest.register(buy.entity) end

    local sell = first(ctx, "sell_chest")
    if sell and sell.entity then sell_chest.register(sell.entity) end

    local combinator = first(ctx, "buy_chest_combinator")
    if combinator and combinator.entity and buy and buy.entity then
        local cw = combinator.entity.get_wire_connector(defines.wire_connector_id.circuit_green, false)
        local bw = buy.entity.get_wire_connector(defines.wire_connector_id.circuit_green, false)
        if cw and bw then
            ---@diagnostic disable-next-line: undefined-field
            cw.connect_to(bw)
        end
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
