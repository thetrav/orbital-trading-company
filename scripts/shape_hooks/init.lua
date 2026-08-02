-- Post-apply behaviour for captured shapes. A shape names one of these in its
-- `hook` field; everything a definition cannot express in data lives here.

local M = {}

M.hooks = {
    room_gates = require("scripts.shape_hooks.room_gates"),
    orbital_station = require("scripts.shape_hooks.orbital_station"),
    station_interior = require("scripts.shape_hooks.station_interior"),
    starting_room = require("scripts.shape_hooks.starting_room"),
    nauvis_production_room = require("scripts.shape_hooks.nauvis_production_room"),
    nauvis_mine_block = require("scripts.shape_hooks.nauvis_mine_block"),
    stock_belts = require("scripts.shape_hooks.stock_belts"),
}

function M.run(name, ctx)
    if not name then return end
    local hook = M.hooks[name]
    if not hook then
        log("shape hook not found: " .. tostring(name))
        return
    end
    hook.run(ctx)
end

return M
