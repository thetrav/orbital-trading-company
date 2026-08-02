local supply_belts = require("scripts.supply_belts")

local M = {}

--- Wire every role=supply and role=intake belt in the shape into Nauvis's
--- stock. Generic on purpose: a shape that only moves items in and out of
--- stock needs no behaviour of its own beyond this.
function M.run(ctx)
    for _, entry in ipairs(ctx.roles.supply or {}) do
        if entry.entity then
            supply_belts.register_from_def(entry.entity, entry.def)
        end
    end
    for _, entry in ipairs(ctx.roles.intake or {}) do
        if entry.entity then
            supply_belts.register_intake(entry.entity)
        end
    end
end

return M
