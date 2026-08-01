local room_builder = require("scripts.room_builder")

local M = {}

local function tile_of(position)
    return math.floor(position[1]), math.floor(position[2])
end

--- Place and register the gates a shape declares, giving each one a computer
--- when the shape also declares a computer facing the same way.
function M.run(ctx)
    local computers = {}
    for _, entry in ipairs(ctx.roles.computer or {}) do
        computers[entry.def.side] = entry.def
    end

    for _, entry in ipairs(ctx.roles.gate or {}) do
        local gx, gy = tile_of(entry.def.position)
        local side = entry.def.side
        local gate = room_builder.place_gate(ctx.surface, side, { gx, gy }, ctx.force_name)
        local computer
        if computers[side] then
            computer = room_builder.place_computer(ctx.surface, gx, gy, side, ctx.force_name)
        end
        room_builder.register_gate(gx, gy, side, gate, computer, ctx.surface.name)
        entry.entity = gate
    end
end

M.tile_of = tile_of

return M
