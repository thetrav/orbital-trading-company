local supply_belts = require("scripts.supply_belts")

local M = {}

--- Wire the sealed production room's stock feeds into the supply belt registry.
function M.run(ctx)
    for _, entry in ipairs(ctx.roles.supply or {}) do
        if entry.entity and entry.def.item then
            supply_belts.register_supply(entry.entity, entry.def.item, entry.def.item)
        end
    end
    ctx.built_lab = (ctx.roles.lab or {})[1] ~= nil and (ctx.roles.lab or {})[1].entity ~= nil
end

return M
