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

    -- One airlock in the middle of each wall, each with its own computer, so a
    -- station expands in all four directions. Nothing here is special enough to
    -- need its own gate code: the sides are the compass DIR_VECTOR uses, so the
    -- shared hook registers each gate expanding away from the room.
    room_gates.run(ctx)

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
