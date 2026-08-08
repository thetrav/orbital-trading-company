-- What can the trading silo's inventory actually be told to do? Slot filters and
-- the limiter bar are what a slot-reservation buy model would rest on, and stack
-- size is the question of whether "reserve N" can ever be finer than one stack.
local trading_silo = require("scripts.trading_silo")

local M = {}

function M.run()
    local surface = game.surfaces["nauvis"]
    local silo = surface.create_entity {
        name = trading_silo.NAME, position = { 200, 200 }, force = "Nauvis",
    }
    if not silo then
        log("PROBE could not create a silo")
        return
    end

    local inventory = silo.get_inventory(defines.inventory.chest)
    log("PROBE slots: " .. #inventory)
    log("PROBE supports_bar: " .. tostring(inventory.supports_bar()))
    log("PROBE supports_filters: " .. tostring(inventory.supports_filters()))

    local ok, err = pcall(function() inventory.set_bar(60) end)
    log("PROBE set_bar(60): ok=" .. tostring(ok) .. " -> get_bar="
        .. tostring(inventory.get_bar and inventory.get_bar()) .. " err=" .. tostring(err))

    local can = pcall(function() return inventory.can_set_filter(1, "iron-plate") end)
    log("PROBE can_set_filter callable: " .. tostring(can)
        .. " value=" .. tostring(can and inventory.can_set_filter(1, "iron-plate")))
    local set_ok, set_err = pcall(function() return inventory.set_filter(1, "iron-plate") end)
    log("PROBE set_filter(1,iron-plate): ok=" .. tostring(set_ok) .. " err=" .. tostring(set_err))
    if set_ok then
        log("PROBE get_filter(1): " .. tostring(inventory.get_filter(1)))
    end

    -- Stack size: an item attribute, or something an inventory can be tuned to?
    for _, name in ipairs { "iron-plate", "iron-ore", "electric-mining-drill", "lab",
        "solar-panel", "substation", "assembling-machine-1", "transport-belt" } do
        local proto = prototypes.item[name]
        log(string.format("PROBE stack %-22s = %s", name, tostring(proto and proto.stack_size)))
    end

    -- How much of one item can the whole silo hold, which is what "fill all
    -- available slots" actually buys.
    local inserted = inventory.insert { name = "iron-plate", count = 999999 }
    log("PROBE iron-plate that fits in 100 slots: " .. inserted)

    silo.destroy()
end

return M
