-- Does Nauvis start with an empty warehouse, and do its own drills break the
-- cold start on their own?
local stock = require("scripts.stock")

local M = {}

local function report(label)
    local items, total = 0, 0
    for name, count in pairs(storage.stock.items or {}) do
        if count > 0 then
            items = items + 1
            total = total + count
        end
        if count > 0 and items <= 6 then
            log("PROBE   " .. label .. " " .. name .. " = " .. count)
        end
    end
    log(string.format("PROBE %s: %d items in stock, %d units total", label, items, total))
end

function M.run()
    report("at init")
    -- Reading a price touches get() for every item; the old lazy seed would
    -- have filled the warehouse just by looking at it.
    for _, name in ipairs { "iron-plate", "copper-plate", "iron-ore", "transport-belt" } do
        log("PROBE get(" .. name .. ") = " .. stock.get(name))
    end
    report("after reads")
end

script.on_nth_tick(600, function()
    if game.tick == 0 then return end
    report("at tick " .. game.tick)
end)

return M
