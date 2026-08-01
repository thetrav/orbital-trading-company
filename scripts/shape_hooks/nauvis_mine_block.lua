local supply_belts = require("scripts.supply_belts")

local M = {}

--- Register each drill's intake belt so mined ore lands in Nauvis's stock.
function M.run(ctx)
    for _, entry in ipairs(ctx.roles.intake or {}) do
        if entry.entity then
            supply_belts.register_intake(entry.entity)
        end
    end
end

return M
